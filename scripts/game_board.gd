class_name GameBoard
extends Node2D

signal tower_placed(tower: Node2D)
signal number_solved(value: int)
signal number_escaped(value: int)
signal level_complete(stars: int)
signal edit_dirty_changed(dirty: bool)

const COLS: int = 10
const ROWS: int = 20
const MAX_TOWER_VALUE: int = 49

enum CellType { PATH, WALL, TOWER, START, END }

# Grid state
var grid: Array = []  # 2D: grid[x][y]
var cell_size: float = 39.0
var board_offset: Vector2 = Vector2.ZERO

# Pathfinding
var astar: AStarGrid2D

# Cell positions
var start_cell: Vector2i = Vector2i.ZERO
var end_cell: Vector2i = Vector2i.ZERO

# Entity tracking
var towers: Dictionary = {}  # Vector2i -> Tower node
var numbers: Array = []  # active NumberEntity nodes
var occupied_cells: Dictionary = {}  # Vector2i -> NumberEntity (cell reservation)
var level_finished: bool = false
var game_paused: bool = false
var edit_mode: bool = false
var _edit_placing: String = ""  # "", "start", or "end"
var _edit_dirty: bool = false  # true if grid changed since last save
var _edit_saved_layout: PackedStringArray = []  # layout at last save

# References (set by main)
var health_manager: HealthManager
var tick_engine: TickEngine
var spawn_manager: SpawnManager
var audio_manager: AudioManager

# Visual layers
@onready var tower_container: Node2D = $TowerContainer
@onready var number_container: Node2D = $NumberContainer
@onready var effects_container: Node2D = $EffectsContainer
var hint_container: Node2D  # for tutorial text

# Preloads
var number_scene: PackedScene = preload("res://scenes/entities/number_entity.tscn")
var tower_scene: PackedScene = preload("res://scenes/entities/tower.tscn")

# Colors
var color_paper: Color = Color("#FDF8E8")
var color_grid: Color = Color("#A8C8E8")
var color_margin: Color = Color("#E88888")
var color_wall: Color = Color("#555555")
var color_path: Color = Color("#FDF8E8")
var color_start: Color = Color("#88CC88")
var color_end: Color = Color("#CC8888")
var color_invalid: Color = Color("#FF0000")

# Font
var caveat_font: Font

func _ready() -> void:
	caveat_font = load("res://assets/fonts/Caveat-Bold.ttf")
	# Create hint container (between towers and numbers, so text is behind marching numbers)
	hint_container = Node2D.new()
	hint_container.name = "HintContainer"
	add_child(hint_container)
	move_child(hint_container, tower_container.get_index() + 1)
	_compute_layout()

func _compute_layout() -> void:
	cell_size = 38.0
	var viewport_size: Vector2 = get_viewport_rect().size
	var board_width: float = cell_size * COLS
	board_offset.x = (viewport_size.x - board_width) / 2.0
	board_offset.y = 60.0  # safe area below notch

# ─── Level Loading ───────────────────────────────────────────────

func load_level(data: LevelData) -> void:
	_clear_board()
	_init_grid()
	_parse_layout(data.grid_layout)
	_setup_astar()
	_spawn_tutorial_hints(data.tutorial_hints)
	queue_redraw()

func _clear_board() -> void:
	for child in tower_container.get_children():
		child.queue_free()
	for child in number_container.get_children():
		child.queue_free()
	for child in effects_container.get_children():
		child.queue_free()
	if hint_container:
		for child in hint_container.get_children():
			child.queue_free()
	towers.clear()
	numbers.clear()
	occupied_cells.clear()
	level_finished = false

func _init_grid() -> void:
	grid = []
	for x in COLS:
		var col: Array = []
		for y in ROWS:
			col.append(CellType.PATH)
		grid.append(col)

func _parse_layout(layout: PackedStringArray) -> void:
	for y in layout.size():
		var row_str: String = layout[y]
		for x in row_str.length():
			if x >= COLS:
				break
			var ch: String = row_str[x]
			match ch:
				"#":
					grid[x][y] = CellType.WALL
				".":
					grid[x][y] = CellType.PATH
				"S":
					grid[x][y] = CellType.START
					start_cell = Vector2i(x, y)
				"E":
					grid[x][y] = CellType.END
					end_cell = Vector2i(x, y)
				_:
					grid[x][y] = CellType.PATH

# ─── Tutorial Hints ──────────────────────────────────────────────

func _spawn_tutorial_hints(hints: Array) -> void:
	if hints.is_empty():
		return
	var pencil_shader: Shader = load("res://assets/shaders/pencil.gdshader")
	for hint in hints:
		if not (hint is Dictionary):
			continue
		var text: String = hint.get("text", "")
		var gx: int = hint.get("x", 0)
		var gy: int = hint.get("y", 0)
		var gw: int = hint.get("width", 4)
		if text.is_empty():
			continue

		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		# Position in grid coordinates
		var px: float = board_offset.x + gx * cell_size
		var py: float = board_offset.y + gy * cell_size
		label.position = Vector2(px, py)
		var gh: int = hint.get("height", 2)
		label.size = Vector2(gw * cell_size, gh * cell_size)

		# Font: Caveat Bold, pencil shader
		label.add_theme_font_override("font", caveat_font)
		label.add_theme_font_size_override("font_size", 32)
		label.add_theme_color_override("font_color", Color("#666666"))
		label.add_theme_constant_override("outline_size", 1)
		label.add_theme_color_override("font_outline_color", Color("#666666"))

		# Pencil shader
		var mat := ShaderMaterial.new()
		mat.shader = pencil_shader
		label.material = mat

		# Random rotation for hand-written notebook feel
		label.pivot_offset = label.size / 2.0
		label.rotation = randf_range(-0.08, 0.08)

		hint_container.add_child(label)

# ─── Pathfinding ─────────────────────────────────────────────────

func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, COLS, ROWS)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.cell_size = Vector2(1, 1)
	astar.update()
	for x in COLS:
		for y in ROWS:
			if grid[x][y] == CellType.WALL or grid[x][y] == CellType.TOWER:
				astar.set_point_solid(Vector2i(x, y))

func get_path_for_number(from: Vector2i) -> Array[Vector2i]:
	if from == end_cell:
		return []
	var id_path = astar.get_id_path(from, end_cell)
	if id_path.size() <= 1:
		return []
	var result: Array[Vector2i] = []
	for i in range(1, id_path.size()):
		result.append(Vector2i(id_path[i]))
	return result

func can_place_tower(cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return false
	var cell_type = grid[cell.x][cell.y]
	if cell_type != CellType.PATH and cell_type != CellType.WALL:
		return false

	# Don't place a tower on a cell occupied by a marching number
	if occupied_cells.has(cell):
		return false

	# Walls are already solid — placing a tower there never breaks connectivity
	if cell_type == CellType.WALL:
		return true

	# For path tiles, temporarily block and check connectivity
	astar.set_point_solid(cell, true)

	# Check start -> end connectivity
	var path_exists: bool = astar.get_id_path(start_cell, end_cell).size() > 0

	# Check all active numbers can still reach end
	if path_exists:
		for num in numbers:
			if is_instance_valid(num) and num.grid_pos != end_cell:
				if astar.get_id_path(num.grid_pos, end_cell).size() == 0:
					path_exists = false
					break

	if not path_exists:
		astar.set_point_solid(cell, false)
		return false

	return true

func place_tower(cell: Vector2i) -> void:
	var was_path: bool = (grid[cell.x][cell.y] == CellType.PATH)
	grid[cell.x][cell.y] = CellType.TOWER
	# For path tiles, astar was already marked solid in can_place_tower
	# For wall tiles, astar was already solid — no change needed

	var tower_node = tower_scene.instantiate()
	tower_node.grid_pos = cell
	tower_node.position = grid_to_local(cell)
	tower_node.cell_size = cell_size
	tower_container.add_child(tower_node)
	towers[cell] = tower_node

	# Only repath if we blocked a path tile (walls were already blocked)
	if was_path:
		_repath_all_numbers()
	queue_redraw()
	tower_placed.emit(tower_node)

func _repath_all_numbers() -> void:
	for num in numbers:
		if is_instance_valid(num):
			var new_path := get_path_for_number(num.grid_pos)
			num.set_path(new_path)

# ─── Number Management ───────────────────────────────────────────

func spawn_number(value: int) -> void:
	# If start cell is occupied, delay — the occupant will move on this tick
	# (numbers are advanced before spawns in the tick order, so this is a fallback)
	if occupied_cells.has(start_cell):
		# Queue for next tick via spawn_manager
		if spawn_manager:
			spawn_manager.requeue_number(value)
		return
	var num_node = number_scene.instantiate()
	num_node.cell_size = cell_size
	var initial_path := get_path_for_number(start_cell)
	number_container.add_child(num_node)
	num_node.setup(value, start_cell, initial_path, self)
	num_node.position = grid_to_local(start_cell)
	numbers.append(num_node)
	occupied_cells[start_cell] = num_node

func remove_number_from_tracking(num: Node2D) -> void:
	# Release occupied cell
	release_cell(num)
	numbers.erase(num)
	# Check level complete after removal
	_check_level_complete()

func is_cell_occupied(cell: Vector2i) -> bool:
	return occupied_cells.has(cell)

func reserve_cell(cell: Vector2i, num: Node2D) -> void:
	occupied_cells[cell] = num

func release_cell(num: Node2D) -> void:
	# Remove any cell this number occupies
	var to_remove: Array[Vector2i] = []
	for cell in occupied_cells:
		if occupied_cells[cell] == num:
			to_remove.append(cell)
	for cell in to_remove:
		occupied_cells.erase(cell)

func on_tick() -> void:
	if level_finished:
		return
	# Advance numbers front-to-back (closest to exit first)
	# so each frees its cell for the one behind it
	var nums_copy: Array = numbers.duplicate()
	nums_copy.sort_custom(_sort_by_path_length)
	for num in nums_copy:
		if is_instance_valid(num) and num in numbers:
			num.advance()

func _sort_by_path_length(a: Variant, b: Variant) -> bool:
	# Shorter remaining path = closer to exit = should move first
	return a.path.size() < b.path.size()

func _check_level_complete() -> void:
	if level_finished:
		return
	if health_manager and health_manager.current_hp <= 0:
		return
	if spawn_manager and spawn_manager.is_done() and numbers.size() == 0:
		level_finished = true
		var stars := health_manager.get_stars()
		level_complete.emit(stars)

# ─── Tower Queries ───────────────────────────────────────────────

func get_tower_at(cell: Vector2i) -> Node2D:
	return towers.get(cell, null)

func get_adjacent_towers(cell: Vector2i) -> Array:
	"""Returns towers adjacent to cell in clockwise order: N, E, S, W"""
	var result: Array = []
	var directions: Array[Vector2i] = [
		Vector2i(0, -1),  # N
		Vector2i(1, 0),   # E
		Vector2i(0, 1),   # S
		Vector2i(-1, 0),  # W
	]
	for dir in directions:
		var adj: Vector2i = cell + dir
		if towers.has(adj):
			result.append(towers[adj])
	return result

# ─── Coordinate Conversion ───────────────────────────────────────

func grid_to_local(cell: Vector2i) -> Vector2:
	return Vector2(
		board_offset.x + cell.x * cell_size + cell_size / 2.0,
		board_offset.y + cell.y * cell_size + cell_size / 2.0
	)

func local_to_grid(pos: Vector2) -> Vector2i:
	var x: int = floori((pos.x - board_offset.x) / cell_size)
	var y: int = floori((pos.y - board_offset.y) / cell_size)
	return Vector2i(x, y)

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS

# ─── Input ───────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if edit_mode:
		if event is InputEventScreenTouch and event.pressed:
			_handle_edit_touch(event.position)
			get_viewport().set_input_as_handled()
		return
	# Don't consume input when paused or level is over
	if game_paused or level_finished or (health_manager and health_manager.current_hp <= 0):
		return
	# Only handle ScreenTouch — mouse clicks are emulated to touch via project settings
	if event is InputEventScreenTouch and event.pressed:
		_handle_touch(event.position)
		get_viewport().set_input_as_handled()

func _handle_touch(screen_pos: Vector2) -> void:
	var cell := local_to_grid(screen_pos)
	if not _in_bounds(cell):
		return

	var cell_type = grid[cell.x][cell.y]

	match cell_type:
		CellType.PATH, CellType.WALL:
			_try_place_tower(cell)
		CellType.TOWER:
			_try_upgrade_tower(cell)
		_:
			pass  # start, end — do nothing

# ─── Edit Mode ───────────────────────────────────────────────────

func _handle_edit_touch(screen_pos: Vector2) -> void:
	var cell := local_to_grid(screen_pos)
	if not _in_bounds(cell):
		return

	# If placing start or end, set it on this cell
	if _edit_placing == "start":
		_edit_move_marker(cell, CellType.START)
		_edit_placing = ""
		return
	if _edit_placing == "end":
		_edit_move_marker(cell, CellType.END)
		_edit_placing = ""
		return

	var cell_type = grid[cell.x][cell.y]
	match cell_type:
		CellType.PATH:
			_edit_set_cell(cell, CellType.WALL)
		CellType.WALL:
			_edit_set_cell(cell, CellType.PATH)
		CellType.START:
			_edit_placing = "start"
		CellType.END:
			_edit_placing = "end"
		CellType.TOWER:
			_edit_set_cell(cell, CellType.PATH)

func _edit_set_cell(cell: Vector2i, new_type: int) -> void:
	var old_type = grid[cell.x][cell.y]
	grid[cell.x][cell.y] = new_type
	# Rebuild A* and check path still exists
	_setup_astar()
	var test_path = astar.get_id_path(start_cell, end_cell)
	if test_path.is_empty():
		# Revert — would break path
		grid[cell.x][cell.y] = old_type
		_setup_astar()
		return
	# Remove tower if converting tower cell
	if old_type == CellType.TOWER and towers.has(cell):
		var tower_node = towers[cell]
		tower_node.queue_free()
		towers.erase(cell)
	_check_edit_dirty()
	queue_redraw()

func _edit_move_marker(cell: Vector2i, marker_type: int) -> void:
	# Clear old marker position
	if marker_type == CellType.START:
		grid[start_cell.x][start_cell.y] = CellType.PATH
		start_cell = cell
	elif marker_type == CellType.END:
		grid[end_cell.x][end_cell.y] = CellType.PATH
		end_cell = cell
	grid[cell.x][cell.y] = marker_type
	_setup_astar()
	_check_edit_dirty()
	queue_redraw()

func edit_clear() -> void:
	# Clear all walls and towers, keep start/end, make everything else path
	for x in COLS:
		for y in ROWS:
			if grid[x][y] == CellType.WALL:
				grid[x][y] = CellType.PATH
			elif grid[x][y] == CellType.TOWER:
				if towers.has(Vector2i(x, y)):
					var tower_node = towers[Vector2i(x, y)]
					tower_node.queue_free()
					towers.erase(Vector2i(x, y))
				grid[x][y] = CellType.PATH
	_setup_astar()
	_check_edit_dirty()
	queue_redraw()

func _check_edit_dirty() -> void:
	var was_dirty := _edit_dirty
	_edit_dirty = get_grid_layout() != _edit_saved_layout
	if _edit_dirty != was_dirty:
		edit_dirty_changed.emit(_edit_dirty)

func mark_edit_saved() -> void:
	_edit_saved_layout = get_grid_layout()
	var was_dirty := _edit_dirty
	_edit_dirty = false
	if was_dirty:
		edit_dirty_changed.emit(false)

func get_grid_layout() -> PackedStringArray:
	var layout := PackedStringArray()
	for y in ROWS:
		var row: String = ""
		for x in COLS:
			match grid[x][y]:
				CellType.WALL:
					row += "#"
				CellType.START:
					row += "S"
				CellType.END:
					row += "E"
				CellType.TOWER:
					row += "."  # towers export as path
				_:
					row += "."
		layout.append(row)
	return layout

# ─── Tower Placement ─────────────────────────────────────────────

func _try_place_tower(cell: Vector2i) -> void:
	if not can_place_tower(cell):
		_flash_invalid(cell)
		return
	if not health_manager.spend(1):
		return
	place_tower(cell)
	if audio_manager:
		audio_manager.play_tower_place()
		audio_manager.vibrate(30)

func _try_upgrade_tower(cell: Vector2i) -> void:
	var tower = get_tower_at(cell)
	if tower == null:
		return
	if tower.value >= MAX_TOWER_VALUE:
		return
	if not health_manager.spend(1):
		return
	tower.increment()
	if audio_manager:
		audio_manager.play_tower_place()
		audio_manager.vibrate(20)

func _flash_invalid(cell: Vector2i) -> void:
	# Visual feedback for invalid placement
	var flash := ColorRect.new()
	flash.color = Color(1, 0, 0, 0.3)
	flash.size = Vector2(cell_size, cell_size)
	flash.position = Vector2(
		board_offset.x + cell.x * cell_size,
		board_offset.y + cell.y * cell_size
	)
	effects_container.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)

# ─── Drawing ─────────────────────────────────────────────────────

func _draw() -> void:
	_draw_paper_background()
	_draw_grid_lines()
	_draw_cells()

func _draw_paper_background() -> void:
	var rect := Rect2(
		board_offset.x, board_offset.y,
		COLS * cell_size, ROWS * cell_size
	)
	draw_rect(rect, color_paper)

func _draw_grid_lines() -> void:
	# Vertical lines
	for x in range(COLS + 1):
		var from := Vector2(board_offset.x + x * cell_size, board_offset.y)
		var to := Vector2(board_offset.x + x * cell_size, board_offset.y + ROWS * cell_size)
		draw_line(from, to, color_grid, 1.0)
	# Horizontal lines
	for y in range(ROWS + 1):
		var from := Vector2(board_offset.x, board_offset.y + y * cell_size)
		var to := Vector2(board_offset.x + COLS * cell_size, board_offset.y + y * cell_size)
		draw_line(from, to, color_grid, 1.0)

func _draw_cells() -> void:
	for x in COLS:
		for y in ROWS:
			var rect := Rect2(
				board_offset.x + x * cell_size + 1,
				board_offset.y + y * cell_size + 1,
				cell_size - 2, cell_size - 2
			)
			match grid[x][y]:
				CellType.WALL:
					_draw_wall_cell(rect, x, y)
				CellType.START:
					_draw_colored_shading(rect, x, y, Color(0.2, 0.55, 0.25, 0.35), Color(0.25, 0.6, 0.3, 0.25))
					_draw_play_button(rect, x, y)
				CellType.END:
					_draw_colored_shading(rect, x, y, Color(0.7, 0.2, 0.2, 0.35), Color(0.75, 0.25, 0.2, 0.25))
					_draw_stop_square(rect, x, y)

func _draw_play_button(rect: Rect2, cx: int, cy: int) -> void:
	var h := _cell_hash(cx, cy)
	var center := rect.position + rect.size / 2.0
	var s := rect.size.x * 0.3  # half-size of triangle
	var col := Color(0.2, 0.5, 0.2, 0.6)

	# Play triangle pointing right, with slight wobble
	var angles := [deg_to_rad(-150.0), deg_to_rad(0.0), deg_to_rad(150.0)]
	var pts: PackedVector2Array = []
	for i in 3:
		var angle: float = angles[i]
		# Wobble each vertex a bit
		var wobble_x := (fmod(float(h + i * 3917), 5.0) - 2.5) * 1.2
		var wobble_y := (fmod(float(h + i * 7213), 5.0) - 2.5) * 1.2
		var r: float = s * 0.85
		if i == 1:
			r = s
		pts.append(center + Vector2(cos(angle) * r + wobble_x, sin(angle) * r + wobble_y))

	# Draw filled triangle
	draw_colored_polygon(pts, col)

	# Draw wobbly outline strokes
	var outline_col := Color(0.15, 0.4, 0.15, 0.7)
	for i in pts.size():
		var from := pts[i]
		var to := pts[(i + 1) % pts.size()]
		draw_line(from, to, outline_col, 1.5)

func _draw_stop_square(rect: Rect2, cx: int, cy: int) -> void:
	var h := _cell_hash(cx, cy)
	var center := rect.position + rect.size / 2.0
	var s := rect.size.x * 0.25
	var col := Color(0.6, 0.15, 0.15, 0.6)

	# Wobbly square corners
	var pts: PackedVector2Array = []
	for i in 4:
		var wx := (fmod(float(h + i * 4219), 5.0) - 2.5) * 1.0
		var wy := (fmod(float(h + i * 6173), 5.0) - 2.5) * 1.0
		var corner: Vector2
		if i == 0:
			corner = center + Vector2(-s + wx, -s + wy)
		elif i == 1:
			corner = center + Vector2(s + wx, -s + wy)
		elif i == 2:
			corner = center + Vector2(s + wx, s + wy)
		else:
			corner = center + Vector2(-s + wx, s + wy)
		pts.append(corner)

	draw_colored_polygon(pts, col)

	var outline_col := Color(0.45, 0.1, 0.1, 0.7)
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], outline_col, 1.5)

func _cell_hash(cx: int, cy: int) -> int:
	# Simple integer hash for grid coordinates
	var h: int = cx * 374761393 + cy * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h)

func _draw_wall_cell(rect: Rect2, cx: int, cy: int) -> void:
	# Pencil graphite shading: multiple layers of angled strokes
	# Inset so strokes don't touch the cell edges
	var inset: float = 3.0
	var x0: float = rect.position.x + inset
	var y0: float = rect.position.y + inset
	var x1: float = rect.end.x - inset
	var y1: float = rect.end.y - inset
	var w: float = x1 - x0
	var h: float = y1 - y0

	var cell_seed: float = float(_cell_hash(cx, cy))
	# 4 visually distinct stroke orientations per cell
	var rot: int = ((cx * 3 + cy * 7 + cx * cy) % 4 + 4) % 4
	# Base pattern directions, then rotate all by rot * 90°
	var base_dirs: Array = [[1.0, 1.0], [0.6, 1.0], [-1.0, 1.0]]
	var dirs: Array = _rotate_dirs(base_dirs, rot)
	var col1: Color = Color(0.45, 0.42, 0.4, 0.35)
	var col2: Color = Color(0.4, 0.38, 0.36, 0.25)
	var col3: Color = Color(0.5, 0.47, 0.44, 0.15)
	_draw_hatch_layer(x0, y0, x1, y1, w, h, 3.5, col1, dirs[0][0], dirs[0][1], cell_seed)
	_draw_hatch_layer(x0, y0, x1, y1, w, h, 5.0, col2, dirs[1][0], dirs[1][1], cell_seed + 100.0)
	_draw_hatch_layer(x0, y0, x1, y1, w, h, 6.0, col3, dirs[2][0], dirs[2][1], cell_seed + 200.0)

func _draw_colored_shading(rect: Rect2, cx: int, cy: int, col_primary: Color, col_secondary: Color) -> void:
	# Colored pencil shading (same technique as walls but with color)
	var inset: float = 3.0
	var x0: float = rect.position.x + inset
	var y0: float = rect.position.y + inset
	var x1: float = rect.end.x - inset
	var y1: float = rect.end.y - inset
	var w: float = x1 - x0
	var h: float = y1 - y0
	var cell_seed: float = float(_cell_hash(cx, cy) + 999)
	var rot: int = ((cx * 5 + cy * 11 + cx * cy) % 4 + 4) % 4
	var col_light: Color = col_primary
	col_light.a *= 0.4
	var base_dirs: Array = [[1.0, 1.0], [-1.0, 1.0], [0.5, 1.0]]
	var dirs: Array = _rotate_dirs(base_dirs, rot)
	_draw_hatch_layer(x0, y0, x1, y1, w, h, 3.0, col_primary, dirs[0][0], dirs[0][1], cell_seed)
	_draw_hatch_layer(x0, y0, x1, y1, w, h, 4.0, col_secondary, dirs[1][0], dirs[1][1], cell_seed + 50.0)
	_draw_hatch_layer(x0, y0, x1, y1, w, h, 5.5, col_light, dirs[2][0], dirs[2][1], cell_seed + 150.0)

func _rotate_dirs(base: Array, rot: int) -> Array:
	"""Rotate an array of [dx, dy] direction pairs by rot * 90°."""
	var result: Array = []
	for d in base:
		var dx: float = d[0]
		var dy: float = d[1]
		match rot:
			1:  # 90° CW: (x,y) → (y,-x)
				result.append([dy, -dx])
			2:  # 180°: (x,y) → (-x,-y)
				result.append([-dx, -dy])
			3:  # 270° CW: (x,y) → (-y,x)
				result.append([-dy, dx])
			_:  # 0°
				result.append([dx, dy])
	return result

func _draw_hatch_layer(x0: float, y0: float, x1: float, y1: float,
		w: float, h: float, spacing: float, color: Color,
		dx_ratio: float, dy_ratio: float, seed_val: float) -> void:
	# Draw parallel lines at angle determined by (dx_ratio, dy_ratio)
	# The line direction is (dx_ratio, dy_ratio), and we sweep perpendicular to it
	var dir_x: float = dx_ratio
	var dir_y: float = dy_ratio
	var dir_len: float = sqrt(dir_x * dir_x + dir_y * dir_y)
	if dir_len < 0.001:
		return
	dir_x /= dir_len
	dir_y /= dir_len
	# Perpendicular direction (for sweeping/spacing)
	var perp_x: float = -dir_y
	var perp_y: float = dir_x

	# How far we need to sweep in the perpendicular direction to cover the rect
	var corner_dots: Array[float] = [
		perp_x * 0.0 + perp_y * 0.0,
		perp_x * w + perp_y * 0.0,
		perp_x * 0.0 + perp_y * h,
		perp_x * w + perp_y * h,
	]
	var min_d: float = corner_dots[0]
	var max_d: float = corner_dots[0]
	for cd in corner_dots:
		min_d = minf(min_d, cd)
		max_d = maxf(max_d, cd)

	# Line extent along direction
	var dir_dots: Array[float] = [
		dir_x * 0.0 + dir_y * 0.0,
		dir_x * w + dir_y * 0.0,
		dir_x * 0.0 + dir_y * h,
		dir_x * w + dir_y * h,
	]
	var min_t: float = dir_dots[0]
	var max_t: float = dir_dots[0]
	for td in dir_dots:
		min_t = minf(min_t, td)
		max_t = maxf(max_t, td)

	var n: int = int((max_d - min_d) / spacing) + 2
	for i in range(n):
		var d: float = min_d + i * spacing
		# Per-stroke variation
		var wobble: float = sin(d * 3.7 + seed_val) * 1.2
		var alpha_var: float = 0.7 + 0.3 * sin(d * 2.1 + seed_val * 0.5)
		var stroke_color: Color = color
		stroke_color.a *= alpha_var
		var thickness: float = 0.8 + 0.4 * sin(d * 5.3 + seed_val)

		# Line start and end in local rect coords (offset by wobble along perp)
		var base_x: float = perp_x * (d + wobble)
		var base_y: float = perp_y * (d + wobble)
		var p1x: float = x0 + base_x + dir_x * min_t
		var p1y: float = y0 + base_y + dir_y * min_t
		var p2x: float = x0 + base_x + dir_x * max_t
		var p2y: float = y0 + base_y + dir_y * max_t

		# Clip line to rect using Liang-Barsky
		var clipped := _clip_line(p1x, p1y, p2x, p2y, x0, y0, x1, y1)
		if clipped.size() == 4:
			draw_line(Vector2(clipped[0], clipped[1]), Vector2(clipped[2], clipped[3]), stroke_color, thickness, true)

func _clip_line(x1: float, y1: float, x2: float, y2: float,
		xmin: float, ymin: float, xmax: float, ymax: float) -> Array[float]:
	var dx: float = x2 - x1
	var dy: float = y2 - y1
	var t0: float = 0.0
	var t1: float = 1.0
	var p: Array[float] = [-dx, dx, -dy, dy]
	var q: Array[float] = [x1 - xmin, xmax - x1, y1 - ymin, ymax - y1]
	for i in 4:
		if absf(p[i]) < 0.0001:
			if q[i] < 0:
				return []
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy]

func _draw_start_end_markers() -> void:
	var font: Font = caveat_font if caveat_font else ThemeDB.fallback_font
	# Draw "S" on start cell
	var s_pos := grid_to_local(start_cell)
	draw_string(font, Vector2(s_pos.x - 8, s_pos.y + 8),
		"S", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color("#66AA66"))

	# Draw "X" on end cell
	var e_pos := grid_to_local(end_cell)
	draw_string(font, Vector2(e_pos.x - 8, e_pos.y + 8),
		"X", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color("#CC4444"))
