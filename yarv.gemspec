# frozen_string_literal: true

require_relative "lib/yarv/version"

Gem::Specification.new do |spec|
  spec.name = "yarv"
  spec.version = YARV::VERSION
  spec.authors = ["Kevin Newton"]
  spec.email = ["kddnewton@gmail.com"]

  spec.summary = "The YARV virtual machine, in Ruby"
  spec.homepage = "https://github.com/kddnewton/yarv"
  spec.license = "MIT"
  spec.metadata = { "rubygems_mfa_required" => "true" }

  spec.files =
    Dir.chdir(__dir__) do
      `git ls-files -z`.split("\x0")
        .reject { |f| f.match(%r{^(test|spec|features)/}) }
    end

  spec.required_ruby_version = ">= 2.7.0"

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = %w[lib]
end
