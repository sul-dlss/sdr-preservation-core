source 'https://rubygems.org'

gem 'confstruct'
gem 'honeybadger'
gem 'nokogiri'
gem 'rake'
gem 'rest-client'
gem 'sys-filesystem'

# bin/console.rb uses pry
gem 'pry'
gem 'pry-doc'

# DLSS gems
gem 'dor-workflow-service', '~> 2.0'
gem 'net-http-persistent', '~> 2.0' # pin net-http-persistent; 3.x is incompatible with faraday 0.12
gem 'druid-tools'
gem 'lyber-core', '~> 4.0'
gem 'moab-versioning', '~> 2.0'
gem 'robot-controller', '~> 2.0'
gem 'sdr-replication', '~> 1.0'

group :development do
  gem 'awesome_print'
end

group :test do
  gem 'equivalent-xml'
  gem 'fakeweb'
  gem 'rspec', '~> 3.0'
  gem 'simplecov', require: false
  gem 'coveralls', require: false
end

# Do not place the capistrano-related gems in the default or development bundle group
# Otherwise a Bundle.require command might try to load them
# leading to failure because these gem's rake task files use capistrano DSL.
group :deployment do
  # Use Capistrano for deployment
  gem 'capistrano', '~> 3.1'
  gem 'capistrano-bundler', '~> 1.1'
  gem 'capistrano-rvm', '~> 0.1'
  gem 'dlss-capistrano', '~> 3.0'
end
