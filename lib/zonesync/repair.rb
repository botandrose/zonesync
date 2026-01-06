# frozen_string_literal: true

module Zonesync
  class Repair
    def initialize(local, remote)
      @local = local
      @remote = remote
      @remote_config = remote.config
    end

    def call(input: $stdin, output: $stdout)
      differences = compute_differences
      if differences.empty?
        output.puts "Already in sync!"
        return
      end

      output.puts "Found #{differences.length} difference#{"s" if differences.length != 1}:\n\n"

      actions = differences.map.with_index do |diff, i|
        display_difference(output, i + 1, diff)
        prompt_action(input, output, diff)
      end

      output.puts
      display_summary(output, actions)

      return unless confirm_apply?(input, output)

      apply_actions(actions)
      update_manifest(output)
      output.puts "\nRepair complete."
    end

    private

    def all_diffable_records(provider)
      # Get all records of diffable types, ignoring manifest filtering
      Record.non_meta(provider.records).select { |r| DIFFABLE_RECORD_TYPES.include?(r.type) }.sort
    end

    def compute_differences
      # For repair, we want ALL records of diffable types, not just those in manifest
      local_records = all_diffable_records(@local)
      remote_records = all_diffable_records(@remote)

      local_by_key = local_records.group_by { |r| [r.name, r.type] }
      remote_by_key = remote_records.group_by { |r| [r.name, r.type] }

      differences = []

      # Records only on remote
      (remote_by_key.keys - local_by_key.keys).each do |key|
        remote_by_key[key].each do |record|
          differences << { type: :remote_only, record: record }
        end
      end

      # Records only on local
      (local_by_key.keys - remote_by_key.keys).each do |key|
        local_by_key[key].each do |record|
          differences << { type: :local_only, record: record }
        end
      end

      # Records in both - check for changes
      (local_by_key.keys & remote_by_key.keys).each do |key|
        local_set = local_by_key[key]
        remote_set = remote_by_key[key]

        if local_set.length == 1 && remote_set.length == 1
          if local_set.first != remote_set.first
            differences << { type: :changed, local: local_set.first, remote: remote_set.first }
          end
        else
          (remote_set - local_set).each { |r| differences << { type: :remote_only, record: r } }
          (local_set - remote_set).each { |r| differences << { type: :local_only, record: r } }
        end
      end

      differences.sort_by { |d| [(d[:record] || d[:local]).name, (d[:record] || d[:local]).type] }
    end

    def display_difference(output, num, diff)
      case diff[:type]
      when :remote_only
        output.puts "#{num}. REMOTE ONLY:"
        output.puts "   #{diff[:record]}"
      when :local_only
        output.puts "#{num}. LOCAL ONLY:"
        output.puts "   #{diff[:record]}"
      when :changed
        output.puts "#{num}. CHANGED:"
        output.puts "   Local:  #{diff[:local]}"
        output.puts "   Remote: #{diff[:remote]}"
      end
      output.puts
    end

    def prompt_action(input, output, diff)
      case diff[:type]
      when :remote_only
        output.print "   [a] Adopt  [d] Delete  [i] Ignore: "
        loop do
          choice = input.gets&.strip&.downcase
          case choice
          when "a" then return { action: :adopt, diff: diff }
          when "d" then return { action: :delete_remote, diff: diff }
          when "i" then return { action: :ignore, diff: diff }
          else output.print "   Invalid. [a/d/i]: "
          end
        end
      when :local_only
        output.print "   [k] Keep (push to remote)  [r] Remove from Zonefile  [i] Ignore: "
        loop do
          choice = input.gets&.strip&.downcase
          case choice
          when "k" then return { action: :keep_local, diff: diff }
          when "r" then return { action: :remove_local, diff: diff }
          when "i" then return { action: :ignore, diff: diff }
          else output.print "   Invalid. [k/r/i]: "
          end
        end
      when :changed
        output.print "   [l] Keep local  [r] Keep remote  [i] Ignore: "
        loop do
          choice = input.gets&.strip&.downcase
          case choice
          when "l" then return { action: :keep_local_changed, diff: diff }
          when "r" then return { action: :keep_remote_changed, diff: diff }
          when "i" then return { action: :ignore, diff: diff }
          else output.print "   Invalid. [l/r/i]: "
          end
        end
      end
    end

    def display_summary(output, actions)
      adopt = actions.count { |a| a[:action] == :adopt }
      delete = actions.count { |a| a[:action] == :delete_remote }
      keep_local = actions.count { |a| a[:action] == :keep_local }
      keep_remote_changed = actions.count { |a| a[:action] == :keep_remote_changed }
      remove_local = actions.count { |a| a[:action] == :remove_local }
      keep_local_changed = actions.count { |a| a[:action] == :keep_local_changed }
      ignore = actions.count { |a| a[:action] == :ignore }

      output.puts "Summary:"
      output.puts "  #{adopt} record#{"s" if adopt != 1} to adopt into Zonefile" if adopt > 0
      output.puts "  #{delete} record#{"s" if delete != 1} to delete from remote" if delete > 0
      output.puts "  #{keep_local} record#{"s" if keep_local != 1} to push to remote" if keep_local > 0
      output.puts "  #{keep_remote_changed} record#{"s" if keep_remote_changed != 1} to pull from remote" if keep_remote_changed > 0
      output.puts "  #{remove_local} record#{"s" if remove_local != 1} to remove from Zonefile" if remove_local > 0
      output.puts "  #{keep_local_changed} local change#{"s" if keep_local_changed != 1} to push to remote" if keep_local_changed > 0
      output.puts "  #{ignore} record#{"s" if ignore != 1} ignored" if ignore > 0
    end

    def confirm_apply?(input, output)
      output.print "\nApply changes? [y/n]: "
      input.gets&.strip&.downcase == "y"
    end

    def update_manifest(output)
      # Re-read both providers to get the updated records
      updated_local = Provider.from({ provider: "Filesystem", path: @local.config.fetch(:path) })
      updated_remote = Provider.from(@remote_config)

      # Generate new manifest based on current local state
      new_manifest = updated_local.manifest.generate

      # Get existing manifest on remote
      existing_manifest = updated_remote.manifest.existing

      if existing_manifest
        if new_manifest != existing_manifest
          output.puts "Updating manifest..."
          updated_remote.change(existing_manifest, new_manifest)
        end
      else
        output.puts "Creating manifest..."
        updated_remote.add(new_manifest)
      end

      # Remove old checksum if present (v2 manifests don't need it)
      if existing_checksum = updated_remote.manifest.existing_checksum
        output.puts "Removing old checksum..."
        updated_remote.remove(existing_checksum)
      end
    end

    def apply_actions(actions)
      zonefile_additions = []
      zonefile_removals = []

      actions.each do |action|
        case action[:action]
        when :adopt
          zonefile_additions << action[:diff][:record]
        when :delete_remote
          @remote.remove(action[:diff][:record])
        when :keep_local
          @remote.add(action[:diff][:record])
        when :remove_local
          zonefile_removals << action[:diff][:record]
        when :keep_local_changed
          @remote.change(action[:diff][:remote], action[:diff][:local])
        when :keep_remote_changed
          zonefile_additions << action[:diff][:remote]
          zonefile_removals << action[:diff][:local]
        end
      end

      if zonefile_additions.any? || zonefile_removals.any?
        update_zonefile(zonefile_additions, zonefile_removals)
      end
    end

    def update_zonefile(additions, removals)
      content = @local.read
      origin = @local.manifest.zone.origin

      # Use treetop parser to find exact character positions of records to remove
      intervals_to_remove = find_record_intervals(content, origin, removals)

      # Remove intervals in reverse order to preserve positions
      intervals_to_remove.sort_by { |i| -i.begin }.each do |interval|
        content = content[0...interval.begin] + content[interval.end..]
      end

      if additions.any?
        content = content.rstrip + "\n\n"
        additions.each do |record|
          short_name = record.short_name(origin)
          line = "#{short_name}  #{record.ttl}  #{record.type}  #{record.rdata}"
          line += "  ; #{record.comment}" if record.comment
          content += "#{line}\n"
        end
      end

      @local.write(content)
    end

    def find_record_intervals(content, origin, removals)
      removal_set = removals.map { |r| [r.name, r.type, r.rdata] }.to_set

      parseable_content, soa_insertion = Zonefile.ensure_soa(content)

      parser = ZonefileParser.new
      result = parser.parse(parseable_content)
      raise Parser::ParsingError, parser.failure_reason unless result

      # Build Zone to get properly qualified record objects
      zone = Parser::Zone.new(result.entries, origin: origin)

      # Pair raw record entries (for intervals) with parser records (for qualified fields)
      raw_entries = result.entries.select { |e| e.parse_type == :record && e.record_type != "SOA" }
      parser_records = zone.records.reject { |r| r.is_a?(Parser::SOA) }

      intervals = []
      raw_entries.zip(parser_records).each do |entry, parser_record|
        record = Record.from_dns_zonefile_record(parser_record)

        if removal_set.include?([record.name, record.type, record.rdata])
          interval = entry.interval
          if soa_insertion && interval.begin >= soa_insertion[:at]
            interval = (interval.begin - soa_insertion[:length])...(interval.end - soa_insertion[:length])
          end
          intervals << interval
        end
      end
      intervals
    end
  end
end
