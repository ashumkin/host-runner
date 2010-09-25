#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'defaultDriver.rb'

class CmdLine < OptionParser
    attr_reader :options

    def initialize
        super
        @options = OpenStruct.new
        @options.url = ""
        @options.ext = ".out.srt"
        @options.user = ""
        @options.pass = ""
        @options.debug = false
        @options.type = nil

        banner = "Usage: subtitles.rb [options]"

        separator ""
        separator "Options:"

        parseargs(ARGV)
        parse!(ARGV)
        validate
    end

    def parseargs(args)
        # Mandatory argument.
        on("-s", "--server URL",
                "Issue tracker API") do |s|
            @options.url = s.strip
        end

         # Optional argument; multi-line description.
        on("-u", "--user [USER]",
                "Username") do |user|
            @options.user = user
        end

        on("-p", "--pass[word] [USER]",
                "Username") do |user|
            @options.user = user
        end

        on("-d", "--debug",
                "Turns on debug mode") do |debug|
            @options.debug = true
        end

        on("-t", "--type [mantis,bz]",
                "Type of issue tracker (Bugzilla, Mantis) (For now Mantis is  only supported)") do |type|
            @options.type = type.to_sym
            @options.type = :mantis
        end

        # No argument, shows at tail.  This will print an options summary.
        # Try it and see!
        on_tail("-h", "--help", "Show this message") do
            puts self
            exit
        end

    end  # parseargs()

    def validate
        raise "Issue tracker URL is not defined!" if @options.url.empty?
    end
end

cmdLine = CmdLine.new

obj = MantisConnectPortType.new(cmdLine.options.url)
obj.wiredump_dev = STDERR if $DEBUG
puts "Server API version is #{obj.mc_version}"
p obj.mc_projects_get_user_accessible(cmdLine.options.user, cmdLine.options.password)

__END__
