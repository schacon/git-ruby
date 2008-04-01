module GitRuby
  
  class GitRubyIndexError < StandardError 
  end
  
  # this file implements my imagination of what the index file does.
  # it accomplishes the same basic tasks, but uses it's own index.gitr file
  # rather than the actual git index file because I don't have the strength to 
  # reverse engineer that particular format quite yet.  Perhaps one day.
  class Index
    
    attr_accessor :base, :path, :ref, :last_commit, :files
    
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
    
    def short_sha(sha)
      if sha
        sha[0,8] 
      else
        '        '
      end
    end
    
    def to_s
      scan_working_directory
      outs = []
      outs << ['mode', 'repo    ', 'index   ', 'working ', 'path'].join("\t")
      @files.sort.each do |f, hsh|
        outs << [hsh[:mode_index], short_sha(hsh[:sha_repo]), short_sha(hsh[:sha_index]), short_sha(hsh[:sha_working]), hsh[:path]].join("\t")
      end
      outs.join("\n")
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


    # scans the current working directory to calculate the shas of files that
    # have been changed since the last scan
    # !! TODO : find removed files !!
    def scan_working_directory
      Dir.chdir(@base.dir.path) do
        Dir.glob('**/*') do |file|
          if File.file?(file)
            file = File.join('.', file) if file[0, 1] != '.'
          
            s = File.stat(file)
            mode = sprintf("%o", s.mode)
            mtimesize = s.mtime.to_i.to_s + s.size.to_s

            if @files[file]
              if(@files[file][:working_mtime_size] != mtimesize)
                sha = Raw::Internal::LooseStorage.calculate_sha(File.read(file), 'blob')
                @files[file][:sha_working] = sha
                @files[file][:mode_working] = mode
                @files[file][:working_mtime_size] = mtimesize
              end
            else
              sha = Raw::Internal::LooseStorage.calculate_sha(File.read(file), 'blob')
              @files[file] = {:path => file, :file => File.basename(file), :type => 'blob', 
                              :sha_working => sha, :mode_working => mode, 
                              :working_mtime_size => mtimesize}
            end
          end
        end
      end
    end
    
    # are there any files that are in the index not in the repo
    # or modified in the working directory that are not in the index
    # 
    def clean?
      scan_working_directory
      clean = true
      @files.each do |f, hsh|
        if hsh[:type] == 'blob' && hsh[:sha_index]
          clean &&= ((hsh[:sha_working] == hsh[:sha_index]) && (hsh[:sha_index] == hsh[:sha_repo]))
        end
      end
      clean
    end
    
    # make working directory match the index
    #  (takes a ref : ref/heads/master, ref/remote/origin/master)
    # - make sure the current index is clean
    # - resolve the new sha and read it into a parallel struc
    # -- remove wd files in old not in new
    # -- add index files in new not in old
    # -- overwrite wd files different in indexes
    # - update the HEAD to the new branch ref if 'ref/heads', else set to new sha
    #
    def checkout(ref)
      if clean?
        @old_files = @files.dup
        @old_ref = @ref.dup
        @old_last_commit = @last_commit.dup
        
        Dir.chdir(@base.repo.path) do
          if File.exists?(ref)
            @ref = ref
            @last_commit = File.read(@ref).chomp
            
            @files = {}
            read_commit(@last_commit)
            
            Dir.chdir(@base.dir.path) do
              # -- remove wd files in old not in new
              @old_files.each do |f, hsh|
                if(!@files[f] || !@files[f][:sha_index])
                  File.unlink(f) if File.file?(f)
                  Dir.rmdir(File.dirname(f)) rescue nil
                end
              end

              # -- add index files in new not in old
              # -- overwrite wd files different in indexes
              @files.each do |f, hsh|
                if(!@old_files[f] || (@old_files[f][:sha_index] != hsh[:sha_index]))
                  # put file from repo
                  case hsh[:type]
                  when 'tree'
                    FileUtils.mkdir_p(f)
                  when 'blob'
                    FileUtils.mkdir_p(File.dirname(f))
                    @base.lib.write_file(f, @base.gblob(hsh[:sha_index]).contents)
                  end
                end
              end            
            end # end work in the working dir
            
            # update the HEAD            
            ref = @base.lib.write_file('HEAD', "ref: #{ref}")
            
          else
            puts 'branch does not exist'  
            @files = @old_files
            @ref = @old_ref
            @last_commit = @old_last_commit
            return false
          end
        end
        
      else
        puts 'not clean index'
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
        @files[file][:sha_index] = sha
        @files[file][:mode_index] = mode
      else
        @files[file] = {:path => file, 
                        :file => File.basename(file), 
                        :type => 'blob', 
                        :sha_index => sha, 
                        :mode_index => mode}
      end
      save_index
      sha
    end
    
    def commit(message)
      if clean?
        puts 'no staged files'
        return false
      end
      
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
      scan_working_directory
      @files
    end
    
    def save_index
      File.open(@path, 'w') { |f| Marshal.dump([@files, @ref, @last_commit], f) }
    end
    
  end
end
