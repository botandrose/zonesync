# frozen_string_literal: true

require_relative "lib/zonesync/version"

Gem::Specification.new do |spec|
  spec.name          = "zonesync"
  spec.version       = Zonesync::VERSION
  spec.authors       = ["Micah Geisel", "James Ottaway"]
  spec.email         = ["micah@botandrose.com", "git@james.ottaway.io"]

  spec.summary       = %q{Sync your Zone file with your DNS host}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/botandrose/zonesync"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "diff-lcs", "~>1.4"
  spec.add_dependency "thor", "~>1.0"
  spec.add_dependency "treetop", "~>1.6"
  spec.add_dependency "sorbet-runtime"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "sorbet"
  spec.add_development_dependency "tapioca"
end
