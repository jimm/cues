#!/usr/bin/env ruby

require 'optparse'
require 'wavefile'

include WaveFile

SAMPLES_DIR = File.join(__dir__, '../samples')
OUTPUT_FORMAT = Format.new(:mono, :pcm_16, 48_000)
MULTI_BEAT_NAMES_REGEX = /^[1-4r]+$/

NAMES = {
  # Beat numbers
  '1' => 'one',
  '2' => 'two',
  '3' => 'three',
  '4' => 'four',
  '5' => 'five',
  '6' => 'six',
  '7' => 'seven',
  '8' => 'eight',
  # Rests
  'rest' => nil, # silence; just advances the beat
  'r' => nil,
  # Metronome
  '_md' => 'clave-high', # metronome downbeat
  '_mk' => 'clave-low'   # metronome click (other beats)
}.freeze

# MIDI note numbers used when writing a MIDI file instead of a wave file.
# There's no audio to play, so each sample name is mapped to a note that a
# General MIDI drum kit (channel 10) or instrument can play as a stand-in.
# The claves (metronome) sounds use General MIDI percussion note numbers;
# everything else gets its own note on a regular (non-percussion) channel so
# they're easy to tell apart in a DAW's piano roll.
MIDI_NOTE_NUMBERS = {
  'clave-high' => 75,   # GM percussion: Claves
  'clave-low' => 37,    # GM percussion: Side Stick
  'clave-middle' => 76, # GM percussion: Hi Wood Block
  'one' => 60,
  'two' => 61,
  'three' => 62,
  'four' => 63,
  'five' => 64,
  'six' => 65,
  'seven' => 66,
  'eight' => 67,
  'intro' => 68,
  'verse' => 69,
  'chorus' => 70,
  'bridge' => 71,
  'end' => 72,
  'solo' => 73,
  'fade' => 74
}.freeze
MIDI_PERCUSSION_CHANNEL = 9 # channel 10, zero-based
MIDI_NOTE_CHANNEL = 0 # channel 1, zero-based
MIDI_FIRST_DYNAMIC_NOTE = 36 # starting note for samples with no fixed mapping

class Cues
  attr_reader :tempo
  attr_accessor :time_signature, :subdivision, :names

  def initialize
    self.tempo = 120
    @time_signature = [4, 4]
    @subdivision = 4
    @names = NAMES.dup
    @beat = 0
    @events = [] # { time: Float (seconds), sample_name: String }
    @sample_cache = {}
    @midi_note_cache = {}
  end

  def tempo=(bpm)
    @tempo = bpm
    @seconds_per_beat = 60.0 / bpm
  end

  def build_cues_file(in_io, out_path, format: :wav)
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
      when 'm', 'meas', 'measure', 'measures'
        insert_measures(words[0].to_i)
      when 'b', 'beat'
        insert_metronome(words[0].to_i)
      when 'c', 'cue'
        insert_cue(words)
      when MULTI_BEAT_NAMES_REGEX
        command.each_char { |ch| insert_name(ch) }
      when 'd', 'downbeat'
        set_clave_sample('_md', words[0])
      when 'k', 'click'
        set_clave_sample('_mk', words[0])
      else
        insert_name(command) # also handles r/rest
      end
    end

    case format
    when :wav
      write_audio_file(out_path)
    when :midi
      write_midi_file(out_path)
    else
      raise "unknown output format: #{format.inspect}"
    end
  end

  def insert_cue(words)
    @beat -= words.length
    words.select { |word| multi_beat_names?(word) }.each do |word|
      @beat -= word.length - 1
    end

    words.each do |word|
      case word
      when MULTI_BEAT_NAMES_REGEX
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
    name = name.downcase
    if %w[rest r].include?(name)
      @beat += 1
      return
    end

    sample_name = @names[name] || name
    report_error("sample \"#{name}\" not found") unless sample_file_exists?(sample_name)

    @events << { time: @beat * @seconds_per_beat, sample_name: sample_name }
    @beat += 1
  end

  # Sets which clave-*.wav file (from SAMPLES_DIR) is used for the metronome
  # downbeat (key == '_md') or click (key == '_mk'). clave_name is the part
  # of the file name after "clave-", e.g. "high", "middle", or "low".
  def set_clave_sample(key, clave_name)
    report_error('missing clave sample name') if clave_name.nil?

    sample_name = "clave-#{clave_name}"
    report_error("clave sample \"#{sample_name}\" not found in #{SAMPLES_DIR}") unless sample_file_exists?(sample_name)

    @names[key] = sample_name
  end

  def write_audio_file(out_path)
    total_frames = @events.reduce(0) do |max_frames, event|
      samples = load_sample(event[:sample_name])
      start_frame = (event[:time] * OUTPUT_FORMAT.sample_rate).round
      [max_frames, start_frame + samples.length].max
    end

    mixed = Array.new(total_frames, 0)
    @events.each do |event|
      samples = load_sample(event[:sample_name])
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

  # Writes a Standard MIDI File instead of a wave file. Since there's no
  # audio to embed, each event becomes a short note-on/note-off pair (see
  # MIDI_NOTE_NUMBERS) so the cues can be used as a guide track in a DAW or
  # MIDI-aware metronome app.
  def write_midi_file(out_path)
    require 'midilib/sequence'
    require 'midilib/consts'

    sequence = MIDI::Sequence.new
    track = MIDI::Track.new(sequence)
    sequence.tracks << track
    track.name = 'Cues'
    track.events << MIDI::Tempo.new(MIDI::Tempo.bpm_to_mpq(@tempo))
    track.events << MIDI::TimeSig.new(@time_signature[0], Math.log2(@time_signature[1]).round, 24, 8)

    ticks_per_beat = sequence.ppqn
    note_length = (ticks_per_beat * 0.5).round # eighth-note-long hit

    @events.each do |event|
      tick = (event[:time] * @tempo / 60.0 * ticks_per_beat).round
      channel, note = midi_note_for(event[:sample_name])

      on = MIDI::NoteOnEvent.new(channel, note, 100)
      on.time_from_start = tick
      track.events << on

      off = MIDI::NoteOffEvent.new(channel, note, 100)
      off.time_from_start = tick + note_length
      track.events << off
    end

    track.recalc_delta_from_times
    track.ensure_track_end_meta_event

    File.open(out_path, 'wb') { |file| sequence.write(file) }
  end

  # Returns [channel, note] for sample_name. Claves (metronome) samples use
  # General MIDI percussion note numbers on the percussion channel; other
  # built-in samples get a fixed note from MIDI_NOTE_NUMBERS. Any other
  # sample name is assigned the next free note, starting at
  # MIDI_FIRST_DYNAMIC_NOTE, the first time it's seen.
  def midi_note_for(sample_name)
    if MIDI_NOTE_NUMBERS.key?(sample_name)
      channel = sample_name.start_with?('clave-') ? MIDI_PERCUSSION_CHANNEL : MIDI_NOTE_CHANNEL
      return [channel, MIDI_NOTE_NUMBERS[sample_name]]
    end

    note = @midi_note_cache[sample_name] ||= MIDI_FIRST_DYNAMIC_NOTE + @midi_note_cache.size
    [MIDI_NOTE_CHANNEL, note]
  end

  def load_sample(sample_name)
    @sample_cache[sample_name] ||= read_sample(sample_name)
  end

  def read_sample(sample_name)
    path = sample_file(sample_name)
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
    word =~ MULTI_BEAT_NAMES_REGEX
  end

  def sample_file(name)
    File.join(SAMPLES_DIR, "#{name}.wav")
  end

  def sample_file_exists?(name)
    File.exist?(sample_file(name))
  end

  def report_error(message)
    puts "line = #{@current_line}"
    puts "error: #{message}"
    exit(1)
  end
end

def parse_cues_cli_options(argv)
  format = :wav
  parser = OptionParser.new do |opts|
    opts.banner = 'usage: cues.rb [options] in_cues_file out_file'
    opts.on('-m', '--midi', 'Generate a MIDI file instead of a wave file') { format = :midi }
    opts.on('-w', '--wav', 'Generate a wave file (default)') { format = :wav }
  end
  in_path, out_path = parser.parse!(argv)
  [in_path, out_path, format]
end

if __FILE__ == $PROGRAM_NAME
  in_path, out_path, format = parse_cues_cli_options(ARGV)
  cues = Cues.new
  File.open(in_path, 'r') do |in_io|
    cues.build_cues_file(in_io, out_path, format: format)
  end
end
