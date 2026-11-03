class_name Enemy
extends CharacterBody3D

enum State { IDLE, CHASE }

@export var move_speed: float = 1.8
@export var detection_range: float = 5.0
@export var stop_distance: float = 1.25

var state: State = State.IDLE

@onready var animation_player: AnimationPlayer = $Model/Visual/AnimationPlayer


func _ready() -> void:
	animation_player.play("Idle")


func _physics_process(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		var direction := player.global_position - global_position
		direction.y = 0.0
		if direction.length() < detection_range and direction.length() > stop_distance:
			state = State.CHASE
			direction = direction.normalized()
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 5.0, 1.0))
		else:
			state = State.IDLE
	var animation := "Walk" if state == State.CHASE else "Idle"
	if animation_player.current_animation != animation:
		animation_player.play(animation, 0.1)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
