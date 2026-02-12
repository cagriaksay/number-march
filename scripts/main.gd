extends Node2D

@onready var game_board: GameBoard = $GameBoard
@onready var tick_engine: TickEngine = $TickEngine
@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var health_manager: HealthManager = $HealthManager
@onready var hud: HUD = $HUD

var current_level: LevelData
var current_level_index: int = -1  # -1 = no level loaded
var level_stars: Dictionary = {}  # level_index -> stars (0-3)
var level_scores: Dictionary = {}  # level_index -> best remaining HP

const SAVE_PATH: String = "user://save_data.json"

# Level select (created in code)
var level_select: LevelSelect

# Audio
var audio_manager: AudioManager

# ─── Lifecycle ───────────────────────────────────────────────────

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

	# HUD signals
	hud.retry_button.pressed.connect(_on_retry)
	hud.levels_button.pressed.connect(_on_show_level_select)
	hud.pause_pressed.connect(_on_pause)
	hud.resume_pressed.connect(_on_resume)
	hud.restart_pressed.connect(_on_restart)
	hud.level_select_pressed.connect(_on_show_level_select)
	hud.fast_forward_toggled.connect(_on_fast_forward)
	hud.settings_changed.connect(save_settings)

	# Create level select screen
	level_select = LevelSelect.new()
	level_select.level_selected.connect(_on_level_selected)
	add_child(level_select)

	# Audio manager
	audio_manager = AudioManager.new()
	audio_manager.music_changed.connect(_on_music_changed)
	add_child(audio_manager)

	# Pass audio manager references
	game_board.audio_manager = audio_manager
	hud.audio_manager_ref = audio_manager

	# Load saved progress
	_load_progress()

	# Start on level select
	_show_level_select()

# ─── Level Loading ───────────────────────────────────────────────

func _load_level(data: LevelData, level_index: int) -> void:
	current_level = data
	current_level_index = level_index
	health_manager.setup(data.starting_hp)
	game_board.load_level(data)
	spawn_manager.setup(data.number_sequence, data.ticks_between_spawns)
	tick_engine.tick_duration = data.tick_speed
	hud.hide_game_over()
	hud.set_scroll_speed(data.ticks_between_spawns, data.tick_speed)
	tick_engine.start()
	game_board.game_paused = false

# ─── Tick / Spawn ────────────────────────────────────────────────

func _on_tick() -> void:
	game_board.on_tick()
	spawn_manager.on_tick()

func _on_spawn_number(value: int) -> void:
	game_board.spawn_number(value)

func _on_queue_updated(visible: Array[int]) -> void:
	hud.update_queue(visible)
	hud.queue_paused = spawn_manager.spawn_blocked

func _on_health_changed(current: int, max_hp: int) -> void:
	hud.update_health(current, max_hp)

# ─── Game End ────────────────────────────────────────────────────

func _on_game_over() -> void:
	tick_engine.stop()
	hud.show_game_over(0, false)
	audio_manager.stop_music(1.5)
	audio_manager.play_game_over()
	audio_manager.vibrate(200)

func _on_level_complete(stars: int) -> void:
	tick_engine.stop()
	# Save best stars and score for this level
	if current_level_index >= 0:
		var prev_stars: int = level_stars.get(current_level_index, 0)
		if stars > prev_stars:
			level_stars[current_level_index] = stars
		var current_score: int = health_manager.current_hp
		var prev_score: int = level_scores.get(current_level_index, 0)
		if current_score > prev_score:
			level_scores[current_level_index] = current_score
		_save_progress()
	hud.show_game_over(stars, true)
	audio_manager.stop_music(1.5)
	audio_manager.play_level_complete()
	audio_manager.vibrate(100)

func _on_number_escaped(value: int) -> void:
	audio_manager.play_escaped()
	audio_manager.vibrate(80)

func _on_number_solved(_value: int) -> void:
	audio_manager.play_solved()

func _on_music_changed(display_name: String) -> void:
	hud.show_music_name(display_name)

# ─── Pause ───────────────────────────────────────────────────────

func _on_pause() -> void:
	tick_engine.pause()
	game_board.game_paused = true

func _on_resume() -> void:
	tick_engine.resume()
	game_board.game_paused = false

func _on_fast_forward(enabled: bool) -> void:
	if enabled:
		Engine.time_scale = 2.0
	else:
		Engine.time_scale = 1.0

func _on_restart() -> void:
	Engine.time_scale = 1.0
	if current_level_index >= 0:
		_load_level(_create_level(current_level_index), current_level_index)
	audio_manager.play_gameplay_music()

# ─── Retry (from game over panel) ───────────────────────────────

func _on_retry() -> void:
	Engine.time_scale = 1.0
	if current_level_index >= 0:
		_load_level(_create_level(current_level_index), current_level_index)
	else:
		_load_level(_create_level(0), 0)
	audio_manager.play_gameplay_music()

# ─── Level Select ────────────────────────────────────────────────

func _on_show_level_select() -> void:
	Engine.time_scale = 1.0
	tick_engine.stop()
	hud.hide_game_over()
	_show_level_select()

func _show_level_select() -> void:
	level_select.update_stars(level_stars, level_scores)
	level_select.visible = true
	hud.visible = false
	game_board.visible = false
	game_board.game_paused = true
	audio_manager.play_level_select_music()

func _hide_level_select() -> void:
	level_select.visible = false
	hud.visible = true
	game_board.visible = true

func _on_level_selected(level_index: int) -> void:
	_hide_level_select()
	_load_level(_create_level(level_index), level_index)
	audio_manager.play_gameplay_music()

# ─── Level Generation (60 seeded levels) ─────────────────────────

const TOTAL_LEVELS: int = 60

func _create_level(level_index: int) -> LevelData:
	# Seed RNG for deterministic levels
	seed(level_index * 73856093 + 19349663)

	var data := LevelData.new()
	data.level_name = "Level " + str(level_index + 1)

	# Difficulty scaling
	var t: float = float(level_index) / float(TOTAL_LEVELS - 1)  # 0.0 to 1.0

	# HP: starts generous, stays reasonable
	data.starting_hp = int(lerpf(120.0, 200.0, t))

	# Tick speed: slower at start, faster later
	data.tick_speed = lerpf(1.5, 0.85, t)

	# Spawns between ticks: 3 throughout (keeps rhythm consistent)
	data.ticks_between_spawns = 3

	# Number count: more numbers at higher levels
	var count: int = int(lerpf(48.0, 160.0, t))

	# Number pools scale with difficulty
	var easy_pool: Array[int] = [4, 6, 8, 9, 10, 12]
	var medium_pool: Array[int] = [4, 6, 8, 9, 10, 12, 14, 15, 16, 18, 20, 21, 24, 25]
	var hard_pool: Array[int] = [6, 8, 10, 12, 14, 15, 16, 18, 20, 21, 24, 25, 27, 28, 30, 32, 36]
	var expert_pool: Array[int] = [12, 14, 16, 18, 20, 24, 25, 27, 28, 30, 32, 36, 40, 42, 45, 48]
	var primes: Array[int] = [7, 11, 13, 17, 19, 23]

	var pool: Array[int]
	var prime_chance: float
	if level_index < 15:
		pool = easy_pool
		prime_chance = 0.0
	elif level_index < 30:
		pool = medium_pool
		prime_chance = 0.08
	elif level_index < 45:
		pool = hard_pool
		prime_chance = 0.12
	else:
		pool = expert_pool
		prime_chance = 0.18

	data.number_sequence = []
	for i in count:
		if randf() < prime_chance:
			data.number_sequence.append(primes[randi() % primes.size()])
		else:
			data.number_sequence.append(pool[randi() % pool.size()])

	# Wall density: more open early, denser later
	var wall_pct: float = lerpf(0.25, 0.40, t)
	data.grid_layout = _generate_seeded_maze(wall_pct)

	# Reset RNG to non-deterministic for gameplay randomness
	randomize()
	return data

func _generate_seeded_maze(wall_pct: float) -> PackedStringArray:
	const C: int = 10
	const R: int = 20

	var grid: Array = []
	for y in R:
		var row: Array = []
		for x in C:
			row.append(".")
		grid.append(row)

	# Random start and end with decent separation
	var start: Vector2i
	var end_pos: Vector2i
	var safety: int = 0
	while safety < 500:
		safety += 1
		start = Vector2i(randi_range(0, C - 1), randi_range(0, R - 1))
		end_pos = Vector2i(randi_range(0, C - 1), randi_range(0, R - 1))
		var dist: int = absi(end_pos.x - start.x) + absi(end_pos.y - start.y)
		if dist >= 15:
			break

	grid[start.y][start.x] = "S"
	grid[end_pos.y][end_pos.x] = "E"

	# Scatter walls
	var wall_target: int = int(C * R * wall_pct)
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

	# Ensure connectivity
	if not _bfs_path_exists(grid, start, end_pos, C, R):
		var path_cells: Array[Vector2i] = _bfs_carve_path(grid, start, end_pos, C, R)
		for cell in path_cells:
			if grid[cell.y][cell.x] == "#":
				grid[cell.y][cell.x] = "."

	grid[start.y][start.x] = "S"
	grid[end_pos.y][end_pos.x] = "E"

	var result: PackedStringArray = PackedStringArray()
	for y in R:
		var row_str: String = ""
		for x in C:
			row_str += grid[y][x]
		result.append(row_str)
	return result

func _bfs_carve_path(grid: Array, start: Vector2i, end_pos: Vector2i, cols: int, rows: int) -> Array[Vector2i]:
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while queue.size() > 0:
		var current: Vector2i = queue[0]
		queue.remove_at(0)
		if current == end_pos:
			var path: Array[Vector2i] = []
			var c: Vector2i = end_pos
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

func _bfs_path_exists(grid: Array, start: Vector2i, end_pos: Vector2i, cols: int, rows: int) -> bool:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while queue.size() > 0:
		var current: Vector2i = queue[0]
		queue.remove_at(0)
		if current == end_pos:
			return true
		for d in dirs:
			var n: Vector2i = current + d
			if n.x >= 0 and n.x < cols and n.y >= 0 and n.y < rows:
				if not visited.has(n) and grid[n.y][n.x] != "#":
					visited[n] = true
					queue.append(n)
	return false

# ─── Save / Load Progress ─────────────────────────────────────────

func _save_progress() -> void:
	var data: Dictionary = {
		"level_stars": {},
		"level_scores": {},
		"settings": {
			"music": audio_manager.music_enabled,
			"sfx": audio_manager.sfx_enabled,
			"vibration": audio_manager.vibration_enabled,
		},
	}
	for key in level_stars:
		data["level_stars"][str(key)] = level_stars[key]
	for key in level_scores:
		data["level_scores"][str(key)] = level_scores[key]
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func save_settings() -> void:
	# Save just settings without needing a level complete
	_save_progress()

func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data = json.data
	if data is Dictionary:
		if data.has("level_stars"):
			for key in data["level_stars"]:
				level_stars[int(key)] = int(data["level_stars"][key])
		if data.has("level_scores"):
			for key in data["level_scores"]:
				level_scores[int(key)] = int(data["level_scores"][key])
		if data.has("settings"):
			var s = data["settings"]
			if s.has("music"):
				audio_manager.music_enabled = bool(s["music"])
			if s.has("sfx"):
				audio_manager.sfx_enabled = bool(s["sfx"])
			if s.has("vibration"):
				audio_manager.vibration_enabled = bool(s["vibration"])
