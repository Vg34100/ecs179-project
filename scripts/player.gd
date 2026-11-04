extends CharacterBody3D

@export var move_speed: float = 6.0
@export var stick_look_speed: float = 2.5
@export var mouse_sensitivity: float = 0.003
@export var aim_speed: float = 20.0
@export var aim_max_distance: float = 6.0
@export var aim_snap_distance: float = 2.0
@export var aim_release_distance: float = 3.5
@export var throw_time: float = 0.9
@export var whistle_max_radius: float = 6.5
@export var whistle_growth_speed: float = 8.0

var squad: Array[Pikmin] = []
var aim_target := Vector3.ZERO
var aim_enemy: Enemy
var aim_offset := Vector3(0, 0, -3)
var whistle_radius: float = 0.0
var trajectory_mesh := ImmediateMesh.new()

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var olimar: Node3D = $Olimar
@onready var animation_player: AnimationPlayer = $Olimar/AnimationPlayer
@onready var aim_material: StandardMaterial3D = $AimTarget.get_active_material(0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	animation_player.play("Idle")
	$Trajectory.mesh = trajectory_mesh


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative * mouse_sensitivity)


func _physics_process(delta: float) -> void:
	# Remove deleted members if another gameplay system frees a Pikmin.
	var previous_squad_size := squad.size()
	for index in range(squad.size() - 1, -1, -1):
		if not is_instance_valid(squad[index]):
			squad.remove_at(index)
	if squad.size() != previous_squad_size:
		update_squad_positions()

	var look_input := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	rotate_camera(look_input * stick_look_speed * delta)

	# Move along the ground relative to the camera's horizontal direction.
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(move_input.x, 0.0, move_input.y)
	direction = direction.rotated(Vector3.UP, camera_pivot.rotation.y)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	if direction.length_squared() > 0.0:
		olimar.rotation.y = atan2(-direction.x, -direction.z)

	var horizontal_velocity := Vector2(get_real_velocity().x, get_real_velocity().z)
	var animation := "Walk" if horizontal_velocity.length() > 0.01 else "Idle"
	if animation_player.current_animation != animation:
		animation_player.play(animation, 0.15, 4.0 if animation == "Walk" else 1.0)

	# Aim first so both actions use the circle shown in this frame.
	update_aim(direction, delta)
	update_trajectory()
	if Input.is_action_just_pressed("dismiss"):
		dismiss_squad()
	if Input.is_action_just_pressed("throw"):
		throw_pikmin()
	update_whistle(delta)


func rotate_camera(amount: Vector2) -> void:
	camera_pivot.rotation.y -= amount.x
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x - amount.y, deg_to_rad(-70.0), deg_to_rad(-7.0)
	)


func update_aim(direction: Vector3, delta: float) -> void:
	# The left stick steers a cursor offset around Olimar. Releasing holds it.
	# Camera rotation alone does not change this world-space offset.
	aim_offset += direction * aim_speed * delta
	aim_offset = aim_offset.limit_length(aim_max_distance)
	aim_target = global_position + aim_offset

	# Snap the circle onto the floor if there is ground at the target.
	var query := PhysicsRayQueryParameters3D.create(
		aim_target + Vector3.UP * 4.0, aim_target + Vector3.DOWN * 8.0, 5
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_target = hit["position"]
	# Keep a nearby enemy selected until the left-stick cursor moves away.
	if is_instance_valid(aim_enemy):
		if aim_enemy.state == Enemy.State.DEAD or not can_snap_to(aim_enemy, aim_release_distance):
			aim_enemy = null
	if not is_instance_valid(aim_enemy):
		aim_enemy = find_aim_enemy()
	if is_instance_valid(aim_enemy):
		aim_target = aim_enemy.get_aim_point()
		aim_material.albedo_color = Color(1, 0.35, 0.2)
	else:
		aim_material.albedo_color = Color(1, 0.8, 0.2)
	$AimTarget.global_position = aim_target + Vector3.UP * 0.03


func get_throw_origin() -> Vector3:
	# Keep the throw origin tied to the aiming direction, too.
	var direction := aim_target - global_position
	direction.y = 0.0
	var side := direction.normalized().cross(Vector3.UP)
	return global_position + Vector3.UP * 0.8 + side * 0.4


func get_throw_velocity() -> Vector3:
	# Pick a velocity that reaches the circle after throw_time seconds.
	# The extra physics step matches gravity being applied before movement.
	var physics_step := 1.0 / Engine.physics_ticks_per_second
	return (aim_target - get_throw_origin()) / throw_time - get_gravity() * (throw_time + physics_step) * 0.5


func update_trajectory() -> void:
	var origin := get_throw_origin()
	var launch_velocity := get_throw_velocity()
	var physics_step := 1.0 / Engine.physics_ticks_per_second
	trajectory_mesh.clear_surfaces()
	trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in range(33):
		var time := throw_time * point / 32.0
		var position_on_arc := origin + launch_velocity * time + get_gravity() * time * (time + physics_step) * 0.5
		trajectory_mesh.surface_add_vertex(position_on_arc)
	trajectory_mesh.surface_end()


func add_to_squad(pikmin: Pikmin) -> void:
	if squad.has(pikmin) or pikmin.state not in [Pikmin.State.IDLE, Pikmin.State.ATTACKING, Pikmin.State.LATCHED]:
		return
	squad.append(pikmin)
	update_squad_positions()


func remove_from_squad(pikmin: Pikmin) -> void:
	if not squad.has(pikmin):
		return
	squad.erase(pikmin)
	if is_instance_valid(pikmin):
		pikmin.stop_following()
	update_squad_positions()


func dismiss_squad() -> void:
	for pikmin in squad:
		if is_instance_valid(pikmin):
			pikmin.stop_following()
	squad.clear()
	update_squad_positions()


func update_squad_positions() -> void:
	# Three columns in a small grid. Offsets stay on the world axes for now.
	for index in range(squad.size()):
		var column := index % 3
		var row := floori(index / 3.0)
		var offset := Vector3((column - 1) * 0.65, 0.0, 0.9 + row * 0.65)
		squad[index].follow(self, offset)
	$HUD/SquadCount.text = "Squad: %d" % squad.size()


func update_whistle(delta: float) -> void:
	if not Input.is_action_pressed("whistle"):
		whistle_radius = 0.0
		$WhistleRadius.hide()
		return

	# Grow from the aiming circle. The maximum always reaches back to Olimar.
	var to_player := global_position - aim_target
	to_player.y = 0.0
	var maximum := maxf(whistle_max_radius, to_player.length() + 0.5)
	whistle_radius = move_toward(whistle_radius, maximum, whistle_growth_speed * delta)
	$WhistleRadius.global_position = aim_target + Vector3.UP * 0.04
	$WhistleRadius.scale = Vector3(whistle_radius, 1.0, whistle_radius)
	$WhistleRadius.show()

	for pikmin in get_tree().get_nodes_in_group("pikmin"):
		var offset: Vector3 = pikmin.global_position - aim_target
		if absf(offset.y) > 2.5:
			continue
		offset.y = 0.0
		if offset.length() <= whistle_radius:
			add_to_squad(pikmin)


func throw_pikmin() -> void:
	if squad.is_empty():
		return

	var pikmin := squad[0]
	remove_from_squad(pikmin)
	var direction := aim_target - global_position
	olimar.rotation.y = atan2(-direction.x, -direction.z)
	pikmin.global_position = get_throw_origin()
	pikmin.launch(get_throw_velocity())


func can_snap_to(enemy: Enemy, distance: float) -> bool:
	var point := enemy.get_aim_point()
	var from_player := point - global_position
	from_player.y = 0.0
	var from_cursor := point - (global_position + aim_offset)
	from_cursor.y = 0.0
	return from_player.length() <= aim_max_distance and from_cursor.length() <= distance


func find_aim_enemy() -> Enemy:
	var closest: Enemy = null
	var best_distance := aim_snap_distance
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.state == Enemy.State.DEAD or not can_snap_to(enemy, aim_snap_distance):
			continue
		var offset: Vector3 = enemy.get_aim_point() - (global_position + aim_offset)
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			closest = enemy
	return closest
