module GitRuby
  class Repository < Path
    
    # initialize a git repository
    def self.init(dir, bare = false)
      puts 'init' + dir
      
      FileUtils.mkdir_p(dir) if !File.exists?(dir)
      
      FileUtils.cd(dir) do
        if(File.exists?('objects'))
          return false # already initialized
        else
          # initialize directory
          create_initial_config(bare)
          FileUtils.mkdir_p('refs/heads')
          FileUtils.mkdir_p('refs/tags')
          FileUtils.mkdir_p('objects/info')
          FileUtils.mkdir_p('objects/pack')
          FileUtils.mkdir_p('branches')
          add_file('description', 'Unnamed repository; edit this file to name it for gitweb.')
          add_file('HEAD', "ref: refs/heads/master\n")
          FileUtils.mkdir_p('hooks')
          FileUtils.cd('hooks') do
            add_file('applypatch-msg', '# add shell script and make executable to enable')
            add_file('post-commit', '# add shell script and make executable to enable')
            add_file('post-receive', '# add shell script and make executable to enable')
            add_file('post-update', '# add shell script and make executable to enable')
            add_file('pre-applypatch', '# add shell script and make executable to enable')
            add_file('pre-commit', '# add shell script and make executable to enable')
            add_file('pre-rebase', '# add shell script and make executable to enable')
            add_file('update', '# add shell script and make executable to enable')
          end
          FileUtils.mkdir_p('info')
          add_file('info/exclude', "# *.[oa]\n# *~")
        end
      end
    end
    
    private

    def self.create_initial_config(bare = false)
      bare ? bare_status = 'true' : bare_status = 'false'
      config = "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = #{bare_status}\n\tlogallrefupdates = true"
      add_file('config', config)
    end
      
    def self.add_file(name, contents)
      File.open(name, 'w') do |f|
        f.write contents
      end
    end
    
    
  end
end
