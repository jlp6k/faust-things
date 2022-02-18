import("stdfaust.lib");

declare name "Granola";
declare author "Jean-Louis Paquelin";
declare copyright "Copyright (C) 2022 Jean-Louis Paquelin <jlp@studionex.com>";
declare version "2022.2.0";  // The version number is YYYY.M.n
declare license "GNU General Public License v3 or later";

// Granola is a granular audio live feed processor.
// Copyright (C) 2022 Jean-Louis Paquelin <jlp@studionex.com>
//
// Granola is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// any later version.
//
// Granola is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Granola.  If not, see <http://www.gnu.org/licenses/>.

/*
    Granola is a monophonic granular live feed processor.

    The grain processor is inspired by the Mutable Instruments Beads. The grain window shape control
    is inspired by the GR-1 Granular synthesizer from Tasty Chips Electronics.

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
        TODO: Automatically trigger grains at a randomized rate.
        TODO: Start a chain of delayed and pitched grains instead of a single one.
    * Grain parameters
        - TIME: Controls the playback position within the table.
          NO NO NO! When the FREEZE toggle button is engaged, as the input signal isn't changing anymore, a slice
          from the table is continuously looped to simulate a live feed. The duration of the slice depends
          on the TIME knob.
          When the the audio isn't FREEZEd, the TIME knob delays the grains.
        - SIZE: Grain duration from 0.03 seconds to the table length, forward or backward playback.
        - SHAPE: The shape of the grain envelope. The shape control allows to morph the shape from a square
          (in this case the grain original amplitude is maintained), to an inverted saw (slow release), to a triangle
          (attack and release time are the same), and finally to a saw (slow attack).
        - PITCH: The pitch of the grain (-2..+2 octaves).
        Note: The four grain parameters are latched when a grain is triggered. Hence, the grain parameters
              remain the same throughout the grain playback but they may differ for multiple grains.
        TODO: TIME slew limiter for tape like scrubing effect. 

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
    // it may rapidly saturate its output. This could be avoided by manualy reducing the output gain or
    // by placing a limiter in the circuit path.
    // Also note that Granola pairs well with a reverb.
    process = Granola(2, 30).ui(0) : co.limiter_1176_R4_mono <: dm.zita_light;
    ```
*/

// The code below is organized in 2 parts: The Granola grain processor, then some
// utility functions.

Granola(BUFFER_DURATION, CONCURRENT_GRAINS) =
environment {
    // (As far as I know) there is no way to get/fix the sample rate at compile time.
    // So the actual sample rate at run time may differ from 48k.
    // Tablesize must be provided at compile time and the actual buffer duration will be greater
    // than the one requeried if ma.SR < 48000.
    tablesize = ceil(BUFFER_DURATION * 48000) : int;
    table = rwtable(tablesize, 0.0);

    grain(grain_number, trigger, writeIndex, g_active,
          time_ctrl,
          size_ctrl,
          pitch_ctrl,
          reverse_ctrl,
          plateau_width_ctrl,
          plateau_position_ctrl) = (writeIndex, _, readIndex : table : *(envelope)), gate
    with {
        // g_size: the number of samples of the grain
        // g_speed: the speed factor of the grain playback
        // g_playback_size: the duration of the playback (in samples)
        g_size = size_ctrl : ba.latch(trigger) : *(ma.SR) : int;
        g_speed = pitch_ctrl;
        g_playback_size = g_size / g_speed : ba.latch(trigger) : int;
        g_direction = select2(reverse_ctrl, 1, -1) : ba.latch(trigger);
        // If recording is not FREEZEd, TIME controls the distance the record head (up to 1 tablesize).
        // If recording is FREEZEd, TIME controls how far the grains (the play heads) are distributed
        // across the table. This way, two consecutive SEEDing produce two different grains.
        g_start_index =
            writeIndex + (tablesize * time_ctrl * select2(writeIndex == writeIndex', 1, g_active / CONCURRENT_GRAINS)) : ba.latch(trigger) : int;
        // compute window attack and sustain in proportions of the total envelope
        // from plateau width and position
        g_sustain = plateau_width_ctrl : ba.latch(trigger);
        g_attack = plateau_position_ctrl * (1 - g_sustain) : ba.latch(trigger);

        // grain clocking
        count = counter(g_playback_size, (g_size - 1) * g_direction, trigger);

        // table read index
        readIndex = (g_start_index + count) % tablesize : int;
        // TODO? Beads stops playback when readIndex reaches/crosses writeIndex.

        // Window
        // Compute the env_gate. It has to be on during attack and sustain, then has to go
        // off to trigger the release of the envelope.
        // Compute the sample index (threshold) value at envelope release start:
        // When the grain is played forward, count goes from 0 to g_size - 1, while
        // when it is played backward, count goes from g_size - 1 to 0.
        forward_release_index = (g_attack + g_sustain) * (g_size - 1);
        backward_release_index = (1 - g_attack - g_sustain) * (g_size - 1);
        // As count is equals 0 when the grain is free (isn't playing), env_gate has
        // to be "gated".
        env_gate = gate & select2(g_direction < 0, count < forward_release_index, count > backward_release_index);

        // compute attack and release times in seconds
        envelopet = float(g_playback_size) / float(ma.SR);
        at = envelopet * g_attack;
        rt = envelopet * (1 - (g_attack + g_sustain));

        envelope = env_gate : en.asr(at, 1, rt) : *(gate);// : ba.lin2LogGain;

        gate = count : >(0);
    };

    grains(freeze_ctrl, writeIndex_ui, density_ctrl, seed_ctrl, input_gain_ctrl, feedback_ctrl, output_gain_ctrl,
           wetting_ctrl, time_ctrl, size_ctrl, size_ctrl, pitch_ctrl, reverse_ctrl,
           plateau_width_ctrl, plateau_position_ctrl) =
        // The output of the grains is fed back into the input stage.
        (input_stage : ((voices_parameters : g_voices), _)) ~ _ : output_stage
    with {
        // period (in samples) of the grain triggering
        g_density = ma.SR / max(density_ctrl, 0.01);

        // g_active counts the number of grains actived (modulo the total number of grains).
        // At each new seed, it has its value increased by 1 modulo CONCURRENT_GRAINS.
        // It allows the spread some behavior across the triggered grains.
        // For instance, passing increasing values to the grains allows them to be spread across the table.
        trigger = (seed_ctrl : ba.impulsify), ba.pulse(g_density) * (density_ctrl >= 0.01) :> _;
        g_active = trigger : (+ : %(10)) ~ _ : +(1);

        // The input_stage has 2 inputs (audio input and feedback) and 2 identical outputs
        // (one for the voices and for the dry signal)
        input_stage = (*(feedback_ctrl) : co.limiter_1176_R4_mono), *(input_gain_ctrl * (1 - freeze_ctrl)) : + <: si.bus(2);
        // The output_stage has 2 inputs (the wet and the dry one., the dry input come directly
        // from the input_stage) and one output (the mix of the two inputs with some gain).
        output_stage = *(wetting_ctrl), *(1 - wetting_ctrl) :> *(output_gain_ctrl);

        // The writeIndex travels the table indices continuously except when the freeze button
        // is engaged.
        writeIndex = writeIndex_counter(tablesize, 1 - freeze_ctrl) : int : writeIndex_ui
        with {
            // TODO? When frozen, smooth the transition between the the newest sample and the oldest.
            writeIndex_counter(size, run) = %(size) ~ +(run);
        };

        // Voices parameters
        voices_parameters = writeIndex, g_active, time_ctrl, size_ctrl, pitch_ctrl, reverse_ctrl, plateau_width_ctrl, plateau_position_ctrl, _;

        // DC offset may appear with short grains, it is removed with the dcblockerat filter stage
        // grain() has 8 parameters: g_active and the audio input + 6 control signals
        g_voices = voices(CONCURRENT_GRAINS, grain, 9, trigger) : fi.dcblockerat(16);
    };

    ui(uix) =
        grains(freeze_ctrl, writeIndex_ui, density_ctrl, seed_ctrl, input_gain_ctrl, feedback_ctrl, output_gain_ctrl,
               wetting_ctrl, time_ctrl, size_ctrl, size_ctrl, pitch_ctrl, reverse_ctrl,
               plateau_width_ctrl, plateau_position_ctrl)
    with {
        // FREEZE recording
        freeze_ctrl = checkbox("h:granola %uix/v:global/v:index/[1]Freeze");
        writeIndex_ui =  hbargraph("h:granola %uix/v:global/v:index/[0]writeIndex", 0, tablesize - 1);

        // Automatic triggering from 0.1 to 100Hz
        density_ctrl = hslider("h:granola %uix/v:grains/[0]density[unit:Hz][scale:log]", 1, 0.01, 1000, 0.01);
        // Manual triggering
        seed_ctrl = button("h:granola %uix/v:grains/SEED");
        // Input Gain
        input_gain_ctrl = vslider("h:granola %uix/v:global/h:volumes/h:input/[0]gain", 0, -1.5, 1, 0.01) : si.smoo : bipollin2exppos(100);
        // Feedback
        feedback_ctrl = vslider("h:granola %uix/v:global/h:volumes/h:input/[1]feedback", 0, 0, 1, 0.01) : si.smoo;
        // Output gain
        output_gain_ctrl = vslider("h:granola %uix/v:global/h:volumes/h:output/[1]gain", 0, -1, 1, 0.01) : si.smoo : bipollin2exppos(100);
        // dry (0) / wet (1)
        wetting_ctrl = vslider("h:granola %uix/v:global/h:volumes/h:output/[0]dry/wet[tooltip:0:dry, 1:wet]", 0.5, 0, 1, 0.01) : si.smoo;

        // position in the table
        time_ctrl = hslider("h:granola %uix/v:grains/[0]time", 0, 0, 1, 0.001);
        // Grain size
        size_ctrl = hslider("h:granola %uix/v:grains/[2]size[unit:s]", 0.5, 0.03, BUFFER_DURATION, 0.01);
        // Grain pitch
        pitch_ctrl = hslider("h:granola %uix/v:grains/[5]pitch[unit:semi]", 0, -24, 24, 0.5) : ba.semi2ratio;
        // Backward playback
        reverse_ctrl = checkbox("h:granola %uix/v:grains/[6]REVERSE");

        // Grain envelope shape
        shape_ctrl = hslider("h:granola %uix/v:grains/[7]shape", 0, 0, 1, 0.01);
        // In order to reduce the number of control knobs, the window plateau width and plateau position
        // are extrapolated from a single shape control. The shape control varies from 0 to 1, smoothly
        // morphing the window envelope from a constant 1, to a decreasing ramp, to a triangle and to an
        // increasing ramp/saw.
        plateau_width_ctrl = 1 - min(shape_ctrl * 3, 1);
        plateau_position_ctrl = max((3 * shape_ctrl/2) - 0.5, 0);
        /*
        // Window plateau width
        plateau_width_ctrl =
            hslider("h:granola %uix/v:grains/v:window/[0]plateau_width", 0.5, 0, 1, 0.001);
        // Window plateau position
        plateau_position_ctrl =
            hslider("h:granola %uix/v:grains/v:window/[1]plateau_position", 0.5, 0.05, 0.95, 0.001);
        */
    };

    demo = Granola(5, 33).ui(0) : co.limiter_1176_R4_mono : hgroup("utilities", ve.moogLadder(normFreq,Q) <: dm.zita_light)
    with {
        fr = hslider("v:moogvcf/[1]cutoff[unit:Hz]", 20000, 20, 20000, 0.1) : si.smoo;
        res = hslider("v:moogvcf/[2]resonance", 0, 0, 0.99, 0.01) : si.smoo;
        
        Q = hslider("v:moogLadder/[1]Q",0.7072,0.7072,25,0.01);
        normFreq = hslider("v:moogLadder/[0]normFreq",1,0,1,0.001):si.smoo;
    };
};

/* --- Utility functions ---------------------------------------------------------------- */

voices(VOICE_COUNT, voice, VOICE_PARAM_COUNT, trigger) =
    ((_ * trigger), si.bus(VOICE_PARAM_COUNT) : parallel_voices(VOICE_COUNT,voice, VOICE_PARAM_COUNT)) ~ _ : !,_
with {
    // parallel_voices
    // The voices are numbered from 1 to VOICE_COUNT
    //  inputs
    //      a trigger with a value corresponding with an available (the last/greatest) voice
    //      VOICE_PARAM_COUNT parallel signals in the order expected by the voice
    //  outputs
    //      the number of the last available voice (0 meaning that there is no more voice available)
    //      the summed outputs of the voices
     parallel_voices(VOICE_COUNT,voice, VOICE_PARAM_COUNT, voice_trigger) =
        voice_trigger_bus, voice_param_bus : ro.interleave(VOICE_COUNT,VOICE_PARAM_COUNT + 1) :
            par(v, VOICE_COUNT, voice_wrapper(voice, v + 1)) : ro.interleave(2,VOICE_COUNT) :
                (si.bus(VOICE_COUNT) :> _), ba.parallelMax(VOICE_COUNT) : ro.cross(2)
    with {
        voice_trigger_bus = voice_trigger <: si.bus(VOICE_COUNT);
        voice_param_bus = par(b, VOICE_PARAM_COUNT, _ <: si.bus(VOICE_COUNT));

        // As a voice, voice_wrapper has 2 outputs, a signal and a gate. However the voice and voice_wrapper
        //gates behaves inversely as described in the following table:
        //          voice gate  |   voice_wrapper gate  
        //      ----------------+-----------------------
        //              0       |   v (the voice number)
        //              1       |           0
        // When the voice gate is greater than 0, it means that the voice is busy. So when the voice_wrapper
        // gate is greater than 0, it means that the corresponding voice is free to be used.
        voice_wrapper(voice, v, called_voice) =
            voice(v, v == called_voice) : _, ((1 - _) * v);
    };
};

// value in [-1, 1]
// produces results in [1/max_output, max_output]
bipollin2exppos(max_output, value) = exp(value * log(max_output));

// If scale >= 0, counts from 0 to scale in (period - 1) steps then goes back to 0.
// If scale < 0, counts from -scale to 0 in (period - 1) steps then goes back to 0.
// The trigger is inhibited when the counter counts to prevent retriggering.
counter(period, scale, trigger) = (trigger & (_ == 0) : count) ~ _
// The previous recursion allows to inhibit the trigger while the counter is active.
// The trigger is passed to the counter when the counter output equals 0. 
with {
    // The counter will count in p steps then will go back to 0. Hence, the whole
    // process will be at the specified period. 
    p = max(1, period - 1);

    // The counter will count from start in delta direction.
    start = select2(scale >= 0, p, 0);
    delta = select2(scale >= 0, -1, 1);

    // Resetting the counter output to 0 after the count is done with _ <: *(_ != _')
    // i.e. the counter doesn't change anymore so its output is multiplied by 0.
    // Scaling from p to scale is done with _ : /(p) : *(abs(scale))
    count(trigger) = select2(trigger > trigger', +(delta) : max(0) : min(p), start) ~ _ <: *(_ != _') : /(p) : *(abs(scale));
};
