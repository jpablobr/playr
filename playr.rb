#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'
require 'ostruct'

module Playr
  require 'librmpd'
  require 'term/ansicolor'

  extend Module.new { attr_accessor :out }

  # ~/.playrrc.rb
  _user_config_file = ENV['HOME']+'/.playrrc.rb'

  # Defaults
  Conf ||= OpenStruct.new(music_dir: '~/music/', mpd_dir: '~/.mpd/')
  Conf.playlists_dir = Conf.mpd_dir + 'playlists/'
  Conf.playlists = {
    fav: Conf.playlists_dir + 'fav.m3u'
  }

  # overrides
  load _user_config_file if File.exist? _user_config_file

  class Client
    require 'readline'
    include Term::ANSIColor

    def initialize
      @mpd    ||= MPD.new
      @vol    ||= Volume.new
      @format ||= Formatter.new
      @print  ||= Printer.new
      begin
        @mpd.connect unless @mpd.connected?
      rescue Errno::ECONNREFUSED => e
        @print.write e.message
        exit 1
      end
      start! unless $TEST
    end

    def stats
      @mpd.stats.each_pair { |k,v| @print.write(k+': ' + v) }
    end

    def song?
      @mpd.current_song.each_pair { |k,v| @print.write(blue(k+": ") + v +"\n") }
    end

    def search what
      @mpd.songs.select { |song| song.fetch('file')[what] }
        .each { |sng| @print.search(sng) }
    end

    def songs what=nil
      if what
        list = @mpd.songs.select { |s| s.fetch('file')[what] }
      else
        list = @mpd.songs
      end
      @print.songs(list)
    end

    def playlist what=nil
      if what
        songs = @mpd.playlist.select { |s| s.fetch('file')[what] }
      else
        songs = @mpd.playlist
      end
      @print.playlist(songs)
    end

    def playlists what=nil
      if what
        songs = @mpd.playlists.select { |pl| pl[what] }
      else
        songs = @mpd.playlists
      end
      @print.playlists(songs)
    end

    def help
      commands
        .group_by{ |m| Client.instance_method(m) }
        .map(&:last)
        .sort { |a,b| a.to_s.size <=> b.to_s.size }
        .each { |s| @print.help(s) }
    end

    def play song
      begin
        @mpd.play song
      rescue RuntimeError => e
        @print.write(e)
      end
    end

    def pause;      @mpd.pause = true            end
    def continue;   @mpd.pause = false           end
    def stop;       @mpd.stop                    end
    def next;       @mpd.next                    end
    def prev;       @mpd.previous                end
    def disconnect; @mpd.disconnect              end
    def repeat;     @mpd.repeat = !@mpd.repeat?  end
    def random;     @mpd.random = !@mpd.random?  end
    def load pl;    @mpd.load(pl)                end
    def +;          @vol.+                       end
    def -;          @vol.-                       end
    def mute;       @vol.mute                    end
    def vol v;      @vol.vol(v)                  end

    def remove
      s = `locate #{@mpd.current_song.fetch('file')}`.chomp
      `rm  #{s}` if File.exist?(s)
    end

    def fav
      file = Conf.music_dir + @mpd.current_song.fetch('file')
      `echo #{file} >> #{Conf.playlists[:fav]}`
    end

    alias :p   :play
    alias :c   :continue
    alias :s   :search
    alias :h   :help
    alias :n   :next
    alias :r   :random
    alias :v   :vol
    alias :f   :fav
    alias :m   :mute
    alias :d   :disconnect
    alias :ps  :pause
    alias :rm  :remove
    alias :ls  :playlist
    alias :lsp :playlists

    private

    def prompt_data
      @format.song_name(@mpd.current_song.fetch('file'))
    end

    def start!
      while line = Readline.readline(@print.prompt(prompt_data)).strip
        next if line.empty?
        Readline.completion_proc = lambda { |word|
          @mpd.songs.map { |s| s.fetch('file') }
            .grep(/^#{Regexp.escape(word)}/)
        }
        unless Readline::HISTORY.to_a[-1] == line
          Readline::HISTORY.push line
        end
        break if line.match(/^(quit|exit|q)$/)
        process_cmd(line)
      end
    end

    def commands
      (Client.instance_methods -
        Object.instance_methods -
        Term::ANSIColor.instance_methods)
        .select { |c| c.to_s !~ /^start!/ }
    end

    def process_cmd cmd
      meth = cmd.split[0]
      args = cmd.split[1..-1]
      if commands.include?(meth.to_sym)
        begin
          send(meth, *args)
        rescue ArgumentError => e
          @print.write("Command \"" + meth + "\"" + e.message + "\n")
        end
      else
        @print.write("Unknown command: #{cmd.inspect}\n")
      end
    end
  end

  class Printer
    include Term::ANSIColor

    def initialize
      @mpd    ||= MPD.new
      @vol    ||= Volume.new
      @format ||= Formatter.new
    end

    def write data; (Playr.out || $>)<< data; data end

    def prompt data, icon='♪'
      prompt_color(data +' '+ icon +' ')
    end

    def search song
      str = blue("song: ") +"%s\n"
      write(str % @format.song_name(song.fetch('file')))
    end

    def songs songs
      songs.each { |s|
        write(blue("♬ ") + @format.song_name(s.fetch('file')) +"\n")
      }
    end

    def playlists pls
      pls.each { |pl| write(blue("pl: ") + pl +"\n") }
    end

    def playlist pl
      song = blue("song:") + yellow("%s ") +"%s\n"
      write(green(@format.pl_name(@mpd.playlist.first)))
      pl.each { |s|
        write(song % [s.fetch('id'), @format.song_name(s.fetch('file'))])
      }
    end

    def help cmd
      aliased = cmd[1].nil? ? '' : ' || '+ green(cmd[1].to_s)
      write(blue(cmd[0].to_s) + aliased + "\n")
    end

    private
    def prompt_color p; @vol.mute? ? red(p) : green(p) end
  end

  class Volume
    def initialize
      @vol_set = 'amixer sset Master'
      @vol_get = 'amixer sget Master'
    end
    def +;     `#{@vol_set} 5%+`               end
    def -;     `#{@vol_set} 5%-`               end
    def mute;  `#{@vol_set} toggle`            end
    def mute?; `#{@vol_get}`.split.last['off'] end
    def vol v; `#{@vol_set} "#{v}"`            end
  end

  class Formatter
    def pl_name pl
      pl.fetch('file').split('/')[0..-2].join('/')
    end

    def song_name song
      song.scan(/[[:print:]]/).join.gsub(/(.*\/)|(\..*$)/,'')
    end
  end

  class Dbg
    include Term::ANSIColor
    def debug cls, mth, cllr, file, line, ivrs={}, lvrs={}
      msg = [
        magenta("#{cls.class.name}##{mth}"),
        "\nCaller => "+ green("#{cllr[0][/`.*'/][1..-2]}"),
        "\n---Instance Vars---"
      ]
      ivrs.each { |v| msg << yellow("#{v}=")  + eval("#{v}").to_s }
      msg << "\n---local Vars---"
      lvrs.each { |v| msg << yellow("#{v}=")  + eval("#{v}").to_s }
      msg << "\n#{file}:#{line}"
      puts red("DBG: #{Time.now}: -------------------------------")
      puts msg
      yield
    end
  end
end

$stdout.sync = $stderr.sync = true
opts = OptionParser.new do |o|
  o.banner = "Usage: playr [OPTION] [<args>]"
  o.separator ""
  o.on("-h", "--help", "Print this help.")      { puts(opts) }
  o.on("-v", "--version", "Print version.")     { puts("0.1.1") }
  o.on("-s", "--start", "Run the mpd client.")  { Playr::Client.new }
  o.on("-t", "--tests", "run tests.")           { eval(DATA.read) }
  o.on("-d", "--debug", "Enable debug output.") { $DEBUG = true }
  o.separator ""
end

opts.parse!(ARGV)

__END__
#encoding: utf-8
$TEST = true
require 'minitest/autorun'

Playr.out = File.new('/dev/null', 'w')

class TestClient < MiniTest::Unit::TestCase
  def setup
    @c = Playr::Client.new
  end

  def test_help_should_not_incude_start_method
    require 'stringio'
    str = StringIO.new << @c.help
    refute_match /start/, str.string
    assert_match /(play|mute|vol|next)/, str.string
  end

  class TestFormatter < MiniTest::Unit::TestCase
    def setup
      @f = Playr::Formatter.new
    end

    def test_pl_name
      assert_equal 'foo/bar/baz', @f.pl_name({'file' => 'foo/bar/baz/quux.mp3'})
    end

    def test_song_name
      assert_equal 'quux', @f.song_name('foo/bar/baz/quux.mp3')
    end
  end

  class TestPrinter < MiniTest::Unit::TestCase
    def setup
      @p = Playr::Printer.new
    end

    def test_prompt
      assert_equal "\e[32mfoo ♪ \e[0m", @p.prompt("foo")
      assert_equal "\e[32mbaz ♬ \e[0m", @p.prompt("baz", "♬")
    end
  end
end
