#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'defaultDriver.rb'
require 'iconv'

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

        on("-e", "--compname",
                "Use computer name to authenticate") do |comp|
            if comp
                comp = `hostname`.chomp
                @options.user = comp
                @options.password = comp
            end
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

class MantisTask
    attr_reader :task, :out, :exit_code

    def initialize(parent, mantis_task)
        @parent = parent
        @task = mantis_task
        @out = nil
        @exit_code = nil
    end

    def run
        @cmd = @task.summary.to_s + ' ' + @task.description.to_s
        p @cmd
        if @task.category.casecmp("run-no-wait")
            @out = `#{@cmd}`
            @exit_code = $?
        end
    end

    def save
        @task.resolution.id, @task.resolution.name = @parent.fixed[:id], @parent.fixed[:name]
        @task.status.id, @task.status.name = @parent.resolved[:id], @parent.resolved[:name]
        p @task
        @parent.save_task(self)
    end
end

class Mantis
    SUPPORTED_API_VERSION = '1.2.3'
    attr_reader :resolved, :fixed
    
    def initialize(cmdLine)
        @obj = MantisConnectPortType.new(cmdLine.options.url)
        @user = cmdLine.options.user
        @pass = cmdLine.options.password
        
        @obj.wiredump_dev = STDERR if $DEBUG
        
        check_version
        get_status_resolved
        get_resolution_resolved
        get_runner_project
        get_new_tasks
    end

    def check_version
        api_version = @obj.mc_version
        puts "Server API version is #{api_version}"
        if api_version > SUPPORTED_API_VERSION
            puts "OK. Supported"
        end
    end

    def get_status_resolved
        statuses = @obj.mc_enum_status(@user, @pass)
        p statuses
        statuses.each do |s|
            if s.name.casecmp("resolved") == 0
                @resolved = {:id => s.id, :name => "resolved"}
                return
            end
        end
        raise 'Resolution "resolved" not found!'
    end

    def get_resolution_resolved
        resolutions = @obj.mc_enum_resolutions(@user, @pass)
        p resolutions
        resolutions.each do |r|
            if r.name.casecmp("fixed") == 0
                @fixed = {:id => r.id, :name => "fixed"}
                return
            end
        end
        raise 'Resolution "fixed" not found!'
    end

    def get_runner_project
        projects = @obj.mc_projects_get_user_accessible(@user, @pass)
        @prj_id = find_runner_project_id(projects)
    end

    def find_runner_project_id(projects)
        projects.each do |p|
            if p.name.casecmp('Runner') == 0
                puts "Found! #{p.id}"
                return p.id
            end
            raise 'Project "Runner" not found'
        end
    end

    def get_new_tasks
        @tasks = @obj.mc_project_get_issues(@user, @pass, @prj_id, nil, nil)
    end

    def list_tasks
        @tasks = filter_new_tasks(@tasks)
    end

    def filter_new_tasks(tasks)
        r = []
        #p tasks
        tasks.each do |t|
            if t.handler \
                    && t.handler.name.casecmp(@user) == 0 \
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
        note.text = Iconv.iconv("UTF-8", "cp1251", task.out)
        @obj.mc_issue_note_add(@user, @pass, task.task.id, note)
        @obj.mc_issue_update(@user, @pass, task.task.id, task.task)
    end
end

cmdLine = CmdLine.new
mantis = Mantis.new(cmdLine)
mantis.list_tasks
mantis.run_tasks

__END__
