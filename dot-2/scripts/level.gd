class_name Level
extends Node2D

signal level_completed
signal player_fell

@export_group("Level Boundaries")
@export var camera_limit_left: int = 0
@export var camera_limit_top: int = -200
@export var camera_limit_right: int = 2800
@export var camera_limit_bottom: int = 720
@export var fall_limit_y: float = 760.0

@onready var player: Player = $Player
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var finish_area: Area2D = $FinishArea
@onready var fall_zone: Area2D = $FallZone

var enemies: Array[Enemy] = []
var is_completed: bool = false
var managed_by_game_manager: bool = false
var _standalone_ui: CanvasLayer = null
var _standalone_status_label: Label = null


func _ready() -> void:
	_configure_window_size()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player:
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.set_camera_limits(
			camera_limit_left,
			camera_limit_top,
			camera_limit_right,
			camera_limit_bottom
		)
		if spawn_point:
			player.reset_at_position(spawn_point.global_position)

	if finish_area:
		finish_area.body_entered.connect(_on_finish_area_body_entered)

	if fall_zone:
		fall_zone.body_entered.connect(_on_fall_zone_body_entered)

	_register_enemies()
	call_deferred("_register_enemies")
	call_deferred("_setup_standalone_fallback_if_needed")


func _register_enemies() -> void:
	enemies.clear()
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy and is_instance_valid(node):
			var enemy_node: Enemy = node as Enemy
			var is_duplicate_pos: bool = false
			for existing: Enemy in enemies:
				if is_instance_valid(existing) and existing != enemy_node:
					if existing.spawn_position.distance_to(enemy_node.spawn_position) < 8.0:
						is_duplicate_pos = true
						break
			if is_duplicate_pos and enemy_node.get_parent() != self:
				enemy_node.queue_free()
				continue
			enemy_node.process_mode = Node.PROCESS_MODE_PAUSABLE
			if not enemy_node.player_collided.is_connected(_on_enemy_player_collided):
				enemy_node.player_collided.connect(_on_enemy_player_collided)
			if not enemies.has(enemy_node):
				enemies.append(enemy_node)


func _setup_standalone_fallback_if_needed() -> void:
	if managed_by_game_manager:
		return
	_standalone_ui = CanvasLayer.new()
	_standalone_ui.layer = 10
	add_child(_standalone_ui)

	_standalone_status_label = Label.new()
	_standalone_status_label.anchor_left = 0.5
	_standalone_status_label.anchor_top = 0.35
	_standalone_status_label.anchor_right = 0.5
	_standalone_status_label.anchor_bottom = 0.35
	_standalone_status_label.offset_left = -260.0
	_standalone_status_label.offset_top = -60.0
	_standalone_status_label.offset_right = 260.0
	_standalone_status_label.offset_bottom = 60.0
	_standalone_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_standalone_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_standalone_status_label.add_theme_font_size_override("font_size", 28)
	_standalone_status_label.add_theme_color_override("font_color", Color(0.1, 0.12, 0.16, 1.0))
	_standalone_status_label.visible = false
	_standalone_ui.add_child(_standalone_status_label)


func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	if player and not is_completed:
		if player.global_position.y > fall_limit_y:
			_handle_player_fall()


func _unhandled_input(event: InputEvent) -> void:
	if managed_by_game_manager:
		return
	if event.is_action_pressed("restart"):
		get_tree().paused = false
		restart_level()
	elif event.is_action_pressed("pause") and not is_completed:
		get_tree().paused = not get_tree().paused
		if _standalone_status_label:
			_standalone_status_label.text = "PAUSED\nPress ESC to Resume or R to Restart"
			_standalone_status_label.visible = get_tree().paused


func _on_finish_area_body_entered(body: Node2D) -> void:
	if is_completed:
		return
	if body == player or body is Player:
		is_completed = true
		if player:
			player.set_victory_state()
		if not managed_by_game_manager and _standalone_status_label:
			_standalone_status_label.text = "LEVEL COMPLETE!\nPress R to Restart"
			_standalone_status_label.visible = true
		level_completed.emit()


func _on_fall_zone_body_entered(body: Node2D) -> void:
	if body == player or body is Player:
		_handle_player_fall()


func _on_enemy_player_collided() -> void:
	if not is_completed:
		restart_level()


func _handle_player_fall() -> void:
	player_fell.emit()
	restart_level()


func restart_level() -> void:
	is_completed = false
	if _standalone_status_label:
		_standalone_status_label.visible = false
	if player and spawn_point:
		player.reset_at_position(spawn_point.global_position)
	_register_enemies()
	for enemy_node: Enemy in enemies:
		if is_instance_valid(enemy_node):
			enemy_node.reset_enemy()


func _configure_window_size() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var root_window: Window = get_window()
	if root_window:
		root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var screen_size: Vector2i = DisplayServer.screen_get_usable_rect().size
		var target_size := Vector2i(
			maxi(1600, int(screen_size.x * 0.85)),
			maxi(900, int(screen_size.y * 0.85))
		)
		DisplayServer.window_set_size(target_size)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
