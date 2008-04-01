require 'tempfile'
require 'net/https'

module GitRuby
  
  class GitRubyInvalidTransport < StandardError; end
  
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
    
    
    # tries to clone the given repo
    #
    # returns {:repository} (if bare)
    #         {:working_directory} otherwise
    #
    # accepts options:
    #  :remote - name of remote (rather than 'origin')
    #  :bare   - no working directory
    # 
    # TODO - make this work with SSH password or auth_key
    #
    def clone(repository, name, opts = {})
      @path = opts[:path] || '.'
      opts[:path] ? clone_dir = File.join(@path, name) : clone_dir = name

      working_dir = clone_dir

      # initialize repository
      if(!opts[:bare])
        clone_dir += '/.git'
      end
            
      GitRuby::Repository.init(clone_dir, opts[:bare])
      @git_dir = File.expand_path(clone_dir)
      
      remote_name = opts[:remote] || 'origin'
      
      if branch = fetch(repository, remote_name)
        # create a local branch 
        update_ref("refs/heads/#{branch}", revparse("#{remote_name}/#{branch}"))
        if !opts[:bare]
          Dir.chdir(working_dir) do
            dumb_checkout(branch)
          end
        end
      end
            
      if opts[:bare]
        return {:repository => clone_dir}
      else
        return {:working_directory => working_dir}
      end
    end
    
    def checkout(branch)
      if branch == branch_current
        puts 'already on branch!'
      end
      @git_index.checkout("refs/heads/#{branch}")
    end
    
    # does a dumb checkout - copies the tree pointed to by the branch
    # to the current directory - used by clone, and possibly at some point
    # archive will use this too
    def dumb_checkout(branch)
      sha = revparse(branch)
      commit = commit_data(sha)
      tree_sha = commit['tree']
      dumb_checkout_tree(tree_sha, '.')
    end
    
    def dumb_checkout_tree(tree_sha, dir)
      FileUtils.mkdir_p(dir)
      tree = ls_tree(tree_sha)
      tree['blob'].each do |file, blob|
        f = File.join(dir, file)
        write_file(f, object_contents(blob[:sha]))
      end
      tree['tree'].each do |subdir, subtree|
        dumb_checkout_tree(subtree[:sha], subdir)
      end
    end
    
    def fetch(repository, remote_name)
      # look at #{repository} for http://, user@, git://
      if repository =~ /^http:\/\//
        # http fetch
        return fetch_over_http(repository, false, remote_name)
      elsif repository =~ /^https:\/\//
        # https fetch
        return fetch_over_http(repository, true, remote_name)
      elsif repository =~ /^git:\/\//
        # git fetch
        raise GitRubyInvalidTransport('transport git:// not yet supported') 
      else
        raise GitRubyInvalidTransport('unknown transport - can only do http/s right now') 
      end
    end
    
    # implements cloning a repository over http/s
    # meant to be called 
    def fetch_over_http(repo_url, use_ssl, remote_name)
      # refs : 909e4d4f706c11cafbe35fd9729dc6cce24d6d6f        refs/heads/master
      # packs: P pack-8607f42392be437e8f46408898de44948ccd357f.pack
      
      success = true
      
      Dir.chdir(@git_dir) do
        # fetch (url)/info/refs
        log('fetching server refs')
        refs = Net::HTTP.get(URI.parse("#{repo_url}/info/refs"))        
        fetch_refs = map_refs(refs)

        # fetch (url)/HEAD, write as FETCH_HEAD
        log('fetching remote HEAD')
        remote_head = Net::HTTP.get(URI.parse("#{repo_url}/HEAD"))
        if !(remote_head =~ /^ref: refs\//)
          fetch_refs[remote_head] = false
        else
          success = remote_head.sub('ref: refs/heads/', '').strip
        end

        fetch_refs.each do |sha, ref|
          log("fetching REF : #{ref} #{sha}")
          if http_fetch(repo_url, sha, 'commit')
            update_ref("refs/remotes/#{remote_name}/#{ref}", sha) if ref
          else
            success = false
          end
        end
      end
      
      success
    end
    
    def map_refs(refs)
      # process the refs file
      # get a list of all the refs/heads/
      fetch_refs = {}
      refs.split("\n").each do |ref|
        if ref =~ /refs\/heads/
          sha, head = ref.split("\t")
          head = head.sub('refs/heads/', '').strip
          fetch_refs[sha] = head
        end
      end
      fetch_refs
    end

    def http_fetch(url, sha, type)
      # fetch from server objects/sh/a1value
      dir = sha[0...2]
      obj = sha[2..40]
      
      path = File.join('objects', dir)
      
      if !get_raw_repo.object_exists?(sha)
        res = Net::HTTP.get_response(URI.parse("#{url}/objects/#{dir}/#{obj}"))
        if res.kind_of?(Net::HTTPSuccess)
          Dir.mkdir(path) if !File.directory?(path)
          write_file(File.join('objects', dir, obj), res.body)
          log("#{type} : #{sha} fetched")
        else
          # file may be packed - get the packfiles if we haven't already and lets try those
          res = Net::HTTP.get_response(URI.parse("#{url}/objects/info/packs"))
          if res.kind_of?(Net::HTTPSuccess)
            # fetch packs we don't have, look for it there  
            # !! todo - look for packfile with our sha in it !!          
            res.body.split("\n").each do |packline|
              pack_type, pack_file = packline.split(' ')
              pack_index = pack_file.sub('.pack', '.idx')
              
              # download this index
              index = Net::HTTP.get(URI.parse("#{url}/objects/pack/#{pack_index}"))
              write_file(File.join('objects', 'pack', pack_index), index)
              
              packf = Net::HTTP.get(URI.parse("#{url}/objects/pack/#{pack_file}"))
              write_file(File.join('objects', 'pack', pack_file), packf)              
            end
            if !get_raw_repo.object_exists?(sha)
              # cannot get the pack info
              puts "NOT IN PACKS" + sha
              return false
            end
          else
            # cannot get the pack info
            puts "FAIL PACK" + res.to_s
            return false
          end
        end
      end
      
      response = true
      
      case type
      when 'commit':
        # if it's a commit, walk the tree, then get it's parents
        commit = commit_data(sha)
        log('walking ' + commit['tree'])
        http_fetch(url, commit['tree'], 'tree')
        commit['parent'].each do |parent|
          log('walking ' + parent)
          response &&= http_fetch(url, parent, 'commit')
        end
      when 'tree':
        data = ls_tree(sha)
        data['blob'].each do |key, blob|
          response &&= http_fetch(url, blob[:sha], 'blob')          
        end
        data['tree'].each do |key, tree|
          response &&= http_fetch(url, tree[:sha], 'tree')          
        end
      end
      
      response
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
      
      ## !! check packed-refs file, too !! 
      ## !! more - partials and such !!
      
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
        contents << ['parent', p].join(' ') if p        
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
      if(!File.exists?(ref_file))
        FileUtils.mkdir_p(File.dirname(ref_file)) rescue nil
      end
      File.open(ref_file, 'w') do |f|
        f.write sha
      end
    end
    
    def commit(message)
      @git_index.commit(message)
    end
    
    def object_contents(sha)
      get_raw_repo.cat_file(revparse(sha))
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
      # !! TODO : check packed-refs file, too !!
      
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
    
    def log(message)
      @logger.info(message) if @logger
    end
    
    def write_file(name, contents)
      File.open(name, 'w') do |f|
        f.write contents
      end
    end
        
  end
end
