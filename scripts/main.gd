extends Node2D

@onready var game_board: GameBoard = $GameBoard
@onready var tick_engine: TickEngine = $TickEngine
@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var health_manager: HealthManager = $HealthManager
@onready var hud: HUD = $HUD

var current_level: LevelData

func _ready() -> void:
	# Wire up references
	game_board.health_manager = health_manager
	game_board.tick_engine = tick_engine
	game_board.spawn_manager = spawn_manager

	# Connect signals
	tick_engine.tick.connect(_on_tick)
	spawn_manager.spawn_number.connect(_on_spawn_number)
	spawn_manager.queue_updated.connect(_on_queue_updated)
	health_manager.health_changed.connect(_on_health_changed)
	health_manager.game_over.connect(_on_game_over)
	game_board.level_complete.connect(_on_level_complete)
	game_board.number_escaped.connect(_on_number_escaped)
	game_board.number_solved.connect(_on_number_solved)

	# HUD
	hud.retry_button.pressed.connect(_on_retry)

	# Load random level
	_load_level(_create_random_level())

func _load_level(data: LevelData) -> void:
	current_level = data
	health_manager.setup(data.starting_hp)
	game_board.load_level(data)
	spawn_manager.setup(data.number_sequence, data.ticks_between_spawns)
	tick_engine.tick_duration = data.tick_speed
	hud.hide_game_over()
	hud.set_scroll_speed(data.ticks_between_spawns, data.tick_speed)
	tick_engine.start()

func _on_tick() -> void:
	# Advance numbers first (frees cells), then spawn new ones
	game_board.on_tick()
	spawn_manager.on_tick()

func _on_spawn_number(value: int) -> void:
	game_board.spawn_number(value)

func _on_queue_updated(visible: Array[int]) -> void:
	hud.update_queue(visible)
	hud.queue_paused = spawn_manager.spawn_blocked

func _on_health_changed(current: int, max_hp: int) -> void:
	hud.update_health(current, max_hp)

func _on_game_over() -> void:
	tick_engine.stop()
	hud.show_game_over(0, false)

func _on_level_complete(stars: int) -> void:
	tick_engine.stop()
	hud.show_game_over(stars, true)

func _on_number_escaped(value: int) -> void:
	pass  # damage handled by number_entity -> health_manager

func _on_number_solved(_value: int) -> void:
	pass  # could track stats

func _on_retry() -> void:
	_load_level(_create_random_level())

# ─── Random Level ────────────────────────────────────────────────

func _create_random_level() -> LevelData:
	var data := LevelData.new()
	data.level_name = "Random"
	data.starting_hp = 150
	data.ticks_between_spawns = 3
	data.tick_speed = 1.3

	# Generate random number sequence (20-30 numbers)
	var count: int = randi_range(20, 30)
	var number_pool: Array[int] = [4, 6, 8, 9, 10, 12, 14, 15, 16, 18, 20, 21, 24, 25, 27, 28, 30, 32, 36, 40, 42, 45, 48]
	var primes: Array[int] = [7, 11, 13, 17, 19, 23]
	data.number_sequence = []
	for i in count:
		# 15% chance of a prime
		if randf() < 0.15:
			data.number_sequence.append(primes[randi() % primes.size()])
		else:
			data.number_sequence.append(number_pool[randi() % number_pool.size()])

	# Generate random maze
	data.grid_layout = _generate_random_maze()
	return data

func _generate_random_maze() -> PackedStringArray:
	const C: int = 10
	const R: int = 20

	# Start with all paths
	var grid: Array = []
	for y in R:
		var row: Array = []
		for x in C:
			row.append(".")
		grid.append(row)

	# Random start and end — any cells with decent separation
	var start: Vector2i
	var end: Vector2i
	while true:
		start = Vector2i(randi_range(0, C - 1), randi_range(0, R - 1))
		end = Vector2i(randi_range(0, C - 1), randi_range(0, R - 1))
		# Ensure minimum distance (Manhattan >= 15)
		var dist: int = absi(end.x - start.x) + absi(end.y - start.y)
		if dist >= 15:
			break

	grid[start.y][start.x] = "S"
	grid[end.y][end.x] = "E"

	# Scatter walls randomly (~35% of cells)
	var wall_target: int = int(C * R * 0.35)
	var walls_placed: int = 0
	var attempts: int = 0
	while walls_placed < wall_target and attempts < 1000:
		attempts += 1
		var wx: int = randi_range(0, C - 1)
		var wy: int = randi_range(0, R - 1)
		if grid[wy][wx] != ".":
			continue
		grid[wy][wx] = "#"
		walls_placed += 1

	# Ensure start-to-end path exists, carve one if not
	if not _bfs_path_exists(grid, start, end, C, R):
		# BFS to find closest reachable cell to end, then carve through
		var path_cells: Array[Vector2i] = _bfs_carve_path(grid, start, end, C, R)
		for cell in path_cells:
			if grid[cell.y][cell.x] == "#":
				grid[cell.y][cell.x] = "."

	grid[start.y][start.x] = "S"
	grid[end.y][end.x] = "E"

	# Convert to strings
	var result: PackedStringArray = PackedStringArray()
	for y in R:
		var row_str: String = ""
		for x in C:
			row_str += grid[y][x]
		result.append(row_str)
	return result

func _bfs_carve_path(grid: Array, start: Vector2i, end: Vector2i, cols: int, rows: int) -> Array[Vector2i]:
	"""BFS ignoring walls to find shortest path, returns cells to carve."""
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while queue.size() > 0:
		var current: Vector2i = queue[0]
		queue.remove_at(0)
		if current == end:
			# Trace back path
			var path: Array[Vector2i] = []
			var c: Vector2i = end
			while c != start:
				path.append(c)
				c = parent[c]
			path.append(start)
			return path
		for d in dirs:
			var n: Vector2i = current + d
			if n.x >= 0 and n.x < cols and n.y >= 0 and n.y < rows:
				if not visited.has(n):
					visited[n] = true
					parent[n] = current
					queue.append(n)
	return []

func _bfs_path_exists(grid: Array, start: Vector2i, end: Vector2i, cols: int, rows: int) -> bool:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while queue.size() > 0:
		var current: Vector2i = queue[0]
		queue.remove_at(0)
		if current == end:
			return true
		for d in dirs:
			var n: Vector2i = current + d
			if n.x >= 0 and n.x < cols and n.y >= 0 and n.y < rows:
				if not visited.has(n) and grid[n.y][n.x] != "#":
					visited[n] = true
					queue.append(n)
	return false
