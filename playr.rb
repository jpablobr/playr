#!/usr/bin/env ruby
# coding: utf-8
require 'optparse'

class Client
  require 'librmpd'
  require 'thread'
  require 'readline'
  require 'shellwords'
  require 'term/ansicolor'
  include Term::ANSIColor

  Readline.completion_proc = lambda do |word|
    commands.each.grep(/^#{ Regexp.escape(word) }/)
  end

  def initialize
    @mpd = MPD.new
    @mpd.connect
  end

  def start!
    while line = Readline.readline("#{blue(prompt)} ♪ ").strip
      next if line.empty?
      unless Readline::HISTORY.to_a[-1] == line
        Readline::HISTORY.push line
      end

      if commands.include?(line.to_sym)
        self.send(line.to_sym)
      elsif line.eql?('quit')
        break
      else
        warn "Unknown command: #{line.inspect}"
      end
    end
  end

  def volume vol
    if vol.nil?
      puts "Volume: #{@mpd.volume}"
    else
      @mpd.volume = vol.to_i
    end
  end

  def stats
    hash = @mpd.stats
    hash.each_pair do |key, value|
      puts "#{key} => #{value}"
    end
  end

  def commands
    cmds = Client.instance_methods -
      Object.instance_methods -
      Term::ANSIColor.instance_methods
    [:start!, :commands].each { |c| cmds.delete(c) }
    cmds
  end

  def song?
    @mpd.current_song.each_pair { |k,v| warn "#{blue(k+":")} #{v}" }
  end

  def playlist?
    warn green("#{pl_name(@mpd.playlist.first.fetch('file'))}")
    @mpd.playlist.each { |l|
      warn "#{blue("song:")} #{song_name(l.fetch('file'))}"
    }
  end

  def playlists?
    @mpd.playlists.each { |pl|
      warn "#{blue("pl:")} #{pl}"
    }
  end

  def pause;      @mpd.pause = !mpd.paused?     end
  def stop;       @mpd.stop                     end
  def next;       @mpd.next                     end
  def prev;       @mpd.previous                 end
  def disconnect; @mpd.disconnect               end
  def repeat;     @mpd.repeat = !@mpd.repeat?   end
  def random;     @mpd.random = !@mpd.random?   end
  def help;       commands.each { |c| warn(c) } end
  def play song;  @mpd.play song                end

  private

  def prompt;         song_name(@mpd.current_song.fetch('file')) end
  def pl_name pl;     pl.split('/')[0..-2].join('/')             end
  def song_name song; song.gsub(/(.*\/)|(\..*$)/,'')             end
end

opts = OptionParser.new do |o|
  o.banner = "Usage: mpd [OPTION] [<args>]"
  o.separator ""
  o.on("-h", "--help", "Print this help.") {
    return $stderr.puts(opts)
  }
  o.on("-v", "--version", "Print version.") {
    return $stderr.puts("0.1.0")
  }
  o.on("-s", "--start", "Run the mpd client.") {
    puts "staring"
    Client.new.start!
  }
  o.on("-t", "--tests", "run tests.") {
    eval(DATA.read)
  }
  o.on("-d", "--debug", "Enable debug output.") {
    $DEBUG = true
  }
  o.separator ""
end

opts.parse!(ARGV)

__END__
require 'minitest/autorun'
class TestClient < MiniTest::Unit::TestCase
  def setup
    @c = Client.new
  end

  def test_should_return_an_array
    assert true, @c.commands.is_a?(Array)
  end

  def test_should_not_incude_start_or_commands_methods
    [:start!, :commands].each { |m|
      assert true, @c.commands.include?(m)
    }
  end
end
