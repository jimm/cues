#!/usr/bin/env ruby

require_relative '../lib/cues'

in_path, out_path, format = parse_cues_cli_options(ARGV)
c = Cues.new
File.open(in_path) do |in_io|
  c.build_cues_file(in_io, out_path, format: format)
end
