require 'pathname'

module RailsCodeHealthFixtures
  ROOT = Pathname.new(File.expand_path('../fixtures/code_samples', __dir__))

  def self.path_for(relative_path)
    path = ROOT.join(relative_path)
    raise ArgumentError, "fixture not found: #{relative_path}" unless path.exist?
    path
  end
end
