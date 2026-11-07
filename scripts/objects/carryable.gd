class_name Carryable
extends CharacterBody3D

enum Kind { FOOD, TREASURE }

@export var kind: Kind = Kind.FOOD
@export_range(1, 30) var required_carriers: int = 1
@export_range(1, 30) var max_carriers: int = 2
# food value is separate from weight so both are easy to balance.
@export_range(0, 50) var seed_yield: int = 3
@export var carry_radius: float = 0.65
@export var carry_speed: float = 1.5

# each entry is a reserved spot. null means another pikmin can take it.
var workers: Array[PikminCarrying] = []
var delivering: bool = false


func _ready() -> void:
	max_carriers = maxi(required_carriers, max_carriers)
	workers.resize(max_carriers)
	$CarryCount.text = "0 / %d" % required_carriers


func _physics_process(delta: float) -> void:
	var crew := get_crew()
	$CarryCount.text = "%d / %d" % [crew.size(), required_carriers]
	# reset first so losing a carrier stops the object on this frame.
	velocity.x = 0.0
	velocity.z = 0.0
	if crew.size() >= required_carriers:
		if update_delivery(crew):
			return
	# only the visual lifts. the body stays on the floor for movement.
	var lift := 0.18 if Vector2(velocity.x, velocity.z).length() > 0.0 else 0.0
	$Visuals.position.y = move_toward($Visuals.position.y, lift, delta * 2.0)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()


func update_delivery(crew: Array[Pikmin]) -> bool:
	var destination := find_destination()
	if destination == null:
		return false
	var marker: Node3D = destination.get_node("CollectionPoint")
	var direction := marker.global_position - global_position
	var height_difference := absf(direction.y)
	direction.y = 0.0
	var radius: float = destination.get("collection_radius")
	if direction.length() <= radius and height_difference < 0.75:
		deliver(destination, crew)
		return true
	# just going straight there for now. movement can add pathfinding here.
	# keeping rotation fixed also keeps everyone's carrying spot steady.
	direction = direction.normalized()
	velocity.x = direction.x * carry_speed
	velocity.z = direction.z * carry_speed
	return false


func has_space() -> bool:
	return not delivering and not is_queued_for_deletion() and workers.has(null)


func reserve(worker: PikminCarrying) -> int:
	if not has_space():
		return -1
	var index := workers.find(null)
	workers[index] = worker
	return index


func release(worker: PikminCarrying) -> void:
	var index := workers.find(worker)
	if index >= 0:
		# don't remove the entry, or everyone after it changes spots.
		workers[index] = null


func get_slot_offset(index: int) -> Vector3:
	var angle := TAU * index / max_carriers
	return Vector3(cos(angle), 0.0, sin(angle)) * carry_radius


func get_slot_position(index: int) -> Vector3:
	return to_global(get_slot_offset(index))


func get_crew() -> Array[Pikmin]:
	var crew: Array[Pikmin] = []
	for index in range(workers.size()):
		var worker := workers[index]
		if not is_instance_valid(worker):
			workers[index] = null
		elif worker.pikmin.is_queued_for_deletion():
			workers[index] = null
		elif worker.pikmin.state == Pikmin.State.CARRYING:
			# approaching a reserved spot doesn't count towards the weight yet.
			crew.append(worker.pikmin)
	return crew


func find_destination() -> Node3D:
	var closest: Node3D = null
	var best_distance := INF
	for point in get_tree().get_nodes_in_group("delivery_points"):
		# onion and ship share these two small methods, not a manager.
		if not point.call("accepts", kind):
			continue
		var marker: Node3D = point.get_node("CollectionPoint")
		var distance := global_position.distance_squared_to(marker.global_position)
		if distance < best_distance:
			best_distance = distance
			closest = point
	return closest


func deliver(destination: Node3D, crew: Array[Pikmin]) -> void:
	delivering = true
	if not destination.call("receive", self, crew):
		delivering = false
		return
	# cancel changes workers, so loop over a copy.
	# detach everyone before deleting the object they're parented to.
	for worker in workers.duplicate():
		if is_instance_valid(worker):
			worker.cancel()
	queue_free()


func get_aim_point() -> Vector3:
	return global_position
