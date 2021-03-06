require_relative '../libdir'
require 'boot'

module Robots
  module SdrRepo
    module SdrRecovery

      # A robot for file cleanup after the object recovery
      class RecoveryCleanup < SdrRobot

        # class instance variables (accessors defined in SdrRobot parent class)
        @workflow_name = 'sdrRecoveryWF'
        @step_name = 'recovery-cleanup'

        # @return [RecoveryCleanup] set workflow name, step name, log location, log severity level
        def initialize(opts = {})
          super(self.class.workflow_name, self.class.step_name, opts)
        end

        # @param druid [String] The item to be processed
        # @return [void] process an object from the queue through this robot
        #   See LyberCore::Robot#work
        def perform(druid)
          LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Enter perform")
          recovery_cleanup(druid)
        end

        # @param druid [String] The object identifier
        # @return [Boolean] complete ingest of the item,  cleanup temp deposit data.
        def recovery_cleanup(druid)
          LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Enter recovery_cleanup")
          recovery_path = Pathname(Sdr::Config.sdr_recovery_home).join(druid.sub('druid:', ''))
          cleanup_recovery_files(druid, recovery_path) if recovery_path.exist?
        end

        # @param druid [String] The object identifier
        # @param recovery_path [Pathname] The temp location of the folder containing the object files being restored
        # @return [Boolean] Cleanup the temp recovery files, raising an error if cleanup failes after 3 attempts
        def cleanup_recovery_files(druid, recovery_path)
          # retry up to 3 times
          tries ||= 3
          recovery_path.rmtree
          return true
        rescue StandardError => e
          if (tries -= 1) > 0
            retry
          else
            raise ItemError.new("Failed rmtree #{recovery_path} (3 attempts)")
          end
        end


        def verification_queries(druid)
          queries = []
          queries
        end

        def verification_files(druid)
          files = []
          files << Sdr::Config.sdr_recovery_home
          files
        end

      end

    end
  end
end

# This is the equivalent of a java main method
if __FILE__ == $0
  ARGF.each do |druid|
    dm_robot = Robots::SdrRepo::SdrRecovery::RecoveryCleanup.new()
    dm_robot.process_item(druid)
  end
end
