#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'

class TestBase < Test::Unit::TestCase
  def setup
    set_file_paths
  end
  
  def test_directory_stuff
    # dir, repo, index
    # set_working, set_index
  end
  
  def test_chdir
  end
  
  def test_repo_size
  end
  
  def test_log
  end
  
  def test_archive
  end
  
  def test_ls_tree
  end
  
  def test_cat_file
  end

  def test_rev_parse
  end
  
  def test_ls_files
  end
    
end