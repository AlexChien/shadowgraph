set :stages, %w(old production)
set :default_stage, "production"
require 'capistrano/ext/multistage'
