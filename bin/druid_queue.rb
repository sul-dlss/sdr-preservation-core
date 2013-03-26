#!/usr/bin/env ruby

require 'environment'
require 'directory_queue'
require 'druid-tools'

class DruidQueue < DirectoryQueue

  def self.syntax
    puts <<-EOF
  
    Syntax: bundle-exec.sh druid_queue.rb {#{WorkflowNames.join('|')}}
    EOF
    self.options
  end

  def self.options
    puts <<-EOF

    queue options:

      enqueue {druid|filename|query_batch_size} =  add item(s) to queue
      size     = report how many items are in the queue
      list {n} = list the first n items that are in the queue

    If Request type is 'enqueue', then druid argument must be one of
      * a valid druid
      * name of a file containing a list of druids
      * the next {query_batch_size} druids that are waiting in the workflow

    If request type is 'size', then the size of the queue is reported

    If request type is 'list n', then the first (n) items in the queue are listed

    EOF
  end
  
  def initialize(workflow)
    @workflow = workflow
    queue_pathname = AppHome.join("log",workflow,"current","queue")
    super(queue_pathname)
  end

  def enqueue(druid_arg)
    if druid_arg.to_s =~ /\A(?:druid:)?([a-z]{2})(\d{3})([a-z]{2})(\d{4})\z/
      add_item(druid_arg)
    elsif Pathname(druid_arg.to_s).exist?
      add_list_from_file(druid_arg)
    elsif is_integer?(druid_arg)
      add_workflow_waiting(Integer(druid_arg))
    else
      DruidQueue.syntax
    end
  end

  def is_integer?(n)
    !!Integer(n)
  rescue
    false
  end

  def add_workflow_waiting(druid_arg)
    if druid_arg > 4000
      puts "Limiting batch size to 4000 or less"
      batch_size =  4000
    else
      batch_size =  druid_arg
    end
    require 'boot'
    if @workflow == 'sdrIngestWF'
      druids = Dor::WorkflowService.get_objects_for_workstep(
          completed='start-ingest', waiting='register-sdr', repository='sdr', workflow=@workflow)
    elsif @workflow == 'sdrMigrationWF'
      druids = Dor::WorkflowService.get_objects_for_workstep(
          completed='migration-start', waiting='migration-register', repository='sdr', workflow=@workflow)
    end
    add_list(druids[0...batch_size],4)
  end

  # @param [String] item The unfiltered item identifer to be added to the queue
  # @return [String] If overridden in a subclass, allows the raw identifier to be massaged,
  #   such as by stripping of a prefix or removing characters not compatible with a filename
  def input_filter(item)
    dt = DruidTools::Druid.new(item)
    dt.id
  end

  # @param [String] id The (possibly filtered) item identfier that is the last part of the queue filename
  # @return [String] If overridden in a subclass, allows the raw identifier to be regenerated,
  #    by reversing the logic in the input_filter method
  def output_filter(id)
    dt = DruidTools::Druid.new(id)
    dt.druid
  end

  def exec(args)
    case args.shift.to_s.upcase
      when 'ENQUEUE'
        enqueue(args.shift)
      when 'SIZE'
        puts queue_size
      when 'LIST'
        puts top_file(n=args.shift.to_i)
      else
        DruidQueue.options
    end
  end

end

# This is the equivalent of a java main method
if __FILE__ == $0

  workflow = ARGV.shift.to_s
  if WorkflowNames.include?(workflow)
    druid_queue = DruidQueue.new(workflow)
    druid_queue.exec(ARGV)
  else
    DruidQueue.syntax
  end

end