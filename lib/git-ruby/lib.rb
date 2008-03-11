require 'tempfile'

module GitRuby
  
  class GitRubyExecuteError < StandardError 
  end
  
  class Lib
      
    @git_dir = nil
    @git_index = nil
    @git_work_dir = nil
    @path = nil
    
    @logger = nil
    @raw_repo = nil
    
    def initialize(base = nil, logger = nil)
      if base.is_a?(GitRuby::Base)
        @git_dir = base.repo.path
        @git_work_dir = base.dir.path if base.dir
        @git_index = base.index if base.index
      elsif base.is_a?(Hash)
        @git_dir = base[:repository]
        @git_index = base[:index] 
        @git_work_dir = base[:working_directory]
      end
      if logger
        @logger = logger
      end
    end    
    
    ## READ COMMANDS ##
        
    def process_commit_data(data, sha = nil)
      in_message = false
            
      if sha
        hsh = {'sha' => sha, 'message' => '', 'parent' => []}
      else
        hsh_array = []        
      end
    
      data.each do |line|
        line = line.chomp
        if in_message && line != ''
          hsh['message'] += line + "\n"
        end

        if (line != '') && !in_message
          data = line.split
          key = data.shift
          value = data.join(' ')
          if key == 'commit'
            sha = value
            hsh_array << hsh if hsh
            hsh = {'sha' => sha, 'message' => '', 'parent' => []}
          end
          if key == 'parent'
            hsh[key] << value
          else
            hsh[key] = value
          end
        elsif in_message && line == ''
          in_message = false
        else
          in_message = true
        end
      end
      
      if hsh_array
        hsh_array << hsh if hsh
        hsh_array
      else
        hsh
      end
    end

    def full_log_commits(opts = {})
      # can do this in pure ruby
      sha = revparse(opts[:object] || branch_current || 'master')
      count = opts[:count] || 30
      
      if /\w{40}$/.match(sha)  # valid sha
        repo = get_raw_repo
        return process_commit_data(repo.log(sha, count))
      end
    end
    
    def revparse(string)
      if /\w{40}/.match(string)  # passing in a sha - just no-op it
        return string
      end
            
      head = File.join(@git_dir, 'refs', 'heads', string)
      return File.read(head).chomp if File.file?(head)

      head = File.join(@git_dir, 'refs', 'remotes', string)
      return File.read(head).chomp if File.file?(head)
      
      head = File.join(@git_dir, 'refs', 'tags', string)
      return File.read(head).chomp if File.file?(head)
      
      ## !! more !!
      
      return string
    end
    
    def get_raw_repo
      @raw_repo ||= GitRuby::Raw::Repository.new(@git_dir)
    end
    
    # returns useful array of raw commit object data
    def commit_data(sha)
      sha = sha.to_s
      cdata = get_raw_repo.cat_file(revparse(sha))
      process_commit_data(cdata, sha)
    end
    
    # !! how do I handle symlinks and other weird files?
    def add(file)
      # add file to object db
      return false if !File.exists?(file)
      return false if !File.file?(file)
            
      sha = get_raw_repo.put_raw_object(File.read(file), 'blob')
      
      # add it to the index
      @git_index.add(file, sha)
    end
    
    def write_tree_contents(tree_contents)
      get_raw_repo.put_raw_object(tree_contents, 'tree')
    end
    
    # tree 48bbf0db7e813affab7d8dd2842b8455ff9876be
    # parent 935badc874edd62a8629aaf103418092c73f0a56
    # author scott Chacon <schacon@agadorsparticus.(none)> 1194720731 -0800
    # committer scott Chacon <schacon@agadorsparticus.(none)> 1194720731 -0800
    # \n
    # message
    def write_commit_info(tree, parents, message)
      contents = []
      contents << ['tree', tree].join(' ')
      parents.each do |p|
        contents << ['parent', p].join(' ')
      end

      name = config_get('user.name')
      email = config_get('user.email')
      author_string = "#{name} <#{email}> #{Time.now.to_i} #{formatted_offset}"
      contents << ['author', author_string].join(' ')
      contents << ['committer', author_string].join(' ')
      contents << ''
      contents << message
      
      get_raw_repo.put_raw_object(contents.join("\n"), 'commit')      
    end
    
    # File vendor/rails/activesupport/lib/active_support/values/time_zone.rb, line 27
    def formatted_offset
      utc_offset = Time.now.utc_offset
      
      return "" if utc_offset == 0
      sign = (utc_offset < 0 ? -1 : 1)
      hours = utc_offset.abs / 3600
      minutes = (utc_offset.abs % 3600) / 60
      "%+03d%s%02d" % [ hours * sign, '', minutes ]
    end
    private :formatted_offset
    
    def update_ref(ref, sha)
      ref_file = File.join(@git_dir, ref)
      return false if !File.exists?(ref_file)
      
      File.open(ref_file, 'w') do |f|
        f.write sha
      end
    end
    
    def commit(message)
      @git_index.commit(message)
    end
    
    def object_contents(sha)
      get_raw_repo.cat_file(revparse(sha)).chomp
    end

    def ls_tree(sha)
      data = {'blob' => {}, 'tree' => {}}
      
      get_raw_repo.object(revparse(sha)).entry.each do |e|
        data[e.format_type][e.name] = {:mode => e.format_mode, :sha => e.sha1}
      end
              
      data
    end

    def branches_all
      head = File.read(File.join(@git_dir, 'HEAD'))
      arr = []
      
      if m = /ref: refs\/heads\/(.*)/.match(head)
        current = m[1]
      end
      arr += list_files('heads').map { |f| [f, f == current] }
      arr += list_files('remotes').map { |f| [f, false] } rescue nil
            
      arr
    end

    def list_files(ref_dir)
      dir = File.join(@git_dir, 'refs', ref_dir)
      files = nil
      Dir.chdir(dir) { files = Dir.glob('**/*').select { |f| File.file?(f) } }
      files
    end
    
    def branch_current
      branches_all.select { |b| b[1] }.first[0] rescue nil
    end

    def config_remote(name)
      hsh = {}
      config_list.each do |key, value|
        if /remote.#{name}/.match(key)
          hsh[key.gsub("remote.#{name}.", '')] = value
        end
      end
      hsh
    end

    def config_get(name)
      c = config_list
      c[name]
    end
    
    def config_list
      config = {}
      config.merge!(parse_config('~/.gitconfig'))
      config.merge!(parse_config(File.join(@git_dir, 'config')))
    end
    
    def parse_config(file)
      hsh = {}
      file = File.expand_path(file)
      if File.file?(file)
        current_section = nil
        File.readlines(file).each do |line|
          if m = /\[(\w+)\]/.match(line)
            current_section = m[1]
          elsif m = /\[(\w+?) "(.*?)"\]/.match(line)
            current_section = "#{m[1]}.#{m[2]}"
          elsif m = /(\w+?) = (.*)/.match(line)
            key = "#{current_section}.#{m[1]}"
            hsh[key] = m[2] 
          end
        end
      end
      hsh
    end
    
    def tags
      tag_dir = File.join(@git_dir, 'refs', 'tags')
      tags = []
      Dir.chdir(tag_dir) { tags = Dir.glob('*') }
      return tags
    end
        
  end
end
