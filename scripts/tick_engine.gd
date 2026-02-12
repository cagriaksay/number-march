class_name TickEngine
extends Node

signal tick

@export var tick_duration: float = 1.0

var elapsed: float = 0.0
var running: bool = false
var paused: bool = false

func start() -> void:
	running = true
	paused = false
	elapsed = 0.0

func stop() -> void:
	running = false

func pause() -> void:
	paused = true

func resume() -> void:
	paused = false

func _process(delta: float) -> void:
	if not running or paused:
		return
	elapsed += delta
	if elapsed >= tick_duration:
		elapsed -= tick_duration
		tick.emit()
