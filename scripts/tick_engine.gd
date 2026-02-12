class_name TickEngine
extends Node

signal tick

@export var tick_duration: float = 1.0

var elapsed: float = 0.0
var running: bool = false

func start() -> void:
	running = true
	elapsed = 0.0

func stop() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if elapsed >= tick_duration:
		elapsed -= tick_duration
		tick.emit()
