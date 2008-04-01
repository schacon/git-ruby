#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'

class TestIndex < Test::Unit::TestCase
  def setup
    set_file_paths
  end
  
  def test_clean
    @git.chdir do
      assert @git.index.clean?

      append_file('example.txt', 'my test content')
      assert !@git.index.clean?

      @git.add('example.txt')
      assert !@git.index.clean?

      @git.commit('added example.txt')
      assert @git.index.clean?

      new_file('new_dang_file.txt', 'my test content')
      assert @git.index.clean?

      @git.add('new_dang_file.txt')
      assert !@git.index.clean?
    end
  end
  
  def test_checkout
    @git.chdir do
      branch = @git.current_branch
      new_file('new_dang_file.txt', 'my test content')
      @git.add('new_dang_file.txt')
      @git.commit('added new file')

      @git.checkout('test_branches')
      assert !File.exists?('new_dang_file.txt')
    
      @git.checkout(branch)
      assert File.exists?('new_dang_file.txt')
    end
  end
  
end