module GitRuby
  
  class GitRubyIndexError < StandardError 
  end
  
  class Index
    
    attr_accessor :base, :path, :ref, :last_commit, :files
    
    # for now, this is done entirely in memory - not writing out a file
    # so until I can duplicate the git index format, path will be ignored
    # for the simple stuff i need to do, pretending we have an index file should be fine
    def initialize(base, path, check_path = false)
      # read in the current HEAD
      if File.extname(path) != '.gitr'
        path += '.gitr'
      end
      
      @base = base
      @path = File.expand_path(path)
      
      if(File.exists?(@path))
        @files, @ref, @last_commit = File.open(@path) { |f| Marshal.load(f) }
      else
        FileUtils.mkdir_p(File.dirname(@path))
        read_head
      end
    end
    
    def read_head
      @files = {}
      FileUtils.cd(@base.repo.path) do
        ref = File.read('HEAD')
        if m = ref.match(/ref: (.*)/)
          @ref = m[1]
          if File.exists?(@ref)
            @last_commit = File.read(@ref).chomp
            read_commit(@last_commit)
          else
            # ref simply does not exist yet - next commit will create it parentless
          end
        else
          raise GitRubyIndexError.new("I don't understand HEAD : #{ref}")
        end
      end
    end

    # read in the commit so we know what in the working directory differs
    def read_commit(commit_sha)
      # find the tree sha and read the tree
      commit = @base.gcommit(commit_sha)
      read_tree_object(commit.gtree)
      save_index
    end
    
    # read the tree into the index
    def read_tree_object(gtree, path = '.')
      gtree.children.each do |file, obj|
        key = File.join(path, file)
        @files[key] = {:path => key, :file => file, :type => obj.type, 
                        :sha_repo => obj.sha, :sha_index => obj.sha,
                        :mode_repo => obj.mode, :mode_index => obj.mode }

        if obj.type == 'tree'
          read_tree_object(obj, key)
        end
      end
    end
    
    def add(file, sha)
      # make sure the file is there
      full_file = File.join(@base.dir.path, file)
      return false if !File.exists?(full_file)

      file = File.join('.', file) if file[0, 1] != '.'

      predir = File.dirname(file)
      if predir != '.'
        this_tree = '.'
        predir.split('/').each do |path|
          if path != '.'
            this_tree = File.join(this_tree, path)
            @files[this_tree] = {:path => this_tree, :file => path, :mode_index => '040000', :type => 'tree'}
          end
        end
      end
      
      s = File.stat(full_file)
      mode = sprintf("%o", s.mode)
      
      if @files[file]
        # update an existing file
        @files[file][:sha_working] = sha
        @files[file][:mode_working] = mode
        
        @files[file][:sha_index] = sha
        @files[file][:mode_index] = mode
      else
        @files[file] = {:path => file, :file => File.basename(file), :type => 'blob', 
                        :sha_working => sha, :sha_index => sha, 
                        :mode_working => mode, :mode_index => mode}
      end
      save_index
      sha
    end
    
    def commit(message)
      # find all the modified files
      dirs = {}
      mods = {}
      
      @files.each do |path, file_hsh|
        tree = File.dirname(path)
        dirs[tree] ||= []
        dirs[tree] << file_hsh

        if file_hsh[:type] == 'blob'
          if (file_hsh[:sha_index] != file_hsh[:sha_repo]) || (file_hsh[:mode_index] != file_hsh[:mode_repo])
            mods[tree] = tree.split('/').size
            
            # go down the tree, adding all the subtrees
            levels = tree.split('/')
            while(new_tree = levels.pop) do
              mods[levels.join('/')] = levels.size if (levels.size > 0)
            end
              
          end
        end
      end
      
      trees = {}
                
      # write new trees
      mods.sort.reverse.each do |mod_tree, depth|
        tree_contents = []
        dirs[mod_tree].each do |f|
          if trees[f[:path]]
            f[:sha_index] = trees[f[:path]]
          end
          sha = [f[:sha_index]].pack("H*")
          str = "%s %s\0%s" % [f[:mode_index], f[:file], sha]
          
          tree_contents << [f[:file], str]
        end
        
        tree_content = tree_contents.sort.map { |h| h[1] }.join('')
        trees[mod_tree] = @base.lib.write_tree_contents(tree_content)
      end
      
      # get new tree ref
      head_tree = trees['.']      
      
      # write commit object
      new_sha = @base.lib.write_commit_info(head_tree, [@last_commit], message)

      # update HEAD ref
      @base.lib.update_ref(@ref, new_sha)
      read_head
    end
        
    def ls_files
      @files
    end
    
    def save_index
      File.open(@path, 'w') { |f| Marshal.dump([@files, @ref, @last_commit], f) }
    end
    
  end
end
