
# Add the directory containing this file to the start of the load path if it
# isn't there already.
$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'git-ruby/base'
require 'git-ruby/path'
require 'git-ruby/lib'

require 'git-ruby/repository'
require 'git-ruby/index'
require 'git-ruby/working_directory'

require 'git-ruby/branch'
require 'git-ruby/branches'
require 'git-ruby/remote'

require 'git-ruby/log'
require 'git-ruby/object'

require 'git-ruby/author'

require 'git-ruby/raw/repository'
require 'fileutils'
require 'logger'


# Git-Ruby Library
#
# This library provides a pure ruby implementation of Git
#
# Author::    Scott Chacon (mailto:schacon@gmail.com)
# License::   MIT License
#
module GitRuby

  VERSION = '0.2.0'
  
  # open a bare repository
  #
  # this takes the path to a bare git repo
  # it expects not to be able to use a working directory
  # so you can't checkout stuff, commit things, etc.
  # but you can do most read operations
  def self.bare(git_dir, options = {})
    Base.bare(git_dir, options)
  end
    
  # open an existing git working directory
  # 
  # this will most likely be the most common way to create
  # a git reference, referring to a working directory.
  # if not provided in the options, the library will assume
  # your git_dir and index are in the default place (.git/, .git/index)
  #
  # options
  #   :repository => '/path/to/alt_git_dir'
  #   :index => '/path/to/alt_index_file'
  def self.open(working_dir, options = {})
    Base.open(working_dir, options)
  end
  
  # initialize a new git repository, defaults to the current working directory
  #
  # options
  #   :repository => '/path/to/alt_git_dir'
  #   :index => '/path/to/alt_index_file'
  def self.init(working_dir = '.', options = {})
    Base.init(working_dir, options)
  end
  
  # clones a remote repository
  #
  # options
  #   :bare => true (does a bare clone)
  #   :repository => '/path/to/alt_git_dir'
  #   :index => '/path/to/alt_index_file'
  #
  # example
  #  Git.clone('git://repo.or.cz/rubygit.git', 'clone.git', :bare => true)
  #
  def self.clone(repository, name, options = {})
    Base.clone(repository, name, options)
  end
    
end
