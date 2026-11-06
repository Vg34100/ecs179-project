class_name Carryable
extends CharacterBody3D

enum Kind { FOOD, TREASURE }

@export var kind: Kind = Kind.FOOD
@export_range(1, 30) var required_carriers: int = 1
@export_range(1, 30) var max_carriers: int = 2
# food value is separate from weight so both are easy to balance.
@export_range(0, 50) var seed_yield: int = 3
@export var carry_radius: float = 0.65


func _ready() -> void:
	$CarryCount.text = "0 / %d" % required_carriers
