class_name PlayerSquad
extends Node

@export var whistle_max_radius: float = 6.5
@export var whistle_growth_speed: float = 8.0

var squad: Array[Pikmin] = []
var whistle_radius: float = 0.0

@onready var player: CharacterBody3D = get_parent()
@onready var aim: PlayerAim = $"../Aim"
@onready var olimar: Node3D = $"../Olimar"


func remove_deleted_members() -> void:
	# enemies can delete a pikmin without going through the squad first.
	var previous_size := squad.size()
	for index in range(squad.size() - 1, -1, -1):
		if not is_instance_valid(squad[index]):
			squad.remove_at(index)
	if squad.size() != previous_size:
		update_squad_positions()


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
		squad[index].follow(player, offset)
	player.get_node("HUD/SquadCount").text = "Squad: %d" % squad.size()


func update_whistle(delta: float) -> void:
	if not Input.is_action_pressed("whistle"):
		whistle_radius = 0.0
		player.get_node("WhistleRadius").hide()
		return

	# Grow from the aiming circle. The maximum always reaches back to Olimar.
	var to_player := player.global_position - aim.aim_target
	to_player.y = 0.0
	var maximum := maxf(whistle_max_radius, to_player.length() + 0.5)
	whistle_radius = move_toward(whistle_radius, maximum, whistle_growth_speed * delta)
	player.get_node("WhistleRadius").global_position = aim.aim_target + Vector3.UP * 0.04
	player.get_node("WhistleRadius").scale = Vector3(whistle_radius, 1.0, whistle_radius)
	player.get_node("WhistleRadius").show()

	for pikmin in get_tree().get_nodes_in_group("pikmin"):
		var offset: Vector3 = pikmin.global_position - aim.aim_target
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
	var direction := aim.aim_target - player.global_position
	olimar.rotation.y = atan2(-direction.x, -direction.z)
	pikmin.global_position = aim.get_throw_origin()
	pikmin.launch(aim.get_throw_velocity())
	if is_instance_valid(aim.aim_enemy):
		pikmin.guide_to(aim.aim_enemy, aim.throw_time)
