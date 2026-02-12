class_name LevelSelect
extends CanvasLayer

signal level_selected(level_index: int)

const TOTAL_LEVELS: int = 60
const COLS: int = 5
const ROWS: int = 12
const CELL_SIZE: float = 56.0
const VIEWPORT_W: float = 390.0
const VIEWPORT_H: float = 870.0

var caveat_bold: Font
var pencil_material: ShaderMaterial
var level_buttons: Array = []
var star_labels: Array = []  # Label nodes showing stars below each level number

func _ready() -> void:
	layer = 2  # Above HUD (layer 1)
	caveat_bold = load("res://assets/fonts/Caveat-Bold.ttf")
	var pencil_shader = load("res://assets/shaders/pencil.gdshader")
	if pencil_shader:
		pencil_material = ShaderMaterial.new()
		pencil_material.shader = pencil_shader
	_build_ui()

func _build_ui() -> void:
	# Paper background
	var bg := ColorRect.new()
	bg.offset_right = VIEWPORT_W
	bg.offset_bottom = VIEWPORT_H
	bg.color = Color(0.992, 0.973, 0.91, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Grid lines (notebook paper style)
	var grid_canvas := Control.new()
	grid_canvas.offset_right = VIEWPORT_W
	grid_canvas.offset_bottom = VIEWPORT_H
	grid_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_canvas.draw.connect(_draw_grid_lines.bind(grid_canvas))
	add_child(grid_canvas)
	grid_canvas.queue_redraw()

	# Title
	var title := Label.new()
	title.text = "Number March"
	title.size = Vector2(VIEWPORT_W, 60)
	title.position = Vector2(0, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if caveat_bold:
		title.add_theme_font_override("font", caveat_bold)
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#333333"))
	title.add_theme_constant_override("outline_size", 1)
	title.add_theme_color_override("font_outline_color", Color("#333333"))
	if pencil_material:
		title.material = pencil_material
	add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "choose a level"
	subtitle.size = Vector2(VIEWPORT_W, 30)
	subtitle.position = Vector2(0, 100)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if caveat_bold:
		subtitle.add_theme_font_override("font", caveat_bold)
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color("#777777"))
	subtitle.add_theme_constant_override("outline_size", 1)
	subtitle.add_theme_color_override("font_outline_color", Color("#777777"))
	if pencil_material:
		subtitle.material = pencil_material
	add_child(subtitle)

	# Level number grid
	var grid_width: float = COLS * CELL_SIZE
	var grid_start_x: float = (VIEWPORT_W - grid_width) / 2.0
	var grid_start_y: float = 160.0

	for i in TOTAL_LEVELS:
		var col: int = i % COLS
		var row: int = i / COLS
		var x: float = grid_start_x + col * CELL_SIZE
		var y: float = grid_start_y + row * CELL_SIZE

		var btn := Button.new()
		btn.text = str(i + 1)
		btn.flat = true
		btn.size = Vector2(CELL_SIZE, CELL_SIZE)
		btn.position = Vector2(x, y)

		if caveat_bold:
			btn.add_theme_font_override("font", caveat_bold)
		btn.add_theme_font_size_override("font_size", 26)
		btn.add_theme_color_override("font_color", Color("#444444"))
		btn.add_theme_color_override("font_hover_color", Color("#222222"))
		btn.add_theme_color_override("font_pressed_color", Color("#2244AA"))
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Subtle hover highlight
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.65, 0.75, 0.9, 0.15)
		hover_style.corner_radius_top_left = 6
		hover_style.corner_radius_top_right = 6
		hover_style.corner_radius_bottom_left = 6
		hover_style.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.65, 0.75, 0.9, 0.25)
		pressed_style.corner_radius_top_left = 6
		pressed_style.corner_radius_top_right = 6
		pressed_style.corner_radius_bottom_left = 6
		pressed_style.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		# Slight random rotation for hand-written feel
		var angle: float = deg_to_rad(sin(float(i) * 2.7 + 0.3) * 4.0)
		btn.pivot_offset = Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
		btn.rotation = angle

		var level_idx: int = i
		btn.pressed.connect(_on_level_pressed.bind(level_idx))
		add_child(btn)
		level_buttons.append(btn)

		# Star label below the number
		var stars_lbl := Label.new()
		stars_lbl.text = ""
		stars_lbl.size = Vector2(CELL_SIZE, 18)
		stars_lbl.position = Vector2(x, y + CELL_SIZE - 14)
		stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stars_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if caveat_bold:
			stars_lbl.add_theme_font_override("font", caveat_bold)
		stars_lbl.add_theme_font_size_override("font_size", 12)
		stars_lbl.add_theme_color_override("font_color", Color(0.7, 0.6, 0.2, 0.85))
		stars_lbl.add_theme_constant_override("outline_size", 1)
		stars_lbl.add_theme_color_override("font_outline_color", Color(0.7, 0.6, 0.2, 0.85))
		# Same slight rotation as the button
		stars_lbl.pivot_offset = Vector2(CELL_SIZE / 2.0, 9)
		stars_lbl.rotation = angle
		if pencil_material:
			stars_lbl.material = pencil_material
		add_child(stars_lbl)
		star_labels.append(stars_lbl)

func update_stars(level_stars: Dictionary) -> void:
	for i in TOTAL_LEVELS:
		var stars: int = level_stars.get(i, 0)
		# Level is unlocked if it's the first one, or the previous level has been completed
		var unlocked: bool = (i == 0) or level_stars.has(i - 1)

		if stars > 0:
			var star_text: String = ""
			for s in 3:
				if s < stars:
					star_text += "★"
				else:
					star_text += "☆"
			star_labels[i].text = star_text
		else:
			star_labels[i].text = ""

		# Gray out and disable locked levels
		if unlocked:
			level_buttons[i].disabled = false
			level_buttons[i].add_theme_color_override("font_color", Color("#444444"))
			level_buttons[i].add_theme_color_override("font_disabled_color", Color("#444444"))
			level_buttons[i].modulate = Color(1, 1, 1, 1)
		else:
			level_buttons[i].disabled = not OS.is_debug_build()
			level_buttons[i].add_theme_color_override("font_color", Color("#CCCCCC"))
			level_buttons[i].add_theme_color_override("font_disabled_color", Color("#CCCCCC"))
			level_buttons[i].modulate = Color(1, 1, 1, 1)

func _draw_grid_lines(canvas: Control) -> void:
	var grid_color := Color(0.66, 0.78, 0.91, 0.4)
	# Horizontal lines
	var line_spacing: float = 38.0
	for i in range(int(VIEWPORT_H / line_spacing) + 1):
		var y: float = i * line_spacing
		canvas.draw_line(Vector2(0, y), Vector2(VIEWPORT_W, y), grid_color, 1.0)
	# Vertical lines
	for i in range(int(VIEWPORT_W / line_spacing) + 1):
		var x: float = i * line_spacing
		canvas.draw_line(Vector2(x, 0), Vector2(x, VIEWPORT_H), grid_color, 1.0)

func _on_level_pressed(level_index: int) -> void:
	level_selected.emit(level_index)
