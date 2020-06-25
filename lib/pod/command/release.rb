module Pod
  class Command
    class Release < Command
      self.summary = 'Release podspecs in current directory'

      def execute(command, options = {})
        options = { :optional => false }.merge options

        puts "#{"==>".magenta} #{command}"
        abort unless (system(command) || options[:optional])
      end

      self.arguments = [
        CLAide::Argument.new('repository', false),
      ]

      def self.options
        [
          ['--skip-lint', 'Skip linting'],
          ['--allow-warnings', 'Allows push even if there are lint warnings'],
          ['--carthage', 'Validates project for carthage deployment'],
          ['--reverse', 'Validates and pushes podspecs in reverse order'],
          ['--verbose', 'Show more debugging information'],
          ['--use-modular-headers', 'allow enabling modular headers for static libraries']
        ].concat(super.reject { |option, _| option == '--silent' })
      end

      def initialize(argv)
        warnings = argv.flag?('allow-warnings')
        @allow_warnings = warnings ? "--allow-warnings" : ""
        @repo = argv.shift_argument unless argv.arguments.empty?
        @carthage = argv.flag?('carthage')
        @reverse = argv.flag?('reverse')
        @verbose = argv.flag?('verbose') ? "--verbose" : ""
        @use_libraries = argv.flag?('use-libraries') ? "--use-libraries" : ""
        @skip_lint = argv.flag?('skip-lint')
        @use_modular_headers = argv.flag?('use-modular-headers') ? "--use-modular-headers": ""
        super
      end

      def run
        specs = Dir.entries(".").select { |s| s.end_with? ".podspec" }
        abort "No podspec found" unless specs.count > 0

        specs = specs.reverse if @reverse

        sources_manager = if defined?(Pod::SourcesManager)
            Pod::SourcesManager
          else
            config.sources_manager
          end
        
        puts "#{"==>".magenta} updating repositories"
        sources_manager.update

        for spec in specs
          name = spec.gsub(".podspec", "")
          version = Specification.from_file(spec).version
          name = Specification.from_file(spec).name

          #sources = sources_manager.all.select { |r| r.name == "master" || r.url.start_with?("git") }
          sources = sources_manager.all
          sources = sources.select { |s| s.name == @repo } if @repo

          pushed_sources = []
          available_sources = sources_manager.all.map { |r| r.name }

          abort "Please run #{"pod install".green} to continue" if sources.count == 0
          for source in sources
            pushed_versions = source.versions(name)
            next unless pushed_versions

            pushed_sources << source
            pushed_versions = pushed_versions.collect { |v| v.to_s }
            abort "#{name} (#{version}) has already been pushed to #{source.name}".red if pushed_versions.include? version.to_s
          end

          repo_unspecified = pushed_sources.count == 0 && sources.count > 1
          if repo_unspecified
            puts "When pushing a new podspec, please specify a repository to push #{name} to:"
            puts ""
            for source in sources
              puts "  * pod release #{source.name}"
            end
            puts ""
            abort
          end

          if pushed_sources.count > 1
            puts "#{name} has already been pushed to #{pushed_sources.join(', ')}. Please specify a repository to push #{name} to:"
            puts ""
            for source in sources
              puts "  * pod release #{source.name}"
            end
            puts ""
            abort
          end

          if !@skip_lint
            # verify lib
            execute "pod lib lint #{spec} #{@use_libraries} #{@allow_warnings} #{@use_modular_headers} --sources=#{available_sources.join(',')}"
          end

          if @carthage
            execute "carthage build --no-skip-current"
          end

          # Create git tag for current version
          puts "#{"==>".magenta} Tagging repository with version #{"#{version}".green}"

          unless system("git tag | grep -x #{version} > /dev/null")
            execute "git pull"
            execute "git tag #{version} -f"
            execute "git push && git push --tags"
          end

          repo = @repo || pushed_sources.first
          if repo == "master"
            execute "pod trunk push #{spec} #{@allow_warnings} #{@use_modular_headers} --verbose"
          else
            execute "pod repo push #{repo} #{spec} #{@allow_warnings} #{@use_modular_headers} --verbose"
          end

          if @carthage && `git remote show origin`.include?("github.com")
            execute "carthage archive #{name}"

            user, repo = /(\w*)\/(\w*).git$/.match(`git remote show origin`)[1, 2]
            file = "#{name}.framework.zip"

            create_release = %(github-release release --user #{user} --repo #{repo} --tag #{version} --name "Version #{version}" --description "Release of version #{version}")
            upload_release = %(github-release upload --user #{user} --repo #{repo} --tag #{version} --name "#{file}" --file "#{file}")

            if ENV['GITHUB_TOKEN'] && system("which github-release")
              execute create_release
              execute upload_release
              execute "rm #{file}"
            else
              puts "Run `#{create_release} --security-token XXX` to create a github release and"
              puts "    `#{upload_release} --security-token XXX` to upload to github releases"
            end
          end
        end
      end
    end
  end
end
