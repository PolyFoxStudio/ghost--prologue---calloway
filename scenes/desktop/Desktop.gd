extends Control

## Desktop
## Main scene of GHOST — manages desktop background, app icons, windows, and UI

# Preload app scenes (commented out until scenes exist)
# const TERMINAL_SCENE = preload("res://scenes/apps/terminal/Terminal.tscn")
# const CIPHERLINK_SCENE = preload("res://scenes/apps/cipherlink/CipherLink.tscn")
# const FILES_SCENE = preload("res://scenes/apps/files/FileBrowser.tscn")
# const NOTEPAD_SCENE = preload("res://scenes/apps/notepad/Notepad.tscn")

# Node references
@onready var _window_layer: Control = $WindowLayer
@onready var _right_click_menu: PopupMenu = $RightClickMenu
@onready var _objectives_board: PanelContainer = $ObjectivesBoard

# Open window tracking
var _open_windows: Dictionary = {}


func _ready() -> void:
	# Connect global signals
	GameState.stage_advanced.connect(_on_stage_advanced)
	ScriptManager.world_event_fired.connect(_on_world_event)
	
	# Connect desktop icon inputs
	$DesktopIcons/TerminalIcon.gui_input.connect(_on_icon_input.bind("terminal"))
	$DesktopIcons/CipherLinkIcon.gui_input.connect(_on_icon_input.bind("cipherlink"))
	$DesktopIcons/FilesIcon.gui_input.connect(_on_icon_input.bind("files"))
	$DesktopIcons/NotepadIcon.gui_input.connect(_on_icon_input.bind("notepad"))


func open_app(app_name: String) -> void:
	# If window already open, bring to front
	if app_name in _open_windows:
		var window: Control = _open_windows[app_name]
		var parent: Node = window.get_parent()
		if parent:
			parent.move_child(window, parent.get_child_count() - 1)
		return
	
	# Match app name to scene (placeholder for now)
	match app_name:
		"terminal":
			print("open_app: terminal")
		"cipherlink":
			print("open_app: cipherlink")
		"files":
			print("open_app: files")
		"notepad":
			print("open_app: notepad")
		_:
			print("open_app: unknown app " + app_name)
	
	# When scenes are uncommented, instantiate here:
	# var window_scene: PackedScene = null
	# match app_name:
	#     "terminal": window_scene = TERMINAL_SCENE
	#     "cipherlink": window_scene = CIPHERLINK_SCENE
	#     "files": window_scene = FILES_SCENE
	#     "notepad": window_scene = NOTEPAD_SCENE
	# 
	# if window_scene:
	#     var window: Control = window_scene.instantiate()
	#     _window_layer.add_child(window)
	#     _open_windows[app_name] = window
	#     window.closed.connect(_on_window_closed.bind(app_name))
	#     _position_new_window(window)


func _on_window_closed(app_name: String) -> void:
	_open_windows.erase(app_name)


func _position_new_window(window: Control) -> void:
	var offset: Vector2 = Vector2(24, 24) * _open_windows.size()
	window.position = Vector2(100, 80) + offset


func _on_stage_advanced(new_stage: int) -> void:
	_objectives_board.refresh()


func _on_world_event(event_name: String) -> void:
	match event_name:
		"calloway_aware":
			print("World event: calloway_aware")
		"alarm_fired":
			print("World event: alarm_fired")
		"epilogue_begin":
			print("World event: epilogue_begin")
		_:
			print("World event: " + event_name)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_desktop_right_click(event.global_position)
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_objectives_board.toggle()
		get_viewport().set_input_as_handled()


func _show_desktop_right_click(pos: Vector2) -> void:
	_right_click_menu.clear()
	_right_click_menu.add_item("Properties", 0)
	
	if not _right_click_menu.id_pressed.is_connected(_on_right_click_item):
		_right_click_menu.id_pressed.connect(_on_right_click_item)
	
	_right_click_menu.position = pos
	_right_click_menu.popup()


func _on_right_click_item(id: int) -> void:
	if id == 0:
		print("Properties clicked — wallpaper panel not yet implemented")


func _on_icon_input(event: InputEvent, app_name: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		open_app(app_name)
		GameState.record_activity()
