class_name HealthManager
extends Node

signal health_changed(new_hp: int, max_hp: int)
signal game_over

var max_hp: int = 100
var current_hp: int = 100

func setup(starting_hp: int) -> void:
	max_hp = starting_hp
	current_hp = starting_hp
	health_changed.emit(current_hp, max_hp)

func spend(amount: int = 1) -> bool:
	"""Spend HP (for tapping). Returns false if cannot afford."""
	if current_hp <= 0:
		return false
	current_hp -= amount
	health_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		game_over.emit()
		return false
	return true

func take_damage(amount: int) -> void:
	"""Take damage from escaped numbers."""
	current_hp -= amount
	health_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		game_over.emit()

func heal(amount: int) -> void:
	"""Gain HP from successful divisions."""
	current_hp += amount
	health_changed.emit(current_hp, max_hp)

func get_stars() -> int:
	var ratio := float(current_hp) / float(max_hp)
	if ratio > 0.66:
		return 3
	elif ratio > 0.33:
		return 2
	elif current_hp > 0:
		return 1
	else:
		return 0
