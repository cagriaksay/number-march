extends Node

# Autoload singleton for Game Center integration (SwiftGodot GDExtension)
# Uses signal-based API from SwiftGodotIosPlugins
# Gracefully does nothing when plugin is unavailable (editor, Android, etc.)

var game_center = null
var is_authenticated: bool = false

# Number March has 60 levels (indices 0-59, displayed as 1-60)
const TOTAL_LEVELS: int = 60

# Leaderboard ID format: level_{N}_score (N = 1..60, score = remaining HP)
# Achievement ID format: level_{N}_complete, all_levels_complete
const LEADERBOARD_SCORE_PREFIX = "level_%d_score"
const ACHIEVEMENT_PREFIX = "level_%d_complete"
const ACHIEVEMENT_ALL_COMPLETE = "all_levels_complete"

func _ready():
	if ClassDB.class_exists("GameCenter"):
		game_center = ClassDB.instantiate("GameCenter")
		_connect_signals()
		game_center.authenticate()
		print("[GameCenter] Plugin found, authenticating...")
	else:
		print("[GameCenter] Plugin not available on this platform.")

func _connect_signals():
	if not game_center:
		return

	# Authentication
	game_center.signin_success.connect(_on_signin_success)
	game_center.signin_fail.connect(_on_signin_fail)

	# Leaderboard score submission
	if game_center.has_signal("leaderboard_score_ingame_success"):
		game_center.leaderboard_score_ingame_success.connect(_on_score_submitted)
		game_center.leaderboard_score_ingame_fail.connect(_on_score_failed)
	elif game_center.has_signal("leaderboard_score_success"):
		game_center.leaderboard_score_success.connect(func(): print("[GameCenter] Score posted"))
		game_center.leaderboard_score_fail.connect(func(err, msg): print("[GameCenter] Score failed: %s" % msg))

	# Achievements
	game_center.achievements_report_success.connect(_on_achievement_reported)
	game_center.achievements_report_fail.connect(_on_achievement_failed)

	# Leaderboard UI
	game_center.leaderboard_dismissed.connect(func(): print("[GameCenter] Leaderboard dismissed"))

# --- Authentication Callbacks ---

func _on_signin_success(player) -> void:
	is_authenticated = true
	print("[GameCenter] Authenticated! Player: %s" % str(player))

func _on_signin_fail(error: int, message: String) -> void:
	is_authenticated = false
	print("[GameCenter] Auth failed (%d): %s" % [error, message])

# --- Leaderboard Score Callbacks ---

func _on_score_submitted(leaderboard_id: String) -> void:
	print("[GameCenter] Score posted to: %s" % leaderboard_id)

func _on_score_failed(error: int, message: String, leaderboard_id: String) -> void:
	print("[GameCenter] Score post failed for %s (%d): %s" % [leaderboard_id, error, message])

# --- Achievement Callbacks ---

func _on_achievement_reported() -> void:
	print("[GameCenter] Achievement reported successfully")

func _on_achievement_failed(error: int, message: String) -> void:
	print("[GameCenter] Achievement report failed (%d): %s" % [error, message])

# --- Leaderboards ---

func post_level_score(level_index: int, score: int):
	"""Post best score (remaining HP) for a level."""
	if not game_center or not is_authenticated:
		return
	var leaderboard_id = LEADERBOARD_SCORE_PREFIX % (level_index + 1)
	game_center.submitScore(score, [leaderboard_id], 0)
	print("[GameCenter] Submitting score %d to %s" % [score, leaderboard_id])

# --- Achievements ---

func award_level_complete(level_index: int):
	"""Award achievement for completing a level."""
	if not game_center or not is_authenticated:
		return
	var achievement_id = ACHIEVEMENT_PREFIX % (level_index + 1)
	if ClassDB.class_exists("GameCenterAchievement"):
		var achievement = ClassDB.instantiate("GameCenterAchievement")
		achievement.identifier = achievement_id
		achievement.percentComplete = 100.0
		achievement.showsCompletionBanner = true
		game_center.reportAchievements([achievement])
		print("[GameCenter] Reporting achievement: %s" % achievement_id)

func award_all_levels_complete():
	"""Award achievement for completing all 60 levels."""
	if not game_center or not is_authenticated:
		return
	if ClassDB.class_exists("GameCenterAchievement"):
		var achievement = ClassDB.instantiate("GameCenterAchievement")
		achievement.identifier = ACHIEVEMENT_ALL_COMPLETE
		achievement.percentComplete = 100.0
		achievement.showsCompletionBanner = true
		game_center.reportAchievements([achievement])
		print("[GameCenter] Reporting all-levels-complete achievement!")

# --- UI ---

func show_leaderboards(level_index: int = -1):
	"""Show Game Center leaderboard overlay."""
	if not game_center or not is_authenticated:
		print("[GameCenter] Cannot show leaderboards - not authenticated")
		return
	if level_index >= 0:
		var leaderboard_id = LEADERBOARD_SCORE_PREFIX % (level_index + 1)
		game_center.showLeaderboard(leaderboard_id)
	else:
		game_center.showLeaderboards()

func show_achievements():
	"""Show Game Center achievements overlay."""
	if not game_center or not is_authenticated:
		print("[GameCenter] Cannot show achievements - not authenticated")
		return
	game_center.showAchievements()

# --- Sync ---

func sync_all_scores(level_stars: Dictionary, level_scores: Dictionary):
	"""After authentication, post all locally saved best scores to Game Center."""
	if not game_center or not is_authenticated:
		return
	for level_idx in level_stars:
		var stars = level_stars[level_idx]
		if stars > 0:
			award_level_complete(level_idx)
			if level_scores.has(level_idx):
				post_level_score(level_idx, level_scores[level_idx])

	if level_stars.size() >= TOTAL_LEVELS:
		var all_complete := true
		for i in TOTAL_LEVELS:
			if not level_stars.has(i) or level_stars[i] <= 0:
				all_complete = false
				break
		if all_complete:
			award_all_levels_complete()

	print("[GameCenter] Synced %d completed levels" % level_stars.size())

# --- Utility ---

func is_available() -> bool:
	"""Check if Game Center is available and authenticated."""
	return game_center != null and is_authenticated
