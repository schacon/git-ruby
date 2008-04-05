#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'
require 'date'

class TestLog < Test::Unit::TestCase
  def setup
    set_file_paths
    @start_date = Time.local(2007, 11, 8, 11, 20, 38);
    @end_date = Time.local(2007, 11, 9, 10, 29, 14)
    @full_size = @git.rev_list.size
  end

  def test_log
    assert @git.log.map { |c| c.sha }.include?('291b6be488d6abc586d3ee03ca61238766625a75')
  end

  def test_rev_list
    assert @git.rev_list.include?('d5b9587b65731e25216743b0caca72051a760211')
  end

  def test_since
    part = @git.rev_list(:since => @start_date).size
    assert @full_size > part
    assert part > 0
  end

  def test_count
    assert_equal 20, @git.rev_list(:count => 20).size
    assert_equal 15, @git.rev_list(:count => 15).size
  end

  def test_until
    part = @git.rev_list(:until => @start_date).size
    assert @full_size > part
    assert part > 0
  end

  def test_between
    part = @git.rev_list(:between => [@start_date, @end_date]).size
    none = @git.rev_list(:between => [@end_date, @start_date]).size
    assert @full_size > part
    assert part > none
    assert_equal 0, none
  end

  def test_first_parent
    part = @git.rev_list(:first_parent => true).size
    assert part > 0
  end
  
  def test_path_limiter
    part1 = @git.rev_list(:path_limiter => './example.txt')
    part2 = @git.rev_list(:path_limiter => './scott/text.txt')
    assert @full_size > part1.size
    assert part1.size > part2.size
    assert part2.size > 0
  end

  def test_multi
    part = @git.rev_list(:path_limiter => './example.txt', :between => [@start_date, @end_date])
    assert_equal part.size, 57
    part = @git.rev_list(:path_limiter => './example.txt')
    assert_equal part.size, 67
  end
  
end