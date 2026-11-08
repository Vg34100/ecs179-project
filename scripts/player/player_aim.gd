class_name PlayerAim
extends Node

@export var aim_speed: float = 20.0
@export var aim_max_distance: float = 6.0
@export var aim_snap_distance: float = 2.0
@export var aim_release_distance: float = 3.5
@export var throw_time: float = 0.9

var aim_target := Vector3.ZERO
var aim_enemy: Enemy
var aim_carryable: Carryable
var aim_offset := Vector3(0, 0, -3)
var trajectory_mesh := ImmediateMesh.new()

@onready var player: CharacterBody3D = get_parent()
@onready var aim_material: StandardMaterial3D = player.get_node("AimTarget").get_active_material(0)


func _ready() -> void:
	player.get_node("Trajectory").mesh = trajectory_mesh


func update_aim(direction: Vector3, delta: float) -> void:
	# The left stick steers a cursor offset around Olimar. Releasing holds it.
	# Camera rotation alone does not change this world-space offset.
	aim_offset += direction * aim_speed * delta
	aim_offset = aim_offset.limit_length(aim_max_distance)
	aim_target = player.global_position + aim_offset

	# Snap the circle onto the floor if there is ground at the target.
	var query := PhysicsRayQueryParameters3D.create(
		aim_target + Vector3.UP * 4.0, aim_target + Vector3.DOWN * 8.0, 5
	)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_target = hit["position"]
	# Keep a nearby enemy selected until the left-stick cursor moves away.
	if is_instance_valid(aim_enemy):
		if aim_enemy.state == Enemy.State.DEAD or not can_snap_to(aim_enemy, aim_release_distance):
			aim_enemy = null
	if not is_instance_valid(aim_enemy):
		aim_enemy = find_aim_enemy()
	if is_instance_valid(aim_enemy):
		# keep enemy priority so a nearby corpse doesn't steal a combat throw.
		aim_carryable = null
		aim_target = aim_enemy.get_aim_point()
		aim_material.albedo_color = Color(1, 0.35, 0.2)
	else:
		update_carryable_aim()
	player.get_node("AimTarget").global_position = aim_target + Vector3.UP * 0.03


func get_throw_origin() -> Vector3:
	# Keep the throw origin tied to the aiming direction, too.
	var direction := aim_target - player.global_position
	direction.y = 0.0
	var side := direction.normalized().cross(Vector3.UP)
	return player.global_position + Vector3.UP * 0.8 + side * 0.4


func get_throw_velocity() -> Vector3:
	# Pick a velocity that reaches the circle after throw_time seconds.
	# The extra physics step matches gravity being applied before movement.
	var physics_step := 1.0 / Engine.physics_ticks_per_second
	return (aim_target - get_throw_origin()) / throw_time - player.get_gravity() * (throw_time + physics_step) * 0.5


func update_trajectory() -> void:
	var origin := get_throw_origin()
	var launch_velocity := get_throw_velocity()
	var physics_step := 1.0 / Engine.physics_ticks_per_second
	trajectory_mesh.clear_surfaces()
	trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in range(33):
		var time := throw_time * point / 32.0
		var position_on_arc := origin + launch_velocity * time + player.get_gravity() * time * (time + physics_step) * 0.5
		trajectory_mesh.surface_add_vertex(position_on_arc)
	trajectory_mesh.surface_end()


func can_snap_to(enemy: Enemy, distance: float) -> bool:
	return can_snap_to_point(enemy.get_aim_point(), distance)


func can_snap_to_point(point: Vector3, distance: float) -> bool:
	var from_player := point - player.global_position
	from_player.y = 0.0
	var from_cursor := point - (player.global_position + aim_offset)
	from_cursor.y = 0.0
	return from_player.length() <= aim_max_distance and from_cursor.length() <= distance


func find_aim_enemy() -> Enemy:
	var closest: Enemy = null
	var best_distance := aim_snap_distance
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.state == Enemy.State.DEAD or not can_snap_to(enemy, aim_snap_distance):
			continue
		var offset: Vector3 = enemy.get_aim_point() - (player.global_position + aim_offset)
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			closest = enemy
	return closest


func update_carryable_aim() -> void:
	if is_instance_valid(aim_carryable):
		if not aim_carryable.has_space() or not can_snap_to_point(aim_carryable.get_aim_point(), aim_release_distance):
			aim_carryable = null
	if not is_instance_valid(aim_carryable):
		aim_carryable = find_aim_carryable()
	if is_instance_valid(aim_carryable):
		aim_target = aim_carryable.get_aim_point()
		aim_material.albedo_color = Color(0.4, 1.0, 0.5)
	else:
		aim_material.albedo_color = Color(1, 0.8, 0.2)


func find_aim_carryable() -> Carryable:
	var closest: Carryable = null
	var best_distance := aim_snap_distance
	for node in get_tree().get_nodes_in_group("carryables"):
		var item := node as Carryable
		# no point selecting an object that can't take another worker.
		if not item.has_space() or not can_snap_to_point(item.get_aim_point(), aim_snap_distance):
			continue
		var offset := item.get_aim_point() - (player.global_position + aim_offset)
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			closest = item
	return closest
