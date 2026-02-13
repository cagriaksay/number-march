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

# Level sel\nect (created in code)
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
	game_board.edit_dirty_changed.connect(_on_edit_dirty_changed)

	# HUD signals
	hud.retry_button.pressed.connect(_on_retry)
	hud.levels_button.pressed.connect(_on_show_level_select)
	hud.pause_pressed.connect(_on_pause)
	hud.resume_pressed.connect(_on_resume)
	hud.restart_pressed.connect(_on_restart)
	hud.level_select_pressed.connect(_on_show_level_select)
	hud.fast_forward_changed.connect(_on_fast_forward)
	hud.settings_changed.connect(save_settings)
	hud.edit_level_pressed.connect(_on_edit_level)
	hud.edit_save_pressed.connect(_on_edit_save)
	hud.edit_clear_pressed.connect(_on_edit_clear)
	hud.edit_done_pressed.connect(_on_edit_done)

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
	level_select.audio_manager_ref = audio_manager

	# Load saved progress
	_load_progress()

	# Sync saved progress to Game Center once authenticated
	if GameCenterManager:
		if GameCenterManager.is_authenticated:
			GameCenterManager.sync_all_scores(level_stars, level_scores)
		elif GameCenterManager.game_center:
			GameCenterManager.game_center.signin_success.connect(
				func(_player): GameCenterManager.sync_all_scores(level_stars, level_scores)
			)

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
	hud.set_level_name("Level " + str(level_index + 1))
	hud.set_scroll_speed(data.ticks_between_spawns, data.tick_speed)
	tick_engine.start()
	game_board.game_paused = false

# ─── Tick / Spawn ────────────────────────────────────────────────

func _on_tick() -> void:
	game_board.on_tick()
	spawn_manager.on_tick()
	# Re-check: if the last number exited during on_tick but spawn_manager
	# only finished on this same tick, the earlier check would have missed it.
	game_board._check_level_complete()

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
		# Post to Game Center
		if GameCenterManager:
			GameCenterManager.post_level_score(current_level_index, health_manager.current_hp)
			GameCenterManager.award_level_complete(current_level_index)
			# Check if all levels are complete
			var all_complete := true
			for i in TOTAL_LEVELS:
				if not level_stars.has(i) or level_stars[i] <= 0:
					all_complete = false
					break
			if all_complete:
				GameCenterManager.award_all_levels_complete()
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

func _on_fast_forward(speed: float) -> void:
	Engine.time_scale = speed

func _on_restart() -> void:
	Engine.time_scale = 1.0
	if current_level_index >= 0:
		_load_level(_create_level(current_level_index), current_level_index)
	audio_manager.play_gameplay_music()

# ─── Retry (from game over panel) ───────────────────────────────

func _on_retry() -> void:
	Engine.time_scale = 1.0
	if hud._survived_last:
		# "Next" button — advance to next level
		var next_index: int = current_level_index + 1
		if next_index >= TOTAL_LEVELS:
			_on_show_level_select()
			return
		_load_level(_create_level(next_index), next_index)
	else:
		# "Retry" button — replay same level
		if current_level_index >= 0:
			_load_level(_create_level(current_level_index), current_level_index)
		else:
			_load_level(_create_level(0), 0)
	audio_manager.play_gameplay_music()

# ─── Edit Mode ───────────────────────────────────────────────────

func _on_edit_level() -> void:
	tick_engine.stop()
	game_board.edit_mode = true
	game_board.game_paused = false
	game_board._edit_saved_layout = game_board.get_grid_layout()
	game_board._edit_dirty = false
	hud.show_edit_mode()

func _on_edit_save() -> void:
	if current_level_index < 0:
		return
	var data := LevelData.new()
	data.grid_layout = game_board.get_grid_layout()
	data.starting_hp = current_level.starting_hp
	data.tick_speed = current_level.tick_speed
	data.ticks_between_spawns = current_level.ticks_between_spawns
	data.number_sequence = current_level.number_sequence
	data.tutorial_hints = current_level.tutorial_hints
	_save_level_file(current_level_index, data)
	game_board.mark_edit_saved()

func _on_edit_clear() -> void:
	game_board.edit_clear()

func _on_edit_dirty_changed(dirty: bool) -> void:
	hud.update_edit_save_enabled(dirty)

func _on_edit_done() -> void:
	game_board.edit_mode = false
	game_board._edit_placing = ""
	hud.hide_edit_mode()
	# Reload the level (picks up saved file if any)
	_load_level(_create_level(current_level_index), current_level_index)
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
	# Priority: saved level file > hand-designed > procedural
	var from_file := _load_level_file(level_index)
	if from_file:
		randomize()
		return from_file

	var hand_designed := _get_hand_designed_level(level_index)
	if hand_designed:
		randomize()
		return hand_designed

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

# ─── Level File Save/Load ─────────────────────────────────────────

const LEVELS_DIR: String = "res://levels/"

func _save_level_file(level_index: int, data: LevelData) -> void:
	DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	var path: String = LEVELS_DIR + "level_%02d.json" % level_index
	var dict := {
		"grid_layout": Array(data.grid_layout),
		"starting_hp": data.starting_hp,
		"tick_speed": data.tick_speed,
		"ticks_between_spawns": data.ticks_between_spawns,
		"number_sequence": data.number_sequence,
		"tutorial_hints": data.tutorial_hints,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(dict, "\t"))
		file.close()

func _load_level_file(level_index: int) -> LevelData:
	var path: String = LEVELS_DIR + "level_%02d.json" % level_index
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var d = json.data
	if not (d is Dictionary):
		return null
	var data := LevelData.new()
	data.level_name = "Level " + str(level_index + 1)
	if d.has("grid_layout"):
		var layout := PackedStringArray()
		for row in d["grid_layout"]:
			layout.append(str(row))
		data.grid_layout = layout
	if d.has("starting_hp"):
		data.starting_hp = int(d["starting_hp"])
	if d.has("tick_speed"):
		data.tick_speed = float(d["tick_speed"])
	if d.has("ticks_between_spawns"):
		data.ticks_between_spawns = int(d["ticks_between_spawns"])
	if d.has("number_sequence"):
		data.number_sequence = []
		for n in d["number_sequence"]:
			data.number_sequence.append(int(n))
	if d.has("tutorial_hints"):
		data.tutorial_hints = d["tutorial_hints"]
	return data

# ─── Hand-designed Levels (Tutorials) ─────────────────────────────

func _get_hand_designed_level(level_index: int) -> LevelData:
	match level_index:
		0: return _tutorial_level_1()
		1: return _level_2_the_bend()
		2: return _level_3_slalom()
		3: return _level_4_spiral()
		4: return _level_5_s_curve()
		5: return _level_6_teeth()
		6: return _level_7_diamond()
		7: return _level_8_fortress()
		8: return _level_9_dense_snake()
		9: return _level_10_gauntlet()
		_: return null

# ─── Level 1: Tutorial ──────────────────────────────────────────

func _tutorial_level_1() -> LevelData:
	var data := LevelData.new()
	data.level_name = "Tutorial"
	data.starting_hp = 150
	data.tick_speed = 2.0
	data.ticks_between_spawns = 4

	data.grid_layout = PackedStringArray([
		"..........",
		"..........",
		"S.........",
		"#########.",
		"..........",
		".#########",
		"..........",
		"#########.",
		"..........",
		".#########",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		".........E",
		"..........",
		"..........",
	])

	data.number_sequence = [4, 6, 4, 8, 6, 4, 9, 6, 4, 8, 6, 4]

	data.tutorial_hints = [
		{"text": "tap a tile to\nplace a tower", "x": 1, "y": 11, "width": 8, "height": 3},
		{"text": "towers divide\nnearby numbers", "x": 1, "y": 14, "width": 8, "height": 3},
		{"text": "tap again\nto increase", "x": 2, "y": 17, "width": 7, "height": 3},
		{"text": "reduce to 1\nbefore they escape!", "x": 1, "y": 0, "width": 8, "height": 2},
	]
	return data

# ─── Level 2: The Bend ──────────────────────────────────────────
# One big wall → simple U-turn

func _level_2_the_bend() -> LevelData:
	var data := LevelData.new()
	data.level_name = "The Bend"
	data.starting_hp = 130
	data.tick_speed = 1.8
	data.ticks_between_spawns = 4

	data.grid_layout = PackedStringArray([
		"S.........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"#########.",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"E.........",
	])

	data.number_sequence = [
		4, 6, 4, 8, 6, 4, 6, 8,
		4, 9, 6, 8, 4, 6, 4, 8,
		6, 9, 4, 6, 8, 4, 6, 4,
	]
	return data

# ─── Level 3: Slalom ────────────────────────────────────────────
# Half-walls from alternating sides

func _level_3_slalom() -> LevelData:
	var data := LevelData.new()
	data.level_name = "Slalom"
	data.starting_hp = 125
	data.tick_speed = 1.7
	data.ticks_between_spawns = 4

	data.grid_layout = PackedStringArray([
		"S.........",
		"..........",
		"######....",
		"..........",
		"....######",
		"..........",
		"######....",
		"..........",
		"....######",
		"..........",
		"######....",
		"..........",
		"....######",
		"..........",
		"######....",
		"..........",
		"....######",
		"..........",
		"..........",
		".........E",
	])

	data.number_sequence = [
		4, 6, 8, 4, 9, 6, 8, 4,
		6, 8, 10, 4, 6, 9, 8, 4,
		6, 8, 4, 10, 6, 8, 4, 6,
		9, 8, 4, 6, 10, 8, 4, 6,
	]
	return data

# ─── Level 4: Spiral ────────────────────────────────────────────
# Concentric rectangles

func _level_4_spiral() -> LevelData:
	var data := LevelData.new()
	data.level_name = "Spiral"
	data.starting_hp = 125
	data.tick_speed = 1.6
	data.ticks_between_spawns = 3

	data.grid_layout = PackedStringArray([
		"S.........",
		".########.",
		".#......#.",
		".#.####.#.",
		".#.#..#.#.",
		".#.#..#.#.",
		".#.#..#.#.",
		".#.####.#.",
		".#......#.",
		".########.",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		".........E",
	])

	data.number_sequence = [
		6, 8, 9, 12, 6, 8, 4, 9,
		12, 6, 8, 15, 6, 9, 12, 8,
		6, 4, 8, 12, 9, 6, 8, 15,
		12, 6, 9, 8, 4, 6, 12, 8,
	]
	return data

# ─── Level 5: S-Curve ───────────────────────────────────────────
# Two walls, start top-right, exit bottom-left

func _level_5_s_curve() -> LevelData:
	var data := LevelData.new()
	data.level_name = "S-Curve"
	data.starting_hp = 120
	data.tick_speed = 1.5
	data.ticks_between_spawns = 3

	data.grid_layout = PackedStringArray([
		".........S",
		"..........",
		"..........",
		"..........",
		"..........",
		".#########",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"#########.",
		"..........",
		"..........",
		"..........",
		"..........",
		"E.........",
	])

	data.number_sequence = [
		8, 9, 12, 6, 10, 8, 4, 12,
		9, 6, 8, 10, 12, 8, 6, 9,
		4, 12, 8, 10, 6, 9, 12, 8,
		8, 6, 10, 12, 9, 4, 8, 6,
		12, 10, 8, 9, 6, 12, 8, 4,
	]
	return data

# ─── Level 6: The Teeth ─────────────────────────────────────────
# Thick comb teeth from top and bottom

func _level_6_teeth() -> LevelData:
	var data := LevelData.new()
	data.level_name = "The Teeth"
	data.starting_hp = 120
	data.tick_speed = 1.4
	data.ticks_between_spawns = 3

	data.grid_layout = PackedStringArray([
		"S.........",
		".##.##.##.",
		".##.##.##.",
		".##.##.##.",
		".##.##.##.",
		".##.##.##.",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		"##.##.##..",
		"##.##.##..",
		"##.##.##..",
		"##.##.##..",
		"##.##.##..",
		".........E",
	])

	data.number_sequence = [
		9, 12, 15, 8, 10, 16, 6, 12,
		18, 9, 8, 15, 12, 10, 6, 16,
		9, 18, 12, 8, 15, 10, 6, 9,
		12, 16, 8, 18, 15, 12, 9, 6,
		10, 8, 16, 12, 18, 15, 9, 12,
		8, 6, 10, 16, 12, 9, 15, 18,
	]
	return data

# ─── Level 7: Diamond ───────────────────────────────────────────
# Diamond-shaped wall block in the center

func _level_7_diamond() -> LevelData:
	var data := LevelData.new()
	data.level_name = "Diamond"
	data.starting_hp = 120
	data.tick_speed = 1.3
	data.ticks_between_spawns = 3

	data.grid_layout = PackedStringArray([
		"S.........",
		"..........",
		"..........",
		"..........",
		"..........",
		".....#....",
		"....###...",
		"...#####..",
		"..#######.",
		".#########",
		"..#######.",
		"...#####..",
		"....###...",
		".....#....",
		"..........",
		"..........",
		"..........",
		"..........",
		"..........",
		".........E",
	])

	data.number_sequence = [
		12, 15, 16, 18, 8, 20, 12, 9,
		24, 15, 16, 12, 18, 8, 20, 15,
		12, 24, 16, 9, 18, 12, 20, 15,
		16, 8, 24, 12, 18, 15, 20, 9,
		12, 16, 24, 18, 15, 8, 12, 20,
		16, 24, 12, 18, 9, 15, 20, 12,
	]
	return data

# ─── Level 8: Fortress ──────────────────────────────────────────
# Central block with walls above and below

func _level_8_fortress() -> LevelData:
	var data := LevelData.new()
	data.level_name = "Fortress"
	data.starting_hp = 115
	data.tick_speed = 1.2
	data.ticks_between_spawns = 3

	data.grid_layout = PackedStringArray([
		"S.........",
		"..........",
		"#########.",
		"..........",
		"..........",
		"...####...",
		"...####...",
		"...####...",
		"...####...",
		"...####...",
		"...####...",
		"...####...",
		"...####...",
		"..........",
		"..........",
		".#########",
		"..........",
		"..........",
		"..........",
		".........E",
	])

	data.number_sequence = [
		15, 16, 18, 20, 24, 12, 25, 16,
		18, 20, 15, 24, 12, 16, 25, 18,
		20, 15, 12, 24, 16, 25, 18, 20,
		15, 16, 12, 24, 25, 18, 20, 15,
		16, 24, 12, 18, 25, 20, 15, 16,
		12, 24, 18, 25, 20, 16, 15, 12,
		24, 18, 25, 20, 16, 15, 12, 24,
	]
	return data

# ─── Level 9: Dense Snake ───────────────────────────────────────
# Maximum turns filling the whole grid

func _level_9_dense_snake() -> LevelData:
	var data := LevelData.new()
	data.level_name = "Dense Snake"
	data.starting_hp = 115
	data.tick_speed = 1.1
	data.ticks_between_spawns = 3

	data.grid_layout = PackedStringArray([
		"S.........",
		"#########.",
		"..........",
		".#########",
		"..........",
		"#########.",
		"..........",
		".#########",
		"..........",
		"#########.",
		"..........",
		".#########",
		"..........",
		"#########.",
		"..........",
		".#########",
		"..........",
		"#########.",
		"..........",
		".........E",
	])

	data.number_sequence = [
		16, 18, 20, 24, 25, 15, 27, 18,
		20, 16, 24, 12, 25, 27, 18, 20,
		16, 15, 24, 25, 27, 18, 12, 20,
		16, 24, 25, 27, 18, 15, 20, 16,
		24, 12, 25, 18, 27, 20, 16, 24,
		25, 15, 27, 18, 20, 12, 16, 24,
		25, 27, 18, 20, 16, 15, 24, 12,
	]
	return data

# ─── Level 10: The Gauntlet ─────────────────────────────────────
# Dense slalom with tight half-walls

func _level_10_gauntlet() -> LevelData:
	var data := LevelData.new()
	data.level_name = "The Gauntlet"
	data.starting_hp = 110
	data.tick_speed = 1.0
	data.ticks_between_spawns = 3

	data.grid_layout = PackedStringArray([
		"S.........",
		"#######...",
		"..........",
		"...#######",
		"..........",
		"#######...",
		"..........",
		"...#######",
		"..........",
		"#######...",
		"..........",
		"...#######",
		"..........",
		"#######...",
		"..........",
		"...#######",
		"..........",
		"#######...",
		"..........",
		".........E",
	])

	data.number_sequence = [
		18, 20, 24, 25, 27, 16, 30, 18,
		20, 24, 12, 25, 27, 30, 16, 18,
		20, 24, 25, 15, 27, 30, 18, 20,
		24, 16, 25, 27, 12, 30, 18, 20,
		24, 25, 27, 30, 16, 18, 15, 20,
		24, 25, 12, 27, 30, 18, 20, 24,
		25, 27, 16, 30, 18, 20, 15, 24,
		25, 27, 30, 12, 18, 20, 24, 16,
	]
	return data
