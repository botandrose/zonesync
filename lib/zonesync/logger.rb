require "logger"
require "fileutils"

class Logger
  def self.log method, args, dry_run: false
    loggers = [::Logger.new(STDOUT)]

    if !dry_run
      FileUtils.mkdir_p("log")
      loggers << ::Logger.new("log/zonesync.log")
    end

    loggers.each do |logger|
      operation = case args
      when Array
        (args.length == 2 ? "\n" : "") +
          args.map { |r| r.to_h.values.join(" ") }.join("->\n")
      else
        args.to_h.values.join(" ")
      end
      logger.info "Zonesync: #{method.capitalize} #{operation}"
    end
  end
end
