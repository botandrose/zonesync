# frozen_string_literal: true

require "logger"
require "fileutils"

module Zonesync
  class Logger
    def self.log(method, records, dry_run: false)
      loggers = [::Logger.new(STDOUT)]

      if !dry_run
        FileUtils.mkdir_p("log")
        loggers << ::Logger.new("log/zonesync.log")
      end

      loggers.each do |logger|
        operation =
          (records.length == 2 ? "\n" : "") +
          records.map { |r| r.to_h.values.join(" ") }.join("->\n")
        logger.info "Zonesync: #{method.capitalize} #{operation}"
      end
    end
  end
end
