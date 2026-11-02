extends CharacterBody3D

@export var move_speed: float = 6.0
@export var stick_look_speed: float = 2.5
@export var mouse_sensitivity: float = 0.003

var squad: Array[Pikmin] = []

@onready var camera_pivot: Node3D = $CameraPivot
@onready var olimar: Node3D = $Olimar
@onready var animation_player: AnimationPlayer = $Olimar/AnimationPlayer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	animation_player.play("Idle")
	recruit_starting_squad.call_deferred()


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

	if Input.is_action_just_pressed("dismiss"):
		dismiss_squad()

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


func recruit_starting_squad() -> void:
	for pikmin in get_tree().get_nodes_in_group("pikmin"):
		add_to_squad(pikmin)


func add_to_squad(pikmin: Pikmin) -> void:
	if squad.has(pikmin) or pikmin.state != Pikmin.State.IDLE:
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
