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
      
      def log(sha, count = 30)
        output = ''
        i = 0

        while sha && (i < count) do
          o = get_raw_object_by_sha1(sha)
          c = GitRuby::Raw::Object.from_raw(o)
          
          output += "commit #{sha}\n"
          output += o.content + "\n\n"

          sha = c.parent.first
          i += 1
        end
        
        output
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
