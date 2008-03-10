#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'

class TestObjects < Test::Unit::TestCase
  def setup
    set_file_paths
  end
  
  def test_object
    #GitRuby::Object.new(self, objectish)
  end
  
  def test_gtree
    #GitRuby::Object.new(self, objectish, 'tree')
  end
  
  def test_gcommit
    #GitRuby::Object.new(self, objectish, 'commit')
  end
  
  def test_gblob
    #GitRuby::Object.new(self, objectish, 'blob')
  end
  
  def test_tags
  end
  
end
