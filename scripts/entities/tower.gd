class_name Tower
extends Node2D

var value: int = 2
var grid_pos: Vector2i = Vector2i.ZERO
var cell_size: float = 39.0

var color_circle: Color = Color("#2244AA")
var color_inert: Color = Color("#AABBCC")
var color_text: Color = Color("#2244AA")
var caveat_font: Font
var circle_rotation: float = 0.0  # random rotation offset for the wobbly circle

@onready var label: Label = $Label

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
	# Random 90° rotation for the wobbly circle
	var rot_options: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
	circle_rotation = rot_options[randi() % 4]
	_update_visual()
	queue_redraw()

func increment() -> void:
	"""Tap to increase value by 1."""
	if value >= 49:
		return
	value += 1
	_update_visual()
	_play_scribble()
	queue_redraw()

func degrade() -> void:
	"""After successful division, lose 1 point."""
	value -= 1
	if value < 1:
		value = 1
	_update_visual()
	_play_degrade()
	queue_redraw()

func _update_visual() -> void:
	if label:
		label.text = str(value)
		# Scale font for large numbers
		var font_size: int = 18
		if value >= 10:
			font_size = 14
		label.add_theme_font_size_override("font_size", font_size)
		# Dim when inert (value 1), full color when active
		var col: Color
		if value <= 1:
			col = color_inert
		else:
			col = color_text
		label.add_theme_color_override("font_color", col)
		label.add_theme_constant_override("outline_size", 1)
		label.add_theme_color_override("font_outline_color", col)

func _draw() -> void:
	# Draw hand-drawn circle
	var radius: float = cell_size * 0.38
	var alpha: float = 0.25 if value <= 1 else 0.5 + (float(value) / 49.0) * 0.5
	var col: Color = color_circle if value >= 2 else color_inert
	col.a = alpha

	# Hand-drawn rounded rectangle
	var half := cell_size * 0.38
	var corner_r := half * 0.3
	var segments_per_corner := 6
	var points: PackedVector2Array = PackedVector2Array()

	# Build rounded rect corners: top-left, top-right, bottom-right, bottom-left
	var corners := [
		[Vector2(-half, -half), Vector2(-half + corner_r, -half), Vector2(-half, -half + corner_r), PI, PI * 1.5],
		[Vector2(half, -half), Vector2(half, -half + corner_r), Vector2(half - corner_r, -half), PI * 1.5, TAU],
		[Vector2(half, half), Vector2(half - corner_r, half), Vector2(half, half - corner_r), 0.0, PI * 0.5],
		[Vector2(-half, half), Vector2(-half, half - corner_r), Vector2(-half + corner_r, half), PI * 0.5, PI],
	]
	for c in corners:
		var center_pt: Vector2 = Vector2(
			c[0].x + (corner_r if c[0].x < 0 else -corner_r),
			c[0].y + (corner_r if c[0].y < 0 else -corner_r))
		for j in range(segments_per_corner + 1):
			var t := float(j) / float(segments_per_corner)
			var angle: float = lerpf(c[3], c[4], t)
			var wobble: float = sin(angle * 5.0 + circle_rotation) * 0.6
			var r: float = corner_r + wobble
			points.append(center_pt + Vector2(cos(angle) * r, sin(angle) * r))

	for i in range(points.size()):
		var next := (i + 1) % points.size()
		draw_line(points[i], points[next], col, 1.8, true)

func _play_scribble() -> void:
	# Quick scale bump feedback
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.05)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _play_degrade() -> void:
	# Subtle shake
	var orig_pos := position
	var tween := create_tween()
	tween.tween_property(self, "position", orig_pos + Vector2(2, 0), 0.03)
	tween.tween_property(self, "position", orig_pos - Vector2(2, 0), 0.03)
	tween.tween_property(self, "position", orig_pos, 0.03)
