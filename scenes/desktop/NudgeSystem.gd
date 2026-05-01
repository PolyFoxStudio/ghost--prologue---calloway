extends Node

const IDLE_THRESHOLD := 240.0
const PROGRESS_WINDOW := 360.0
const NUDGE_COOLDOWN := 300.0
const MAX_NUDGES := 2
const ENDING_BEAT_THRESHOLD := 360.0

const NUDGES := {
	1: [
		"brief's in your downloads whenever you're ready.\ntake your time.",
		"just checking you got the file okay.\nsometimes that archive takes a second to appear.",
	],
	2: [
		"network file has everything you need for the endpoint.\nI'll feed you tokens when you're connecting.",
		"still here. just need to know when you're going in\nso I can have a token ready.",
	],
	3: [
		"archive path's in the brief if you need it.\ncalloway's credentials should get you straight there.",
		"you're on their network — the path in the brief\nshould be accessible under calloway's session.\nlet me know if you're hitting something unexpected.",
	],
	4: [
		"staging server's standing by whenever you're ready\nto start pulling. I'm watching the connection.",
		"calloway's still active on their machine.\nthe longer we're in here the more likely\nthey notice something. whenever you're ready.",
	],
	"5a": [
		"extraction's confirmed clean. wipe whenever you're set.",
		"we've got the files. calloway's still in there.\nprobably trying to work out what happened to the archive.",
	],
	"5b": [
		"wipe's done. just need the logs cleaned before we close out.",
		"the scrub script should handle everything.\nlet me know when you're out.",
	],
	"5_edge": [
		"looks like the session closed before the wipe ran.\nVPN's still available if you need to go back in.",
	],
	"ending": [
		"I'm here.\nno rush.",
	],
}

var _last_nudge_time: Dictionary = {}
var _nudge_counts: Dictionary = {}
var _check_interval: float = 30.0
var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _check_interval:
		return
	_elapsed = 0.0
	_check_nudge()


func _check_nudge() -> void:
	var idle: float = GameState.get_idle_seconds()
	var no_progress: float = GameState.get_seconds_since_stage_advance()
	
	if idle < IDLE_THRESHOLD:
		return
	if no_progress < PROGRESS_WINDOW:
		return
	
	var stage: int = GameState.objective_stage
	
	if stage == 6 and GameState.alarm_fired:
		if idle >= ENDING_BEAT_THRESHOLD:
			_maybe_fire_nudge("ending")
		return
	
	if GameState.logs_cleared and not GameState.wipe_complete:
		_maybe_fire_nudge("5_edge")
		return
	
	if stage == 5:
		if GameState.wipe_complete:
			_maybe_fire_nudge("5b")
		else:
			_maybe_fire_nudge("5a")
		return
	
	_maybe_fire_nudge(stage)


func _maybe_fire_nudge(stage_key: Variant) -> void:
	var count: int = _nudge_counts.get(stage_key, 0)
	if count >= MAX_NUDGES:
		return
	
	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = _last_nudge_time.get(stage_key, -9999.0)
	if count > 0 and (now - last) < NUDGE_COOLDOWN:
		return
	
	var nudge_list: Array = NUDGES.get(stage_key, [])
	if count >= nudge_list.size():
		return
	
	_last_nudge_time[stage_key] = now
	_nudge_counts[stage_key] = count + 1
	
	ScriptManager.queue_message({
		"from": "cipher",
		"body": nudge_list[count],
		"delay": 0.0
	})
