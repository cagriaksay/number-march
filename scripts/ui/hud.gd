class_name HUD
extends CanvasLayer

var caveat_font: Font
var caveat_bold: Font
var pencil_material: ShaderMaterial

const DEBUG_FPS: bool = true

@onready var health_label: Label = $HealthLabel
var fps_label: Label
@onready var queue_container: Control = $QueueContainer
@onready var game_over_panel: PanelContainer = $GameOverPanel
@onready var game_over_label: Label = $GameOverPanel/VBoxContainer/ResultLabel
@onready var stars_label: Label = $GameOverPanel/VBoxContainer/StarsLabel
@onready var retry_button: Button = $GameOverPanel/VBoxContainer/RetryButton

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
		fps_label.offset_left = 330.0
		fps_label.offset_top = 12.0
		fps_label.offset_right = 382.0
		fps_label.offset_bottom = 30.0
		fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fps_label.add_theme_font_size_override("font_size", 11)
		fps_label.add_theme_color_override("font_color", Color("#999999"))
		add_child(fps_label)

func _apply_font(lbl: Label, size: int, color: Color) -> void:
	if caveat_bold:
		lbl.add_theme_font_override("font", caveat_bold)
	elif caveat_font:
		lbl.add_theme_font_override("font", caveat_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.add_theme_color_override("font_outline_color", color)

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
	# Position each label: offset by +1 slot so label 0 scrolls from SLOT_WIDTH to 0
	for i in queue_labels.size():
		var x_pos: float = (i + 1) * QUEUE_SLOT_WIDTH - queue_scroll
		queue_labels[i].position.x = x_pos
		_style_queue_label(queue_labels[i], i, x_pos)

func _create_queue_label(val: int) -> Label:
	var lbl := Label.new()
	lbl.text = str(val)
	lbl.size = Vector2(QUEUE_SLOT_WIDTH, 30)
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
	# Clear queue on reset
	for lbl in queue_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	queue_labels.clear()
	queue_data.clear()
	queue_scroll = 0.0
	queue_paused = false
