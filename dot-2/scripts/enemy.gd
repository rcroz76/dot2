class_name Enemy
extends CharacterBody2D

signal player_collided

@export_group("Patrol Settings")
## Horizontal patrol speed in pixels per second.
@export var patrol_speed: float = 95.0
## Maximum horizontal distance from spawn point before turning around.
@export var patrol_range: float = 115.0
## Brief pause duration when turning around at patrol endpoints.
@export var turn_pause_duration: float = 0.4

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var ledge_ray: RayCast2D = $LedgeRay

var default_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
var spawn_position: Vector2 = Vector2.ZERO
var direction: float = 1.0
var pause_timer: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	spawn_position = global_position
	if hitbox and not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	if animated_sprite and animated_sprite.sprite_frames:
		animated_sprite.play("walk")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += default_gravity * delta
	else:
		velocity.y = 0.0

	if pause_timer > 0.0:
		pause_timer = maxf(0.0, pause_timer - delta)
		velocity.x = 0.0
		if animated_sprite and animated_sprite.sprite_frames.has_animation("angry"):
			if animated_sprite.animation != &"angry":
				animated_sprite.play("angry")
	else:
		# Check patrol distance bounds, wall collision, or platform ledge ahead
		var reached_bound: bool = (
			(direction > 0.0 and global_position.x >= spawn_position.x + patrol_range)
			or (direction < 0.0 and global_position.x <= spawn_position.x - patrol_range)
		)
		var reached_ledge: bool = is_on_floor() and ledge_ray != null and not ledge_ray.is_colliding()
		if reached_bound or is_on_wall() or reached_ledge:
			_reverse_direction()
		else:
			velocity.x = direction * patrol_speed
			if animated_sprite:
				animated_sprite.flip_h = direction < 0.0
				if animated_sprite.animation != &"walk":
					animated_sprite.play("walk")

	move_and_slide()

	if hitbox:
		for body: Node2D in hitbox.get_overlapping_bodies():
			if body is Player and body.global_position.distance_to(global_position) < 42.0:
				_trigger_player_hit(body as Player)
				return

	# Also check slide collisions in case the player runs or jumps into the enemy physics body
	for i: int in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		if col and col.get_collider() is Player:
			_trigger_player_hit(col.get_collider() as Player)
			break


func _reverse_direction() -> void:
	direction = -direction
	pause_timer = turn_pause_duration
	velocity.x = 0.0
	if ledge_ray:
		ledge_ray.position.x = absf(ledge_ray.position.x) * direction
	if animated_sprite:
		animated_sprite.flip_h = direction < 0.0
		if animated_sprite.sprite_frames.has_animation("angry"):
			animated_sprite.play("angry")


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player:
		_trigger_player_hit(body as Player)


func _trigger_player_hit(player_node: Player) -> void:
	player_collided.emit()
	# Also directly notify the active Level or GameManager so an Enemy placed anywhere in the scene tree always works
	if player_node and player_node.get_parent() is Level:
		var lvl: Level = player_node.get_parent() as Level
		if not lvl.is_completed:
			lvl.restart_level()
			return
	var root_node: Window = get_tree().root if get_tree() else null
	if root_node:
		for node: Node in root_node.find_children("*", "Level", true, false):
			if node is Level:
				var lvl: Level = node as Level
				if not lvl.is_completed:
					lvl.restart_level()
					return


func reset_enemy() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	direction = 1.0
	pause_timer = 0.0
	if ledge_ray:
		ledge_ray.position.x = absf(ledge_ray.position.x)
	if animated_sprite:
		animated_sprite.flip_h = false
		animated_sprite.play("walk")
