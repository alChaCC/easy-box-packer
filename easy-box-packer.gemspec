# coding: utf-8

Gem::Specification.new do |s|
  s.name         = 'easy-box-packer'
  s.version      = '0.4.0'
  s.author       = 'Aloha Chen'
  s.email        = 'y.alohac@gmail.com'
  s.homepage     = 'https://github.com/alChaCC/easy-box-packer'
  s.license      = 'MIT'
  s.summary      = '3D bin-packing with weight limit using first-fit decreasing algorithm and empty maximal spaces'
  s.files        = Dir['LICENSE.txt', 'README.md', 'easy-box-packer.rb']
  s.require_path = '.'
  s.required_ruby_version = '>= 2.7'
  s.metadata     = {
    'source_code_uri' => 'https://github.com/alChaCC/easy-box-packer',
    'rubygems_mfa_required' => 'true'
  }
  s.add_development_dependency 'rspec', '~> 3.13'
end
