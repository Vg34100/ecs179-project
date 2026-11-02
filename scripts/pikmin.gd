class_name Pikmin
extends CharacterBody3D

enum State { IDLE }

var state: State = State.IDLE

@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer


func _ready() -> void:
	animation_player.play("Idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
