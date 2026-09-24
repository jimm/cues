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
