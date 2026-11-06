class_name Enemy
extends CharacterBody3D

enum State { IDLE, CHASE, BITE, HURT, SHAKE, DEAD }

@export var move_speed: float = 1.8
@export var detection_range: float = 5.0
@export var bite_range: float = 1.25
@export var max_health: int = 120
@export var landing_damage: int = 0
@export var allows_latching: bool = true
@export var shake_interval: float = 3.0

var state: State = State.IDLE
var target: Node3D
var health: int
var state_time: float = 0.0
var latch_time: float = 0.0
var hurt_cooldown: float = 0.0
var action_done: bool = false
var back_slots: Array[Node3D] = []
var skeleton: Skeleton3D
var bite_bone: int = -1

@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $Model/Visual/AnimationPlayer


func _ready() -> void:
	health = max_health
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	bite_bone = skeleton.find_bone("anchor_bite")
	if allows_latching:
		make_back_slots()
	animation_player.animation_finished.connect(_on_animation_finished)
	update_health_label()
	enter_state(State.IDLE)


func _physics_process(delta: float) -> void:
	state_time += delta
	hurt_cooldown = maxf(0.0, hurt_cooldown - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	if state == State.DEAD:
		return

	if not get_latched_pikmin().is_empty():
		latch_time += delta
		if latch_time >= shake_interval and state not in [State.SHAKE, State.BITE]:
			enter_state(State.SHAKE)
	else:
		latch_time = 0.0

	match state:
		State.IDLE, State.CHASE:
			target = find_target()
			if target == null:
				enter_state(State.IDLE)
			else:
				var direction := target.global_position - global_position
				direction.y = 0.0
				if direction.length() > 0.05:
					rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 5.0, 1.0))
				if direction.length() <= bite_range:
					if target.has_method("get_bitten"):
						enter_state(State.BITE)
					else:
						enter_state(State.IDLE)
				else:
					enter_state(State.CHASE)
					direction = direction.normalized()
					velocity.x = direction.x * move_speed
					velocity.z = direction.z * move_speed
		State.BITE:
			if not is_instance_valid(target) or global_position.distance_to(target.global_position) > bite_range + 0.5:
				enter_state(State.CHASE)
			elif not action_done and state_time >= 0.55:
				action_done = true
				bite()
		State.SHAKE:
			if not action_done and state_time >= 0.45:
				action_done = true
				shake_off()

	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()


func find_target() -> Node3D:
	var closest: Node3D = null
	var best_distance := detection_range
	for pikmin in get_tree().get_nodes_in_group("pikmin"):
		if not pikmin.can_be_bitten():
			continue
		var distance := global_position.distance_to(pikmin.global_position)
		if distance < best_distance:
			best_distance = distance
			closest = pikmin
	# Olimar can lure enemies, but leader health is outside this prototype.
	if closest == null:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player != null and global_position.distance_to(player.global_position) < detection_range:
			closest = player
	return closest


func enter_state(next_state: State) -> void:
	if state == next_state and animation_player.is_playing():
		return
	state = next_state
	state_time = 0.0
	action_done = false
	match state:
		State.IDLE: animation_player.play("Idle", 0.1)
		State.CHASE: animation_player.play("Walk", 0.1)
		State.BITE: animation_player.play("Bite", 0.1)
		State.HURT: animation_player.play("Hurt", 0.1)
		State.SHAKE: animation_player.play("ShakeOff", 0.1)
		State.DEAD:
			collision_layer = 0
			for pikmin in get_latched_pikmin():
				pikmin.detach_from_enemy()
				pikmin.launch(Vector3.UP * 2.0, false)
			animation_player.play("Death", 0.1)


func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health = maxi(0, health - amount)
	update_health_label()
	if health == 0:
		enter_state(State.DEAD)
	elif state in [State.IDLE, State.CHASE] and hurt_cooldown <= 0.0:
		hurt_cooldown = 2.0
		enter_state(State.HURT)


func receive_landing(pikmin: Node3D, hit_position: Vector3, allow_latch: bool) -> void:
	if state == State.DEAD:
		return
	if landing_damage > 0:
		take_damage(landing_damage)
	if state == State.DEAD:
		pikmin.launch(Vector3.UP * 2.0, false)
		return
	# Only the rear/top of a large Bulborb is a valid back landing.
	if allows_latching and allow_latch and to_local(hit_position).z > -0.25:
		for slot in back_slots:
			if slot.get_child_count() == 0:
				pikmin.attach_to_enemy(self, slot)
				return
	pikmin.start_attacking(self)


func make_back_slots() -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "anchor_latch_back"
	skeleton.add_child(attachment)
	for index in range(6):
		var slot := Marker3D.new()
		slot.name = "BackSlot%d" % index
		# Imported skeleton units become tenths of a world unit in this model.
		slot.position = Vector3((index % 3 - 1) * 3.5, 0.3, (floori(index / 3.0) - 0.5) * 4.0)
		attachment.add_child(slot)
		back_slots.append(slot)


func get_latched_pikmin() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for slot in back_slots:
		for child in slot.get_children():
			result.append(child)
	return result


func shake_off() -> void:
	for pikmin in get_latched_pikmin():
		var direction: Vector3 = pikmin.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() < 0.01:
			direction = global_basis.x
		pikmin.detach_from_enemy()
		pikmin.launch(direction.normalized() * 3.0 + Vector3.UP * 4.0, false)
	latch_time = 0.0


func bite() -> void:
	var mouth := skeleton.global_transform * skeleton.get_bone_global_pose(bite_bone).origin
	var victim: Node3D = null
	var best_distance: float = 0.85
	for pikmin in get_tree().get_nodes_in_group("pikmin"):
		if not pikmin.can_be_bitten():
			continue
		var distance := mouth.distance_to(pikmin.global_position + Vector3.UP * 0.2)
		if distance < best_distance:
			best_distance = distance
			victim = pikmin
	if victim != null:
		victim.get_bitten()


func update_health_label() -> void:
	$Health.text = "%d / %d" % [health, max_health]


func _on_animation_finished(animation: StringName) -> void:
	if state == State.DEAD and animation == &"Death":
		queue_free()
	elif animation in [&"Bite", &"Hurt", &"ShakeOff"]:
		enter_state(State.IDLE)


func get_aim_point() -> Vector3:
	if allows_latching and not back_slots.is_empty():
		for slot in back_slots:
			if slot.get_child_count() == 0:
				return slot.global_position
		return back_slots[0].global_position
	var body: CollisionShape3D = $CollisionShape3D
	return body.global_position + Vector3.UP * body.shape.size.y * 0.5
