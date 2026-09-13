#!/usr/bin/env ruby

require 'wavefile'

include WaveFile

SAMPLES_DIR = File.join(__dir__, '../samples')
OUTPUT_FORMAT = Format.new(:mono, :pcm_16, 48_000)

NAMES = {
  '1' => 'one.wav',
  '2' => 'two.wav',
  '3' => 'three.wav',
  '4' => 'four.wav',
  'one' => 'one.wav',
  'two' => 'two.wav',
  'three' => 'three.wav',
  'four' => 'four.wav',
  'intro' => 'intro.wav',
  'verse' => 'verse.wav',
  'chorus' => 'chorus.wav',
  'bridge' => 'bridge.wav',
  'end' => 'end.wav',
  'rest' => nil,             # silence; just advances the beat
  '_md' => 'clave-high.wav', # metronome downbeat
  '_mk' => 'clave-low.wav'   # metronome click (other beats)
}.freeze

class Cues
  attr_reader :tempo
  attr_accessor :time_signature, :subdivision, :names

  def initialize
    self.tempo = 120
    @time_signature = [4, 4]
    @subdivision = 4
    @names = NAMES.dup
    @beat = 0
    @events = [] # { time: Float (seconds), filename: String }
    @sample_cache = {}
  end

  def tempo=(bpm)
    @tempo = bpm
    @seconds_per_beat = 60.0 / bpm
  end

  def build_cues_audio_file(in_io, out_path)
    in_io.readlines.each do |line|
      line = line.sub(/ *#.*/, '').strip
      next if line.empty?

      @current_line = line
      command, *words = line.split
      case command
      when 't', 'tempo'
        self.tempo = words[0].to_i
      when %r{(\d+)/(\d+)}
        @time_signature = [::Regexp.last_match(1).to_i, ::Regexp.last_match(2).to_i]
      when 'v', 'subdivision'
        @subdivision = words[0].to_i
      when 'm', 'measure'
        insert_measures(words[0].to_i)
      when 'b', 'beat'
        insert_metronome(words[0].to_i)
      when 'c', 'cue'
        insert_cue(words)
      when /^[1-4]+$/
        command.each_char { |ch| insert_name(ch) }
      when 'd', 'downbeat'
        set_clave_sample('_md', words[0])
      when 'k', 'click'
        set_clave_sample('_mk', words[0])
      else
        insert_name(command)
      end
    end

    write_audio_file(out_path)
  end

  def insert_cue(words)
    @beat -= words.length
    words.select { |word| multi_beat_names?(word) }.each do |word|
      @beat -= word.length - 1
    end

    words.each do |word|
      case word
      when /^[1-4]+$/
        word.each_char { |ch| insert_name(ch) }
      else
        insert_name(word)
      end
    end
  end

  def insert_measures(num_measures)
    num_measures.times do
      insert_name('_md') # downbeat
      insert_metronome(@time_signature[0] - 1)
    end
  end

  def insert_metronome(num_beats)
    # BROKEN if subdivision < 4
    num_beats.times do
      # FIXME: can't use insert_name because that assumes we move to the next
      # whole beat
      insert_name('_mk')
      # TODO: fix for eighths, etc.
    end
  end

  def insert_name(name)
    if name == 'rest'
      @beat += 1
      return
    end

    filename = @names[name]
    report_error("name \"#{name}\" not found") if filename.nil?

    @events << { time: @beat * @seconds_per_beat, filename: filename }
    @beat += 1
  end

  # Sets which clave-*.wav file (from SAMPLES_DIR) is used for the metronome
  # downbeat (key == '_md') or click (key == '_mk'). clave_name is the part
  # of the file name after "clave-", e.g. "high", "middle", or "low".
  def set_clave_sample(key, clave_name)
    report_error('missing clave sample name') if clave_name.nil?

    filename = "clave-#{clave_name}.wav"
    unless File.exist?(File.join(SAMPLES_DIR, filename))
      report_error("clave sample \"#{filename}\" not found in #{SAMPLES_DIR}")
    end

    @names[key] = filename
  end

  def write_audio_file(out_path)
    total_frames = @events.reduce(0) do |max_frames, event|
      samples = load_sample(event[:filename])
      start_frame = (event[:time] * OUTPUT_FORMAT.sample_rate).round
      [max_frames, start_frame + samples.length].max
    end

    mixed = Array.new(total_frames, 0)
    @events.each do |event|
      samples = load_sample(event[:filename])
      start_frame = (event[:time] * OUTPUT_FORMAT.sample_rate).round
      samples.each_with_index do |sample, i|
        frame = start_frame + i
        mixed[frame] = clamp_pcm16(mixed[frame] + sample)
      end
    end

    Writer.new(out_path, OUTPUT_FORMAT) do |writer|
      writer.write(Buffer.new(mixed, OUTPUT_FORMAT))
    end
  end

  def load_sample(filename)
    @sample_cache[filename] ||= read_sample(filename)
  end

  def read_sample(filename)
    path = File.join(SAMPLES_DIR, filename)
    raise "sample file not found: #{path}" unless File.exist?(path)

    samples = nil
    native_rate = nil
    Reader.new(path) do |reader|
      native_rate = reader.native_format.sample_rate
      samples = reader.read(reader.total_sample_frames).samples
    end

    resample(samples, native_rate, OUTPUT_FORMAT.sample_rate)
  end

  # wavefile's Buffer#convert can change bit depth and channel count, but not
  # sample rate, so any sample recorded at a rate other than OUTPUT_FORMAT's
  # is resampled here using linear interpolation.
  def resample(samples, from_rate, to_rate)
    return samples if from_rate == to_rate

    ratio = from_rate.to_f / to_rate
    new_length = (samples.length / ratio).round
    Array.new(new_length) do |i|
      src_pos = i * ratio
      idx0 = [src_pos.floor, samples.length - 1].min
      idx1 = [idx0 + 1, samples.length - 1].min
      frac = src_pos - idx0
      ((samples[idx0] * (1 - frac)) + (samples[idx1] * frac)).round
    end
  end

  def clamp_pcm16(value)
    value.clamp(-32_768, 32_767)
  end

  def multi_beat_names?(word)
    word =~ /^[1-4]+$/
  end

  def report_error(message)
    puts "line = #{@current_line}"
    puts "error: #{message}"
    exit(1)
  end
end

if __FILE__ == $PROGRAM_NAME
  # usage: cues.rb in_cues_file out_wav_file
  cues = Cues.new
  File.open(ARGV[0], 'r') do |in_io|
    cues.build_cues_audio_file(in_io, ARGV[1])
  end
end
