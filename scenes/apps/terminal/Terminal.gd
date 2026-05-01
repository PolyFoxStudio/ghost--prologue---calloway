class_name Terminal
extends VBoxContainer

const PROMPT_LOCAL := "ghost@local:~$"
const PROMPT_REMOTE := "jcalloway@vd-internal:~$"
const TRANSFER_DURATION := 480.0

var _vfs: VirtualFileSystem
var _current_prompt: String = PROMPT_LOCAL
var _history: Array[String] = []
var _history_index: int = -1
var _remote_session: bool = false
var _awaiting_mfa: bool = false
var _in_calloway_message_mode: bool = false
var _calloway_buffer: String = ""
var _calloway_exchange_count: int = 0
var _transfer_halfway_sent: bool = false

@onready var _output: VBoxContainer = $OutputScroll/OutputContainer
@onready var _input_field: LineEdit = $InputRow/InputField
@onready var _prompt_label: Label = $InputRow/PromptLabel
@onready var _scroll: ScrollContainer = $OutputScroll


func _ready() -> void:
	_vfs = VirtualFileSystem.new()
	_input_field.text_submitted.connect(_on_command_submitted)
	_input_field.grab_focus()
	GameState.record_activity()


func _input(event: InputEvent) -> void:
	GameState.record_activity()
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP:
				_cycle_history(-1)
			KEY_DOWN:
				_cycle_history(1)
			KEY_TAB:
				_attempt_tab_complete()
				get_viewport().set_input_as_handled()
			KEY_D:
				if event.ctrl_pressed and _in_calloway_message_mode:
					_send_calloway_message()
					get_viewport().set_input_as_handled()


func _on_command_submitted(text: String) -> void:
	var stripped_text: String = text.strip_edges()
	if stripped_text.is_empty():
		return
	
	if _awaiting_mfa:
		_handle_mfa_input(stripped_text)
		_input_field.clear()
		return
	
	if _in_calloway_message_mode:
		_calloway_buffer += stripped_text + "\n"
		_input_field.clear()
		return
	
	_print_line(_current_prompt + " " + stripped_text)
	_history.push_front(stripped_text)
	_history_index = -1
	_input_field.clear()
	_process_command(stripped_text)
	GameState.record_activity()
	
	await get_tree().process_frame
	_scroll_to_bottom()


func _process_command(cmd: String) -> void:
	var parts: PackedStringArray = cmd.split(" ", false)
	if parts.is_empty():
		return
	
	var base: String = parts[0]
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	
	match base:
		"ls":
			_cmd_ls(args)
		"cat":
			_cmd_cat(args)
		"cd":
			_cmd_cd(args)
		"tar":
			_cmd_tar(args)
		"openvpn":
			_cmd_openvpn(args)
		"ssh":
			_cmd_ssh(args)
		"exit", "logout":
			_cmd_exit()
		"rsync":
			_cmd_rsync(args)
		"shred":
			_cmd_shred(args)
		"write":
			_cmd_communicate(args)
		"wall":
			_cmd_communicate(args)
		"./scrub_logs.sh":
			_cmd_scrub_logs(args)
		"clear":
			_clear_output()
		"echo":
			if " | wall" in cmd:
				# Extract message between quotes
				var quote_start: int = cmd.find('"')
				var quote_end: int = -1
				if quote_start != -1:
					quote_end = cmd.find('"', quote_start + 1)
				if quote_start != -1 and quote_end != -1:
					var message: String = cmd.substr(quote_start + 1, quote_end - quote_start - 1)
					_cmd_communicate_direct(message)
				else:
					_print_line("echo: invalid syntax", "error")
			else:
				# Just echo the rest
				var echo_text: String = cmd.substr(5).strip_edges()
				_print_line(echo_text)
		_:
			_print_line(base + ": command not found", "error")


# ==================== COMMAND IMPLEMENTATIONS ====================

func _cmd_ls(args: Array[String]) -> void:
	var path: String = _vfs.current_path if args.is_empty() else args[0]
	var result: Variant = _vfs.list(path)
	
	if result == null:
		_print_line("ls: " + path + ": No such file or directory", "error")
		return
	
	if result == "PERMISSION_DENIED":
		_print_line("ls: " + path + ": Permission denied", "error")
		return
	
	if result == "FILE":
		_print_line("ls: " + path + ": Not a directory", "error")
		return
	
	for entry in result:
		_print_line(entry)


func _cmd_cat(args: Array[String]) -> void:
	if args.is_empty():
		_print_line("cat: missing operand", "error")
		return
	
	var path: String = args[0]
	var result: Variant = _vfs.read_file(path)
	
	if result == null:
		_print_line("cat: " + path + ": No such file or directory", "error")
		return
	
	if result == "PERMISSION_DENIED":
		_print_line("cat: " + path + ": Permission denied", "error")
		return
	
	if result == "IS_DIR":
		_print_line("cat: " + path + ": Is a directory", "error")
		return
	
	if result == "[EXECUTABLE]":
		_print_line("cat: " + path + ": Binary or executable file", "error")
		return
	
	_vfs.on_file_read(path)
	
	var lines: PackedStringArray = result.split("\n")
	for line in lines:
		_print_line(line)


func _cmd_cd(args: Array[String]) -> void:
	if args.is_empty():
		_vfs.current_path = "/home/ghost"
		_update_prompt()
		return
	
	var path: String = args[0]
	
	if path == "-":
		_print_line("cd: OLDPWD not set", "error")
		return
	
	var resolved: String = _vfs._resolve_path(path)
	var result: Variant = _vfs._navigate_to(resolved)
	
	if result == null:
		_print_line("cd: " + path + ": No such file or directory", "error")
		return
	
	if result == "PERMISSION_DENIED":
		_print_line("cd: " + path + ": Permission denied", "error")
		return
	
	if result == "FILE":
		_print_line("cd: " + path + ": Not a directory", "error")
		return
	
	_vfs.current_path = resolved
	_vfs.on_directory_entered(resolved)
	_update_prompt()


func _cmd_tar(args: Array[String]) -> void:
	var has_extract: bool = false
	var archive_file: String = ""
	var verbose: bool = false
	
	for arg in args:
		if arg.begins_with("-"):
			if "x" in arg:
				has_extract = true
			if "v" in arg:
				verbose = true
		elif arg.ends_with(".tar.gz"):
			archive_file = arg
	
	if not has_extract or archive_file.is_empty():
		_print_line("tar: missing archive operand", "error")
		return
	
	if not _vfs.file_exists("~/downloads/brief_calloway_vd.tar.gz"):
		_print_line("tar: " + archive_file + ": Cannot open: No such file or directory", "error")
		return
	
	if _vfs._brief_extracted:
		_print_line("tar: " + archive_file + ": Cannot open: No such file or directory", "error")
		return
	
	if verbose:
		_print_line("calloway_jordan_profile.txt")
		_print_line("vantage_dynamics_network.txt")
		_print_line("target_archive_map.txt")
		_print_line("objectives.txt")
		_print_line("calloway_jbc.pem")
	
	await get_tree().create_timer(0.8).timeout
	_vfs.populate_brief()
	
	if GameState.objective_stage < 2:
		GameState.advance_stage(2)


func _cmd_openvpn(args: Array[String]) -> void:
	var has_config: bool = false
	var has_remote: bool = false
	
	for i in args.size():
		if args[i] == "--config":
			has_config = true
		if args[i] == "--remote":
			has_remote = true
	
	if not has_config or not has_remote:
		_print_line("openvpn: missing required arguments", "error")
		return
	
	if GameState.vpn_established:
		_print_line("openvpn: tunnel already active", "error")
		return
	
	if not _vfs.file_exists("~/downloads/brief_calloway/calloway_jbc.pem"):
		_print_line("openvpn: calloway_jbc.pem: No such file", "error")
		return
	
	_print_line("Attempting connection to 203.0.113.44:1194...")
	await get_tree().create_timer(1.2).timeout
	_print_line("TLS handshake complete.", "success")
	await get_tree().create_timer(0.4).timeout
	_print_line("MFA token required:", "primary")
	
	_awaiting_mfa = true
	_input_field.placeholder_text = "token:"
	
	ScriptManager.queue_message({
		"from": "cipher",
		"body": "token: 847291 — in case you need it.\n18 seconds left.",
		"delay": 90.0,
		"trigger": "vpn_established"
	})


func _handle_mfa_input(token: String) -> void:
	_awaiting_mfa = false
	_input_field.placeholder_text = ""
	
	if token.strip_edges() == "847291":
		await get_tree().create_timer(0.6).timeout
		_print_line("Authentication successful.", "success")
		_print_line("Connected as: vd-jbc-0042", "secondary")
		_print_line("Internal address: 10.88.241.122", "secondary")
		_print_line("VPN tunnel established.", "success")
		
		GameState.vpn_established = true
		GameState.advance_stage(3)
		ScriptManager.fire_event("vpn_established")
		_vfs.set_remote_session(false)
	else:
		_print_line("Authentication failed.", "error")
		_print_line("MFA token required:", "primary")
		_awaiting_mfa = true


func _cmd_ssh(args: Array[String]) -> void:
	if not GameState.vpn_established:
		_print_line("ssh: connect to host 10.88.241.7 port 22: Connection refused", "error")
		return
	
	if _remote_session:
		_print_line("ssh: already connected to vd-internal", "error")
		return
	
	var has_jcalloway: bool = false
	for arg in args:
		if "jcalloway@" in arg:
			has_jcalloway = true
			break
	
	if not has_jcalloway:
		_print_line("ssh: Could not resolve hostname: Name or service not known", "error")
		return
	
	await get_tree().create_timer(0.8).timeout
	_print_line("Last login: [DATE] 22:47:31")
	
	_remote_session = true
	_vfs.set_remote_session(true)
	_current_prompt = PROMPT_REMOTE
	_update_prompt()


func _cmd_exit() -> void:
	if not _remote_session:
		_print_line("[no active remote session]", "secondary")
		return
	
	_print_line("Connection to 10.88.241.7 closed.", "secondary")
	_remote_session = false
	_vfs.set_remote_session(false)
	_current_prompt = PROMPT_LOCAL
	_update_prompt()


func _cmd_rsync(args: Array[String]) -> void:
	if not GameState.vpn_established:
		_print_line("rsync: connection refused — no active tunnel", "error")
		return
	
	if not GameState.archive_located:
		_print_line("rsync: /internal/projects/vd-secure/calloway_jb/: No such file or directory", "error")
		return
	
	if GameState.transfer_running:
		_print_line("rsync: transfer already in progress", "error")
		return
	
	if GameState.transfer_complete:
		_print_line("rsync: destination already exists — use --force to overwrite", "error")
		return
	
	_print_line("sending incremental file list", "secondary")
	_print_line("calloway_jb/README_DO_NOT_OPEN.txt         4.2 KB")
	_print_line("calloway_jb/archive_index.txt              1.8 KB")
	_print_line("calloway_jb/package_01/                   [DIR]")
	_print_line("calloway_jb/package_02/                   [DIR]")
	_print_line("calloway_jb/package_03/                   [DIR]")
	_print_line("calloway_jb/package_04/                   [DIR]")
	_print_line("calloway_jb/package_05_FINAL/             [DIR]")
	_print_line("calloway_jb/contacts/                     [DIR]")
	
	GameState.transfer_running = true
	_run_transfer()


func _run_transfer() -> void:
	var elapsed: float = 0.0
	var last_pct: int = -1
	
	while elapsed < TRANSFER_DURATION:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		
		GameState.transfer_progress = elapsed / TRANSFER_DURATION
		var pct: int = int(GameState.transfer_progress * 100.0)
		
		if pct != last_pct:
			_update_progress_line(pct)
			last_pct = pct
		
		if pct >= 50 and not _transfer_halfway_sent:
			_transfer_halfway_sent = true
			ScriptManager.queue_message({
				"from": "cipher",
				"body": "halfway there. staging server's holding clean.\n\ncalloway's still active on their machine.\njust so you know.",
				"delay": 0.0
			})
	
	GameState.transfer_running = false
	GameState.transfer_complete = true
	_update_progress_line(100)
	_print_line("")
	_print_line("sent 5.1 GB", "secondary")
	_print_line("transfer complete — " + _get_session_time(), "secondary")
	_print_line("integrity check: PASSED", "success")
	
	AudioManager.play_transfer_complete()
	GameState.advance_stage(5)
	
	ScriptManager.queue_message({
		"from": "cipher",
		"body": "got it. everything's on staging.\nhash matches — clean transfer.",
		"delay": 2.0
	})


func _update_progress_line(pct: int) -> void:
	var filled: int = pct / 5
	var bar: String = "[" + "=".repeat(filled) + " ".repeat(20 - filled) + "]"
	var gb: float = snappedf(pct / 100.0 * 5.1, 0.1)
	var line: String = "Progress: " + bar + " " + str(pct) + "% — " + str(gb) + " GB of 5.1 GB"
	
	# Remove old progress line if it exists
	if _output.get_child_count() > 0:
		var last_child: Node = _output.get_child(_output.get_child_count() - 1)
		if last_child.has_meta("is_progress"):
			last_child.queue_free()
	
	var style: String = "success" if pct == 100 else "amber"
	var label: Label = _print_line(line, style)
	label.set_meta("is_progress", true)


func _cmd_shred(args: Array[String]) -> void:
	if not GameState.transfer_complete:
		ScriptManager.queue_message({
			"from": "cipher",
			"body": "transfer's still running. wipe after we've confirmed\nthe staging copy.",
			"delay": 1.0
		})
		return
	
	if not _remote_session:
		_print_line("shred: no active remote session", "error")
		return
	
	if _vfs._archive_wiped:
		_print_line("shred: /internal/projects/vd-secure/calloway_jb/: No such file or directory", "error")
		return
	
	_print_line("shred: /internal/projects/vd-secure/calloway_jb/")
	
	for pass_num in [1, 2, 3]:
		_print_line("  [pass " + str(pass_num) + "/3]  " + "████████████████████" + "  overwriting", "error")
		await get_tree().create_timer(3.0).timeout
	
	await get_tree().create_timer(0.8).timeout
	_print_line("  [removing]...", "dim")
	
	ScriptManager.fire_event("wipe_in_progress")
	await get_tree().create_timer(2.0).timeout
	
	_vfs.wipe_archive()
	GameState.wipe_complete = true
	
	_print_line("shred complete — " + _get_session_time(), "secondary")
	_print_line("/internal/projects/vd-secure/calloway_jb/ — REMOVED", "dim")
	_print_line("verification: NO DATA RECOVERABLE", "success")
	
	if GameState.logs_cleared:
		GameState.advance_stage(6)


func _cmd_communicate(args: Array[String]) -> void:
	if not _remote_session:
		_print_line("write: jcalloway: user not logged in", "error")
		return
	
	if not GameState.archive_located:
		_print_line("write: jcalloway: user not logged in", "error")
		return
	
	if GameState.wipe_complete:
		_print_line("write: jcalloway: user not logged in", "error")
		return
	
	_print_line("Message to jcalloway@vd-internal (Ctrl+D to send):", "secondary")
	_in_calloway_message_mode = true
	_calloway_buffer = ""


func _cmd_communicate_direct(message: String) -> void:
	if not _remote_session:
		_print_line("write: jcalloway: user not logged in", "error")
		return
	
	if not GameState.archive_located:
		_print_line("write: jcalloway: user not logged in", "error")
		return
	
	if GameState.wipe_complete:
		_print_line("write: jcalloway: user not logged in", "error")
		return
	
	_send_calloway_message_with(message)


func _send_calloway_message() -> void:
	_in_calloway_message_mode = false
	_send_calloway_message_with(_calloway_buffer)
	_calloway_buffer = ""


func _send_calloway_message_with(message: String) -> void:
	GameState.ghost_communicated_with_calloway = true
	_calloway_exchange_count += 1
	
	await get_tree().create_timer(2.0).timeout
	_print_line("")
	_print_line("[BROADCAST — vd-internal — anonymous]", "secondary")
	_print_line("")
	
	var response: String = _get_calloway_response(message.to_lower())
	var lines: PackedStringArray = response.split("\n")
	
	for line in lines:
		_print_line(line)
		await get_tree().create_timer(0.05).timeout
	
	if _calloway_exchange_count >= 3:
		GameState.set_flag("ghost_knows_mayas_name", true)


func _get_calloway_response(msg: String) -> String:
	# KNOW keywords
	if "dead" in msg or "deaths" in msg or "readme" in msg or "knew" in msg or \
	   "medical" in msg or "firmware" in msg or "evidence" in msg or \
	   "whistleblow" in msg or "archive contains" in msg:
		GameState.set_flag("ghost_knows_mayas_name", true)
		GameState.set_flag("calloway_offered_key", true)
		return """you read it.

I knew someone would come eventually.
I thought I'd have more time.

my daughter is six. her name is maya.
I've been building this case for eight months.

if you're going to take it — copy it first.
give it to someone. anyone.
I don't care who has it as long as someone does.

just don't destroy it.

the journalist contact — I'll give you the key.
you won't need to be the one who publishes it.
just make sure someone can."""
	
	# WARN keywords
	if "warn" in msg or "danger" in msg or "careful" in msg or \
	   "leave" in msg or "safe" in msg or "get out" in msg:
		return """I know.

I've known for a week someone was coming.
I've been trying to get everything out in time.

there's a six-year-old who needs me to have
been worth something.

do what you're going to do."""
	
	# DEMAND keywords
	if "stop" in msg or "don't" in msg or "cease" in msg or \
	   "halt" in msg or "disconnect" in msg:
		return """I won't stop.

you can take the files. I understand.
but I won't stop trying to make sure
someone finds out what they did.

please. whatever you're here to do —
don't let them win."""
	
	# IDENTITY keywords
	if "who are you" in msg or "who is this" in msg or "identify" in msg:
		return """someone who's spent eight months on this.

fourteen people are dead.
vantage dynamics knew before the first one.

who are you?"""
	
	# Default
	return "who are you?"


func _cmd_scrub_logs(args: Array[String]) -> void:
	if GameState.logs_cleared:
		_print_line("scrub_logs.sh: logs already cleared", "error")
		return
	
	_print_line("scrubbing VPN authentication logs...", "primary")
	await get_tree().create_timer(0.6).timeout
	_print_line("DONE", "success")
	
	_print_line("scrubbing internal access logs...", "primary")
	await get_tree().create_timer(0.6).timeout
	_print_line("DONE", "success")
	
	_print_line("scrubbing session records...", "primary")
	await get_tree().create_timer(0.6).timeout
	_print_line("DONE", "success")
	
	_print_line("verifying: no residual entries found.", "primary")
	await get_tree().create_timer(0.6).timeout
	_print_line("CLEAN", "success")
	
	if not GameState.wipe_complete:
		_print_line("")
		_print_line("NOTE: Remote session terminated. Archive wipe not confirmed.", "amber")
		_print_line("      Wipe objective remains active — re-establish access to complete.", "amber")
	
	GameState.logs_cleared = true
	_remote_session = false
	_vfs.set_remote_session(false)
	_current_prompt = PROMPT_LOCAL
	_update_prompt()
	
	await get_tree().create_timer(0.3).timeout
	_print_line("VPN session terminated.", "secondary")
	GameState.vpn_established = false
	
	if GameState.wipe_complete:
		GameState.advance_stage(6)


# ==================== OUTPUT HELPERS ====================

func _print_line(text: String, style: String = "primary") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	match style:
		"primary":
			label.modulate = Color("#d4d4d4")
		"error":
			label.modulate = Color("#cc3333")
		"success":
			label.modulate = Color("#3a8a3a")
		"amber":
			label.modulate = Color("#c8841a")
		"dim":
			label.modulate = Color("#4a4a4a")
		"secondary":
			label.modulate = Color("#8a8a8a")
	
	_output.add_child(label)
	return label


func _scroll_to_bottom() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _clear_output() -> void:
	for child in _output.get_children():
		child.queue_free()


func _update_prompt() -> void:
	_prompt_label.text = _current_prompt


func _cycle_history(direction: int) -> void:
	_history_index = clamp(_history_index + direction, -1, _history.size() - 1)
	
	if _history_index == -1:
		_input_field.text = ""
	else:
		_input_field.text = _history[_history_index]
	
	_input_field.caret_column = _input_field.text.length()


func _attempt_tab_complete() -> void:
	var current_text: String = _input_field.text
	var parts: PackedStringArray = current_text.split(" ")
	
	if parts.is_empty():
		return
	
	var last_token: String = parts[parts.size() - 1]
	
	if not ("/" in last_token or "~" in last_token):
		return
	
	var completions: Array[String] = _vfs.get_completions(last_token)
	
	if completions.size() == 1:
		# Replace last token with completion
		parts[parts.size() - 1] = completions[0]
		_input_field.text = " ".join(parts)
		_input_field.caret_column = _input_field.text.length()
	elif completions.size() > 1:
		# Print current line, completions, then reprint prompt
		_print_line(_current_prompt + " " + current_text)
		_print_line("  ".join(completions), "secondary")


func _get_session_time() -> String:
	return Time.get_time_string_from_system()
