extends PanelContainer

## AppWindow
## Reusable window chrome for all application windows in GHOST

# Signals
signal closed
signal focused

# Exported properties
@export var title: String = "app":
	set(value):
		title = value
		if is_inside_tree():
			_update_title()

@export var min_size: Vector2 = Vector2(320, 240)

# Internal state
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_start_pos: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO

# Node references
@onready var _title_label: Label = %TitleLabel
@onready var _title_bar: HBoxContainer = %TitleBar
@onready var _close_button: Button = %CloseButton
@onready var _minimise_button: Button = %MinimiseButton
@onready var _resize_handle: Control = %ResizeHandle


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	_close_button.pressed.connect(_on_close)
	_minimise_button.pressed.connect(_on_minimise)
	_title_bar.gui_input.connect(_on_titlebar_input)
	_resize_handle.gui_input.connect(_on_resize_input)
	
	_update_title()


func _update_title() -> void:
	if _title_label:
		_title_label.text = title


func _on_close() -> void:
	closed.emit()
	queue_free()


func _on_minimise() -> void:
	visible = false


func _on_titlebar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = get_global_mouse_position() - global_position
			focused.emit()
			_bring_to_front()
	
	if event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_screen()


func _on_resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if _resizing:
			_resize_start_pos = get_global_mouse_position()
			_resize_start_size = size
	
	if event is InputEventMouseMotion and _resizing:
		var new_size: Vector2 = _resize_start_size + (get_global_mouse_position() - _resize_start_pos)
		size = new_size.clamp(min_size, Vector2(9999, 9999))


func _bring_to_front() -> void:
	var parent: Node = get_parent()
	if parent:
		parent.move_child(self, parent.get_child_count() - 1)


func _clamp_to_screen() -> void:
	var screen: Vector2 = get_viewport_rect().size
	global_position.x = clampf(global_position.x, 0.0, screen.x - size.x)
	global_position.y = clampf(global_position.y, 0.0, screen.y - size.y)
