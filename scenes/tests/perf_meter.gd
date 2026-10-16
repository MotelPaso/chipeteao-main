class_name PerfMeter
extends RefCounted
## Frame-cost meter the soak harness carries (iteration 63).
##
## WHY IT EXISTS. Every soak runs with --fixed-fps 60, which advances game
## time by exactly 1/60 s per frame and then runs the next frame as fast as
## the machine allows. So a headless soak's WALL time per frame is the CPU
## cost of one frame of the game — scripts, physics, scene tree — with the
## renderer stubbed out, and a windowed soak's is the same plus the GPU.
## Nothing measured that before: the HUD's FPS badge only tells a player
## the number, never which frame cost what or how big the horde was then.
##
## WHAT IT PRINTS. A `Perf` line every WINDOW_FRAMES drawn frames (the
## window's own percentiles beside the horde and node counts, so a slow
## window can be read against what was on screen), and one `Perf summary`
## on the way out. Times are milliseconds of wall clock between two
## consecutive _process calls of the harness. Performance.TIME_PROCESS and
## TIME_PHYSICS_PROCESS are NOT used: in the first soak that sampled them
## the physics one read 280 ms for twenty seconds of 0.6 ms frames — it
## does not describe the frame it is read in.
##
## WITH A WINDOW the wall clock includes the GPU, but on a Mac it is only
## trustworthy FULLSCREEN: a windowed frame went through the compositor's
## sync even under --disable-vsync (one windowed soak read 8.28 ms at p50
## with one enemy and with sixty-four — a 120 Hz panel's refresh), while
## --fullscreen ran uncapped. RenderingServer's measured GPU render time is
## not used either: it read 0.00 for every window on Metal.
##
## It only MEASURES. Nothing here changes the run or what a soak asserts.

## Drawn frames per Perf line: 10 s of game time under --fixed-fps 60.
const WINDOW_FRAMES: int = 600
## Frames skipped before anything is recorded: the boot frame alone loads
## the run scene and every preload behind it, and would own the maximum
## of every soak.
const WARMUP_FRAMES: int = 30
## A frame slower than this is a hitch a player feels (two 60 Hz vsyncs).
const HITCH_MS: float = 33.3

var _last_usec: int = 0
var _frames: int = 0
var _window: PackedFloat32Array = PackedFloat32Array()
var _all: PackedFloat32Array = PackedFloat32Array()
var _hitches: int = 0
var _tree: SceneTree = null


func _init(tree: SceneTree) -> void:
	_tree = tree


## Called from the harness's _process, once per drawn frame.
func tick() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
		return
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_frames += 1
	if _frames <= WARMUP_FRAMES:
		return
	_window.append(ms)
	_all.append(ms)
	if ms > HITCH_MS:
		_hitches += 1
	if _window.size() >= WINDOW_FRAMES:
		_print_window()


func _print_window() -> void:
	var stats := _stats(_window)
	print(("Perf t=%.0f ms avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f"
			+ " enemies=%d nodes=%d orphans=%d"
			+ " draws=%d prims=%d objs3d=%d bodies=%d pairs=%d") % [
			RunState.run_time, stats[0], stats[1], stats[2], stats[3], stats[4],
			_tree.get_node_count_in_group(&"enemies"),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	_window.clear()


## Printed once, from the harness's _exit_tree.
func summary() -> void:
	if _all.is_empty():
		print("Perf summary: frames=0")
		return
	var stats := _stats(_all)
	var total := 0.0
	for ms in _all:
		total += ms
	print("Perf summary: frames=%d wall=%.1fs ms avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f hitches=%d" % [
			_all.size(), total / 1000.0, stats[0], stats[1], stats[2], stats[3],
			stats[4], _hitches])



## [avg, p50, p95, p99, max] of a frame-time sample.
static func _stats(sample: PackedFloat32Array) -> Array[float]:
	var sorted := sample.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += ms
	var last := sorted.size() - 1
	return [total / float(sorted.size()),
			sorted[int(last * 0.50)], sorted[int(last * 0.95)],
			sorted[int(last * 0.99)], sorted[last]]
