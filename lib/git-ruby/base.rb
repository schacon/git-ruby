module GitRuby
  
  class Base

    @working_directory = nil
    @repository = nil
    @index = nil

    @lib = nil
    @logger = nil
    
    # opens a bare Git Repository - no working directory options
    def self.bare(git_dir, opts = {})
      default = {:repository => File.expand_path(git_dir)}
      git_options = default.merge(opts)
      
      self.new(git_options)
    end
    
    # opens a new Git Project from a working directory
    # you can specify non-standard git_dir and index file in the options
    def self.open(working_dir, opts={})    
      default = {:working_directory => File.expand_path(working_dir)}
      git_options = default.merge(opts)
      
      self.new(git_options)
    end
    
    # initializes a git repository
    #
    # options:
    #  :repository
    #  :index_file
    #
    def self.init(working_dir, opts = {})
      default = {:working_directory => File.expand_path(working_dir),
                 :repository => File.join(working_dir, '.git')}
      git_options = default.merge(opts)      
      
      if git_options[:working_directory]
        # if !working_dir, make it
        FileUtils.mkdir_p(git_options[:working_directory]) if !File.directory?(git_options[:working_directory])
      end

      if git_options[:working_directory]
        git_options[:repository] = File.join(working_dir, '.git') if !git_options[:repository]
      end
      
      GitRuby::Repository.init(git_options[:repository])
      
      self.new(git_options)
    end    
    
    # clones a git repository locally
    #
    #  repository - http://repo.or.cz/w/sinatra.git
    #  name - sinatra
    #
    # options:
    #   :repository
    #
    #    :bare
    #   or 
    #    :working_directory
    #    :index_file
    #
    def self.clone(repository, name, opts = {})
      # run git-clone 
      self.new(GitRuby::Lib.new(nil, opts[:logger]).clone(repository, name, opts))
    end
    
            
    def initialize(options = {})
      if working_dir = options[:working_directory]
        options[:repository] = File.join(working_dir, '.git') if !options[:repository]
        options[:index] = File.join(working_dir, '.git', 'index') if !options[:index]
      end
      if options[:logger]
        @logger = options[:logger]
        @logger.info("Starting Git")
      end
      
      @working_directory = GitRuby::WorkingDirectory.new(options[:working_directory]) if options[:working_directory]
      @repository = GitRuby::Repository.new(options[:repository]) if options[:repository]
      @index = GitRuby::Index.new(self, options[:index], false) if options[:index]
      @lib = nil
    end
  
    # returns a reference to the working directory
    #  @git.dir.path
    #  @git.dir.writeable?
    def dir
      @working_directory
    end

    # returns reference to the git repository directory
    #  @git.dir.path
    def repo
      @repository
    end
    
    # returns reference to the git index file
    def index
      @index
    end
    
    
    def set_working(work_dir, check = true)
      @lib = nil
      @working_directory = GitRuby::WorkingDirectory.new(work_dir.to_s, check)
    end

    def set_index(index_file, check = true)
      @lib = nil
      @index = GitRuby::Index.new(self, index_file.to_s, check)
    end
    
    # changes current working directory for a block
    # to the git working directory
    #
    # example
    #  @git.chdir do 
    #    # write files
    #    @git.add
    #    @git.commit('message')
    #  end
    def chdir
      Dir.chdir(dir.path) do
        yield dir.path
      end
    end
    
    # returns the repository size in bytes
    # this only works on linux/unix right now (requires 'du' command)
    def repo_size
      size = 0
      Dir.chdir(repo.path) do
        (size, dot) = `du -s`.chomp.split
      end
      size.to_i
    end
    
    # factory methods
    
    # returns a Git::Object of the appropriate type
    # you can also call @git.gtree('tree'), but that's 
    # just for readability.  If you call @git.gtree('HEAD') it will
    # still return a Git::Object::Commit object.  
    #
    # @git.object calls a factory method that will run a rev-parse 
    # on the objectish and determine the type of the object and return 
    # an appropriate object for that type 
    def object(objectish)
      GitRuby::Object.new(self, objectish)
    end
    
    def gtree(objectish)
      GitRuby::Object.new(self, objectish, 'tree')
    end
    
    def gcommit(objectish)
      GitRuby::Object.new(self, objectish, 'commit')
    end
    
    def gblob(objectish)
      GitRuby::Object.new(self, objectish, 'blob')
    end


    # returns a Git::Log object with count commits
    def log(count = 30)
      GitRuby::Log.new(self, count)
    end

    # this is a convenience method for accessing the class that wraps all the actual 'git' calls. 
    def lib
      @lib ||= GitRuby::Lib.new(self, @logger)
    end
    
    # returns a Git::Branches object of all the Git::Branch objects for this repo
    def branches
      GitRuby::Branches.new(self)
    end
    
    # returns a Git::Branch object for branch_name
    def branch(branch_name = 'master')
      GitRuby::Branch.new(self, branch_name)
    end
    
    # checks out a branch as the new git working directory
    def checkout(branch = 'master', opts = {})
      self.lib.checkout(branch, opts)
    end
    
    # returns an array of all Git::Tag objects for this repository
    def tags
      self.lib.tags.map { |r| tag(r) }
    end

=begin    
    # returns a Git::Tag object
    def tag(tag_name)
      GitRuby::Object.new(self, tag_name, 'tag', true)
    end
    
    # creates an archive file of the given tree-ish
    def archive(treeish, file = nil, opts = {})
      self.object(treeish).archive(file, opts)
    end    
=end
                
    def with_working(work_dir)
      return_value = false
      old_working = @working_directory
      set_working(work_dir) 
      Dir.chdir work_dir do
        return_value = yield @working_directory
      end
      set_working(old_working)
      return_value
    end
    
    def with_temp_working &blk
      tempfile = Tempfile.new("temp-workdir")
      temp_dir = tempfile.path
      tempfile.unlink
      Dir.mkdir(temp_dir, 0700)
      with_working(temp_dir, &blk)
    end
    
    
    # runs git rev-parse to convert the objectish to a full sha
    #
    #   @git.revparse("HEAD^^")
    #   @git.revparse('v2.4^{tree}')
    #   @git.revparse('v2.4:/doc/index.html')
    #
    def revparse(objectish)
      self.lib.revparse(objectish)
    end
    
    def ls_tree(objectish)
      self.lib.ls_tree(objectish)
    end

    def ls_files
      self.index.ls_files
    end
    
    def add(file = '.')
      if file == '.'
        # add all files
        Dir.glob("**/*").each do |file|
          if File.file?(file)
            self.lib.add(file)
          end
        end
      else
        self.lib.add(file)
      end
    end
    
    def commit(message)
      self.lib.commit(message)
    end
    
    def checkout(branch)
      self.lib.checkout(branch)
    end
    
    def cat_file(objectish)
      self.lib.object_contents(objectish)
    end

    # returns the name of the branch the working directory is currently on
    def current_branch
      self.lib.branch_current
    end

    
  end
  
end
