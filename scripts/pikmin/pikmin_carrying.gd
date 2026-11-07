class_name PikminCarrying
extends Node

@export var search_radius: float = 1.8
@export var arrival_distance: float = 0.2
@export var approach_timeout: float = 5.0

var target: Carryable
var slot: int = -1
var search_timer: float = 0.0
var approach_time: float = 0.0

@onready var pikmin: Pikmin = get_parent()


func update(delta: float) -> void:
	if pikmin.state in [Pikmin.State.MOVING_TO_CARRY, Pikmin.State.CARRYING]:
		if not is_instance_valid(target) or target.delivering:
			cancel()
			return
	if pikmin.state == Pikmin.State.MOVING_TO_CARRY:
		approach_time += delta
		# don't stay stuck on an unreachable spot forever.
		if approach_time >= approach_timeout:
			cancel()
			return
		var offset := target.get_slot_position(slot) - pikmin.global_position
		var height_difference := absf(offset.y)
		offset.y = 0.0
		if offset.length() <= arrival_distance and height_difference < 0.6:
			attach()
	elif pikmin.state == Pikmin.State.IDLE and pikmin.is_on_floor():
		# idle pikmin look occasionally. squad members keep following instead.
		search_timer -= delta
		if search_timer <= 0.0:
			search_timer = 0.25
			find_work()


func find_work() -> void:
	var closest: Carryable = null
	var best_distance := search_radius
	for node in get_tree().get_nodes_in_group("carryables"):
		var item := node as Carryable
		if not item.has_space():
			continue
		var offset := item.global_position - pikmin.global_position
		if absf(offset.y) > 1.0:
			continue
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			closest = item
	if closest == null:
		return
	var reserved_slot := closest.reserve(self)
	if reserved_slot < 0:
		return
	target = closest
	slot = reserved_slot
	approach_time = 0.0
	pikmin.follow_target = null
	pikmin.attack_target = null
	pikmin.state = Pikmin.State.MOVING_TO_CARRY


func get_velocity() -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	var direction := target.get_slot_position(slot) - pikmin.global_position
	direction.y = 0.0
	return direction.normalized() * minf(pikmin.move_speed, direction.length() * 4.0)


func attach() -> void:
	# move with the object so separate physics don't fight the group.
	# movement can replace this with proper carrier motion later.
	pikmin.reparent(target, true)
	pikmin.position = target.get_slot_offset(slot)
	pikmin.rotation = Vector3.ZERO
	pikmin.model.rotation.y = atan2(pikmin.position.x, pikmin.position.z)
	pikmin.velocity = Vector3.ZERO
	pikmin.collision_layer = 0
	pikmin.collision_mask = 0
	pikmin.state = Pikmin.State.CARRYING


func cancel() -> void:
	if is_instance_valid(target):
		if pikmin.get_parent() == target:
			pikmin.reparent(get_tree().current_scene, true)
			pikmin.rotation = Vector3.ZERO
			pikmin.scale = Vector3.ONE
		target.release(self)
	target = null
	slot = -1
	search_timer = 0.5
	if pikmin.state in [Pikmin.State.MOVING_TO_CARRY, Pikmin.State.CARRYING]:
		pikmin.state = Pikmin.State.IDLE
		pikmin.collision_layer = 2
		pikmin.collision_mask = 1
		pikmin.velocity = Vector3.ZERO
