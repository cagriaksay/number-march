class_name AudioManager
extends Node

signal music_changed(display_name: String)

# Music players (two for crossfade)
var music_player_a: AudioStreamPlayer
var music_player_b: AudioStreamPlayer
var active_player: AudioStreamPlayer  # which one is currently playing

# SFX players (pool for overlapping sounds)
var sfx_players: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE: int = 6

# Track data
var music_tracks: Dictionary = {}  # filename (no ext) -> AudioStream
var music_display_names: Dictionary = {}  # filename (no ext) -> "Display Name"
var sfx_clips: Dictionary = {}  # sfx name -> AudioStream

var current_music_key: String = ""

# Gameplay music list (shuffled per session)
var gameplay_tracks: Array[String] = []
var gameplay_index: int = 0

# Volume (linear)
const MUSIC_VOLUME_DB: float = -8.0
const SFX_VOLUME_DB: float = -4.0

func _ready() -> void:
	_create_players()
	_load_music()
	_load_sfx()
	_build_gameplay_playlist()

func _create_players() -> void:
	music_player_a = AudioStreamPlayer.new()
	music_player_a.bus = "Master"
	music_player_a.volume_db = MUSIC_VOLUME_DB
	add_child(music_player_a)

	music_player_b = AudioStreamPlayer.new()
	music_player_b.bus = "Master"
	music_player_b.volume_db = MUSIC_VOLUME_DB
	add_child(music_player_b)

	active_player = music_player_a

	# SFX pool
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = SFX_VOLUME_DB
		add_child(p)
		sfx_players.append(p)

func _load_music() -> void:
	var music_files: Array[Array] = [
		["hallway_between_bells", "Hallway Between Bells"],
		["chalkboard_rebels", "Chalkboard Rebels"],
		["detention_escape", "Detention Escape"],
		["back_row_breakout", "Back Row Breakout"],
		["homework_heist", "Homework Heist"],
		["neon_gym_class_calculus", "Neon Gym Class Calculus"],
		["golden_hour_loop", "Golden Hour Loop"],
		["final_boss_pop_quiz", "Final Boss Pop Quiz"],
		["cafeteria_code_red", "Cafeteria Code Red"],
		["sirens_in_the_arcade", "Sirens In The Arcade"],
		["slow_motion_hallway_hero", "Slow Motion Hallway Hero"],
	]
	for entry in music_files:
		var key: String = entry[0]
		var display: String = entry[1]
		var path: String = "res://assets/audio/music/" + key + ".ogg"
		var stream = load(path)
		if stream:
			music_tracks[key] = stream
			music_display_names[key] = display

func _load_sfx() -> void:
	var sfx_files: Array[String] = [
		"sfx_game_over",
		"sfx_level_complete",
		"sfx_tower_place",
		"sfx_division",
		"sfx_solved",
		"sfx_escaped",
		"sfx_spawn",
		"sfx_button",
	]
	for sfx_name in sfx_files:
		var path: String = "res://assets/audio/sfx/" + sfx_name + ".ogg"
		var stream = load(path)
		if stream:
			sfx_clips[sfx_name] = stream

func _build_gameplay_playlist() -> void:
	gameplay_tracks = []
	for key in music_tracks.keys():
		if key != "hallway_between_bells":  # exclude level select track
			gameplay_tracks.append(key)
	gameplay_tracks.shuffle()
	gameplay_index = 0

# ─── Music Playback ──────────────────────────────────────────────

func play_music(track_key: String, crossfade_duration: float = 1.0) -> void:
	if track_key == current_music_key:
		return
	if not music_tracks.has(track_key):
		return

	current_music_key = track_key
	var stream: AudioStream = music_tracks[track_key]

	# Determine which player to fade in
	var fade_in_player: AudioStreamPlayer
	var fade_out_player: AudioStreamPlayer
	if active_player == music_player_a:
		fade_in_player = music_player_b
		fade_out_player = music_player_a
	else:
		fade_in_player = music_player_a
		fade_out_player = music_player_b

	# Start new track
	fade_in_player.stream = stream
	fade_in_player.volume_db = -40.0
	fade_in_player.play()

	# Crossfade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fade_in_player, "volume_db", MUSIC_VOLUME_DB, crossfade_duration)
	if fade_out_player.playing:
		tween.tween_property(fade_out_player, "volume_db", -40.0, crossfade_duration)
		tween.tween_callback(fade_out_player.stop).set_delay(crossfade_duration)

	active_player = fade_in_player

	# Emit display name
	var display_name: String = music_display_names.get(track_key, track_key)
	music_changed.emit(display_name)

	# Connect finished signal for auto-advance (gameplay tracks loop through playlist)
	if fade_in_player.finished.is_connected(_on_music_finished):
		fade_in_player.finished.disconnect(_on_music_finished)
	fade_in_player.finished.connect(_on_music_finished)

func stop_music(fade_duration: float = 0.5) -> void:
	current_music_key = ""
	var tween := create_tween()
	tween.set_parallel(true)
	if music_player_a.playing:
		tween.tween_property(music_player_a, "volume_db", -40.0, fade_duration)
		tween.tween_callback(music_player_a.stop).set_delay(fade_duration)
	if music_player_b.playing:
		tween.tween_property(music_player_b, "volume_db", -40.0, fade_duration)
		tween.tween_callback(music_player_b.stop).set_delay(fade_duration)

func play_level_select_music() -> void:
	play_music("hallway_between_bells")

func play_gameplay_music() -> void:
	if gameplay_tracks.is_empty():
		_build_gameplay_playlist()
	if gameplay_tracks.is_empty():
		return
	var track_key: String = gameplay_tracks[gameplay_index]
	play_music(track_key)

func _on_music_finished() -> void:
	# Auto-advance to next gameplay track
	if current_music_key == "hallway_between_bells":
		# Level select loops
		play_music("hallway_between_bells")
		return
	gameplay_index = (gameplay_index + 1) % gameplay_tracks.size()
	var next_key: String = gameplay_tracks[gameplay_index]
	current_music_key = ""  # reset so play_music doesn't skip
	play_music(next_key, 0.5)

# ─── SFX Playback ───────────────────────────────────────────────

func play_sfx(sfx_name: String) -> void:
	if not sfx_clips.has(sfx_name):
		return
	var player := _get_free_sfx_player()
	if player:
		player.stream = sfx_clips[sfx_name]
		player.volume_db = SFX_VOLUME_DB
		player.play()

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in sfx_players:
		if not p.playing:
			return p
	# All busy — reuse first one
	return sfx_players[0]

# Convenience methods
func play_tower_place() -> void:
	play_sfx("sfx_tower_place")

func play_division() -> void:
	play_sfx("sfx_division")

func play_solved() -> void:
	play_sfx("sfx_solved")

func play_game_over() -> void:
	play_sfx("sfx_game_over")

func play_level_complete() -> void:
	play_sfx("sfx_level_complete")

func play_escaped() -> void:
	play_sfx("sfx_escaped")

func play_button() -> void:
	play_sfx("sfx_button")
