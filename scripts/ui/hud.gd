class_name HUD
extends CanvasLayer

signal pause_pressed
signal resume_pressed
signal restart_pressed
signal level_select_pressed
signal fast_forward_toggled(enabled: bool)

var caveat_font: Font
var caveat_bold: Font
var pencil_material: ShaderMaterial

const DEBUG_FPS: bool = true

@onready var health_label: Label = $HealthLabel
var fps_label: Label
var pause_button: Button
var ff_button: Button
var ff_active: bool = false
@onready var queue_container: Control = $QueueContainer
@onready var game_over_panel: PanelContainer = $GameOverPanel
@onready var game_over_label: Label = $GameOverPanel/VBoxContainer/ResultLabel
@onready var stars_label: Label = $GameOverPanel/VBoxContainer/StarsLabel
@onready var retry_button: Button = $GameOverPanel/VBoxContainer/RetryButton
@onready var levels_button: Button = $GameOverPanel/VBoxContainer/LevelsButton

# Pause popup
var pause_overlay: Control
var pause_paper: Control
var is_paused: bool = false

# Music name display
var music_name_label: Label
var music_name_tween: Tween

func _ready() -> void:
	caveat_font = load("res://assets/fonts/Caveat-Regular.ttf")
	caveat_bold = load("res://assets/fonts/Caveat-Bold.ttf")
	game_over_panel.visible = false
	# Dark panel background for game over
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.2, 0.92)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	game_over_panel.add_theme_stylebox_override("panel", panel_style)
	_apply_font(health_label, 28, Color("#333333"))
	_apply_font(game_over_label, 32, Color("#FFFFFF"))
	_apply_font(stars_label, 28, Color("#E8C840"))
	if caveat_bold:
		retry_button.add_theme_font_override("font", caveat_bold)
	elif caveat_font:
		retry_button.add_theme_font_override("font", caveat_font)
	retry_button.add_theme_font_size_override("font_size", 22)
	if caveat_bold:
		levels_button.add_theme_font_override("font", caveat_bold)
	elif caveat_font:
		levels_button.add_theme_font_override("font", caveat_font)
	levels_button.add_theme_font_size_override("font_size", 22)
	# Pencil shader for HUD labels
	var pencil_shader = load("res://assets/shaders/pencil.gdshader")
	if pencil_shader:
		pencil_material = ShaderMaterial.new()
		pencil_material.shader = pencil_shader
		health_label.material = pencil_material
	# Debug FPS counter
	if DEBUG_FPS:
		fps_label = Label.new()
		fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fps_label.offset_left = 240.0
		fps_label.offset_top = 12.0
		fps_label.offset_right = 330.0
		fps_label.offset_bottom = 30.0
		fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fps_label.add_theme_font_size_override("font_size", 11)
		fps_label.add_theme_color_override("font_color", Color("#999999"))
		add_child(fps_label)
	# Pause button (top-right)
	_create_pause_button()
	# Pause popup (hidden initially)
	_create_pause_popup()
	# Music name label (bottom area, above queue)
	_create_music_name_label()

func _apply_font(lbl: Label, size: int, color: Color) -> void:
	if caveat_bold:
		lbl.add_theme_font_override("font", caveat_bold)
	elif caveat_font:
		lbl.add_theme_font_override("font", caveat_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_outline_color", color)

# ─── Pause Button ────────────────────────────────────────────────

func _create_pause_button() -> void:
	# Fast forward button (left of pause)
	ff_button = Button.new()
	ff_button.text = ">>"
	ff_button.flat = true
	ff_button.offset_left = 296.0
	ff_button.offset_top = 10.0
	ff_button.offset_right = 336.0
	ff_button.offset_bottom = 42.0
	if caveat_bold:
		ff_button.add_theme_font_override("font", caveat_bold)
	ff_button.add_theme_font_size_override("font_size", 20)
	ff_button.add_theme_color_override("font_color", Color("#555555"))
	ff_button.add_theme_color_override("font_hover_color", Color("#333333"))
	ff_button.add_theme_color_override("font_pressed_color", Color("#333333"))
	ff_button.mouse_filter = Control.MOUSE_FILTER_STOP
	ff_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	ff_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	ff_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	ff_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	ff_button.pressed.connect(_on_ff_pressed)
	add_child(ff_button)

	# Pause button
	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.flat = true
	pause_button.offset_left = 340.0
	pause_button.offset_top = 10.0
	pause_button.offset_right = 380.0
	pause_button.offset_bottom = 42.0
	if caveat_bold:
		pause_button.add_theme_font_override("font", caveat_bold)
	pause_button.add_theme_font_size_override("font_size", 20)
	pause_button.add_theme_color_override("font_color", Color("#555555"))
	pause_button.add_theme_color_override("font_hover_color", Color("#333333"))
	pause_button.add_theme_color_override("font_pressed_color", Color("#333333"))
	pause_button.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	pause_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	pause_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	pause_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pause_button.pressed.connect(_on_pause_pressed)
	add_child(pause_button)

func _on_ff_pressed() -> void:
	ff_active = not ff_active
	if ff_active:
		ff_button.add_theme_color_override("font_color", Color("#CC2222"))
		ff_button.add_theme_color_override("font_hover_color", Color("#CC2222"))
		ff_button.add_theme_color_override("font_pressed_color", Color("#CC2222"))
		ff_button.add_theme_color_override("font_focus_color", Color("#CC2222"))
	else:
		ff_button.add_theme_color_override("font_color", Color("#555555"))
		ff_button.add_theme_color_override("font_hover_color", Color("#333333"))
		ff_button.add_theme_color_override("font_pressed_color", Color("#333333"))
		ff_button.add_theme_color_override("font_focus_color", Color("#555555"))
	fast_forward_toggled.emit(ff_active)

func _on_pause_pressed() -> void:
	if is_paused:
		return
	show_pause()

# ─── Pause Popup (Tilted Paper) ─────────────────────────────────

func _create_pause_popup() -> void:
	# Dim overlay behind the paper
	pause_overlay = Control.new()
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.offset_right = 390.0
	pause_overlay.offset_bottom = 870.0
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pause_overlay)

	# Dark semi-transparent background
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(dim)

	# Tilted paper container
	pause_paper = Control.new()
	pause_paper.size = Vector2(220, 260)
	pause_paper.position = Vector2(85, 260)
	pause_paper.pivot_offset = Vector2(110, 130)
	pause_paper.rotation = deg_to_rad(-3.5)
	pause_paper.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.add_child(pause_paper)

	# Paper background (off-white with shadow)
	var shadow := ColorRect.new()
	shadow.size = Vector2(220, 260)
	shadow.position = Vector2(4, 4)
	shadow.color = Color(0.0, 0.0, 0.0, 0.15)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_paper.add_child(shadow)

	var paper_bg := ColorRect.new()
	paper_bg.size = Vector2(220, 260)
	paper_bg.color = Color(0.98, 0.96, 0.90, 1.0)
	paper_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_paper.add_child(paper_bg)

	# Faint grid lines on paper
	var line_container := Control.new()
	line_container.size = Vector2(220, 260)
	line_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_paper.add_child(line_container)

	# "Paused" title
	var title := Label.new()
	title.text = "Paused"
	title.size = Vector2(220, 50)
	title.position = Vector2(0, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(title, 34, Color("#333333"))
	if pencil_material:
		title.material = pencil_material
	pause_paper.add_child(title)

	# Resume button
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.flat = true
	resume_btn.size = Vector2(160, 44)
	resume_btn.position = Vector2(30, 80)
	_style_paper_button(resume_btn)
	resume_btn.pressed.connect(_on_resume_pressed)
	pause_paper.add_child(resume_btn)

	# Restart button
	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.flat = true
	restart_btn.size = Vector2(160, 44)
	restart_btn.position = Vector2(30, 132)
	_style_paper_button(restart_btn)
	restart_btn.pressed.connect(_on_restart_pressed)
	pause_paper.add_child(restart_btn)

	# Level Select button
	var levels_btn := Button.new()
	levels_btn.text = "Levels"
	levels_btn.flat = true
	levels_btn.size = Vector2(160, 44)
	levels_btn.position = Vector2(30, 184)
	_style_paper_button(levels_btn)
	levels_btn.pressed.connect(_on_level_select_pressed)
	pause_paper.add_child(levels_btn)

func _style_paper_button(btn: Button) -> void:
	if caveat_bold:
		btn.add_theme_font_override("font", caveat_bold)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color("#444444"))
	btn.add_theme_color_override("font_hover_color", Color("#222222"))
	btn.add_theme_color_override("font_pressed_color", Color("#222222"))
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Underline style
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.0, 0.0, 0.0, 0.06)
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.0, 0.0, 0.0, 0.1)
	pressed_style.corner_radius_top_left = 4
	pressed_style.corner_radius_top_right = 4
	pressed_style.corner_radius_bottom_left = 4
	pressed_style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("pressed", pressed_style)
	var normal_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func show_pause() -> void:
	is_paused = true
	pause_overlay.visible = true
	pause_button.visible = false
	ff_button.visible = false
	# Animate paper in
	pause_paper.scale = Vector2(0.8, 0.8)
	pause_paper.modulate.a = 0.0
	var tween := pause_paper.create_tween()
	tween.set_parallel(true)
	tween.tween_property(pause_paper, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(pause_paper, "modulate:a", 1.0, 0.15)
	pause_pressed.emit()

func hide_pause() -> void:
	is_paused = false
	pause_overlay.visible = false
	pause_button.visible = true
	ff_button.visible = true
	resume_pressed.emit()

func _on_resume_pressed() -> void:
	hide_pause()

func _on_restart_pressed() -> void:
	is_paused = false
	pause_overlay.visible = false
	pause_button.visible = true
	ff_button.visible = true
	restart_pressed.emit()

func _on_level_select_pressed() -> void:
	is_paused = false
	pause_overlay.visible = false
	pause_button.visible = true
	ff_button.visible = true
	level_select_pressed.emit()

func update_health(current: int, _max_hp: int) -> void:
	health_label.text = str(current)
	var col: Color
	if current < 20:
		col = Color("#CC2222")
	else:
		col = Color("#333333")
	health_label.add_theme_color_override("font_color", col)
	health_label.add_theme_color_override("font_outline_color", col)

const QUEUE_SLOT_WIDTH: float = 31.0

var queue_labels: Array = []  # currently displayed Label nodes
var queue_scroll: float = 0.0  # continuous scroll offset in pixels
var queue_scroll_speed: float = 0.0  # pixels per second
var queue_data: Array[int] = []  # current visible numbers
var queue_paused: bool = false  # pause scroll when spawn is blocked

# Queue waddle animation
var queue_waddle_time: float = 0.0
const QUEUE_WADDLE_SPEED: float = 2.5  # cycles per second
const QUEUE_TILT: float = 0.12  # radians (~7°)
const QUEUE_BOUNCE: float = 1.5  # pixels vertical

func update_queue(visible_numbers: Array[int]) -> void:
	# Check if front number was consumed
	var shifted: bool = false
	if queue_data.size() > 0 and visible_numbers.size() > 0:
		if queue_data[0] != visible_numbers[0]:
			shifted = true

	queue_data = visible_numbers.duplicate()

	if shifted and queue_labels.size() > 0:
		# Remove the departing first label (just let it scroll off to the left)
		var departing: Label = queue_labels[0]
		queue_labels.remove_at(0)
		var tween := departing.create_tween()
		tween.tween_property(departing, "modulate:a", 0.0, 0.3)
		tween.tween_callback(departing.queue_free)
		# Subtract one slot from scroll (keeps remaining labels in place, no jump)
		queue_scroll -= QUEUE_SLOT_WIDTH
		if queue_scroll < 0.0:
			queue_scroll = 0.0

	# Remove excess
	while queue_labels.size() > visible_numbers.size():
		var old_lbl: Label = queue_labels.pop_back()
		old_lbl.queue_free()

	# Add missing labels at the end
	while queue_labels.size() < visible_numbers.size():
		var i: int = queue_labels.size()
		var lbl := _create_queue_label(visible_numbers[i])
		queue_container.add_child(lbl)
		queue_labels.append(lbl)

	# Update text
	for i in queue_labels.size():
		queue_labels[i].text = str(visible_numbers[i])

func set_scroll_speed(ticks_between_spawns: int, tick_duration: float) -> void:
	# One slot width per spawn interval
	var spawn_interval: float = ticks_between_spawns * tick_duration
	if spawn_interval > 0:
		queue_scroll_speed = QUEUE_SLOT_WIDTH / spawn_interval

func _process(delta: float) -> void:
	if DEBUG_FPS and fps_label:
		fps_label.text = str(int(Engine.get_frames_per_second()))

	if queue_labels.is_empty():
		return
	# Continuously scroll left (unless paused by blocked spawn)
	if not queue_paused:
		queue_scroll += delta * queue_scroll_speed
	# Clamp so scroll never exceeds one slot (prevents leftward drift over time)
	if queue_scroll > QUEUE_SLOT_WIDTH:
		queue_scroll = QUEUE_SLOT_WIDTH
	# Waddle timer
	queue_waddle_time += delta * QUEUE_WADDLE_SPEED
	# Position each label: offset by +1 slot so label 0 scrolls from SLOT_WIDTH to 0
	for i in queue_labels.size():
		var x_pos: float = (i + 1) * QUEUE_SLOT_WIDTH - queue_scroll
		queue_labels[i].position.x = x_pos
		_style_queue_label(queue_labels[i], i, x_pos)
		# South Park waddle: tilt and bounce
		var phase: float = queue_waddle_time + i * 0.5
		var tilt: float = sin(phase * TAU) * QUEUE_TILT
		var bounce: float = abs(sin(phase * TAU)) * QUEUE_BOUNCE
		queue_labels[i].rotation = tilt
		queue_labels[i].position.y = -bounce

func _create_queue_label(val: int) -> Label:
	var lbl := Label.new()
	lbl.text = str(val)
	lbl.size = Vector2(QUEUE_SLOT_WIDTH, 30)
	lbl.pivot_offset = Vector2(QUEUE_SLOT_WIDTH / 2.0, 15.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if caveat_bold:
		lbl.add_theme_font_override("font", caveat_bold)
	elif caveat_font:
		lbl.add_theme_font_override("font", caveat_font)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color("#555555"))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color("#555555"))
	if pencil_material:
		lbl.material = pencil_material
	return lbl

func _style_queue_label(lbl: Label, index: int, x_pos: float) -> void:
	var container_width: float = 390.0
	# Clip off-screen labels
	if x_pos < -QUEUE_SLOT_WIDTH:
		lbl.modulate.a = 0.0
		return
	elif x_pos < 0:
		# Scrolled just past left edge — fade out gracefully
		var fade: float = 1.0 - (-x_pos / QUEUE_SLOT_WIDTH)
		lbl.modulate.a = clampf(fade, 0.0, 1.0)
	elif x_pos > container_width - 40:
		# Fading in from right edge
		var fade_in: float = (container_width - x_pos) / 40.0
		lbl.modulate.a = clampf(fade_in, 0.0, 0.7)
	else:
		lbl.modulate.a = 0.7

	# Only the first label (next to spawn) is larger
	if index == 0:
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Color("#333333"))
		lbl.add_theme_color_override("font_outline_color", Color("#333333"))
		lbl.modulate.a = 1.0
	else:
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color("#555555"))
		lbl.add_theme_color_override("font_outline_color", Color("#555555"))

func show_game_over(stars: int, survived: bool) -> void:
	game_over_panel.visible = true
	pause_button.visible = false
	ff_button.visible = false
	if survived:
		game_over_label.text = "Level Complete!"
		var star_text: String = ""
		for i in 3:
			if i < stars:
				star_text += "★ "
			else:
				star_text += "☆ "
		stars_label.text = star_text
	else:
		game_over_label.text = "Game Over"
		stars_label.text = ""
	retry_button.text = "Retry"

func hide_game_over() -> void:
	game_over_panel.visible = false
	pause_button.visible = true
	ff_button.visible = true
	# Reset fast forward state
	ff_active = false
	ff_button.add_theme_color_override("font_color", Color("#555555"))
	ff_button.add_theme_color_override("font_hover_color", Color("#333333"))
	# Clear ALL queue children (including orphaned departing labels with active tweens)
	for child in queue_container.get_children():
		child.queue_free()
	queue_labels.clear()
	queue_data.clear()
	queue_scroll = 0.0
	queue_scroll_speed = 0.0
	queue_waddle_time = 0.0
	queue_paused = false

# ─── Music Name Display ─────────────────────────────────────────

func _create_music_name_label() -> void:
	music_name_label = Label.new()
	music_name_label.text = ""
	music_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	music_name_label.offset_left = 40.0
	music_name_label.offset_right = 350.0
	music_name_label.offset_top = 30.0
	music_name_label.offset_bottom = 48.0
	music_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	music_name_label.modulate.a = 0.0
	_apply_font(music_name_label, 14, Color("#888888"))
	if pencil_material:
		music_name_label.material = pencil_material
	add_child(music_name_label)

func show_music_name(display_name: String) -> void:
	if not music_name_label:
		return
	music_name_label.text = "♫ " + display_name
	# Kill any existing tween
	if music_name_tween and music_name_tween.is_valid():
		music_name_tween.kill()
	# Fade in, hold, fade out
	music_name_label.modulate.a = 0.0
	music_name_tween = music_name_label.create_tween()
	music_name_tween.tween_property(music_name_label, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_OUT)
	music_name_tween.tween_interval(4.0)
	music_name_tween.tween_property(music_name_label, "modulate:a", 0.0, 1.2).set_ease(Tween.EASE_IN)
