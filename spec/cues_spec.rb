require 'rspec'
require 'stringio'
require 'wavefile'
require_relative '../lib/cues'

include WaveFile

TEST_OUTPUT_FILE = '/tmp/cues_test.wav'

RSpec.describe Cues do
  before(:each) { @c = Cues.new }

  after(:each) do
    File.delete(TEST_OUTPUT_FILE) if File.exist?(TEST_OUTPUT_FILE)
  end

  context 'building an audio file' do
    it 'generates a valid wave file with the metronome mixed in' do
      File.open(File.join(__dir__, 'example.txt'), 'r') do |in_io|
        @c.build_cues_audio_file(in_io, TEST_OUTPUT_FILE)
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

  context 'choosing the metronome samples' do
    it 'lets the user set the downbeat and click clave samples' do
      cue_text = "d middle\nk low\nb 1\n"
      @c.build_cues_audio_file(StringIO.new(cue_text), TEST_OUTPUT_FILE)

      expect(@c.names['_md']).to eq 'clave-middle.wav'
      expect(@c.names['_mk']).to eq 'clave-low.wav'
    end
  end
end

RSpec::Matchers.define :include_any_nonzero do
  match { |samples| samples.any? { |s| s != 0 } }
end
