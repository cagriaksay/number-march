class_name NumberEntity
extends Node2D

var value: int = 1
var grid_pos: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var cell_size: float = 39.0
var board: GameBoard
var is_moving: bool = false
var dead: bool = false  # solved or escaped — stop all logic

var color_number: Color = Color("#333333")
var color_strike: Color = Color("#CC2222")
var caveat_font: Font

# Continuous movement
var walk_from: Vector2 = Vector2.ZERO
var walk_to: Vector2 = Vector2.ZERO
var walk_progress: float = 0.0
var walk_speed: float = 1.0  # 0-1 progress per second
var move_direction: Vector2i = Vector2i.ZERO
var checked_towers: bool = false  # check once per tile at midpoint
var pending_advance: bool = false  # queued next advance from tick

# Walk animation (South Park style: tilt side to side)
var walk_steps: int = 4
var tilt_amount: float = 0.18  # radians (~10°)
var bounce_amount: float = 2.0  # pixels vertical bounce

@onready var label: Label = $Label

func setup(start_value: int, start_pos: Vector2i, initial_path: Array[Vector2i], game_board: GameBoard) -> void:
	value = start_value
	grid_pos = start_pos
	path = initial_path
	board = game_board
	_update_label()

func _ready() -> void:
	caveat_font = load("res://assets/fonts/Caveat-Bold.ttf")
	if caveat_font and label:
		label.add_theme_font_override("font", caveat_font)
	# Apply pencil shader directly to the label
	var pencil_shader = load("res://assets/shaders/pencil.gdshader")
	if pencil_shader and label:
		var mat := ShaderMaterial.new()
		mat.shader = pencil_shader
		label.material = mat
	_update_label()

func set_path(new_path: Array[Vector2i]) -> void:
	path = new_path

func advance() -> void:
	"""Called each tick. Queue up the next move."""
	if dead:
		return
	if is_moving:
		# Already moving — queue the next advance for when we arrive
		pending_advance = true
		return
	_start_next_move()

func _start_next_move() -> void:
	if path.is_empty():
		_reach_exit()
		return

	var next_cell: Vector2i = path[0]

	# Skip this tick if the next cell is occupied
	if board.is_cell_occupied(next_cell):
		return

	path.remove_at(0)

	# Release old cell, reserve new one
	board.release_cell(self)
	board.reserve_cell(next_cell, self)

	move_direction = next_cell - grid_pos
	grid_pos = next_cell
	is_moving = true
	checked_towers = false

	walk_from = position
	walk_to = board.grid_to_local(next_cell)
	walk_progress = 0.0

	# Speed: traverse one tile in exactly one tick (continuous, no gap)
	var tick: float = board.tick_engine.tick_duration if board.tick_engine else 1.0
	walk_speed = 1.0 / tick

func _process(delta: float) -> void:
	if dead or not is_moving:
		return

	walk_progress += delta * walk_speed
	if walk_progress > 1.0:
		walk_progress = 1.0

	# Smooth position interpolation
	position = walk_from.lerp(walk_to, walk_progress)

	# Walk animation: South Park style tilt side to side
	var current_step: int = int(walk_progress * walk_steps)
	if current_step >= walk_steps:
		current_step = walk_steps - 1
	var step_phase: float = fmod(walk_progress * walk_steps, 1.0)
	var lean_direction: float = 1.0 if current_step % 2 == 0 else -1.0
	var lean_intensity: float = sin(step_phase * PI)

	# Rock/tilt left-right like a paper cutout waddling
	rotation = lean_direction * lean_intensity * tilt_amount
	# Small vertical bounce (up at mid-step)
	position.y -= lean_intensity * bounce_amount

	# Arrived at tile center — check towers here
	if walk_progress >= 1.0:
		position = walk_to
		rotation = 0.0
		is_moving = false

		# Division check at the center of the tile (right next to adjacent towers)
		if not checked_towers:
			checked_towers = true
			_check_adjacent_towers()

		# Stop if solved/escaped during tower check
		if dead:
			return

		# Immediately start next move if one is pending (continuous motion)
		if pending_advance:
			pending_advance = false
			_start_next_move()

func _check_adjacent_towers() -> void:
	var adj_towers: Array = board.get_adjacent_towers(grid_pos)
	for tower in adj_towers:
		var diff: Vector2i = tower.grid_pos - grid_pos
		if absi(diff.x) + absi(diff.y) != 1:
			continue
		if tower.value >= 2 and value % tower.value == 0:
			var old_value: int = value
			value = value / tower.value
			tower.degrade()
			_play_divide_effect(old_value)
			_update_label()
			if value <= 1:
				_solve()
				return

func _solve() -> void:
	"""Number reduced to 1 or less — disappear."""
	dead = true
	board.remove_number_from_tracking(self)
	board.number_solved.emit(value)
	_play_eraser_effect()

func _reach_exit() -> void:
	"""Number reached the end tile."""
	dead = true
	board.remove_number_from_tracking(self)
	if value > 1:
		board.number_escaped.emit(value)
		board.health_manager.take_damage(value)
		_play_escape_effect()
	else:
		board.number_solved.emit(value)
		_play_eraser_effect()

func _update_label() -> void:
	if label:
		label.text = str(value)
		label.add_theme_color_override("font_color", color_number)
		label.add_theme_constant_override("outline_size", 1)
		label.add_theme_color_override("font_outline_color", color_number)
		var font_size: int = 22
		if value >= 100:
			font_size = 14
		elif value >= 10:
			font_size = 18
		label.add_theme_font_size_override("font_size", font_size)

func _play_divide_effect(old_value: int) -> void:
	var flash := Label.new()
	flash.text = str(old_value)
	flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if caveat_font:
		flash.add_theme_font_override("font", caveat_font)
	flash.add_theme_font_size_override("font_size", 11)
	flash.add_theme_color_override("font_color", color_strike)
	flash.size = Vector2(cell_size, 20)
	flash.position = Vector2(-cell_size / 2.0, -cell_size / 2.0 - 8)
	add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "position:y", flash.position.y - 18, 0.35)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.35)
	tween.tween_callback(flash.queue_free)

func _play_eraser_effect() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.2)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)

func _play_escape_effect() -> void:
	modulate = Color(1, 0.3, 0.3, 1)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
