Git Library for Ruby
====================

A pure ruby implementation of Git


Homepage
--------

Git public hosting of the project source code and project wiki is at:

[http://github.com/schacon/gitruby](http://github.com/schacon/gitruby "Git-Ruby at GitHub")


Gitr
----

I have included a command line pure-ruby git client called 'gitr'

The following commands are available - they all will run in pure ruby, without forking out the the git binary.
In fact, they can be run on a machine without git compiled on it.

Commands currently implemented: 

* add
* commit
* log
* log-shas
* cat-file (treeish)
* rev-parse (treeish)
* branches
* ls-tree (tree)
     
     
Examples
--------

Here are some of examples of how to use the Git-Ruby package. 

First you have to remember to require rubygems if it's not.  Then include the 'git-ruby' gem.


    require 'rubygems'
    require 'git-ruby'

    g = GitRuby.open('my_project')  # has a .git subdir

    g.add('file')
    g.commit('commit message')

    g.log.each do |commit|
      puts commit.sha
      puts commit.message
      puts commit.author.email

      commit.gtree.children.each do |name, obj|
        if obj.tree?
          puts ['tree: ' name, obj.sha].join("\t")
        end

        if obj.blob?
          puts ['blob: ' name, obj.sha].join("\t")
        end
      end
    end