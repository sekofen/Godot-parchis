extends RefCounted
## Offline synthesis source for the game's original sound palette.
## Dedicated deterministic noise; never reads the gameplay random generator.
const RATE := 24000
const DURATIONS := {"select": .10, "dice_charge": .65, "dice_impact": .24, "launch": .7, "travel": .25, "land": .24, "shield": .65, "capture": .8, "finish": 1.1, "victory": 1.8, "comms": .42, "text": .035, "turn": .3, "doubles": .65}

static func render(key: String) -> AudioStreamWAV:
	var duration: float = DURATIONS[key]
	var count := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 240519 + key.hash()
	var noise := 0.0
	for sample in range(count):
		var t := float(sample) / RATE
		var u := t / duration
		noise = lerpf(noise, rng.randf_range(-1, 1), .35)
		var v := 0.0
		match key:
			"select": v = sin(TAU * 740 * t) * exp(-t * 42) * .6
			"text": v = (sin(TAU * 1200 * t) * .25 + noise * .2) * exp(-t * 120)
			"dice_charge": v = (sin(TAU * (90 * t + 190 * t * t)) * .38 + noise * .25) * sin(PI * u)
			"dice_impact": v = noise * exp(-t * 38) * .85 + sin(TAU * 145 * t) * exp(-t * 28) * .45
			"launch": v = (sin(TAU * (80 * t + 360 * t * t)) * .3 + noise * .45) * sin(PI * u)
			"travel": v = (noise * .3 + sin(TAU * 180 * t) * .22) * sin(PI * u)
			"land": v = (sin(TAU * (150 * t - 50 * t * t)) * .65 + noise * .1) * exp(-t * 20)
			"capture": v = (sin(TAU * (650 * t - 330 * t * t)) * .4 + noise * .3) * sin(PI * u) * (1 - u)
			"shield": v = (sin(TAU * 440 * t) + .5 * sin(TAU * 660 * t) + .25 * sin(TAU * 880 * t)) * exp(-t * 6) * .45
			"comms": v = (sin(TAU * 523.25 * t) * .4 + sin(TAU * 784 * t) * .2) * exp(-t * 8)
			"turn": v = sin(TAU * (440 if u < .5 else 554.37) * t) * sin(PI * fmod(u * 2, 1.0)) * .35
			"doubles", "finish", "victory":
				var notes := [261.63, 329.63, 392.0, 523.25]
				for index in range(4):
					var local_t := t - index * duration * .14
					if local_t >= 0:
						v += sin(TAU * float(notes[index]) * (2 if key == "doubles" else 1) * local_t) * exp(-local_t * 4) * .2
		# A short edge ramp prevents clicks, and a soft ceiling prevents clipping.
		var edge := minf(t * 500, 1) * minf((duration - t) * 150, 1)
		bytes.encode_s16(sample * 2, int(clampf(v * edge, -.9, .9) * 32767))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = RATE
	sound.data = bytes
	return sound
