#!/usr/bin/env ruby
# Author::    Bess Sadler  (mailto:bess@stanford.edu)
# Date::      13 May 2010

require File.expand_path(File.dirname(__FILE__) + '/../boot')

require 'lyber_core'
require 'logger'

#:title:The SdrIngest Workflow
#= The SdrIngest Workflow
#The +SdrIngest+ workflow takes objects from Dor's queue and deposits them into SDR.
#The most up to date description of the deposit workflow is always in 
#config/workflows/sdrIngest/sdrIngestWorkflow.xml. (Content included below.)
#:include:config/workflows/sdrIngest/sdrIngestWorkflow.xml
module SdrIngest
  
  # +PopulateMetadata+ finds a stub object in Sedora and populates its datastreams with the contents from a bagit object.
  class PopulateMetadata < LyberCore::Robots::Robot
    
    # the fedora object to operate on
    attr_reader :obj
    
    # the bag to fetch metadata from
    attr_reader :bag
    
    # the druid of the current workitem
    attr_reader :druid 
    
    # The directory to read bags from, mostly used for testing
    attr_reader :bag_directory
    attr_writer :bag_directory
    
    # Accessor method for datastream
    attr_reader :identity_metadata, :content_metadata, :provenance_metadata
    
    # Override the LyberCore::Robot initialize method so we can set object attributes during initialization
    def initialize(string1,string2)
      super(string1,string2)
      # by default, get the bags from the SDR_DEPOSIT_DIR
      # this can be explicitly changed if necessary
      @bag_directory = SDR_DEPOSIT_DIR
      
      # Logging information
      @logg = Logger.new("populate_metadata.log")
      @logg.level = Logger::DEBUG
      @logg.formatter = proc{|s,t,p,m|"%5s [%s] (%s) %s :: %s\n" % [s, 
                          t.strftime("%Y-%m-%d %H:%M:%S"), $$, p, m]}
    end

    # Override the robot LyberCore::Robot.process_item method.
    # * Makes use of the Robot Framework FileUtilities.
    def process_item(work_item)
      @logg.debug("Enter process_item")
      # Identifiers
      @druid = work_item.druid
    
      raise IOError, "Can't find a bag at #{@bag}" unless self.bag_exists?
      raise IOError, "Can't load sedora object for #{@druid}" unless self.get_fedora_object
      self.populate_identity_metadata
      self.populate_provenance_metadata
      self.populate_content_metadata
      @obj.save
    end
    
    def process_druid(druid)
      @druid = druid
    
      raise IOError, "Can't find a bag at #{@bag}" unless self.bag_exists?
      raise IOError, "Can't load sedora object for #{@druid}" unless self.get_fedora_object
      self.populate_identity_metadata
      self.populate_provenance_metadata
      self.populate_content_metadata
      @obj.save
    end
    
    # Check to see if the bagit directory exists.
    # It does not check the validity of the bag, it assumes this has already happened.
    def bag_exists?
      @bag = @bag_directory + '/' + self.druid
      File.directory? @bag
    end
    
    # fetch the fedora object from the repository so we can attach datastreams to it
    # throw an error if we can't find the object
    def get_fedora_object
      @logg.debug("Connecting to #{SEDORA_URI}...")
      # puts "Connecting to #{SEDORA_URI}..."
      begin
        Fedora::Repository.register(SEDORA_URI)
        @obj = ActiveFedora::Base.load_instance(@druid)
      rescue Errno::ECONNREFUSED => e
        @logg.error("Can't connect to Fedora at url #{SEDORA_URI} : #{e.inspect}")
        @logg.error( "#{e.backtrace}")
        
        raise RuntimeError, "Can't connect to Fedora at url #{SEDORA_URI} : #{e}"   
        return nil     
      rescue
        return nil
      end
    end
    
    # Go grab the given filename from the bagit object, 
    # make a datastream out of it using the given label, 
    # attach it to the fedora object, and save. 
    # Throw an error if you can't find a bag or if you can't find the file
    def populate_metadata(filename,label)
      mdfile = File.expand_path(@bag + '/data/metadata/' + filename)
      md = ActiveFedora::Datastream.new(:pid=>@obj.pid, :dsid=>label, :dsLabel=>label, :blob=>IO.read(mdfile))
      @obj.add_datastream(md)
      return md
    end
    
    def populate_identity_metadata
      @identity_metadata = populate_metadata('identityMetadata.xml','IDENTITY')
    end
    
    def populate_provenance_metadata
      @provenance_metadata = populate_metadata('provenanceMetadata.xml','PROVENANCE')
    end
    
    def populate_content_metadata
      @content_metadata = populate_metadata('contentMetadata.xml','CONTENTMD')
    end
    
  end
end


# This is the equivalent of a java main method
if __FILE__ == $0
  # If this robot is invoked with a specific druid, it will populate the metadata for that druid only
  if(ARGV[0])
    puts "Updating metadata for #{ARGV[0]}"
    dm_robot = SdrIngest::PopulateMetadata.new("sdrIngestWF","populate-metadata")
    dm_robot.process_druid(ARGV[0])
  else
    dm_robot = SdrIngest::PopulateMetadata.new('sdrIngestWF', 'populate-metadata')
    # puts "workflow = #{dm_robot.workflow}"
    dm_robot.start
  end
  puts "Done."
end
