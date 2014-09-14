require 'thor'
require 'envied/env_var_extractor'

class ENVied
  class Cli < Thor
    include Thor::Actions
    source_root File.expand_path('../templates', __FILE__)

    desc "--version", "Shows version number"
    def version
      puts ENVied::VERSION
    end
    map %w(-v --version) => :version

    desc "extract", "Grep code to find ENV-variables"
    long_desc <<-LONG
      Greps source-files to find all ENV-variables your code is using.

      This task helps you find potential variables to put in your Envfile.

      By default the test/spec-folders are excluded. Use `--tests` to include them.
    LONG
    option :globs, type: :array, default: ENVied::EnvVarExtractor.defaults[:globs], banner: "*.* lib/*"
    option :tests, type: :boolean, default: false, desc: "include tests/specs"
    def extract
      globs = options[:globs]
      globs << "{test,spec}/*" if options[:tests]
      var_occurences = ENVied::EnvVarExtractor.new(globs: globs).extract

      puts "Found %d occurrences of %d variables:" % [var_occurences.values.flatten.size, var_occurences.size]
      var_occurences.sort.each do |var, occs|
        puts var
        occs.sort_by{|i| i[:path].size }.each do |occ|
          puts "* %s:%s" % occ.values_at(:path, :line)
        end
        puts
      end
    end

    desc "init", "Generates a default Envfile in the current working directory"
    def init
      puts "Writing Envfile to #{File.expand_path('Envfile')}"
      template("Envfile.tt")

      puts <<-INIT
Add the following snippet to your app so it's run during initialization:
ENVied.require(*ENV['ENVIED_GROUPS'] || [:default, ENV['RACK_ENV']])
INIT
    end

    desc "init:rails", "Generate all files needed for a Rails project"
    define_method "init:rails" do
      puts "Writing Envfile to #{File.expand_path('Envfile')}"
      template("Envfile.tt")

      template("rails-initializer.tt", 'config/initializers/envied.rb')
    end

    desc "check", "Checks whether you environment contains required variables"
    long_desc <<-LONG
      Checks whether required variables are present and valid in your shell.

      On success the process will exit with status 0.
      Else the missing/invalid variables will be shown, and the process will exit with status 1.
    LONG
    option :groups, type: :array, default: %w(default), banner: 'default production'
    def check
      ENVied.require(*options[:groups])
      puts "All variables for group(s) #{options[:groups]} are present and valid"
    end

    desc "check:heroku", "Checks whether a Heroku config contains required variables"

    long_desc <<-LONG
      Checks the config of your Heroku app against the local Envfile.

      The Heroku config should be piped to this task:

      heroku config | bundle exec envied check:heroku

      It's more convenient to generate a shell script using the check:heroku:binstub-task.

      On success the process will exit with status 0.
      Else the missing/invalid variables will be shown, and the process will exit with status 1.
    LONG
    option :groups, type: :array, default: %w(default production), banner: 'default production'
    define_method "check:heroku" do
      if STDIN.tty?
        error <<-ERR
Please pipe the contents of `heroku config` to this task.
I.e. `heroku config | bundle exec envied check:heroku`"
ERR
        exit 1
      end
      config = STDIN.read
      heroku_env = Hash[config.split("\n")[1..-1].each_with_object([]) do |i, res|
        res << i.split(":", 2).map(&:strip)
      end]
      ENV.replace({}).update(heroku_env)
      ENVied.require(*options[:groups])
      puts "All variables for group(s) #{options[:groups]} are present and valid in your Heroku app"
    end

    desc "check:heroku:binstub", "Generates a shell script for the check:heroku-task"
    long_desc <<-LONG
      Generates a shell script to check the Heroku config against the local Envfile.

      The same as the check:heroku-task, but all in one script (no need to pipe `heroku config` to it etc.).

    LONG
    option :dest, banner: "where to put the script", default: 'bin/heroku-env-check'
    option :app, banner: "name of Heroku app"
    option :groups, type: :array, default: %w(default production), banner: 'default production'
    define_method "check:heroku:binstub" do
      require 'fileutils'
      @app = options[:app]
      @dest = @app ? File.join(*%W(bin #{@app}-env-check)) : options[:dest]
      @groups = options[:groups]
      full_dest = File.expand_path(@dest)
      template("heroku-env-check.tt", full_dest)
      FileUtils.chmod 0755, full_dest
    end
  end
end
