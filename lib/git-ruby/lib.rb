require 'tempfile'

module GitRuby
  
  class GitRubyExecuteError < StandardError 
  end
  
  class Lib
      
    @git_dir = nil
    @git_index_file = nil
    @git_work_dir = nil
    @path = nil
    
    @logger = nil
    @raw_repo = nil
    
    def initialize(base = nil, logger = nil)
      if base.is_a?(GitRuby::Base)
        @git_dir = base.repo.path
        @git_index_file = base.index.path if base.index
        @git_work_dir = base.dir.path if base.dir
      elsif base.is_a?(Hash)
        @git_dir = base[:repository]
        @git_index_file = base[:index] 
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
      
      ## more
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
    
    def object_contents(sha)
      #command('cat-file', ['-p', sha])
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
      arr += list_files('remotes').map { |f| [f, false] }
            
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
      #command('config', ['--get', name])
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
