
## and further modified by lyber-core/config.rb

Dor::Config.configure do
  robots do
   workspace nil
  end
  workflow do
   url 'https://workflow-server.stanford.edu/workflow'
  end
  ssl do
   cert_file "#{ROBOT_ROOT}/config/certs/ls-xxx.crt"
   key_file "#{ROBOT_ROOT}/config/certs/ls-xxx.key"
   key_pass 'yyy'
  end
end
#puts Dor::Config.inspect

Sdr::Config.configure do
  ingest_transfer do
    account "userid@dor-host.stanford.edu"
    export_dir "/dor/export/"
  end
  logdir File.join(ROBOT_ROOT, 'log')
  dor_export Dir.mktmpdir('export')
  sdr_recovery_home File.join(ROBOT_ROOT,'spec', "temp")
  audit_verbose true
end


# Moab::Config is created in moab-versioning/lib/moab/config.rb
Moab::Config.configure do
  storage_roots File.join(ROBOT_ROOT,'spec','fixtures')
  storage_trunk 'repository'
  deposit_trunk 'deposit'
  path_method :druid
end
