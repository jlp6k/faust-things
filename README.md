# Faust Things

This repository contains various audio related projects programmed in Faust.

### Granola

Granola is a monophonic granular live feed processor.

The grain processor is inspired by the Mutable Instruments Beads. The grain window shape control is inspired by the GR-1 Granular synthesizer from Tasty Chips Electronics.

#### Specifications

* Audio I/O
    - Manual input and output gain control.
    - Recording time: BUFFER_DURATION.
    - The FREEZE button freezes the content of the recording table.
    - Feedback path with attenuation and limiter (with 1 sample delay). The feedback signal comes from
        the grains output (it's before the dry/wet crossfader).
    - Dry/Wet control.
    - TODO: Stereo I/O with automatic level detection with a limiter.
    - TODO: Gate signal in sync with the grains.
    - TODO: Antialiased output.
    - TODO: Spatialized output.
* Grains generation modes
    - The SEED button triggers a grain.
    - Automatically trigger grains at a periodic rate with the DENSITY parameter (at maximum density
        there are 1000 grains generated per second (M.I. Beads has a maximum rate of ~260 grains per second).  
    Note: The actual number of triggered grains cannot exceed the CONCURRENT_GRAINS value (30 for M.I. Beads).
    - TODO: Automatically trigger grains at a randomized rate.
    - TODO: Start a chain of delayed and pitched grains instead of a single one.
* Grain parameters
    - TIME: Controls the playback position of each grain within the table. In other words, it delays the grains.
    - SIZE: Grain duration from 0.03 seconds to the table length, forward or backward playback.
    - SHAPE: The shape of the grain envelope. The shape control allows to morph the shape from a square
        (in this case the grain original amplitude is maintained), to an inverted saw (slow release), to a triangle
        (attack and release time are the same), and finally to a saw (slow attack).  
        ![Window envelope from the shape parameter value](https://raw.githubusercontent.com/jlp6k/faust-things/main/images/Granola/Window%20shape.gif)
    - PITCH: The pitch of the grain (-2..+2 octaves).  
    Note: The four grain parameters are latched when a grain is triggered. Hence, the grain parameters
            remain the same throughout the grain playback but they may differ for multiple grains.
    - TODO: TIME slew limiter for tape like scrubing effect.

#### Usage

```
_ : Granola(BUFFER_DURATION, CONCURRENT_GRAINS).ui(uix) : _
```

Where:

* `BUFFER_DURATION`: buffer duration in seconds.
* `CONCURRENT_GRAINS`: (int) number of grains allocated.
* `uix`: (int) the UI instance number.


A demo function of Granola with a limiter, a LPF and a reverb on the output.

```
_ : Granola(BUFFER_DURATION, CONCURRENT_GRAINS).demo : _, _
```

#### Examples

```
// A Granola's demonstration setup with a 5 seconds buffer and an up-to-15-grains polyphony.
process = Granola(5, 15).demo;
```

```
// A Granola grain processor.
// It has a 1 second audio buffer and up to 30 grains playing a the same time.
process = Granola(1, 30).ui(0);
```

```
// Two Granola instances allowing to process each channel of a stereo signal differently.
// They have a 5 seconds audio buffer and up to 15 grains playing a the same time.
process = Granola(5, 15).ui(0), Granola(5, 15).ui(1);
```

```
// Two Granola instances sharing the same user interface making a stereo grain processor.
// They have a 5 seconds audio buffer and up to 15 grains playing a the same time.
process = Granola(5, 15).ui(0), Granola(5, 15).ui(0);
```

```
// As the Granola grain processor is able to play many copies of the input signal simultaneously,
// it may rapidly saturate its output. This could be avoided by manualy reducing the output gain,
// by selecting a smoother grain-window shape and/or by placing a limiter in the circuit path.
// Also note that Granola pairs well with a reverb.
process = Granola(2, 30).ui(0) : co.limiter_1176_R4_mono <: dm.zita_light;
```

```
// Granola used as a delay like effect. Parameters are taylored for the default audio file
// of the Faust web IDE (wait 5 seconds to let the table be filled). Play it looped.
process = Granola(5, 10).grains(0, _, 4.76, 0, 0.5, 0, 0.5, 0.5, 0.03, 0.5, 1, 0, 0, 0.5);
```

```
// Granola used as a complex feedback effect: the most important parameter here is the 6th,
// the feedback control. Feed the input with some audio (the looped  default audio file, for
// example). Let the feedback grow. It will gradually decrease when the sound is muted.
//
// __Be careful with your ears, this can get very loud.__
//
process = Granola(5, 10).grains(0, _, 4.72, 0, 1, 0.4, 1, 0.6, 0.604, 3, 0.972, 0, 0, 0.5);
```
