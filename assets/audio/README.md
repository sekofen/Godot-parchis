# Original sci-fi effects

Fourteen original synthesized mono 24 kHz WAV effects: selection, dice charge,
dice impact, launch, travel, landing, shield, capture recall, extraction, victory,
communications, text tick, turn change and doubles. No voice recordings, sampled
third-party audio, or external sound downloads.

The source is `tools/AudioPalette.gd`. Rebuild the assets with:

```
godot --headless --path . --script tools/bake_audio.gd
```

Noise uses a dedicated deterministic generator, independent of gameplay dice.
Envelopes ramp both edges and samples are limited below full scale. Godot may
compress the imported streams; WAV source files remain PCM16. `ArenaAudio.gd`
loads assets into a bounded voice pool with throttled UI ticks. Effects and
nonverbal dialogue cues have independent levels. Muting stops current sounds.
Settings and portrait motion preference persist in `user://audio_settings.cfg`.
