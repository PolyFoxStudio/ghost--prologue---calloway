extends Node

## ScriptManager
## Message queue and event system for GHOST narrative

# Signals
signal message_queued(message: Dictionary)
signal world_event_fired(event_name: String)


func queue_message(msg: Dictionary) -> void:
	if msg.has("delay") and msg["delay"] > 0.0:
		var timer: SceneTreeTimer = get_tree().create_timer(msg["delay"])
		timer.timeout.connect(_send_message.bind(msg))
	else:
		_send_message(msg)


func _send_message(msg: Dictionary) -> void:
	# Check trigger condition if present
	if msg.has("trigger"):
		if not _evaluate_trigger(msg["trigger"]):
			return
	
	# Set any flags specified in the message
	if msg.has("flags_set"):
		for flag_name: String in msg["flags_set"]:
			var flag_value: bool = msg["flags_set"][flag_name]
			GameState.set_flag(flag_name, flag_value)
	
	# Emit the message
	message_queued.emit(msg)


func fire_event(event_name: String) -> void:
	world_event_fired.emit(event_name)


func _evaluate_trigger(condition: String) -> bool:
	return GameState.get(condition) == true
