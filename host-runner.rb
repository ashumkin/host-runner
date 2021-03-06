#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
cdir = File.dirname(__FILE__)
require cdir + '/defaultDriver.rb'
require 'pp'

class CmdLine < OptionParser
    attr_reader :options

    def initialize(args)
        super
        @options = OpenStruct.new
        @options.url = ""
        @options.user = ""
        @options.pass = ""
        @options.debug = false
        @options.type = nil
        @options.codepage = "cp1251"
		@options.iconvused = false
		unless /^1\.9/.match(RUBY_VERSION)
			require 'iconv'
			@options.iconvused = true
		end

		separator ""

        init
        parse!(args)
        validate
    end

    def set_comp_name_suffix()
        @options.user += '-pc'
        @options.password = @options.user
    end

    def init
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

        on("-p", "--pass[word] [PASSWORD]",
                "Password") do |password|
            @options.password = password
        end

        on("-e", "--compname",
                "Use computer name as username to authenticate") do |e|
            @options.user = `hostname`.chomp if e
        end

        on("-E", "--pc",
                "Use suffix \"-pc\" to username to authenticate") do |suffix|
            set_comp_name_suffix() if suffix
        end

        on("-c", "--down-case",
                "Use downcase") do |down_case|
            if down_case
                p @options
                @options.user.downcase!
                @options.password.downcase!
            end
        end

        on("-d", "--debug",
                "Turns on debug mode") do |debug|
            @options.debug = true
        end

        on("-t", "--type [mantis,bz]",
                "Type of issue tracker (Bugzilla, Mantis) (For now Mantis is only supported)") do |type|
            @options.type = type.to_sym
            @options.type = :mantis
        end

        # No argument, shows at tail.  This will print an options summary.
        # Try it and see!
        on_tail("-h", "--help", "Show this message") do
            puts self
            exit
        end

    end  # init()

    def validate
        raise "Issue tracker URL is not defined!" if @options.url.empty?
    end
end

class MantisTask
    attr_reader :task, :out, :exit_code

    def initialize(parent, mantis_task)
        @parent = parent
        @task = mantis_task
        @out = nil
        @exit_code = nil
    end

    def run
        @cmd = @task.summary.to_s
        @cmd += ' ' + @task.description.to_s
		if @parent.opts.iconvused
			# Iconv must already be loaded in check_login
			@cmd = Iconv.iconv(@parent.opts.codepage, 'UTF-8', @cmd)[0]
		else
			@cmd.encode!('UTF-8', @parent.opts.codepage)
		end
        if @cmd[0,1] == "@"
            puts "multicommand!"
            @cmd = @cmd[1,@cmd.length]
            @commands = @cmd.split(/\r?\n/)
        end
        @commands = [@cmd]
        @out = ""
        if @task.category.casecmp("run")
            @commands.each do |cmd|
                p cmd if @parent.debug
                @out += `#{cmd}`
                @exit_code = $?
                if @exit_code !=0 
                    return @exit_code
                end
            end
        elsif @task.category.casecmp("run-no-wait")
        end
    end

    def save
        @task.resolution.id, @task.resolution.name = @parent.fixed[:id], @parent.fixed[:name]
        @task.status.id, @task.status.name = @parent.resolved[:id], @parent.resolved[:name]
        p @task if $DEBUG
        @parent.save_task(self)
    end
end

class Mantis
    SUPPORTED_API_VERSION = '1.2.3'
    attr_reader :resolved, :fixed, :opts
    
    def initialize(cmdLine)
		@opts = cmdLine.options
        @obj = MantisConnectPortType.new(@opts.url)

        @obj.wiredump_dev = STDERR if $DEBUG
        
        check_version
        puts "Username #{@opts.user}..." if @opts.debug
        get_status_resolved
        get_resolution_resolved
        get_runner_project
        get_new_tasks
    end

    def check_version
        api_version = @obj.mc_version
        puts "Server #{@obj.proxy.endpoint_url}"
        puts "API version is #{api_version}"
        if api_version > SUPPORTED_API_VERSION
            puts "OK. Supported"
        end
    end

    def get_status_resolved
        statuses = @obj.mc_enum_status(@opts.user, @opts.password)
        p statuses if $DEBUG
        statuses.each do |s|
            if s.name.casecmp("resolved") == 0
                @resolved = {:id => s.id, :name => "resolved"}
                return
            end
        end
        raise 'Resolution "resolved" not found!'
    end

    def get_resolution_resolved
        resolutions = @obj.mc_enum_resolutions(@opts.user, @opts.password)
        p resolutions if $DEBUG
        resolutions.each do |r|
            if r.name.casecmp("fixed") == 0
                @fixed = {:id => r.id, :name => "fixed"}
                return
            end
        end
        raise 'Resolution "fixed" not found!'
    end

    def get_runner_project
        projects = @obj.mc_projects_get_user_accessible(@opts.user, @opts.password)
        @prj_id = find_runner_project_id(projects)
    end

    def find_runner_project_id(projects)
        projects.each do |p|
            if p.name.casecmp('Runner') == 0
                puts "Found \"Runner\"! (ID = #{p.id})" if @opts.debug
                return p.id
            end
        end
        raise 'Project "Runner" for user not found'
    end

    def get_new_tasks
        @tasks = @obj.mc_project_get_issues(@opts.user, @opts.password, @prj_id, nil, nil)
    end

    def list_tasks
        @tasks = filter_new_tasks(@tasks)
    end

    def filter_new_tasks(tasks)
        r = []
        #p tasks
        tasks.each do |t|
            if t.handler \
                    && t.handler.name.casecmp(@opts.user) == 0 \
                    && /open/i.match(t.resolution.name)
                r << t
            end
        end
        return r
    end

    def run_tasks
        if @tasks.empty?
            puts "There are no news tasks to execute"
            return 0
        end
        @tasks.map! do |t|
            task = MantisTask.new(self, t)
            task.run
            task.save
        end
    end

    def save_task(task)
        note = IssueNoteData.new()
        note.text = task.out
		if @opts.iconvused
			note.text = Iconv.iconv("UTF-8", @opts.codepage, task.out)
		else
			note.text.encode!('UTF-8', @opts.codepage)
		end
        @obj.mc_issue_note_add(@opts.user, @opts.password, task.task.id, note)
        @obj.mc_issue_update(@opts.user, @opts.password, task.task.id, task.task)
    end
end

cmdLine = CmdLine.new(ARGV.dup)
mantis = Mantis.new(cmdLine)
mantis.list_tasks
mantis.run_tasks

__END__
