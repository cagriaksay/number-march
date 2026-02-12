class_name SpawnManager
extends Node

signal spawn_number(value: int)
signal queue_updated(visible: Array[int])
signal all_spawned

var number_sequence: Array[int] = []
var spawn_index: int = 0
var ticks_between_spawns: int = 5
var tick_counter: int = 0
var finished: bool = false
var spawn_blocked: bool = false  # true when last spawn was requeued

func setup(sequence: Array[int], interval: int) -> void:
	number_sequence = sequence
	ticks_between_spawns = interval
	spawn_index = 0
	tick_counter = interval  # start at threshold so first number spawns immediately
	finished = false
	_emit_queue()

func on_tick() -> void:
	if finished:
		return
	# Don't advance timer if last spawn was blocked (waiting for start cell to clear)
	if spawn_blocked:
		_spawn_next()
		return
	tick_counter += 1
	if tick_counter >= ticks_between_spawns:
		tick_counter = 0
		_spawn_next()

func _spawn_next() -> void:
	if spawn_index >= number_sequence.size():
		finished = true
		all_spawned.emit()
		return
	spawn_blocked = false
	var value: int = number_sequence[spawn_index]
	spawn_index += 1
	spawn_number.emit(value)
	_emit_queue()

func _emit_queue() -> void:
	queue_updated.emit(get_visible_queue())

func get_visible_queue() -> Array[int]:
	var end_idx: int = mini(spawn_index + 13, number_sequence.size())
	var result: Array[int] = []
	for i in range(spawn_index, end_idx):
		result.append(number_sequence[i])
	return result

func requeue_number(value: int) -> void:
	"""Re-insert a number at the front of the remaining sequence (spawn was blocked)."""
	spawn_blocked = true
	number_sequence.insert(spawn_index, value)
	_emit_queue()

func is_done() -> bool:
	return finished
