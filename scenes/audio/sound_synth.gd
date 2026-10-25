class_name SoundSynth
## Audio domain: the procedural sound engine. Renders a *recipe* — a length plus a list of layers —
## into a 16-bit mono AudioStreamWAV, with no files and no outside input: a recipe and a seed always
## render to the same bytes (the noise comes from a local RandomNumberGenerator, never the gameplay
## one).
##
## Recipe: { "length": s, "drive": 0 (optional tanh saturation), "vary": 0 (optional), "loop": false
## (optional), "layers": [layer, …] }. Every layer has `type`, `gain` (default 1) and `delay` (s,
## default 0) and runs from its delay until it has decayed:
##   noise  white noise through an envelope — `attack` (s), `decay` (time constant, s), `lp` / `hp`
##          (low-pass, two poles, and high-pass, one pole, cut-off in Hz; 0 = off). Cracks, scuffs,
##          hiss, tails.
##   tone   a sine that glides from `freq` to `freq_end` (time constant `sweep`) under an envelope
##          with `decay`. Thumps, pings.
##   modes  damped sinusoids — `freqs`, optional `amps`, `decays` (one per mode, or one `decay` for
##          all), optional `detune` (± fraction, random per mode). How a struck material rings.
##   pulses a periodic excitation rung through resonators: `rate` pulses a second (rounded to whole
##          pulses per clip; 0 = continuous noise instead of pulses), each a burst of noise decaying
##          over `burst` s, its level cycling through `pattern` (an engine's cylinders) and nudged
##          by `spread`, its timing by `jitter` (a fraction of the gap); the excitation is shaped by
##          `lp` / `hp`, then `noise` of it is heard as it is and the rest rings through the
##          resonators `freqs` / `amps` / `decays`; `wobble` [cycles per clip, depth] swells it. An
##          engine's firing, a tyre's squeal.
## `vary` (0..1) makes every render of a recipe its own take: each layer's gain, decay, glide,
## cut-offs, partial levels and delay are nudged by up to that fraction (a pitch by about half of
## it), drawn from the seed, so one recipe yields many distinct but related sounds. A footstep wants
## it; a gunshot does not. The mix is normalized to SoundLibraryConfig.peak, optionally saturated,
## and faded out over its last few ms. A `loop` recipe is not faded and its stream loops forward
## over the whole clip. In a loop, whatever a layer still sounds past the clip's end comes round
## again at its start (a pulse near the end rings on into the beginning), so decaying layers join
## without a seam; a steady tone must still be a whole number of cycles of the length.

## An envelope below this has ended; a layer stops there instead of running to the end of the clip.
const SILENCE := 0.0006
## Time constants a layer is run for before it is considered finished (e^-8 ≈ -70 dB).
const TAIL_CONSTANTS := 8.0
## Fade (s) applied to the end of every clip so it never ends on a click.
const FADE_OUT := 0.004


## Render `recipe` to a stream. `seed_value` fixes its noise and detune.
static func render(recipe: Dictionary, seed_value: int) -> AudioStreamWAV:
	var rate := SoundLibraryConfig.sample_rate
	var count := maxi(int(float(recipe.get("length", 0.3)) * rate), 1)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var vary: float = recipe.get("vary", 0.0)
	var loop: bool = recipe.get("loop", false)
	for source: Dictionary in recipe.get("layers", []):
		var layer := _varied(source, vary, rng) if vary > 0.0 else source
		match layer.get("type", ""):
			"noise":
				_noise(mix, layer, rate, rng, loop)
			"tone":
				_tone(mix, layer, rate, loop)
			"modes":
				_modes(mix, layer, rate, rng, loop)
			"pulses":
				_pulses(mix, layer, rate, rng, loop)
	return _to_stream(mix, rate, float(recipe.get("drive", 0.0)), loop)


## A copy of `layer` with its numbers nudged by up to `vary` (see the header): levels and times by
## the full amount, frequencies and cut-offs by half of it.
static func _varied(layer: Dictionary, vary: float, rng: RandomNumberGenerator) -> Dictionary:
	var out := layer.duplicate()
	for key: String in ["gain", "decay", "sweep", "attack"]:
		if out.has(key):
			out[key] = float(out[key]) * (1.0 + rng.randf_range(-vary, vary))
	for key: String in ["freq", "freq_end", "lp", "hp"]:
		if out.has(key) and float(out[key]) > 0.0:
			out[key] = float(out[key]) * (1.0 + rng.randf_range(-vary, vary) * 0.5)
	if out.has("delay") and float(out["delay"]) > 0.0:
		out["delay"] = float(out["delay"]) * (1.0 + rng.randf_range(-vary, vary) * 0.5)
	for key: String in ["amps", "freqs", "decays"]:
		if out.has(key):
			out[key] = _nudged(out[key], vary, 0.5 if key == "freqs" else 1.0, rng)
	return out


## `values` each nudged, in order, by a roll of up to `vary` times `scale` (1 for levels and times,
## 0.5 for frequencies).
static func _nudged(values: Array, vary: float, scale: float, rng: RandomNumberGenerator) -> Array:
	var scaled := []
	for v in values:
		scaled.append(float(v) * (1.0 + rng.randf_range(-vary, vary) * scale))
	return scaled


## Peak absolute sample (0..1) of a 16-bit mono stream made by `render`.
static func peak_of(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var peak := 0
	for i in range(0, data.size() - 1, 2):
		peak = maxi(peak, absi(data.decode_s16(i)))
	return peak / 32_768.0


## One-pole low-pass coefficient for cut-off `hz` (1 = pass everything).
static func _coef(hz: float, rate: int) -> float:
	if hz <= 0.0:
		return 1.0
	return 1.0 - exp(-TAU * hz / rate)


## One-pole high-pass coefficient for a layer's `hp` cut-off (0 = no high-pass).
static func _hp(layer: Dictionary, rate: int) -> float:
	var hz: float = layer.get("hp", 0.0)
	return _coef(hz, rate) if hz > 0.0 else 0.0


## Samples an envelope with time constant `decay` (s) takes to die away (TAIL_CONSTANTS of them).
static func _ring(decay: float, rate: int) -> int:
	return int(decay * rate * TAIL_CONSTANTS)


## Samples a layer that rings for `ring` samples runs for, starting at `start` in a clip of `size`:
## to the clip's end, or in a loop (`looped`) for at most one clip's length, round past the end.
static func _span(size: int, start: int, ring: int, looped := false) -> int:
	return maxi(mini(size if looped else size - start, ring), 0)


## Where sample `i` lands in a clip of `size`: past the end it comes round to the start (a layer
## runs at most one clip long).
static func _at(i: int, size: int) -> int:
	return i - size if i >= size else i


## Shape `samples` in place: two poles of low-pass (`lp`, a `_coef`: a duller roll-off than one),
## then one of high-pass (`hp`, 0 = none).
static func _shape(samples: PackedFloat32Array, lp: float, hp: float) -> void:
	var low := 0.0
	var low2 := 0.0
	var slow := 0.0
	for i in samples.size():
		low += lp * (samples[i] - low)
		low2 += lp * (low - low2)
		var y := low2
		if hp > 0.0:
			slow += hp * (y - slow)
			y -= slow
		samples[i] = y


## Mix a layer of decaying noise (shaped by a 2-pole low-pass and a 1-pole high-pass) into `mix`.
static func _noise(
	mix: PackedFloat32Array,
	layer: Dictionary,
	rate: int,
	rng: RandomNumberGenerator,
	looped := false,
) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var attack := maxi(int(float(layer.get("attack", 0.0005)) * rate), 1)
	var decay := maxf(float(layer.get("decay", 0.02)), 0.0005)
	var voice := PackedFloat64Array([
		layer.get("gain", 1.0),
		exp(-1.0 / (decay * rate)),
		_coef(float(layer.get("lp", 0.0)), rate),
		_hp(layer, rate),
		attack,
	])
	_mix_noise(mix, Vector2i(start, _span(mix.size(), start, _ring(decay, rate) + attack, looped)),
			voice, rng)


## Mix up to `span.y` samples of noise into `mix` from sample `span.x` (round past its end), each
## drawn from `rng` and shaped as it goes; `voice` is the layer's [gain, envelope fall a sample,
## low-pass coefficient, high-pass coefficient (0 = none), attack in samples]. Stops once the
## envelope drops below SILENCE.
static func _mix_noise(
	mix: PackedFloat32Array,
	span: Vector2i,
	voice: PackedFloat64Array,
	rng: RandomNumberGenerator,
) -> void:
	var gain := voice[0]
	var fall := voice[1]
	var lp := voice[2]
	var hp := voice[3]
	var attack := int(voice[4])
	var size := mix.size()
	var env := 1.0
	var low := 0.0
	var low2 := 0.0
	var slow := 0.0
	for i in span.y:
		low += lp * (rng.randf() * 2.0 - 1.0 - low)
		low2 += lp * (low - low2)  # two poles: a duller roll-off than one
		if hp > 0.0:
			slow += hp * (low2 - slow)
		mix[_at(span.x + i, size)] += ((low2 - slow if hp > 0.0 else low2) * env * gain
				* (float(i + 1) / attack if i < attack else 1.0))
		env *= fall
		if env < SILENCE:
			break


## Mix a layer of decaying sine, gliding from `freq` to `freq_end`, into `mix`.
static func _tone(mix: PackedFloat32Array, layer: Dictionary, rate: int, looped := false) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var gain: float = layer.get("gain", 1.0)
	var f1: float = layer.get("freq_end", layer.get("freq", 100.0))
	var decay := maxf(float(layer.get("decay", 0.05)), 0.0005)
	var glide := exp(-1.0 / (maxf(float(layer.get("sweep", 0.03)), 0.0005) * rate))
	var fall := exp(-1.0 / (decay * rate))
	var size := mix.size()
	var phase := 0.0
	var bend: float = float(layer.get("freq", 100.0)) - f1
	var env := 1.0
	for i in _span(size, start, _ring(decay, rate), looped):
		phase += TAU * (f1 + bend) / rate
		mix[_at(start + i, size)] += sin(phase) * env * gain
		bend *= glide
		env *= fall
		if env < SILENCE:
			break


## Each mode is a two-pole resonator, y[n] = 2r·cos(w)·y[n-1] - r²·y[n-2]: a damped sine with no
## per-sample sin() or exp().
static func _modes(
	mix: PackedFloat32Array,
	layer: Dictionary,
	rate: int,
	rng: RandomNumberGenerator,
	looped := false,
) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var freqs: Array = layer.get("freqs", [])
	var amps: Array = layer.get("amps", [])
	var decays: Array = layer.get("decays", [])
	var detune: float = layer.get("detune", 0.0)
	for m in freqs.size():
		var hz := float(freqs[m]) * (1.0 + rng.randf_range(-detune, detune))
		if hz >= rate * 0.45:
			continue  # past what the sample rate can carry
		var decay := maxf(
			float(decays[m]) if m < decays.size() else float(layer.get("decay", 0.05)),
			0.0005,
		)
		var n := _span(mix.size(), start, _ring(decay, rate), looped)
		if n < 2:
			continue
		var level := (float(amps[m]) if m < amps.size() else 1.0) * float(layer.get("gain", 1.0))
		_resonate(mix, Vector2i(start, n), TAU * hz / rate, exp(-1.0 / (decay * rate)), level)


## Ring one mode into `mix` over `span` (x the layer's first sample, y how many it runs for): a
## two-pole resonator at angular step `w` and per-sample radius `r`, struck at `level`, stopped once
## it has died away.
static func _resonate(
	mix: PackedFloat32Array,
	span: Vector2i,
	w: float,
	r: float,
	level: float,
) -> void:
	var size := mix.size()
	var c1 := 2.0 * r * cos(w)
	var c2 := -r * r
	var y2 := 0.0
	var y1 := level * r * sin(w)
	mix[_at(span.x + 1, size)] += y1
	for i in range(2, span.y):
		var y := c1 * y1 + c2 * y2
		mix[_at(span.x + i, size)] += y
		y2 = y1
		y1 = y
		if absf(y) + absf(y2) < SILENCE * 0.1:
			break


## Mix a `pulses` layer (see the header) into `mix`. The excitation (a train of noise bursts, or
## continuous noise) is shaped by the low- and high-pass, heard directly at `noise`, and drives each
## resonator; everything runs on past the clip's end until it has decayed, and in a loop (`looped`)
## that overhang is folded back onto the start, so the clip is one period of a train that never
## began: it loops without a seam.
static func _pulses(
	mix: PackedFloat32Array,
	layer: Dictionary,
	rate: int,
	rng: RandomNumberGenerator,
	looped := false,
) -> void:
	var count := mix.size()
	var exc := PackedFloat32Array()
	exc.resize(count + _ring(_longest(layer), rate))
	if float(layer.get("rate", 0.0)) > 0.0:
		_train(exc, layer, rate, rng, looped)
	else:
		for i in count:
			exc[i] = rng.randf() * 2.0 - 1.0
	_shape(exc, _coef(float(layer.get("lp", 0.0)), rate), _hp(layer, rate))
	_fold(mix, _resonated(exc, layer, rate), layer, looped)


## A `pulses` layer's burst time constant (s).
static func _burst(layer: Dictionary) -> float:
	return maxf(float(layer.get("burst", 0.01)), 0.0005)


## The longest time constant (s) of a `pulses` layer, its burst or a resonator's decay: how long it
## runs on past the clip's end.
static func _longest(layer: Dictionary) -> float:
	var longest := _burst(layer)
	for d in layer.get("decays", []):
		longest = maxf(longest, float(d))
	return longest


## Add a `pulses` layer's train of noise bursts to `exc` (the clip, then its tail): `rate` a second,
## rounded to whole pulses per clip, each placed with its `jitter`, at its `pattern` level nudged by
## `spread`; one that would start before the clip comes round from its end in a loop (`looped`),
## else starts at its start.
static func _train(
	exc: PackedFloat32Array,
	layer: Dictionary,
	rate: int,
	rng: RandomNumberGenerator,
	looped: bool,
) -> void:
	var tail := _ring(_longest(layer), rate)
	var count := exc.size() - tail
	var pulses := maxi(roundi(float(count) / rate * float(layer.get("rate", 0.0))), 1)
	var gap := float(count) / pulses
	var jitter: float = layer.get("jitter", 0.0)
	var span := mini(_ring(_burst(layer), rate), tail)
	var fall := exp(-1.0 / (_burst(layer) * rate))
	for k in pulses:
		var at := roundi(k * gap + rng.randf_range(-jitter, jitter) * gap)
		if at < 0:
			at += count if looped else -at
		var env := _pulse_level(layer, k, rng)
		for i in span:
			exc[at + i] += (rng.randf() * 2.0 - 1.0) * env
			env *= fall


## The level of pulse `k` of a `pulses` layer: its `pattern` entry, nudged by up to `spread`.
static func _pulse_level(layer: Dictionary, k: int, rng: RandomNumberGenerator) -> float:
	var pattern: Array = layer.get("pattern", [1.0])
	var spread: float = layer.get("spread", 0.0)
	return float(pattern[k % pattern.size()]) * (1.0 + rng.randf_range(-spread, spread))


## A `pulses` layer's sound before its gain: the shaped excitation `exc` heard directly at `noise`,
## plus each of its resonators driven by it (a resonator's decay is the layer's longest when it
## names none).
static func _resonated(exc: PackedFloat32Array, layer: Dictionary, rate: int) -> PackedFloat32Array:
	var n := exc.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var direct: float = layer.get("noise", 0.0)
	if direct != 0.0:
		for i in n:
			out[i] = exc[i] * direct
	var freqs: Array = layer.get("freqs", [])
	var amps: Array = layer.get("amps", [])
	var decays: Array = layer.get("decays", [])
	for m in freqs.size():
		var hz := float(freqs[m])
		if hz >= rate * 0.45:
			continue  # past what the sample rate can carry
		var decay := maxf(float(decays[m]) if m < decays.size() else _longest(layer), 0.0005)
		var amp := float(amps[m]) if m < amps.size() else 1.0
		_drive(out, exc, TAU * hz / rate, exp(-1.0 / (decay * rate)), amp)
	return out


## Add to `out` a resonator at angular step `w` and per-sample radius `r` driven by `exc`, scaled
## so it peaks near `amp` whatever its frequency and decay.
static func _drive(
	out: PackedFloat32Array,
	exc: PackedFloat32Array,
	w: float,
	r: float,
	amp: float,
) -> void:
	var c1 := 2.0 * r * cos(w)
	var c2 := -r * r
	var drive := amp * (1.0 - r) * 2.0 * sin(w)
	var y1 := 0.0
	var y2 := 0.0
	for i in out.size():
		var y := c1 * y1 + c2 * y2 + exc[i] * drive
		out[i] += y
		y2 = y1
		y1 = y


## Mix a `pulses` layer's sound `out` (the clip, then its tail) into `mix` at its `gain`: in a loop
## (`looped`) the tail folded back onto the start, swelled by its `wobble` [cycles per clip, depth].
static func _fold(
	mix: PackedFloat32Array,
	out: PackedFloat32Array,
	layer: Dictionary,
	looped: bool,
) -> void:
	var count := mix.size()
	var n := out.size()
	var gain: float = layer.get("gain", 1.0)
	var wobble: Array = layer.get("wobble", [0, 0.0])
	var cycles := float(wobble[0])
	var depth := float(wobble[1])
	for i in count:
		var v := out[i]
		if looped:
			var j := i + count
			while j < n:
				v += out[j]
				j += count
		if depth != 0.0:
			v *= 1.0 + depth * sin(TAU * cycles * i / count)
		mix[i] += v * gain


## Normalize, optionally saturate, fade the tail (unless it loops) and pack as 16-bit little-endian
## PCM.
static func _to_stream(
	mix: PackedFloat32Array,
	rate: int,
	drive: float,
	loop := false,
) -> AudioStreamWAV:
	var count := mix.size()
	var top := 0.0
	for i in count:
		top = maxf(top, absf(mix[i]))
	var fade := 0 if loop else maxi(int(FADE_OUT * rate), 1)
	var norm := 1.0 / tanh(drive) if drive > 0.0 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var v := mix[i] / top if top > 0.000001 else 0.0
		if drive > 0.0:
			v = tanh(v * drive) * norm
		v *= SoundLibraryConfig.peak
		if fade > 0 and i >= count - fade:
			v *= float(count - i) / fade
		bytes.encode_s16(i * 2, clampi(int(v * 32_767.0), -32_767, 32_767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream
