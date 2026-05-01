extends PanelContainer

## ObjectivesBoard
## Displays current active objectives in a floating panel

const STAGE_OBJECTIVES: Dictionary = {
	0: [],
	1: ["READ THE BRIEF"],
	2: ["ESTABLISH ACCESS"],
	3: ["LOCATE ARCHIVE"],
	4: ["EXTRACT FILES"],
	5: ["WIPE ARCHIVE", "CLEAR LOGS"],
	6: [],
}

@onready var _list: VBoxContainer = $VBoxContainer/ObjectiveList
@onready var _header: Label = $VBoxContainer/Header


func _ready() -> void:
	GameState.stage_advanced.connect(_on_stage_advanced)
	refresh()


func toggle() -> void:
	visible = !visible


func refresh() -> void:
	# Clear existing entries
	for child in _list.get_children():
		child.queue_free()
	
	# Get current stage and objectives
	var current_stage: int = GameState.objective_stage
	var objectives: Array = STAGE_OBJECTIVES.get(current_stage, [])
	
	# Stage 6 = all complete
	if current_stage == 6:
		_add_entry("all objectives complete")
		return
	
	# No objectives
	if objectives.is_empty():
		_add_entry("[no active objectives]")
		return
	
	# Add each objective
	for objective in objectives:
		_add_entry(objective)


func _add_entry(text: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	
	var bullet: Label = Label.new()
	bullet.text = "·"
	
	var objective_label: Label = Label.new()
	objective_label.text = text
	
	row.add_child(bullet)
	row.add_child(objective_label)
	
	_list.add_child(row)


func _on_stage_advanced(new_stage: int) -> void:
	_fade_out_then_refresh()


func _fade_out_then_refresh() -> void:
	# Fade out
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	
	# Refresh content
	refresh()
	
	# Fade in
	var tween_in: Tween = create_tween()
	tween_in.tween_property(self, "modulate:a", 1.0, 0.3)
