require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'rubygems'
require 'lyber_core'
require 'sdrIngest/validate_bag'
require 'tmpdir'

describe Sdr::ValidateBag do 

  context "bag_exists?" do

    before(:each) do
      @druid = "lkdjflksdjda"
      @path = File.join(Dir.tmpdir, "lkdjflksdjda")
      @data = File.join(@path, DATA_DIR)
      @bagit = File.join(@path, BAGIT_TXT)
      @bag = File.join(@path, BAG_INFO_TXT)
      FileUtils.mkdir_p(@data)
      FileUtils.touch(@bagit)
      FileUtils.touch(@bag)
    end

    after(:each) do
      FileUtils.rm_rf(@path)
    end
    
    it "should return true to test the initial bag setup"  do
      	puts @path
        robot = Sdr::ValidateBag.new()
      	robot.bag_exists?(@druid,@path).should == true
    end 

    it "should return false when base_path does not exist" do
      # delete the bag dir
      FileUtils.rm_rf @path   

      robot = Sdr::ValidateBag.new()
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end

    it "should return false when @path is not a directory" do 
      FileUtils.rm_rf(@path)
      FileUtils.touch(@path) # create a file

      robot = Sdr::ValidateBag.new()      	
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end
      
    it "should return false when data_dir does not exist" do
      FileUtils.rm_rf(@data)

      robot = Sdr::ValidateBag.new()
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end

    it "should return false when data_dir is not a directory" do
      FileUtils.rm_rf(@data)
      FileUtils.touch(@data)

      robot = Sdr::ValidateBag.new()
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end

    it "should return false when bagit_txt_file does not exist" do
      FileUtils.rm_rf(@bagit)

      robot = Sdr::ValidateBag.new()
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end

    it "should return false when bagit_txt_file is not a file" do
      FileUtils.rm_rf(@bagit)
      FileUtils.mkdir(@bagit)

      robot = Sdr::ValidateBag.new()
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end

    it "should return false when bag_info_txt_file does not exist" do
      FileUtils.rm_rf(@bag)

      robot = Sdr::ValidateBag.new()
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end

    it "should return false when bag_info_txt_file is not a file" do
      FileUtils.rm_rf(@bag)
      FileUtils.mkdir(@bag)

      robot = Sdr::ValidateBag.new()
      lambda{robot.bag_exists?(@druid,@path)}.should raise_exception(LyberCore::Exceptions::ItemError)
    end

    it "should return true when it is a real bag" do
      pending("updating bagit gem to support v0.96")
      path = File.join(Dir.tmpdir, "lkdjflksdjfalddfsdfa")
      BagIt::Bag.new(path)

      robot = Sdr::ValidateBag.new()
      robot.bag_exists?(@druid,path).should == true

      FileUtils.rm_rf(path)
    end
  end

  context "validate" do
    
      it "should raise error when bag does not exist" do
        robot = Sdr::ValidateBag.new()
        mock_workitem = mock("workitem")
        mock_workitem.stub!(:druid).and_return("druid:ab123cd4567")

        lambda {robot.process_item(mock_workitem)}.should raise_error
      end

      it "should return nil when bag is valid" do
        robot = Sdr::ValidateBag.new()
        mock_workitem = mock("workitem")
        mock_workitem.stub!(:druid).and_return("druid:ab123cd4567")
        mock_bag = mock("bag")
	robot.stub!(:bag_exists?).and_return(true)
        BagIt::Bag.stub!(:new).and_return(mock_bag)
        mock_bag.stub!(:valid?).and_return(true)
        
        robot.process_item(mock_workitem).should be_nil
      end

      it "should raise error when bag is not valid" do
        robot = Sdr::ValidateBag.new()
        mock_workitem = mock("workitem")
        mock_workitem.stub!(:druid).and_return("druid:ab123cd4567")
        mock_bag = mock("bag")
	robot.stub!(:bag_exists?).and_return(true)
        BagIt::Bag.stub!(:new).and_return(mock_bag)
        mock_bag.stub!(:valid?).and_return(false)
        
        lambda {robot.process_item(mock_workitem)}.should raise_error
      end
  end
end
