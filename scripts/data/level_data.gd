class_name LevelData
extends Resource

## Human-readable level name
@export var level_name: String = "Level 1"

## Grid layout: 15 strings of 10 characters each
## '#' = wall, '.' = path, 'S' = start, 'E' = end
@export var grid_layout: PackedStringArray = []

## Starting HP for this level
@export var starting_hp: int = 100

## Sequence of numbers to spawn
@export var number_sequence: Array[int] = []

## Ticks between spawns
@export var ticks_between_spawns: int = 5

## Tick speed in seconds (lower = faster)
@export var tick_speed: float = 1.0
