require_relative '../libdir'
require 'boot'
require 'sdr/item_error'
require 'sdr/fatal_error'

module Robots
  module SdrRepo

    # Contains the shared methods used by all robots that inherit from this object
    class SdrRobot
      include LyberCore::Robot

      # accessors for class instance variables
      # methods are inherited by subclasses, but @workflow_name and @step_name are not global values
      # @see http://martinfowler.com/bliki/ClassInstanceVariable.html
      class << self
        attr_accessor :workflow_name
        attr_accessor :step_name
      end

      def initialize(workflow_name, step_name, opts = {})
        super('sdr', workflow_name, step_name, opts)
      end

      # @param druid [String] The object being processed
      # @return [Boolean] process the object, then set success or error status
      def process_item(druid)
        elapsed = Benchmark.realtime do
          perform druid # implemented in the robot subclass
        end
        update_workflow_status 'sdr', druid, self.class.workflow_name, self.class.step_name, 'completed', elapsed
        LyberCore::Log.info "Completed #{druid} in #{elapsed} seconds"
        return 'completed'
      rescue StandardError => e
        Honeybadger.notify(e)

        message = if e.cause
                    "#{e.message}; caused by #{e.cause.inspect}"
                  else
                    e.message
                  end

        backtrace = if e.cause
                      e.cause.backtrace
                    else
                      e.backtrace
                    end

        update_workflow_error_status 'sdr', druid, self.class.workflow_name, self.class.step_name, message

        log_message = "#{druid} #{message} #{backtrace.join("\n")}"

        if  e.is_a?(FatalError)
          LyberCore::Log.fatal log_message
          'fatal'
        else
          LyberCore::Log.error log_message
          'error'
        end
      end

      # @param opts [Hash] options (:tries and :interval)
      # @param request [Object] the block of code to execute
      # @return [Boolean] retry request up to :tries times, sleeping :interval seconds after each failed attempt
      def transmit(opts={}, &request)
        tries ||= opts[:tries] || 3
        interval ||= opts[:interval] || 20
        request.call(nil)
      rescue StandardError => e
        if (tries -= 1) > 0
          sleep interval
          retry
        else
          raise FatalError.new("Failed to transmit request")
        end
      end

      def create_workflow_rows(repo, druid, workflow_name, wf_xml, opts = {:create_ds => true})
        transmit(opts) { Dor::WorkflowService.create_workflow(repo, druid, workflow_name, wf_xml, opts) }
      end

      def get_workflow_xml(repo, druid, workflow_name, opts={})
        transmit(opts) { Dor::WorkflowService.get_workflow_xml(repo, druid, workflow_name) }
      end

      def get_workflow_status(repo, druid, workflow_name, step_name, opts={})
        transmit(opts) { Dor::WorkflowService.get_workflow_status(repo, druid, workflow_name, step_name) }
      end

      def update_workflow_status(repo, druid, workflow_name, step_name, status, elapsed, opts={})
        opts[:elapsed] = elapsed
        opts[:note] = Socket.gethostname
        transmit(opts) { Dor::WorkflowService.update_workflow_status(repo, druid, workflow_name, step_name, status, opts) }
      end

      def update_workflow_error_status(repo, druid, workflow_name, step_name, msg, opts={})
        LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Enter update_workflow_error_status")
        message = msg.lines.first.chomp[0..80] + (msg.length > 80 ? ' ...' : '')
        params = {repo: repo, druid: druid, workflow_name: workflow_name, step_name: step_name, message: message}
        LyberCore::Log.debug(params.inspect)
        LyberCore::Log.debug(opts.inspect)
        opts[:note] = Socket.gethostname
        transmit(opts) { Dor::WorkflowService.update_workflow_error_status(repo, druid, workflow_name, step_name, message, opts ) }
      end
    end
  end
end

