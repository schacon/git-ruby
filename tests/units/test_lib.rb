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
  
  def test_diff_data
    tr1 = 'e8bd03b163f82fba4560c11839d49361a78dec85'
    tr2 = '33edabb4334cbe849a477a0d2893cdb768fa3091'
    diff = @git.lib.diff_data(tr1, tr2)
    assert_equal './example.txt', diff.first[0]
    assert_equal 'modified', diff.first[1]
    assert_equal '8a3fb747983bf2a7f4ef136af4bfcf7993a19307', diff.first[2]
    assert_equal 'a115413501949f4f09811fd1aaecf136c012c7d7', diff.first[3]
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
