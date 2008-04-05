#
# converted from the gitrb project
#
# authors: 
#    Matthias Lederhofer <matled@gmx.net>
#    Simon 'corecode' Schubert <corecode@fs.ei.tum.de>
#
# provides native ruby access to git objects and pack files
#

require 'git-ruby/raw/internal/object'
require 'git-ruby/raw/internal/pack'
require 'git-ruby/raw/internal/loose'
require 'git-ruby/raw/object'

module GitRuby
  module Raw
    
    class Repository
      def initialize(git_dir)
        @git_dir = git_dir
        @loose = GitRuby::Raw::Internal::LooseStorage.new(git_path("objects"))
        @packs = []
        initpacks
      end

      def show
        @packs.each do |p|
          puts p.name
          puts
          p.each_sha1 do |s|
            puts "**#{p[s].type}**"
            if p[s].type.to_s == 'commit'
              puts s.unpack('H*')
              puts p[s].content
            end
          end
          puts
        end
      end

      def object(sha)
        o = get_raw_object_by_sha1(sha)
        c = GitRuby::Raw::Object.from_raw(o)
      end
            
      def cat_file(sha)
        object(sha).raw_content
      end
      
      def log(sha, options = {})
        walk_log(sha, 0, options)
      end
      
      def walk_log(sha, count, opts)
        array = []
        
        if (sha && (!opts[:count] || (count < opts[:count])))
          o = get_raw_object_by_sha1(sha)
          c = GitRuby::Raw::Object.from_raw(o)

          add_sha = true
          
          if opts[:since] && opts[:since].is_a?(Time) && (opts[:since] > c.committer.date)
            add_sha = false
          end
          if opts[:until] && opts[:until].is_a?(Time) && (opts[:until] < c.committer.date)
            add_sha = false
          end
          
          # follow all parents unless '--first-parent' is specified #
          subarray = []
          
          if !c.parent.first && opts[:path_limiter]  # check for the last commit
            add_sha = false
          end
          
          if opts[:first_parent]
            psha = c.parent.first
            subarray += walk_log(psha, count + 1, opts)
            if psha && !files_changed?(c.tree, object(psha).tree, opts[:path_limiter])
              add_sha = false
            end
          else
            c.parent.each do |psha|
              subarray += walk_log(psha, count + 1, opts)
              if psha && !files_changed?(c.tree, object(psha).tree, opts[:path_limiter])
                add_sha = false 
              end
            end
          end
          
          if add_sha
            output = "commit #{sha}\n"
            output += o.content + "\n\n"
            array << [sha, output]
          end

          array += subarray
                                
        end
        
        array
      end
      
      # returns true if the files in path_limiter were changed, or no path limiter
      def files_changed?(tree_sha1, tree_sha2, path_limiter = nil)
        if path_limiter
          mod = quick_diff(tree_sha1, tree_sha2)
          files = mod.map { |c| c.first }
          path_limiter.to_a.each do |filepath|
            if files.include?(filepath)
              return true
            end
          end
          return false
        end
        true
      end
      
      def quick_diff(tree1, tree2, path = '.')
        # handle empty trees
        changed = []

        t1 = ls_tree(tree1) if tree1
        t2 = ls_tree(tree2) if tree2

        # finding files that are different
        t1['blob'].each do |file, hsh|
          t2_file = t2['blob'][file] rescue nil
          full = File.join(path, file)
          if !t2_file
            changed << [full, 'added', hsh[:sha], nil]      # not in parent
          elsif (hsh[:sha] != t2_file[:sha])
            changed << [full, 'modified', hsh[:sha], t2_file[:sha]]   # file changed
          end
        end if t1
        t2['blob'].each do |file, hsh|
          if !t1['blob'][file]
            changed << [File.join(path, file), 'removed', nil, hsh[:sha]]
          end if t1
        end if t2

        t1['tree'].each do |dir, hsh|
          t2_tree = t2['tree'][dir] rescue nil
          full = File.join(path, dir)
          if !t2_tree
            changed += quick_diff(hsh[:sha], nil, full)  # recurse
          elsif (hsh[:sha] != t2_tree[:sha])
            changed += quick_diff(hsh[:sha], t2_tree[:sha], full)  # recurse
          end
        end if t1
        t2['tree'].each do |dir, hsh|
          full = File.join(path, dir)
          changed += quick_diff(nil, hsh[:sha], full)  # recurse
        end if t2

        changed
      end
      
      def ls_tree(sha)
        data = {'blob' => {}, 'tree' => {}}
        self.object(sha).entry.each do |e|
          data[e.format_type][e.name] = {:mode => e.format_mode, :sha => e.sha1}
        end              
        data
      end
      
      def get_object_by_sha1(sha1)
        r = get_raw_object_by_sha1(sha1)
        return nil if !r
        Object.from_raw(r, self)
      end
      
      def put_raw_object(content, type)
        @loose.put_raw_object(content, type)
      end
      
      def object_exists?(sha1)
        sha_hex = [sha1].pack("H*")
        return true if in_packs?(sha_hex)
        return true if in_loose?(sha_hex)
        initpacks
        return true if in_packs?(sha_hex) #maybe the object got packed in the meantime
        false
      end
      
      def in_packs?(sha_hex)
        # try packs
        @packs.each do |pack|
          return true if pack[sha_hex]
        end
        false
      end
      
      def in_loose?(sha_hex)
        return true if @loose[sha_hex]
        false
      end
      
      def get_raw_object_by_sha1(sha1)
        sha1 = [sha1].pack("H*")

        # try packs
        @packs.each do |pack|
          o = pack[sha1]
          return o if o
        end

        # try loose storage
        o = @loose[sha1]
        return o if o

        # try packs again, maybe the object got packed in the meantime
        initpacks
        @packs.each do |pack|
          o = pack[sha1]
          return o if o
        end

        nil
      end

      protected
      
        def git_path(path)
          return "#@git_dir/#{path}"
        end

      private 
      
        def initpacks
          @packs.each do |pack|
            pack.close
          end
          @packs = []
          if File.exists?(git_path("objects/pack"))
            Dir.open(git_path("objects/pack/")) do |dir|
              dir.each do |entry|
                if entry =~ /\.pack$/i
                  @packs << GitRuby::Raw::Internal::PackStorage.new(git_path("objects/pack/" \
                                                                    + entry))
                end
              end
            end
          end
        end
      
    end
    
  end
end
