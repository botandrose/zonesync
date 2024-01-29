require "logger"
require "fileutils"

class Logger
  def self.log method, args
    stdout = ::Logger.new(STDOUT)

    FileUtils.mkdir_p("log")
    file = ::Logger.new("log/zonesync.log")

    [stdout,file].each do |logger|
      operation = case args
      when Array
        args.map { |h| h.values.join(" ") }.join(" -> ")
      when Hash
        args.values.join(" ")
      else
        raise args.inspect
      end
      logger.info "Zonesync: #{method.capitalize} #{operation}"
    end
  end
end
