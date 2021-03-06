require_relative '../libdir'
require 'boot'
require 'sdr_ingest/complete_deposit'

module Robots
  module SdrRepo
    module SdrMigration

      # A robot for completing the migration of the queued objects
      # Most methods inherit from complete-deposit robot's class
      class MigrationComplete < SdrIngest::CompleteDeposit

        # class instance variables (accessors defined in SdrRobot parent class)
        @workflow_name = 'sdrMigrationWF'
        @step_name = 'migration-complete'

        # @param druid [String] The object identifier
        # @param storage_object [StorageObject] The representation of a digitial object's storage directory
        # @return [void] complete ingest of the item,  cleanup temp deposit data.
        def complete_deposit(druid, storage_object)
          new_version = storage_object.ingest_bag
          result = new_version.verify_version_storage
          if result.verified == false
            LyberCore::Log.info result.to_json(verbose=false)
            raise ItemError.new("Failed validation")
          end
          bag_pathname = storage_object.deposit_bag_pathname
          cleanup_deposit_files(druid, bag_pathname)
        end

        # @param druid [String] The object identifier
        # @param bag_pathname [Object] The temp location of the bag containing the object version being deposited
        # @return [Boolean] Cleanup the temp deposit files, raising an error if cleanup failes after 3 attempts
        def cleanup_deposit_files(druid, bag_pathname)
          # retry up to 3 times
          sleep_time = [0, 2, 6]
          attempts ||= 0
          bag_pathname.rmtree
          return true
        rescue StandardError => e
          if (attempts += 1) < sleep_time.size
            sleep sleep_time[attempts].to_i
            retry
          else
            raise ItemError.new("Failed cleanup deposit (#{attempts} attempts)")
          end
        end

        def verification_queries(druid)
          storage_url = Sdr::Config.sdr_storage_url
          workflow_url = Dor::Config.workflow.url
          queries = []
          queries << [
              "#{storage_url}/objects/#{druid}",
              200, /<html>/]
          queries << [
              "#{workflow_url}/sdr/objects/#{druid}/workflows/sdrMigrationWF",
              200, /completed/]
          queries
        end

        def verification_files(druid)
          files = []
          files << Moab::StorageServices.object_path(druid).to_s
          files
        end

      end

    end
  end
end

# This is the equivalent of a java main method
if __FILE__ == $0
  ARGF.each do |druid|
    dm_robot = Robots::SdrRepo::SdrMigration::MigrationComplete.new()
    dm_robot.process_item(druid)
  end
end
