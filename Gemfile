source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.6.6'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.0.3'
# Use postgresql as the database for Active Record
gem 'pg', '>= 0.18', '< 2.0'
# Use Puma as the app server
gem 'puma', '~> 4.3'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5'
# Transpile app-like JavaScript. Read more: https://github.com/rails/webpacker
gem 'webpacker', '~> 4.0'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.7'
# Use OAuth to integrate with the main Artemis API
gem 'oauth2'
# Support for ENV variables locally
gem 'dotenv-rails', groups: %w[development test]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.4.2', require: false

gem 'http'
gem 'memoist', '~> 0.16.2'

# Metrc API client
gem 'artemis_api', '~> 0.7.4'
gem 'Metrc', git: 'https://github.com/artemis-ag/Metrc.git'
gem 'ncs_analytics', git: 'https://github.com/artemis-ag/ncs-integration.git'

# Serialization
gem 'jsonapi-rails', '~> 0.4.0' # JSONAPI serialization

gem 'pry'
gem 'sidekiq', '~> 5.2', '>= 5.2.7'
gem 'sidekiq-scheduler', '~> 3.0'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %w[mingw mswin x64_mingw jruby]

gem 'bugsnag', '~> 6.13'

gem 'pmap'

gem 'rest-client'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: %w[mri mingw x64_mingw]
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rails-controller-testing'
  gem 'rspec-rails', '~> 4.0.0.beta2'
  gem 'rubocop'
  gem 'rubocop-performance'
  gem 'rubocop-rails'
  gem 'rubocop-rspec'
  gem 'rubocop-rspec-focused'
end

group :development do
  gem 'guard-rspec', require: false
  gem 'guard-rubocop', '~> 1.3'
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'rb-readline'
  gem 'terminal-notifier'
  gem 'terminal-notifier-guard'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 2.15'
  gem 'ci_reporter'
  gem 'database_cleaner'
  gem 'rspec-activemodel-mocks'
  gem 'rspec-html-matchers', '~> 0.9.1'
  gem 'selenium-webdriver'
  gem 'shoulda-matchers'
  gem 'simplecov'
  gem 'simplecov-console', '~> 0.5.0'
  # Easy installation and use of web drivers to run system tests with browsers
  gem 'webdrivers'
  gem 'webmock'
end
