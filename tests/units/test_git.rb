#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'

class TestGit < Test::Unit::TestCase
  def setup
    set_file_paths
  end
  
  def test_git_open
    g = GitRuby.open(@wdir)
    assert_match('.git', g.repo.path)
  end
  
  def test_git_bare
    g = GitRuby.bare(File.join(@wdir, '.git'))
    assert_match('.git', g.repo.path)
  end
  
  def test_git_init
    in_temp_dir do 
      assert(!File.exists?('.git/config'))
      GitRuby.init
      assert(File.exists?('.git/config'))
      assert(File.exists?('.git/refs/heads'))
    end
  end
  
end