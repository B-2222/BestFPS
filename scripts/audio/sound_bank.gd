class_name SoundBank
extends RefCounted
## Procedurally generated sound effects.
##
## Every sound here is synthesised at load rather than loaded from a file. Two
## reasons: this environment cannot reach any asset host, and more usefully, a
## generated bank has no licence attached and no binary blobs in the repo --
## the "asset" is thirty lines of maths that can be re-tuned by changing a
## number instead of re-recording.
##
## They are placeholders in the same sense the weapon models are. When real
## audio arrives it replaces the streams; nothing that *plays* them changes.

const RATE := 32000

## Cached by name, because building a stream costs a few milliseconds and a
## rifle asks for the same one ten times a second.
static var _cache: Dictionary = {}

static func get_sound(name: StringName) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var stream := _build(name)
	_cache[name] = stream
	return stream

static func _build(name: StringName) -> AudioStreamWAV:
	match name:
		# duration, body pitch, brightness, punch -- the four dials that make a
		# rifle crack, a shotgun boom and a pistol snap out of the same code.
		&"shot_rifle": return _gunshot(0.22, 110.0, 0.55, 0.9, 11)
		&"shot_shotgun": return _gunshot(0.42, 68.0, 0.32, 1.3, 22)
		&"shot_sniper": return _gunshot(0.58, 84.0, 0.44, 1.15, 33)
		&"shot_pistol": return _gunshot(0.16, 140.0, 0.70, 0.7, 44)
		&"mag_out": return _click(0.09, 320.0, 0.75, 55)
		&"mag_in": return _click(0.12, 190.0, 0.60, 66)
		&"charge": return _click(0.15, 240.0, 0.85, 77)
		&"switch": return _click(0.10, 260.0, 0.55, 88)
		&"footstep": return _thud(0.11, 90.0, 0.55, 99)
		&"land": return _thud(0.24, 58.0, 0.40, 111)
		&"jump": return _thud(0.09, 150.0, 0.30, 122)
		&"hit": return _blip(0.055, 1500.0, 1100.0)
		&"hit_head": return _blip(0.075, 2100.0, 1500.0)
		&"kill": return _blip(0.20, 900.0, 300.0)
		&"impact": return _thud(0.10, 220.0, 0.80, 133)
	return _click(0.05, 300.0, 0.5, 1)

# ---------------------------------------------------------------------------

## Noise through a one-pole low pass for the crack, plus a downward-swept sine
## for the body. Real gunshots are mostly broadband noise with a low thump
## underneath, and that is enough to tell four weapons apart.
static func _gunshot(duration: float, body_hz: float, brightness: float,
		punch: float, seed_value: int) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var filtered := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var progress := t / duration
		# Sharp attack, long-ish tail.
		var envelope := exp(-progress * 6.0) * (1.0 - exp(-t * 900.0))
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), brightness)
		var swept := body_hz * (1.0 - 0.55 * progress)
		var body := sin(TAU * swept * t) * exp(-t * 16.0)
		samples[i] = clampf((filtered * 0.8 + body * punch) * envelope, -1.0, 1.0)
	return _to_stream(samples)

## Mechanical noises: a short tone with a noisy transient on the front.
static func _click(duration: float, tone_hz: float, noise_mix: float,
		seed_value: int) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var t := float(i) / float(RATE)
		var envelope := exp(-t * 45.0) * (1.0 - exp(-t * 2500.0))
		var tone := sin(TAU * tone_hz * t)
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 160.0)
		samples[i] = clampf((tone * (1.0 - noise_mix) + noise * noise_mix) * envelope, -1.0, 1.0)
	return _to_stream(samples)

## Footfalls and impacts: heavily damped low noise, no tone to speak of.
static func _thud(duration: float, body_hz: float, damping: float,
		seed_value: int) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var filtered := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var envelope := exp(-t / (duration * 0.30))
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), damping)
		var body := sin(TAU * body_hz * t) * exp(-t * 26.0)
		samples[i] = clampf((filtered * 0.5 + body * 0.8) * envelope, -1.0, 1.0)
	return _to_stream(samples)

## Interface feedback: a clean swept sine, no noise.
static func _blip(duration: float, start_hz: float, end_hz: float) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var progress := t / duration
		var frequency := lerpf(start_hz, end_hz, progress)
		phase += TAU * frequency / float(RATE)
		var envelope := exp(-progress * 4.5) * (1.0 - exp(-t * 1200.0))
		samples[i] = clampf(sin(phase) * envelope * 0.7, -1.0, 1.0)
	return _to_stream(samples)

static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
