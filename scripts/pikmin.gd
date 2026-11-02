class_name Pikmin
extends CharacterBody3D

enum State { IDLE, FOLLOWING }

@export var move_speed: float = 8.0
@export var acceleration: float = 24.0
@export var start_distance: float = 0.9
@export var stop_distance: float = 0.3
@export var reaction_delay: float = 0.15

var follow_target: Node3D
var follow_offset := Vector3.ZERO
var state: State = State.IDLE
var is_catching_up: bool = false
var follow_timer: float = 0.0

@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer


func _ready() -> void:
	animation_player.play("Idle")


func _physics_process(delta: float) -> void:
	var desired_velocity := Vector3.ZERO
	if state == State.FOLLOWING:
		if is_instance_valid(follow_target):
			desired_velocity = get_follow_velocity(delta)
		else:
			stop_following()
	velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)
	if desired_velocity.length_squared() > 0.01:
		var facing := atan2(-desired_velocity.x, -desired_velocity.z)
		model.rotation.y = lerp_angle(model.rotation.y, facing, minf(10.0 * delta, 1.0))
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
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
	if follow_target != target or state != State.FOLLOWING:
		is_catching_up = false
		follow_timer = 0.0
	follow_target = target
	follow_offset = offset
	state = State.FOLLOWING


func stop_following() -> void:
	follow_target = null
	state = State.IDLE
	is_catching_up = false
	follow_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func update_animation() -> void:
	var horizontal_velocity := Vector2(get_real_velocity().x, get_real_velocity().z)
	var animation := "Walk" if horizontal_velocity.length() > 0.15 else "Idle"
	if animation_player.current_animation != animation:
		animation_player.play(animation, 0.1, 4.0 if animation == "Walk" else 1.0)
