# Cues

Cues is a script that turns a text file that describes metronome clicks and
voice cues into a `.wav` audio file. It plays click and vocal cue samples
("verse", "two", "three", "four") at the beats you specify, mixing them
together into a single audio file you can use directly or import into your
DAW.

The word and metronome ("clave") samples live in the [samples](./samples)
directory.

## The Cue File

The text file format is simple: each line can have one of the following
commands, or it can be a comment (starting with "#") or a blank line.
Anything after any "#" on a line is ignored, so don't use that character in
your custom sample names.

- **track NN**: (t/track) Sets the tempo to NN beats per minute. Default is
  120 bpm.
- **N/M**: Sets the time signature. Default is 4/4.
- **subdivision N**: (v/subdivision) Sets the click subdivision. 4 is a
  quarter note (default), 8 is an eighth, etc. The default is 4 (quarter
  notes).
- **measure N**: (m/meas/measures) Inserts N measures of clicks.
- **beat N**: (b/beat) Inserts N beats of clicks.
- **cue <name> ...**: (c/cue) Cues leading into the next measure or beat.
  "Name" can be any name or the shortcuts "1234" or "234". Each name will be
  played on a beat. Metronome clicks will continue during a cue. (See "Cues
  vs. inline samples" below.)
- **downbeat <clave-name>**: (d/downbeat) Sets which `clave-*.wav` sample
  plays the metronome downbeat (the first beat of each measure).
  "clave-name" is the part of the file name after "clave-", e.g. "high" for
  `clave-high.wav`. The default is "high".
- **click <clave-name>**: (k/click) Sets which `clave-*.wav` sample plays
  the metronome click (every beat other than the downbeat). The default is
  "low". The downbeat and click can be set to the same sample if you want
  every beat to sound the same.
- **<sample-name>**: Insert the sample on the beat and move to the next
  beat. Note that a metronome click will not be played on that beat (but see
  "cue" for how to do that).
- **rest**: (r/rest) Skips to the next beat, playing no audio.

Additionally, there are shortcuts for commonly used samples.

- Any name that has only the numbers 1-4 (soon 1-8) or the letter "r" (for
  _rest_) will be expanded to those individual samples. So for example the
  line "1r2r1234" will be expanded to the lines "1" (an alias for "one"),
  "r" (an alias for "rest"), "2", etc.

Any cue can also use a shortcut name. So for example the line "cue intro
1234" would expand to "intro" then "1", then "2", etc.

Here are the built-in names, each backed by a `.wav` file of the same name
in the samples directory:

- one or 1
- two or 2
- three or 3
- four or 4
- five or 5 (coming soon)
- six or 6 (coming soon)
- seven or 7 (coming soon)
- eight or 8 (coming soon)
- intro
- verse
- chorus
- bridge
- end
- solo (coming soon)
- fade (coming soon)
- rest or r (plays nothing; just advances to the next beat)

Samples can overlap. If a word sample is longer than one beat, it keeps
playing while later clicks or words start on subsequent beats, just as it
would if spoken over a click track.

### Cues vs. inline samples

There's a difference between
```
m 7
intro
234
```
and
```
m 8
cue intro 234
```

The first one will play the metronome for 7 bars, then "intro 2 3 4" with no
metronome, for a total of 8 bars.

The second one will play the metronome for 8 bars, and over the last bar's
metronome you'll hear "intro 2 3 4". Still 8 bars, but you'll hear both the
metronome and the words during the last bar.

## Adding Samples

If you add samples to the [samples](./samples) directory, you can use them
by name. The file "samples/glass.wav" can be inserted by using the name
"glass" in the Cues text file.

## An Example File

```
# Here's a sample Cues file. This text is ignored. This sample file
# sometimes uses the abbreviations for each of the commands ("t" for
# tempo, "c" for cue).

t 120    # Set tempo to 120 (the default)
4/4      # Set the time signature (4/4 is also the default)
v 4      # Set the click subdivision. 4 == quarter note (default),
         # 8 == eighth, etc.

# Count-in. First bar contains four clicks. Second bar contains four
# notes, one on each beat: "intro", "two", "three", and "four". See
# "cue" below for a slightly shorter way to write this.
m 1
intro
234

# Intro
m 8      # 8 bars of intro

# A cue. Because there are four notes in this cue ("verse", "two",
# "three", and "four"), we travel "back in time" four beats to play
# them during the 8th bar.
cue verse 234  # could type "c" instead of "cue"

# Verse 1
m 16

# Verse 2 with cue to the chorus
m 16
c chorus 234

# Chorus with cue to the next verse. Since comment lines and blank
# lines are ignored, it doesn't matter if you put the cue line right
# after the chorus, or right before the verse. It's personal preference.
m 8

# Verse with a cue before it
c verse 234
m 16

# Bridge, with cue before it
c bridge 234
m 16

# ... the rest of the song ...
```

## To Do

- Create the additional samples (5, 6, 7, 8, etc.)
- Add a way to define a section with a name and length, and use that to
  refer to an entire section's worth of metronome clicks. For example, if a
  section was defined with name = "verse" and length = "16" then you could
  type "verse" and it'd be the same as typing "measures 16".
