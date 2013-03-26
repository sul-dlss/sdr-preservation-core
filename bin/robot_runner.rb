#!/usr/bin/env ruby

require 'environment'
require 'druid_queue'
require 'status_activity'
require 'status_process'
require 'status_workflow'
require 'boot'
require 'socket'
require 'pathname'
require 'sys/filesystem'
require 'time'

Breakdown = Struct.new(:timestamp,:write_process_status,:create_robot,:check_status,:run_robot,:get_elapsed_time,:write_ingest_detail)

# You must subclass and provide a get_robots method
class RobotRunner

  def self.syntax
    puts <<-EOF

    Syntax: bundle-exec.sh robot_runner.rb  {#{WorkflowNames.join('|')}} ['debug'] ['verify']

    If debug specified, logger will include debug output

    If verify specified, post-robot queries and output file verification will be done

    EOF
  end

  def initialize(args)
    @workflow = args[0]
    @loglevel = (args.map(&:upcase).include?('DEBUG')) ? 0 : 1
    @verify = (args.map(&:upcase).include?('VERIFY')) ? true : false
    @environment = ENV["ROBOT_ENVIRONMENT"]
    @repository_home = Sdr::Config.storage_node
    @status_process = StatusProcess.new(@workflow)
    @item_counts = {:completed=>0,:error=>0, :fatal=>0}
  end

  # loglevel is one of the following integers (default = 1 (INFO))
  #    DEBUG = 0
  #    INFO = 1
  #    WARN = 2
  #    ERROR = 3
  #    FATAL = 4
  def loglevel=(level)
    @loglevel=level
  end

  def verify=(flag)
    @verify = flag
  end

  def run_pipeline
    subject = "Starting #{@workflow} pipeline"
    @status_process.write_process_log(subject)
    email_run_status(subject)
    status = process_queue
    message = @item_counts.inspect
    @status_process.write_process_log(message)
    subject = "Stopping #{@workflow} pipeline: #{status}"
    @status_process.write_process_log(subject)
    email_run_status(subject, message)
    @status_process.delete_pid_file
  end

  def email_run_status(subject,message=nil)
    message ||= subject
    `echo '#{message}' | mail -s '#{subject}' $USER `
  end

  def process_queue()
    druid_queue = DruidQueue.new(@workflow)
    sequential_errors = 0
    error_sleep = [0,60,300,1000]
    while true
      stop,why = @status_process.stop_process?
      return why if stop
      druid = druid_queue.next_item
      if druid
        logfile = initialize_logfile(druid)
        status = process_druid(druid, logfile)
        logfile = move_logfile(logfile, status)
        case status
          when'fatal'
            @item_counts[:fatal] += 1
            @status_process.set_state("FATAL ERROR")
            email_log_file(druid, logfile, status)
            return "fatal error"
          when 'error'
            @item_counts[:error] += 1
            sequential_errors += 1
            if sequential_errors > 1
              email_log_file(druid, logfile, status)
              @status_process.write_process_status($$, "sleeping", "#{sequential_errors} errors")
              sleep (error_sleep[sequential_errors] || error_sleep.last)
              if sequential_errors > 3
                @status_process.set_state("SEQUENTIAL ERRORS")
                return "too many sequential errors"
              end
            end
          else
            @item_counts[:completed] += 1
            sequential_errors = 0
        end
      else
        @status_process.write_process_status($$, "sleeping", "empty queue")
        sleep 300
      end
    end
  end


  def initialize_logfile(druid)
    druid_id = druid.split(/:/)[-1]
    log = "#{AppHome}/log/#{@workflow}/current/active/#{druid_id}"
    logfile = Pathname(log)
    logfile.parent.mkpath
    LyberCore::Log.set_logfile(log)
    LyberCore::Log.set_level(@loglevel || Logger::INFO)
    LyberCore::Log.info "druid = #{druid}"
    LyberCore::Log.info "workflow = #{@workflow}"
    LyberCore::Log.info "environment = #{@environment}"
    LyberCore::Log.info "timestamp = #{Time.now.iso8601}"
    logfile
  end

  # run all robots (in sequence) to process the specified druid
  def process_druid(druid, logfile)
    #@breakdown = Breakdown.new(nil,0,0,0,0,0,0)
    status = nil
    robots = get_robots
    robots.each do |robot|
      #t0=Time.now
      @status_process.write_process_status($$, druid.split(':')[-1], robot.name)
      #@breakdown.write_process_status += (Time.now - t0)
      status = run_robot(robot, druid, logfile)
      status = analyze_logfile(logfile) if status == 'error'
      return status if status =='error' or status == 'fatal'
    end
    write_ingest_detail(druid)
    #breakdown_log = "#{AppHome}/log/#{@workflow}/current/status/breakdown.txt"
    #Pathname(breakdown_log).open('a'){|f| f.write "#{@breakdown.values.join('|')}\n"}
    status
  end

  def get_robots()
    unless @robots
      sw = StatusWorkflow.new(@workflow)
      @robots = sw.robots
    end
    @robots
  end

  def run_robot(robot, druid, logfile)
    begin
      #t0=Time.now
      LyberCore::Log.info "=" * 60
      robot_opts = {:logfile => logfile.to_s, :loglevel => @loglevel, :argv => ['-d', druid]}
      require robot.classpath
      #    robot_object = eval(robot.classname).new(robot_opts)
      # http://www.ruby-forum.com/topic/182803
      robot_class = robot.classname.split('::').reduce(Object){|cls, c| cls.const_get(c) }
      robot_object = robot_class.new(robot_opts)
      #@breakdown.create_robot += (Time.now - t0)
      #t0=Time.now
      begin
        robot_status = Dor::WorkflowService.get_workflow_status(
            'sdr', druid, @workflow, robot.name)
      rescue
        robot_status = (robot.classname == 'Sdr::MigrationStart') ? 'waiting' : 'unknown'
      end
      #@breakdown.check_status += (Time.now - t0)
      #t0=Time.now
      case robot_status
        when 'completed'
          LyberCore::Log.info "#{druid} #{robot.name} status = previously completed"
        when 'waiting','error'
          # Here's where we run the robot
          robot_object.start
          #@breakdown.run_robot += (Time.now - t0)
          #t0=Time.now
          robot_status = Dor::WorkflowService.get_workflow_status(
              'sdr', druid, @workflow, robot.name)
          LyberCore::Log.info "#{druid} #{robot.name} status = #{robot_status}"
          #@breakdown.check_status += (Time.now - t0)
          return 'error'if robot_status != "completed"
          if @verify
            return 'error' unless verify_results(robot_object, druid)
          end
        else
          LyberCore::Log.error "#{druid} #{robot.name} unexpected status = #{robot_status}"
          return 'fatal'
      end
    rescue Exception
      LyberCore::Log.error "#{$!.inspect}\n#{$@}"
      return 'fatal'
    end
    return robot_status
  end

  def verify_results(robot_object, druid)
    queries = robot_object.verification_queries(druid)
    queries.each do |query|
      url = query[0]
      expect_code = query[1]
      expect_pattern = query[2]
      LyberCore::Log.info "query_url = #{url.sub(/\/\/.*:.*@/,'//user:pass@')}"
      response = RestClient.get url
      LyberCore::Log.info "response.code = #{response.code}"
      match = response.body =~ expect_pattern ? 'matches:' : 'differs:'
      LyberCore::Log.info "response.body #{match} #{expect_pattern.inspect}"
      if match != 'matches:'
        LyberCore::Log.error "ItemError: Query response does not match expected pattern - #{expect_pattern.inspect}"
        return false
      end
    end
    output_files = robot_object.verification_files(druid)
    output_files.each do |filepath|
      pathname = Pathname(filepath)
      existence = pathname.exist? ? 'found:' : 'missing:'
      LyberCore::Log.info "pathname #{existence} #{pathname.to_s}"
      if existence != 'found:'
        Lybercore::Log.error "ItemError: Expected output file not found - #{pathname}"
        return false
      end
    end
    return true
  end

  def analyze_logfile(logfile)
    log=Pathname(logfile).read
    if log.include?('FATAL')
      return 'fatal'
    elsif log.include?('ItemError')
      return 'error'
    elsif log.include?('ERROR')
      return 'fatal'
    else
      return 'completed'
    end
  end

  def move_logfile(logfile, status)
    logdir = status == 'fatal' ? 'error' : status
    log_destination=logfile.parent.parent.join(logdir,logfile.basename)
    log_destination.parent.mkpath
    log_destination.make_link(logfile)
    logfile.unlink
    log_destination
  end

  def email_log_file(druid, logfile, status)
    `cat #{logfile} | mail -s '#{@workflow} - #{status} occurred for #{druid}' $USER `
  end

  def write_ingest_detail(druid)
    #t0=Time.now
    ingest_detail = IngestDetail.new
    time = Time.now
    ingest_detail.date = time.strftime('%Y-%m-%d')
    ingest_detail.time = time.strftime('%H:%M:%S')
    ingest_detail.pipes = @status_process.process_count
    ingest_detail.druid = druid.split(/:/)[-1]
    get_version_stats(druid,ingest_detail)
    ingest_detail.elapsed  = get_elapsed_time(druid)
    statlog = "#{AppHome}/log/#{@workflow}/current/status/ingest-history.txt"
    Pathname(statlog).open('a'){|f| f.write(ingest_detail.values.join('|')+"\n")}
    ingest_detail
    #@breakdown.write_ingest_detail  += ((Time.now - t0) - #@breakdown.get_elapsed_time)
  end

  def get_version_stats(druid,ingest_detail)
    repository = Stanford::StorageRepository.new
    storage_object = repository.storage_object(druid)
    version = storage_object.find_object_version
    write_item_tree(version)
    ingest_detail.version = version.version_id
    additions = version.file_inventory('additions')
    content = additions.group('content')
    ingest_detail.cfiles = content ? content.file_count.to_i : 0
    ingest_detail.cbytes = content ? content.byte_count.to_i : 0
    metadata = additions.group('metadata')
    ingest_detail.mfiles = metadata ? metadata.file_count.to_i : 0
    ingest_detail.mbytes = metadata ? metadata.byte_count.to_i : 0
    ingest_detail
  end

  def write_item_tree(version)
    version_path = version.version_pathname.relative_path_from(Pathname(@repository_home))
    tree = `cd #{@repository_home}; tree -s #{version_path}`
    treefile = "#{AppHome}/log/#{@workflow}/current/status/latest-item.txt"
    Pathname(treefile).open('w')do |f|
      f.write "Latest Addition to #{@repository_home}\n"
      f.write "#{'='*50}\n"
      f.write(tree)
    end
    tree
  end

  def get_elapsed_time(druid)
    #t0=Time.now
    workflow_xml = Dor::WorkflowService.get_workflow_xml('sdr',druid, @workflow)
    workflow_xml_doc = Nokogiri::XML.parse(workflow_xml)
    processes = workflow_xml_doc.xpath(".//process")
    seconds = processes.inject(0.0){|elapsed, process| elapsed + (process['elapsed'] || 0).to_f}
    seconds
    #@breakdown.get_elapsed_time += (Time.now - t0)
  end

end

# This is the equivalent of a java main method
if __FILE__ == $0
  workflow = ARGV[0].to_s
  if WorkflowNames.include?(workflow)
    runner = RobotRunner.new(ARGV)
    runner.run_pipeline
  else
    RobotRunner.syntax
  end
end