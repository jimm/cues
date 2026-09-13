#!/usr/bin/env ruby

require_relative '../lib/cues'

c = Cues.new
File.open(ARGV[0]) do |in_io|
  c.build_cues_audio_file(in_io, '/tmp/cues_example.wav')
end
