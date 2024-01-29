require "rake"

task :zonesync => :environment do
  Zonesync.call
end
