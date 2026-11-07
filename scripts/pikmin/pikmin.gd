class_name Pikmin
extends CharacterBody3D

enum Type { RED, YELLOW, BLUE }

# just the color for now. each type uses the same movement and combat.
@export var pikmin_type: Type = Type.RED

enum State { IDLE, FOLLOWING, THROWN, ATTACKING, LATCHED, MOVING_TO_CARRY, CARRYING }

@export var move_speed: float = 8.0
@export var acceleration: float = 24.0
@export var start_distance: float = 0.9
@export var stop_distance: float = 0.3
@export var reaction_delay: float = 0.15

@export var attack_damage: int = 5
@export var attack_interval: float = 0.8
@export var attack_range: float = 1.2
@export var guidance_speed_limit: float = 14.0

var throw_target: Enemy
var flight_time_left: float = 0.0
var attack_target: Enemy
var attack_timer: float = 0.0
var latch_allowed: bool = true
var follow_target: Node3D
var follow_offset := Vector3.ZERO
var state: State = State.IDLE
var is_catching_up: bool = false
var follow_timer: float = 0.0

@onready var carrying: PikminCarrying = $Carrying
@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $Model/Visual/AnimationPlayer


func _ready() -> void:
	animation_player.play("Idle")
	animation_player.get_animation("Attack").loop_mode = Animation.LOOP_LINEAR
	animation_player.get_animation("Carry").loop_mode = Animation.LOOP_LINEAR


func _physics_process(delta: float) -> void:
	carrying.update(delta)
	if state == State.CARRYING:
		update_animation()
		return

	if state == State.LATCHED:
		if is_instance_valid(attack_target) and attack_target.state != Enemy.State.DEAD:
			attack(delta)
			update_animation()
		else:
			detach_from_enemy()
		return

	if state != State.THROWN:
		var desired_velocity := Vector3.ZERO
		if state == State.FOLLOWING:
			if is_instance_valid(follow_target):
				desired_velocity = get_follow_velocity(delta)
			else:
				stop_following()

		if state == State.ATTACKING:
			desired_velocity = get_attack_velocity(delta)
		if state == State.MOVING_TO_CARRY:
			desired_velocity = carrying.get_velocity()

		velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)
		if desired_velocity.length_squared() > 0.01:
			var facing := atan2(-desired_velocity.x, -desired_velocity.z)
			model.rotation.y = lerp_angle(model.rotation.y, facing, minf(10.0 * delta, 1.0))

	if state == State.THROWN:
		update_throw_guidance(delta)

	if state == State.THROWN or not is_on_floor():
		velocity += get_gravity() * delta
	var was_falling := velocity.y < 0.0
	move_and_slide()
	if state == State.THROWN and was_falling:
		for index in range(get_slide_collision_count()):
			var collision := get_slide_collision(index)
			var enemy := collision.get_collider() as Enemy
			if enemy != null and enemy.state != Enemy.State.DEAD:
				if collision.get_normal().y > 0.5:
					enemy.receive_landing(self, collision.get_position(), latch_allowed)
				elif latch_allowed:
					start_attacking(enemy)
				break
	if state == State.THROWN and is_on_floor():
		var enemy := find_nearby_enemy() if latch_allowed else null
		if enemy != null:
			start_attacking(enemy)
		else:
			stop_following()
	update_animation()


func get_follow_velocity(delta: float) -> Vector3:
	var direction := follow_target.global_position + follow_offset - global_position
	direction.y = 0.0
	var distance := direction.length()

	# Wait for a real gap before chasing; stop at a smaller distance.
	# Having two distances keeps tiny target changes from restarting movement.
	if not is_catching_up:
		if distance > start_distance:
			follow_timer += delta
		else:
			follow_timer = 0.0
		if follow_timer >= reaction_delay:
			is_catching_up = true
	elif distance <= stop_distance:
		is_catching_up = false
		follow_timer = 0.0

	if not is_catching_up:
		return Vector3.ZERO

	# Slow down on approach rather than running full speed into the slot.
	var speed := minf(move_speed, distance * 4.0)
	return direction.normalized() * speed


func follow(target: Node3D, offset: Vector3) -> void:
	carrying.cancel()
	if state in [State.ATTACKING, State.LATCHED]:
		detach_from_enemy()
	if follow_target != target or state != State.FOLLOWING:
		is_catching_up = false
		follow_timer = 0.0
	follow_target = target
	follow_offset = offset
	state = State.FOLLOWING


func stop_following() -> void:
	carrying.cancel()
	follow_target = null
	state = State.IDLE
	collision_mask = 1
	is_catching_up = false
	follow_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func update_animation() -> void:
	if state == State.THROWN:
		return

	var horizontal_velocity := Vector2(get_real_velocity().x, get_real_velocity().z)
	var animation := "Walk" if horizontal_velocity.length() > 0.15 else "Idle"
	if state == State.CARRYING:
		animation = "Carry"
	if state == State.LATCHED or (state == State.ATTACKING and animation == "Idle"):
		animation = "Attack"
	if animation_player.current_animation != animation:
		animation_player.play(animation, 0.1, 4.0 if animation == "Walk" else 1.0)


func launch(throw_velocity: Vector3, allow_latch: bool = true) -> void:
	carrying.cancel()
	detach_from_enemy()
	latch_allowed = allow_latch
	collision_mask = 5
	follow_target = null
	state = State.THROWN
	is_catching_up = false
	follow_timer = 0.0
	velocity = throw_velocity
	model.rotation.y = atan2(-velocity.x, -velocity.z)
	animation_player.play("Throw", 0.1)


func find_nearby_enemy() -> Enemy:
	var closest: Enemy = null
	var best_distance: float = 1.8
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.state == Enemy.State.DEAD:
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			closest = enemy
	return closest


func start_attacking(enemy: Enemy) -> void:
	carrying.cancel()
	detach_from_enemy()
	follow_target = null
	attack_target = enemy
	attack_timer = 0.0
	state = State.ATTACKING
	collision_mask = 1


func get_attack_velocity(delta: float) -> Vector3:
	if not is_instance_valid(attack_target) or attack_target.state == Enemy.State.DEAD:
		stop_following()
		return Vector3.ZERO
	var direction := attack_target.global_position - global_position
	direction.y = 0.0
	if direction.length() > attack_range:
		return direction.normalized() * minf(move_speed, direction.length() * 3.0)
	if is_on_floor():
		attack(delta)
	return Vector3.ZERO


func attack(delta: float) -> void:
	attack_timer += delta
	if attack_timer >= attack_interval:
		attack_timer -= attack_interval
		attack_target.take_damage(attack_damage)


func attach_to_enemy(enemy: Enemy, slot: Node3D) -> void:
	carrying.cancel()
	attack_target = enemy
	follow_target = null
	attack_timer = 0.0
	state = State.LATCHED
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	reparent(slot, true)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	model.rotation = Vector3.ZERO
	animation_player.play("Attack", 0.1)


func detach_from_enemy() -> void:
	throw_target = null
	flight_time_left = 0.0
	if state == State.LATCHED:
		reparent(get_tree().current_scene, true)
		rotation = Vector3.ZERO
		scale = Vector3.ONE
	attack_target = null
	state = State.IDLE
	collision_layer = 2
	collision_mask = 1


func can_be_bitten() -> bool:
	return not is_queued_for_deletion() and state in [
		State.IDLE, State.FOLLOWING, State.ATTACKING,
		State.MOVING_TO_CARRY, State.CARRYING,
	]


func get_bitten() -> void:
	carrying.cancel()
	detach_from_enemy()
	queue_free()


func guide_to(enemy: Enemy, flight_time: float) -> void:
	throw_target = enemy
	flight_time_left = flight_time


func update_throw_guidance(delta: float) -> void:
	if not is_instance_valid(throw_target) or throw_target.state == Enemy.State.DEAD:
		throw_target = null
		return

	# Keep aiming at the original enemy even if Olimar selects another one.
	var destination := throw_target.get_aim_point()
	var target_velocity := throw_target.get_real_velocity()
	var remaining := maxf(flight_time_left, 0.1)
	var correction := (destination - global_position) / remaining
	var horizontal := Vector2(correction.x + target_velocity.x, correction.z + target_velocity.z)
	horizontal = horizontal.limit_length(guidance_speed_limit)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	# Adjust the arc only during the planned flight. Then let gravity finish
	# the landing, while horizontal guidance keeps up with the moving body.
	if flight_time_left > 0.0:
		var time := maxf(flight_time_left, delta)
		var vertical := (destination.y - global_position.y) / time - get_gravity().y * (time + delta) * 0.5
		velocity.y = clampf(vertical, -12.0, 12.0)
		flight_time_left = maxf(0.0, flight_time_left - delta)
	if horizontal.length_squared() > 0.01:
		model.rotation.y = atan2(-velocity.x, -velocity.z)
