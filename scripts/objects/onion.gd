extends Node3D

@export var collection_radius: float = 0.8
@export var supported_types: Array[Pikmin.Type] = [
	Pikmin.Type.RED, Pikmin.Type.YELLOW, Pikmin.Type.BLUE,
]

# scenes are shared; reproduction only needs to choose the color.
const PIKMIN_SCENES = {
	Pikmin.Type.RED: preload("res://scenes/red_pikmin.tscn"),
	Pikmin.Type.YELLOW: preload("res://scenes/yellow_pikmin.tscn"),
	Pikmin.Type.BLUE: preload("res://scenes/blue_pikmin.tscn"),
}

var spawn_index: int = 0

@onready var animation_player: AnimationPlayer = $Visual/AnimationPlayer


func _ready() -> void:
	animation_player.play("Idle")


func accepts(kind: Carryable.Kind) -> bool:
	return kind == Carryable.Kind.FOOD and not supported_types.is_empty()


func receive(item: Carryable, crew: Array[Pikmin]) -> bool:
	if not accepts(item.kind):
		return false
	produce_pikmin(choose_type(crew), item.seed_yield)
	animation_player.clear_queue()
	animation_player.play("ReceiveFood")
	animation_player.queue("SeedSpit")
	animation_player.queue("Idle")
	return true


func choose_type(crew: Array[Pikmin]) -> Pikmin.Type:
	var counts: Dictionary = {}
	for pikmin in crew:
		# colors this onion hasn't unlocked can't be produced yet.
		if supported_types.has(pikmin.pikmin_type):
			counts[pikmin.pikmin_type] = counts.get(pikmin.pikmin_type, 0) + 1
	var chosen_type := supported_types[0]
	var highest_count := 0
	# ties, or no supported carriers, use the inspector order for now.
	for candidate in supported_types:
		var count: int = counts.get(candidate, 0)
		if count > highest_count:
			highest_count = count
			chosen_type = candidate
	return chosen_type


func produce_pikmin(pikmin_type: Pikmin.Type, amount: int) -> void:
	for index in range(maxi(0, amount)):
		var pikmin: Pikmin = PIKMIN_SCENES[pikmin_type].instantiate()
		# spread each delivery around the onion instead of making one pile.
		var angle := spawn_index * 2.4
		var radius := 1.8 + 0.35 * (spawn_index % 3)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
		spawn_index += 1
		get_tree().current_scene.add_child(pikmin)
		pikmin.global_position = $CollectionPoint.global_position + offset + Vector3.UP * 0.1
		# ready to whistle for now. seed landing and plucking can go here later.
