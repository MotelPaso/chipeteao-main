extends Node
## Autoload "Sfx": pooled playback for the synthesized sound set in
## assets/audio/sfx (rendered by scripts/tools/generate_sfx.gd — every
## sound is original, generated audio). One-shots go through play() onto a
## round-robin pool of AudioStreamPlayers so overlapping hits never cut
## each other; loops (the shrine channel hum) get a dedicated voice via
## play_loop()/stop_loop(). Repetitive ids take a small random pitch
## jitter against machine-gun sameness, spammy ids are rate limited so
## hordes can't clip, and everything routes through an "Sfx" bus created
## in code (headless-safe: players simply mix into the dummy driver).
## Processes always, so card picks and run-end stingers sound under pause.

const BUS_NAME := &"Sfx"

const STREAMS: Dictionary[StringName, AudioStream] = {
	&"hit_soft": preload("res://assets/audio/sfx/hit_soft.wav"),
	&"hit_crit": preload("res://assets/audio/sfx/hit_crit.wav"),
	&"enemy_die": preload("res://assets/audio/sfx/enemy_die.wav"),
	&"gem_pickup": preload("res://assets/audio/sfx/gem_pickup.wav"),
	&"level_up": preload("res://assets/audio/sfx/level_up.wav"),
	&"card_pick": preload("res://assets/audio/sfx/card_pick.wav"),
	&"player_hurt": preload("res://assets/audio/sfx/player_hurt.wav"),
	&"dodge": preload("res://assets/audio/sfx/dodge.wav"),
	&"slide": preload("res://assets/audio/sfx/slide.wav"),
	&"shrine_channel": preload("res://assets/audio/sfx/shrine_channel.wav"),
	&"shrine_done": preload("res://assets/audio/sfx/shrine_done.wav"),
	&"chest_open": preload("res://assets/audio/sfx/chest_open.wav"),
	&"boss_roar": preload("res://assets/audio/sfx/boss_roar.wav"),
	&"boss_roar_2": preload("res://assets/audio/sfx/boss_roar_2.wav"),
	&"boss_die": preload("res://assets/audio/sfx/boss_die.wav"),
	&"streak": preload("res://assets/audio/sfx/streak.wav"),
	&"laser_hum": preload("res://assets/audio/sfx/laser_hum.wav"),
	&"burrow_pop": preload("res://assets/audio/sfx/burrow_pop.wav"),
}

## Ids meant for play_loop(): forced to LOOP_FORWARD at ready, because the
## generated wav files carry no loop metadata.
const LOOP_IDS: Array[StringName] = [&"shrine_channel", &"laser_hum"]

## One-shot voices; overlapping sounds round-robin across these.
@export var pool_size: int = 12
## Master SFX level, applied to the "Sfx" audio bus.
@export var bus_volume_db: float = 0.0
## Default random pitch spread (fraction, so 0.08 = ±8%) for jittered_ids.
@export var default_pitch_jitter: float = 0.08
## Repetitive ids that get default_pitch_jitter when play() is called
## without an explicit jitter.
@export var jittered_ids: Array[StringName] = [
	&"hit_soft", &"hit_crit", &"enemy_die", &"gem_pickup", &"burrow_pop",
]
## Per-id cap on plays per rolling second; ids not listed are uncapped.
@export var rate_limits: Dictionary[StringName, int] = {
	&"hit_soft": 10,
	&"hit_crit": 10,
	&"gem_pickup": 10,
	&"burrow_pop": 8,
}
## Per-id base volume (dB) so the constant hit_soft sits well under the
## rare stingers; play()'s volume_db_offset stacks on top.
@export var id_volume_db: Dictionary[StringName, float] = {
	&"hit_soft": -14.0,
	&"hit_crit": -7.0,
	&"enemy_die": -10.0,
	&"gem_pickup": -12.0,
	&"level_up": -4.0,
	&"card_pick": -6.0,
	&"player_hurt": -5.0,
	&"dodge": -8.0,
	&"slide": -10.0,
	&"shrine_channel": -10.0,
	&"shrine_done": -5.0,
	&"chest_open": -5.0,
	&"boss_roar": -3.0,
	&"boss_roar_2": -3.0,
	&"boss_die": -2.0,
	&"streak": -6.0,
	&"laser_hum": -16.0,
	&"burrow_pop": -8.0,
}


## Rolling one-second window of play timestamps for one rate-limited id.
class RateWindow:
	extends RefCounted
	var times: Array[float] = []


var _pool: Array[AudioStreamPlayer] = []
## Per-voice start stamp (seconds); drives the steal policy below.
var _started_at: Array[float] = []
var _next_voice: int = 0
var _rate_state: Dictionary[StringName, RateWindow] = {}
var _loop_players: Dictionary[StringName, AudioStreamPlayer] = {}
## Live acquire_loop() holders per id (several lasers share one hum voice).
var _loop_refcounts: Dictionary[StringName, int] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bus()
	for i in pool_size:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS_NAME
		add_child(voice)
		_pool.append(voice)
		_started_at.append(-1000.0)
	for id: StringName in LOOP_IDS:
		var wav := STREAMS.get(id) as AudioStreamWAV
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))


## Autoloads only leave the tree at app shutdown. Anything still mid-
## playback then is released by the audio thread, which races engine
## teardown and loses ("leaked AudioStreamPlayback" on headless exits) —
## so stop every voice and wait out one dummy-driver mix period (~93ms)
## before teardown continues.
func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _pool:
		voice.stop()
	stop_all_loops()
	OS.delay_msec(200)


## Fire a one-shot. volume_db_offset stacks on the id's base volume.
## pitch_jitter < 0 means "use the id's default" (default_pitch_jitter for
## jittered_ids, none otherwise); pass an explicit fraction to override.
func play(id: StringName, volume_db_offset: float = 0.0, pitch_jitter: float = -1.0) -> void:
	var stream := STREAMS.get(id) as AudioStream
	if stream == null:
		push_warning("Sfx: unknown sound id '%s'" % id)
		return
	var now := _now()
	if not _rate_check(id, now):
		return
	var idx := _alloc_voice()
	var voice := _pool[idx]
	voice.stream = stream
	voice.volume_db = _id_volume(id) + volume_db_offset
	voice.pitch_scale = _rolled_pitch(id, pitch_jitter)
	voice.play()
	_started_at[idx] = now


## Starts a dedicated looping voice for `id` (no-op while already
## playing). Loop voices live outside the one-shot pool and are never
## stolen.
func play_loop(id: StringName) -> void:
	var stream := STREAMS.get(id) as AudioStream
	if stream == null:
		push_warning("Sfx: unknown loop id '%s'" % id)
		return
	var player := _loop_players.get(id) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = BUS_NAME
		player.stream = stream
		player.volume_db = _id_volume(id)
		add_child(player)
		_loop_players[id] = player
	if not player.playing:
		player.play()


func stop_loop(id: StringName) -> void:
	var player := _loop_players.get(id) as AudioStreamPlayer
	if player != null and player.playing:
		player.stop()


## Reference-counted loop for sounds many emitters share (laser beams):
## the loop starts on the first acquire and stops only when every acquirer
## has released. Emitters MUST pair each acquire with exactly one release
## (guard with a held flag; release from _exit_tree for mid-loop frees).
func acquire_loop(id: StringName) -> void:
	var count := int(_loop_refcounts.get(id, 0))
	_loop_refcounts[id] = count + 1
	if count == 0:
		play_loop(id)


func release_loop(id: StringName) -> void:
	var count := int(_loop_refcounts.get(id, 0))
	if count <= 0:
		return
	count -= 1
	_loop_refcounts[id] = count
	if count == 0:
		stop_loop(id)


## How many acquire_loop() holders `id` currently has (test hook).
func loop_refcount(id: StringName) -> int:
	return int(_loop_refcounts.get(id, 0))


## Run-end safety: the manager processes through pause, so a channel hum
## started before a death would otherwise drone over the end screen.
## Clears loop refcounts too — holders are about to be freed with the run.
func stop_all_loops() -> void:
	for id: StringName in _loop_players:
		_loop_players[id].stop()
	_loop_refcounts.clear()


# --- voice allocation -------------------------------------------------------

## Round-robin scan for an idle voice starting at the cursor. Steal
## policy: with every voice busy, the voice that STARTED LONGEST AGO is
## restarted (it is the closest to finishing and the least noticeable to
## lose); ties break to the lowest index.
func _alloc_voice() -> int:
	for offset in _pool.size():
		var idx := (_next_voice + offset) % _pool.size()
		if not _pool[idx].playing:
			_next_voice = (idx + 1) % _pool.size()
			return idx
	var oldest := 0
	for i in _pool.size():
		if _started_at[i] < _started_at[oldest]:
			oldest = i
	_next_voice = (oldest + 1) % _pool.size()
	return oldest


# --- helpers ----------------------------------------------------------------

## True (and the play is recorded) when `id` is under its per-second cap
## at time `now`. Takes the clock as a parameter so a harness can prove
## the cap over a simulated second.
func _rate_check(id: StringName, now: float) -> bool:
	if not rate_limits.has(id):
		return true
	if not _rate_state.has(id):
		_rate_state[id] = RateWindow.new()
	var window: RateWindow = _rate_state[id]
	var times := window.times
	while not times.is_empty() and now - times[0] > 1.0:
		times.pop_front()
	if times.size() >= rate_limits[id]:
		return false
	times.append(now)
	return true


func _rolled_pitch(id: StringName, override_jitter: float) -> float:
	var jitter := override_jitter
	if jitter < 0.0:
		jitter = default_pitch_jitter if jittered_ids.has(id) else 0.0
	if jitter <= 0.0:
		return 1.0
	return 1.0 + randf_range(-jitter, jitter)


func _id_volume(id: StringName) -> float:
	return id_volume_db[id] if id_volume_db.has(id) else 0.0


## Real (pause- and time_scale-immune) clock for stamps and rate windows.
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _setup_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_send(idx, &"Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_NAME), bus_volume_db)
