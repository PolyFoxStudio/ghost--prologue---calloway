extends Node

## AudioManager
## Audio playback and mixing control for GHOST

@export var message_receive: AudioStream
@export var transfer_complete: AudioStream

@onready var _sfx_ui: AudioStreamPlayer = $SFX_UI
@onready var _sfx_terminal: AudioStreamPlayer = $SFX_Terminal
@onready var _ambient: AudioStreamPlayer = $Ambient


func play_message_receive() -> void:
	_sfx_ui.stream = message_receive
	_sfx_ui.play()


func play_transfer_complete() -> void:
	_sfx_terminal.stream = transfer_complete
	_sfx_terminal.play()


func fade_in_ambient(duration: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index("Ambient")
	AudioServer.set_bus_volume_db(bus_idx, -80.0)
	
	var tween: Tween = create_tween()
	tween.tween_method(
		func(volume: float) -> void:
			AudioServer.set_bus_volume_db(bus_idx, volume),
		-80.0,
		-20.0,
		duration
	)
