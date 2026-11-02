extends CharacterBody3D

@export var move_speed: float = 6.0
@export var stick_look_speed: float = 2.5
@export var mouse_sensitivity: float = 0.003

@onready var camera_pivot: Node3D = $CameraPivot
@onready var olimar: Node3D = $Olimar
@onready var animation_player: AnimationPlayer = $Olimar/AnimationPlayer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	animation_player.play("Idle")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative * mouse_sensitivity)


func _physics_process(delta: float) -> void:
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

	# Face the direction we want to move, without turning the camera.
	if direction.length_squared() > 0.0:
		olimar.rotation.y = atan2(-direction.x, -direction.z)

	# Use actual movement so walking into a wall does not keep playing Walk.
	var horizontal_velocity := Vector2(get_real_velocity().x, get_real_velocity().z)
	var animation := "Walk" if horizontal_velocity.length() > 0.01 else "Idle"
	if animation_player.current_animation != animation:
		animation_player.play(animation, 0.15, 4.0 if animation == "Walk" else 1.0)


func rotate_camera(amount: Vector2) -> void:
	camera_pivot.rotation.y -= amount.x
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x - amount.y, deg_to_rad(-65.0), deg_to_rad(15.0)
	)
