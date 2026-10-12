class_name Player
extends CharacterBody2D

@export_group("Horizontal Movement")
## Maximum horizontal running speed in pixels per second.
@export var move_speed: float = 280.0
## Ground horizontal acceleration in pixels per second squared.
@export var acceleration: float = 1800.0
## Ground horizontal friction/deceleration in pixels per second squared.
@export var deceleration: float = 2200.0
## Airborne horizontal acceleration in pixels per second squared.
@export var air_acceleration: float = 1300.0
## Airborne horizontal deceleration in pixels per second squared.
@export var air_deceleration: float = 900.0

@export_group("Jump & Gravity")
## Upward velocity applied when jumping (negative is up in 2D).
@export var jump_velocity: float = -520.0
## Multiplier applied to upward velocity when jump key is released early.
@export var jump_cut_multiplier: float = 0.5
## Multiplier on project default gravity while rising.
@export var gravity_scale: float = 1.0
## Multiplier on gravity while falling for crisp platforming feel.
@export var fall_gravity_multiplier: float = 1.35
## Terminal downward velocity in pixels per second.
@export var max_fall_speed: float = 980.0

@export_group("Platformer Assists")
## Time in seconds the player can still jump after walking off a ledge.
@export var coyote_time: float = 0.12
## Time in seconds a jump press is remembered before touching the floor.
@export var jump_buffer_time: float = 0.12

@export_group("Idle Personality")
## Seconds of standing still before the character starts looking around.
@export var look_around_delay: float = 1.6
## Seconds of standing still before the character looks bored and sighs.
@export var bored_delay: float = 4.4
## Seconds of standing still before the character gets visibly frustrated.
@export var frustrated_delay: float = 7.2

const BASE_SPRITE_POS := Vector2(-0.5, -0.5)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D

var default_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var landing_timer: float = 0.0
var landing_duration: float = 0.42
var last_airborne_vel_y: float = 0.0
var last_impact_speed: float = 0.0
var idle_timer: float = 0.0
var was_on_floor: bool = false
var controls_enabled: bool = true
var last_smoke_effect: Node2D = null


func _ready() -> void:
	_ensure_input_actions()
	if animated_sprite and animated_sprite.sprite_frames:
		animated_sprite.play("idle")


func _physics_process(delta: float) -> void:
	var on_floor_now: bool = is_on_floor()

	# Detect landing transition from air to floor
	if on_floor_now and not was_on_floor:
		last_impact_speed = maxf(240.0, last_airborne_vel_y)
		landing_duration = clampf(remap(last_impact_speed, 220.0, 880.0, 0.36, 0.50), 0.36, 0.50)
		landing_timer = landing_duration
		idle_timer = 0.0
		if animated_sprite and animated_sprite.sprite_frames.has_animation("land"):
			animated_sprite.play("land")
		_spawn_landing_smoke(last_impact_speed)

	# Update Coyote Time
	if on_floor_now:
		coyote_timer = coyote_time
		last_airborne_vel_y = 0.0
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)

	# Update Jump Buffer and Landing Timer
	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	landing_timer = maxf(0.0, landing_timer - delta)

	# Apply Gravity
	if not on_floor_now:
		var current_gravity: float = default_gravity * gravity_scale
		if velocity.y > 0.0:
			current_gravity *= fall_gravity_multiplier
		velocity.y = minf(velocity.y + current_gravity * delta, max_fall_speed)
		last_airborne_vel_y = maxf(last_airborne_vel_y, velocity.y)

	if controls_enabled:
		_handle_jump_input()
		_handle_horizontal_movement(delta, on_floor_now)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)

	was_on_floor = on_floor_now
	move_and_slide()

	_update_animation(delta)


func _handle_jump_input() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	# Execute buffered jump if on floor or within coyote time window
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		landing_timer = 0.0
		idle_timer = 0.0
		_reset_sprite_transform()
		if animated_sprite and animated_sprite.sprite_frames.has_animation("jump"):
			animated_sprite.play("jump")

	# Variable jump height when releasing jump button early while ascending
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier


func _handle_horizontal_movement(delta: float, on_floor_now: bool) -> void:
	var direction: float = Input.get_axis("move_left", "move_right")

	if direction != 0.0:
		idle_timer = 0.0
		var accel: float = acceleration if on_floor_now else air_acceleration
		velocity.x = move_toward(velocity.x, direction * move_speed, accel * delta)
		if animated_sprite:
			animated_sprite.flip_h = direction < 0.0
	else:
		var decel: float = deceleration if on_floor_now else air_deceleration
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)


func _update_animation(delta: float) -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return

	if not controls_enabled:
		_reset_sprite_transform()
		if is_on_floor() and animated_sprite.sprite_frames.has_animation("happy"):
			if animated_sprite.animation != &"happy":
				animated_sprite.play("happy")
		return

	if not is_on_floor():
		idle_timer = 0.0
		_reset_sprite_transform()
		if velocity.y < 0.0:
			if animated_sprite.animation != &"jump":
				animated_sprite.play("jump")
		else:
			if animated_sprite.animation != &"fall":
				animated_sprite.play("fall")
		return

	# Play landing effort expression and squash/strain recovery when touching the ground
	if landing_timer > 0.0:
		idle_timer = 0.0
		if animated_sprite.animation != &"land":
			animated_sprite.play("land")
		_apply_landing_effort_transform()
		return

	if absf(velocity.x) > 12.0:
		idle_timer = 0.0
		_reset_sprite_transform()
		if animated_sprite.animation != &"run":
			animated_sprite.play("run")
		return

	# Stationary on the floor: advance idle personality progression
	idle_timer += delta
	_update_idle_personality()


func _apply_landing_effort_transform() -> void:
	if not animated_sprite or landing_duration <= 0.0:
		return
	var progress: float = 1.0 - (landing_timer / landing_duration)
	var intensity: float = clampf(remap(last_impact_speed, 220.0, 880.0, 0.75, 1.25), 0.75, 1.25)
	# Heavy initial impact squash followed by a strained push-up recovery
	var squash_curve: float = sin(clampf(progress * 1.35, 0.0, 1.0) * PI) * (1.0 - progress * 0.45)
	var strain_jitter: float = sin(progress * 38.0) * 0.8 * (1.0 - progress) * intensity
	var scale_x: float = 1.0 + 0.24 * squash_curve * intensity
	var scale_y: float = 1.0 - 0.22 * squash_curve * intensity
	animated_sprite.scale = Vector2(scale_x, scale_y)
	animated_sprite.position = BASE_SPRITE_POS + Vector2(strain_jitter, (1.0 - scale_y) * 19.5)


func _spawn_landing_smoke(impact_speed: float) -> void:
	var parent_node: Node = get_parent()
	if not parent_node:
		return

	var smoke_root := Node2D.new()
	smoke_root.name = "LandingSmoke"
	smoke_root.global_position = global_position + Vector2(0.0, 19.5)
	smoke_root.z_index = 5
	parent_node.add_child(smoke_root)
	last_smoke_effect = smoke_root

	var scale_factor: float = clampf(remap(impact_speed, 220.0, 880.0, 0.85, 1.45), 0.85, 1.45)
	var tween: Tween = smoke_root.create_tween().set_parallel(true)

	# Spawn billowing ground smoke puffs spreading left and right along the floor
	var puff_configs: Array[Dictionary] = [
		{"side": -1.0, "start_x": -8.0, "end_x": -38.0, "end_y": -6.0, "size": 12.0, "delay": 0.0, "dark": true},
		{"side": 1.0, "start_x": 8.0, "end_x": 38.0, "end_y": -6.0, "size": 12.0, "delay": 0.0, "dark": true},
		{"side": -1.0, "start_x": -14.0, "end_x": -52.0, "end_y": -12.0, "size": 10.0, "delay": 0.02, "dark": false},
		{"side": 1.0, "start_x": 14.0, "end_x": 52.0, "end_y": -12.0, "size": 10.0, "delay": 0.02, "dark": false},
		{"side": -1.0, "start_x": -4.0, "end_x": -24.0, "end_y": -15.0, "size": 9.0, "delay": 0.03, "dark": false},
		{"side": 1.0, "start_x": 4.0, "end_x": 24.0, "end_y": -15.0, "size": 9.0, "delay": 0.03, "dark": false},
		{"side": -1.0, "start_x": -18.0, "end_x": -64.0, "end_y": -4.0, "size": 7.0, "delay": 0.04, "dark": true},
		{"side": 1.0, "start_x": 18.0, "end_x": 64.0, "end_y": -4.0, "size": 7.0, "delay": 0.04, "dark": true},
	]

	for cfg: Dictionary in puff_configs:
		var puff := Node2D.new()
		var base_size: float = float(cfg["size"]) * scale_factor
		var rect := ColorRect.new()
		rect.size = Vector2(base_size, base_size)
		rect.position = -rect.size * 0.5
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bool(cfg["dark"]):
			rect.color = Color(0.38, 0.42, 0.49, 0.88)
		else:
			rect.color = Color(0.56, 0.60, 0.67, 0.82)
		puff.add_child(rect)

		puff.position = Vector2(float(cfg["start_x"]), -2.0)
		puff.scale = Vector2(0.45, 0.45)
		smoke_root.add_child(puff)

		var target_pos := Vector2(
			float(cfg["end_x"]) * scale_factor,
			float(cfg["end_y"]) * scale_factor
		)
		var delay: float = float(cfg["delay"])
		var duration: float = 0.42

		tween.tween_property(puff, "position", target_pos, duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "scale", Vector2(1.35, 1.15), duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "rotation", float(cfg["side"]) * 0.45, duration).set_delay(delay)
		tween.tween_property(puff, "modulate:a", 0.0, duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Add visible effort sweat/strain droplets near the head on harder landings
	if impact_speed > 300.0:
		for side: float in [-1.0, 1.0]:
			var drop := ColorRect.new()
			drop.size = Vector2(4.0, 4.0)
			drop.position = Vector2(side * 18.0 - 2.0, -34.0)
			drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			drop.color = Color(0.22, 0.25, 0.30, 0.85)
			smoke_root.add_child(drop)
			var drop_target := Vector2(side * 30.0 - 2.0, -44.0)
			tween.tween_property(drop, "position", drop_target, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(drop, "modulate:a", 0.0, 0.28)

	tween.chain().tween_callback(smoke_root.queue_free)


func _update_idle_personality() -> void:
	var target_anim: StringName = &"idle"

	if idle_timer < look_around_delay:
		target_anim = &"idle"
		_reset_sprite_transform()
	else:
		# Cycle through Look Around -> Bored -> Frustrated after initial breathing idle
		var cycle_duration: float = 9.0
		var cycle_time: float = fmod(idle_timer - look_around_delay, cycle_duration)
		var look_span: float = maxf(1.5, bored_delay - look_around_delay)
		var bored_span: float = maxf(1.5, frustrated_delay - bored_delay)

		if cycle_time < look_span:
			target_anim = &"idle_look_around"
			_reset_sprite_transform()
		elif cycle_time < look_span + bored_span:
			target_anim = &"idle_bored"
			# Subtle heavy-sigh droop while anchored at the feet (bottom = +19.5)
			var sigh_wave: float = maxf(0.0, sin((cycle_time - look_span) * 2.6))
			var scale_y: float = 1.0 - 0.07 * sigh_wave
			var scale_x: float = 1.0 + 0.05 * sigh_wave
			animated_sprite.scale = Vector2(scale_x, scale_y)
			animated_sprite.position = BASE_SPRITE_POS + Vector2(0.0, (1.0 - scale_y) * 19.5)
		else:
			target_anim = &"idle_frustrated"
			# Frustrated trembling + occasional impatient stomp/hop
			var frust_time: float = cycle_time - (look_span + bored_span)
			var jitter_x: float = sin(frust_time * 42.0) * 1.4
			var stomp_wave: float = maxf(0.0, sin(frust_time * 7.5))
			var hop_y: float = -3.0 * pow(stomp_wave, 4.0)
			var squash: float = 0.06 * pow(stomp_wave, 2.0)
			animated_sprite.scale = Vector2(1.0 + squash, 1.0 - squash * 0.5)
			animated_sprite.position = BASE_SPRITE_POS + Vector2(jitter_x, hop_y)

	if animated_sprite.sprite_frames.has_animation(target_anim):
		if animated_sprite.animation != target_anim:
			animated_sprite.play(target_anim)
	elif animated_sprite.animation != &"idle":
		animated_sprite.play("idle")


func _reset_sprite_transform() -> void:
	if animated_sprite:
		animated_sprite.scale = Vector2.ONE
		animated_sprite.position = BASE_SPRITE_POS


func set_camera_limits(left: int, top: int, right: int, bottom: int) -> void:
	if camera:
		camera.limit_left = left
		camera.limit_top = top
		camera.limit_right = right
		camera.limit_bottom = bottom


func set_victory_state() -> void:
	controls_enabled = false
	velocity.x = 0.0
	_reset_sprite_transform()
	if animated_sprite and animated_sprite.sprite_frames.has_animation("happy"):
		animated_sprite.play("happy")


func reset_at_position(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	velocity = Vector2.ZERO
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	landing_timer = 0.0
	last_airborne_vel_y = 0.0
	last_impact_speed = 0.0
	idle_timer = 0.0
	was_on_floor = false
	controls_enabled = true
	_reset_sprite_transform()
	if animated_sprite:
		animated_sprite.flip_h = false
		animated_sprite.play("idle")
	if camera:
		camera.reset_smoothing()


func _ensure_input_actions() -> void:
	var default_bindings: Dictionary = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP],
		"restart": [KEY_R],
		"pause": [KEY_ESCAPE],
	}
	for action_name: String in default_bindings.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			for keycode: Key in default_bindings[action_name]:
				var ev := InputEventKey.new()
				ev.physical_keycode = keycode
				InputMap.action_add_event(action_name, ev)
