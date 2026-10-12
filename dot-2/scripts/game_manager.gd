class_name GameManager
extends Node2D

## Optional list of level scenes for multi-level progression.
@export var level_scenes: Array[PackedScene] = []

@onready var current_level: Level = $Level01
@onready var pause_overlay: Control = $UI/PauseOverlay
@onready var completion_overlay: Control = $UI/CompletionOverlay
@onready var resume_button: Button = $UI/PauseOverlay/Panel/VBoxContainer/ResumeButton
@onready var pause_restart_button: Button = $UI/PauseOverlay/Panel/VBoxContainer/RestartButton
@onready var play_again_button: Button = $UI/CompletionOverlay/Panel/VBoxContainer/PlayAgainButton

var is_level_complete: bool = false
var current_level_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if pause_overlay:
		pause_overlay.visible = false
	if completion_overlay:
		completion_overlay.visible = false

	if resume_button:
		resume_button.pressed.connect(toggle_pause)
	if pause_restart_button:
		pause_restart_button.pressed.connect(restart_current_level)
	if play_again_button:
		play_again_button.pressed.connect(restart_current_level)

	_bind_level(current_level)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		restart_current_level()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and not is_level_complete:
		toggle_pause()
		get_viewport().set_input_as_handled()


func _bind_level(level_node: Level) -> void:
	if not level_node:
		return
	level_node.managed_by_game_manager = true
	level_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	if not level_node.level_completed.is_connected(_on_level_completed):
		level_node.level_completed.connect(_on_level_completed)


func toggle_pause() -> void:
	if is_level_complete:
		return
	var new_pause_state: bool = not get_tree().paused
	get_tree().paused = new_pause_state
	if pause_overlay:
		pause_overlay.visible = new_pause_state
	if new_pause_state and resume_button:
		resume_button.grab_focus()


func restart_current_level() -> void:
	get_tree().paused = false
	is_level_complete = false
	if pause_overlay:
		pause_overlay.visible = false
	if completion_overlay:
		completion_overlay.visible = false
	if current_level:
		current_level.restart_level()


func load_level_by_index(index: int) -> void:
	if index < 0 or index >= level_scenes.size():
		restart_current_level()
		return
	if current_level:
		current_level.queue_free()
	current_level_index = index
	var next_instance: Node = level_scenes[index].instantiate()
	add_child(next_instance)
	move_child(next_instance, 0)
	current_level = next_instance as Level
	_bind_level(current_level)
	restart_current_level()


func _on_level_completed() -> void:
	is_level_complete = true
	get_tree().paused = false
	if pause_overlay:
		pause_overlay.visible = false
	if completion_overlay:
		completion_overlay.visible = true
	if play_again_button:
		play_again_button.grab_focus()
