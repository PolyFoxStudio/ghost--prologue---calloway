extends Node

## GameState
## Central state management for GHOST game progression

# Story progression flags
var ghost_read_readme: bool = false
var ghost_read_index: bool = false
var ghost_communicated_with_calloway: bool = false
var ghost_knows_mayas_name: bool = false
var ghost_has_decryption_key: bool = false
var calloway_offered_key: bool = false
var calloway_warned: bool = false
var ghost_stood_down: bool = false
var ghost_went_silent_alarm: bool = false
var ghost_rationalized: bool = false
var ghost_named_it: bool = false
var ghost_accepted_guilt: bool = false
var cipher_knows_truth: bool = false
var cipher_investigating: bool = false
var ghost_flagged_timing: bool = false
var client_investigation_flagged: bool = false
var ghost_went_silent_final: bool = false

# Session state flags
var vpn_established: bool = false
var archive_located: bool = false
var transfer_complete: bool = false
var wipe_complete: bool = false
var logs_cleared: bool = false
var calloway_aware: bool = false
var alarm_fired: bool = false
var epilogue_active: bool = false
var transfer_running: bool = false

# Progression tracking
var objective_stage: int = 0
var last_activity_time: float = 0.0
var last_stage_advance_time: float = 0.0
var transfer_progress: float = 0.0

# Signals
signal stage_advanced(new_stage: int)
signal flag_changed(flag_name: String, value: bool)


func _ready() -> void:
	last_activity_time = Time.get_ticks_msec()
	last_stage_advance_time = Time.get_ticks_msec()


func set_flag(flag_name: String, value: bool) -> void:
	set(flag_name, value)
	flag_changed.emit(flag_name, value)


func advance_stage(new_stage: int) -> void:
	if new_stage > objective_stage:
		objective_stage = new_stage
		last_stage_advance_time = Time.get_ticks_msec()
		stage_advanced.emit(new_stage)


func record_activity() -> void:
	last_activity_time = Time.get_ticks_msec()


func get_idle_seconds() -> float:
	return (Time.get_ticks_msec() - last_activity_time) / 1000.0


func get_seconds_since_stage_advance() -> float:
	return (Time.get_ticks_msec() - last_stage_advance_time) / 1000.0
