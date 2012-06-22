require File.join(File.dirname(__FILE__),'libdir')
require 'boot'

module Sdr

  # A robot for adding core datastreams to the Fedora object using metadata files from the bagit object.
  class PopulateMetadata < LyberCore::Robots::Robot
    
    # set workflow name, step name, log location, log severity level
    def initialize()
      super('sdrIngestWF', 'populate-metadata',
        :logfile => "#{Sdr::Config.logdir}/populate-metadata.log",
        :loglevel => Logger::INFO,
        :options => ARGV[0])
      env = ENV['ROBOT_ENVIRONMENT']
      LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Environment is : #{env}")
      LyberCore::Log.debug("Process ID is : #{$PID}")
    end

    # @param work_item [LyberCore::Robots::WorkItem] The item to be processed
    # @return [void] process an object from the queue through this robot
    #   Overrides LyberCore::Robots::Robot.process_item method.
    #   See LyberCore::Robots::Robot#process_queue
    def process_item(work_item)
      LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Enter process_item")
      druid = work_item.druid
      fill_datastreams(druid)
    end

    # @param druid [String] The object identifier
    # @return [SedoraObject] Add the core metadata datastreams to the Fedora object
    def fill_datastreams(druid)
      LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Enter fill_datastreams")
      bag_pathname = find_bag(druid)
      sedora_object = Sdr::SedoraObject.find(druid)
      set_datastream_content(sedora_object, bag_pathname, 'identityMetadata')
      set_datastream_content(sedora_object, bag_pathname, 'provenanceMetadata')
      set_datastream_content(sedora_object, bag_pathname, 'relationshipMetadata')
      sedora_object.save
      sedora_object
    rescue ActiveFedora::ObjectNotFoundError => e
      raise LyberCore::Exceptions::FatalError.new("Cannot find object #{druid}",e)
    rescue  Exception => e
      raise LyberCore::Exceptions::FatalError.new("Cannot process item #{druid}",e)
    end

    # @param druid [String] The object identifier
    # @return [Pathname] Find and verify the BagIt bag directory.
    def find_bag(druid)
      LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Enter find_bag")
      bag_pathname = SdrDeposit.bag_pathname(druid)
      unless bag_pathname.directory?
        raise LyberCore::Exceptions::ItemError.new(druid, "Can't find a bag at #{bag_pathname.to_s}")
      end
      bag_pathname
    end

    # @param sedora_object [SedoraObject] The Fedora object to which datatream content is to be saved
    # @param bag_pathname [Pathname] The location of the BagIt bag containing the object data files
    # @param dsid [String] The datastream identifier, which is also the basename of the XML data file
    # @return [void] Perform the following steps:
    #   - Determine the metadata files full path in the bagit object,
    #   - determine if the metadata file exists, and if so
    #   - copy the content of the metadata file to the datastream.
    # @raise [LyberCore::Exceptions::FatalError] if we can't find the file
    def set_datastream_content(sedora_object, bag_pathname, dsid)
      LyberCore::Log.debug("( #{__FILE__} : #{__LINE__} ) Enter set_datastream_content for #{dsid}")
      md_pathname = bag_pathname.join('data/metadata',"#{dsid}.xml")
      if md_pathname.file?
        sedora_object.datastreams[dsid].content = md_pathname.read
      end
    rescue Exception => e
      raise LyberCore::Exceptions::FatalError.new("Cannot add #{dsid} datastream for #{sedora_object.pid}",e)
    end
    
  end
end

# This is the equivalent of a java main method
if __FILE__ == $0
    dm_robot = SdrIngest::PopulateMetadata.new()
    dm_robot.start
end
