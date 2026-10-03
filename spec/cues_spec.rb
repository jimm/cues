require 'rspec'
require 'stringio'
require 'wavefile'
require 'midilib/sequence'
require_relative '../lib/cues'

include WaveFile

TEST_OUTPUT_FILE = '/tmp/cues_test.wav'
TEST_MIDI_OUTPUT_FILE = '/tmp/cues_test.mid'

RSpec.describe Cues do
  before(:each) { @c = Cues.new }

  after(:each) do
    File.delete(TEST_OUTPUT_FILE) if File.exist?(TEST_OUTPUT_FILE)
    File.delete(TEST_MIDI_OUTPUT_FILE) if File.exist?(TEST_MIDI_OUTPUT_FILE)
  end

  context 'building an audio file' do
    it 'generates a valid wave file with the metronome mixed in' do
      File.open(File.join(__dir__, 'example.txt'), 'r') do |in_io|
        @c.build_cues_file(in_io, TEST_OUTPUT_FILE)
      end

      Reader.new(TEST_OUTPUT_FILE) do |reader|
        expect(reader.native_format.channels).to eq 1
        expect(reader.native_format.bits_per_sample).to eq 16
        expect(reader.native_format.sample_rate).to eq 48_000
        expect(reader.total_sample_frames).to be > 0

        # The first event is the downbeat of measure 1, so the file should
        # start with audible (non-silent) samples rather than silence.
        opening_samples = reader.read(1000).samples
        expect(opening_samples).to include_any_nonzero
      end
    end
  end

  context 'building a MIDI file' do
    it 'generates a valid MIDI file with a note for each event' do
      File.open(File.join(__dir__, 'example.txt'), 'r') do |in_io|
        @c.build_cues_file(in_io, TEST_MIDI_OUTPUT_FILE, format: :midi)
      end

      sequence = MIDI::Sequence.new
      File.open(TEST_MIDI_OUTPUT_FILE, 'rb') { |file| sequence.read(file) }

      expect(sequence.tracks.length).to eq 1
      note_on_events = sequence.tracks.first.events.select { |e| e.is_a?(MIDI::NoteOnEvent) }
      expect(note_on_events.length).to eq @c.instance_variable_get(:@events).length
    end
  end

  context 'MIDI note timing' do
    it 'places note on/off events at the correct tick offsets' do
      File.open(File.join(__dir__, 'example.txt'), 'r') do |in_io|
        @c.build_cues_file(in_io, TEST_MIDI_OUTPUT_FILE, format: :midi)
      end

      sequence = MIDI::Sequence.new
      File.open(TEST_MIDI_OUTPUT_FILE, 'rb') { |file| sequence.read(file) }

      ticks_per_beat = sequence.ppqn
      note_length = (ticks_per_beat * 0.5).round

      note_events = sequence.tracks.first.events.select do |e|
        e.is_a?(MIDI::NoteOnEvent) || e.is_a?(MIDI::NoteOffEvent)
      end

      # Measure 1 is in 3/4 time: a downbeat (clave-high) followed by two
      # metronome clicks (clave-low), each on the percussion channel, one
      # beat apart.
      [
        { class: MIDI::NoteOnEvent, channel: 9, note: 75, time_from_start: 0 },
        { class: MIDI::NoteOffEvent, channel: 9, note: 75, time_from_start: note_length },
        { class: MIDI::NoteOnEvent, channel: 9, note: 37, time_from_start: ticks_per_beat },
        { class: MIDI::NoteOffEvent, channel: 9, note: 37, time_from_start: ticks_per_beat + note_length },
        { class: MIDI::NoteOnEvent, channel: 9, note: 37, time_from_start: ticks_per_beat * 2 }
      ].each_with_index do |attrs, i|
        expect(note_events[i]).to have_attributes(attrs)
      end

      # The "intro" cue is a non-percussion name on the regular note
      # channel, one measure (3 beats) after the downbeat.
      intro_on = note_events.find { |e| e.is_a?(MIDI::NoteOnEvent) && e.note == 68 }
      expect(intro_on.channel).to eq 0
      expect(intro_on.time_from_start).to eq ticks_per_beat * 3
    end
  end

  context 'MIDI tempo' do
    it 'sets the MIDI tempo to match the tempo set in the cues file' do
      File.open(File.join(__dir__, 'example.txt'), 'r') do |in_io|
        @c.build_cues_file(in_io, TEST_MIDI_OUTPUT_FILE, format: :midi)
      end

      sequence = MIDI::Sequence.new
      File.open(TEST_MIDI_OUTPUT_FILE, 'rb') { |file| sequence.read(file) }

      # example.txt sets the tempo to 86 bpm ("t 86"). The MIDI tempo meta
      # event stores microseconds per quarter note, so converting back to
      # bpm can be off by a tiny rounding amount.
      expect(sequence.bpm).to be_within(0.01).of(@c.tempo)
    end
  end

  context 'choosing the metronome samples' do
    it 'lets the user set the downbeat and click clave samples' do
      cue_text = "d middle\nk low\nb 1\n"
      @c.build_cues_file(StringIO.new(cue_text), TEST_OUTPUT_FILE)

      expect(@c.names['_md']).to eq 'clave-middle'
      expect(@c.names['_mk']).to eq 'clave-low'
    end
  end

  context 'uses of sample_file_exists? throughout cues.rb' do
    it 'insert_name accepts a name whose sample file exists' do
      expect { @c.insert_name('one') }.not_to raise_error
      expect(@c.instance_variable_get(:@events).last[:sample_name]).to eq 'one'
    end

    it 'insert_name reports an error and exits when the sample file is missing' do
      silence_output do
        expect { @c.insert_name('no-such-sample') }.to raise_error(SystemExit)
      end
    end

    it 'insert_name looks up mapped names (e.g. "1" => "one") before checking the sample file' do
      expect { @c.insert_name('1') }.not_to raise_error
      expect(@c.instance_variable_get(:@events).last[:sample_name]).to eq 'one'
    end

    it 'set_clave_sample accepts a clave name whose sample file exists' do
      @c.set_clave_sample('_md', 'middle')
      expect(@c.names['_md']).to eq 'clave-middle'
    end

    it 'set_clave_sample reports an error and exits when the clave sample file is missing' do
      silence_output do
        expect { @c.set_clave_sample('_md', 'no-such-clave') }.to raise_error(SystemExit)
      end
    end
  end

  context '#read_sample' do
    it 'raises when the underlying sample file does not exist even though sample_file_exists? was not checked' do
      expect { @c.read_sample('no-such-sample') }.to raise_error(/sample file not found/)
    end
  end
end

def silence_output
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
ensure
  $stdout = original_stdout
end

RSpec::Matchers.define :include_any_nonzero do
  match { |samples| samples.any? { |s| s != 0 } }
end
