#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'

class TestCommit < Test::Unit::TestCase
  def setup
    set_file_paths
  end
  
  def test_add
    @git.chdir do
      new_file('testfile', 'my test content')
      @git.add('testfile')
      assert_equal('496e96cbea07239ad519b413758f2cb00700d1c9', @git.ls_files['./testfile'][:sha_index])
    end
  end
  
  def test_commit
    @git.chdir do
      new_file('testfile', 'my test content')
      @git.add('testfile')
      FileUtils.mkdir_p('anotherdir')
      FileUtils.cd('anotherdir') do
        new_file('testfile2', 'more test content')
      end
      @git.add('anotherdir/testfile2')
      @git.commit('message')
    end
    
    assert_equal('b0dc94e199ea41bc2fd88ba6914d0f12f608a3c6', @git.log.first.gtree.sha)
  end
  
end