extends Node3D

@export var collection_radius: float = 0.8
@export var supported_types: Array[Pikmin.Type] = [
	Pikmin.Type.RED, Pikmin.Type.YELLOW, Pikmin.Type.BLUE,
]

@onready var animation_player: AnimationPlayer = $Visual/AnimationPlayer


func _ready() -> void:
	animation_player.play("Idle")


func accepts(kind: Carryable.Kind) -> bool:
	return kind == Carryable.Kind.FOOD and not supported_types.is_empty()


func receive(item: Carryable, _crew: Array[Pikmin]) -> bool:
	if not accepts(item.kind):
		return false
	animation_player.play("ReceiveFood")
	animation_player.queue("Idle")
	return true
