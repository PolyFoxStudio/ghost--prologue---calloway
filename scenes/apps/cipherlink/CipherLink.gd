extends HSplitContainer

signal first_opened

var _first_open: bool = true
var _send_failed_mode: bool = false

@onready var _messages: VBoxContainer = $MessagePanel/MessageScroll/MessageContainer
@onready var _scroll: ScrollContainer = $MessagePanel/MessageScroll
@onready var _input: LineEdit = $MessagePanel/InputRow/InputField
@onready var _response_options: HBoxContainer = $MessagePanel/ResponseOptions
@onready var _presence: ColorRect = $ContactsSidebar/VBoxContainer/ContactList/CipherContact/PresenceIndicator

func _ready() -> void:
	_presence.color = Color("#3a8a3a")
	_input.text_submitted.connect(_on_input_submitted)
	ScriptManager.message_queued.connect(_on_message_received)
	_input.focus_mode = Control.FOCUS_CLICK
	
	if _first_open:
		_first_open = false
		_on_first_open()
	
	# Grab focus on the input field after everything is set up
	_input.call_deferred("grab_focus")

func _on_first_open() -> void:
	first_opened.emit()
	_deliver_message({
		"from": "cipher",
		"body": "alright. job's live. routing's clean — I checked it\ntwice, came back cold both times.\n\ntarget is jordan calloway. corporate analyst,\nvantage dynamics. mid-level. access to the internal\ndocument archive. they've been doing something with\nit — moving files around, compressing batches, the\npattern looks like staged extraction.\n\nclient thinks calloway is building a package for\na competitor.\n\nyour job: get in ahead of them. pull whatever\nthey've staged, wipe the trail. standard IP\nprotection work.\n\nI've got calloway's home network mapped.\nbrief's in your downloads.",
		"timestamp": "23:08"
	})
	GameState.advance_stage(1)
	ScriptManager.fire_event("brief_delivered")

func _on_message_received(msg: Dictionary) -> void:
	_deliver_message(msg)
	AudioManager.play_message_receive()

func _deliver_message(msg: Dictionary) -> void:
	var container: VBoxContainer = VBoxContainer.new()
	
	# Timestamp
	var timestamp_label: Label = Label.new()
	timestamp_label.text = msg.get("timestamp", _get_current_time())
	timestamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timestamp_label.add_theme_color_override("font_color", Color("#4a4a4a"))
	timestamp_label.add_theme_font_size_override("font_size", 10)
	
	# Message body
	var body_label: Label = Label.new()
	body_label.text = msg["body"]
	body_label.add_theme_color_override("font_color", Color("#d4d4d4"))
	body_label.add_theme_font_size_override("font_size", 13)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	container.add_child(timestamp_label)
	container.add_child(body_label)
	_messages.add_child(container)
	
	# Read receipt
	var receipt_label: Label = Label.new()
	receipt_label.text = "[READ]"
	receipt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	receipt_label.add_theme_color_override("font_color", Color("#4a4a4a"))
	receipt_label.add_theme_font_size_override("font_size", 10)
	container.add_child(receipt_label)
	
	await get_tree().process_frame
	_scroll_to_bottom()
	GameState.record_activity()

func show_response_options(options: Array) -> void:
	for child in _response_options.get_children():
		child.queue_free()
	
	for option in options:
		var button: Button = Button.new()
		button.text = option
		button.pressed.connect(_on_response_selected.bind(option))
		_response_options.add_child(button)
	
	_response_options.visible = true

func _on_response_selected(text: String) -> void:
	_send_ghost_message(text)
	_response_options.visible = false
	for child in _response_options.get_children():
		child.queue_free()

func _on_input_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	
	if _send_failed_mode:
		_handle_send_failed()
		_input.clear()
		return
	
	_send_ghost_message(text)
	_input.clear()
	GameState.record_activity()

func _send_ghost_message(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", Color("#d4d4d4"))
	label.add_theme_font_size_override("font_size", 13)
	_messages.add_child(label)
	
	ScriptManager.fire_event("ghost_sent_message:" + text)
	
	await get_tree().process_frame
	_scroll_to_bottom()

func activate_send_failed_mode() -> void:
	_send_failed_mode = true
	_presence.color = Color("#4a4a4a")

func _handle_send_failed() -> void:
	await get_tree().create_timer(0.3).timeout
	
	var label: Label = Label.new()
	label.text = "no active route"
	label.add_theme_color_override("font_color", Color("#4a4a4a"))
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_messages.add_child(label)
	_scroll_to_bottom()
	
	await get_tree().create_timer(2.0).timeout
	label.queue_free()

func _scroll_to_bottom() -> void:
	_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value

func _get_current_time() -> String:
	return Time.get_time_string_from_system().substr(0, 5)
