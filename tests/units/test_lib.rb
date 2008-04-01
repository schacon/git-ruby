#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'

class TestLib < Test::Unit::TestCase
  def setup
    set_file_paths
  end
  
  def test_dumb_checkout
    in_temp_dir do
      assert !File.exists?('example.txt')
      @git.lib.dumb_checkout('test_object')
      assert File.exists?('example.txt')
    end
  end
  
  def test_revparse
    #self.lib.revparse(objectish)
  end
  
  def test_ls_tree
    #self.lib.ls_tree(objectish)
  end
  
  def test_cat_file
    #self.lib.object_contents(objectish)
  end

  def test_current_branch
    #self.lib.branch_current
  end
end
