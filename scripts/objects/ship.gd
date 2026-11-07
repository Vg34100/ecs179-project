extends Node3D

@export var collection_radius: float = 0.8

@onready var animation_player: AnimationPlayer = $Visual/AnimationPlayer


func _ready() -> void:
	animation_player.play("Idle")


func accepts(kind: Carryable.Kind) -> bool:
	return kind == Carryable.Kind.TREASURE


func receive(item: Carryable, _crew: Array[Pikmin]) -> bool:
	if not accepts(item.kind):
		return false
	# just collecting it for now. scoring or saving can be added here later.
	animation_player.play("CaptureTreasure")
	animation_player.queue("Idle")
	return true
