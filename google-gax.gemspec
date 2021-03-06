# -*- ruby -*-
# encoding: utf-8
$LOAD_PATH.push File.expand_path('../lib', __FILE__)
require 'google/gax/version'

Gem::Specification.new do |s|
  s.name = 'google-gax'
  s.version = Google::Gax::VERSION
  s.authors = ['Google API Authors']
  s.email = 'googleapis-packages@google.com'
  s.homepage = 'https://github.com/googleapis/gax-ruby'
  s.summary = 'Aids the development of APIs for clients and servers based'
  s.summary += ' on GRPC and Google APIs conventions'
  s.description = 'Google API Extensions'
  s.files = %w(Rakefile README.md)
  s.files += Dir.glob('lib/**/*')
  s.files += Dir.glob('spec/**/*')
  s.require_paths = %w(lib)
  s.platform = Gem::Platform::RUBY
  s.license = 'BSD-3-Clause'

  s.required_ruby_version = '>= 2.0.0'

  s.add_dependency 'googleauth', '~> 0.5.1'
  s.add_dependency 'grpc', '~> 1.0'
  s.add_dependency 'googleapis-common-protos', '~> 1.3.1'
  s.add_dependency 'google-protobuf', '~> 3.2'
  s.add_dependency 'rly', '~> 0.2.3'

  s.add_development_dependency 'codecov', '~> 0.1'
  s.add_development_dependency 'rake', '>= 10.0'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'rubocop', '~> 0.32'
  s.add_development_dependency 'simplecov', '~> 0.9'
end
