class_name VirtualFileSystem
extends RefCounted

## Virtual filesystem for the game world
## All file operations are in-memory only


# ============================================================================
# CONSTANTS — File Content
# ============================================================================

const CONTENT_OBJECTIVES := """OPERATION BRIEF — CALLOWAY / VANTAGE DYNAMICS
Prepared by: [CLIENT]
Classification: EYES ONLY

OBJECTIVES:
  1. Access target archive:
       /internal/projects/vd-secure/calloway_jb/
  2. Extract full contents to secure staging location
  3. Verify extraction integrity
  4. Wipe target archive — overwrite, no recovery path
  5. Remove access logs for the operation window
  6. Confirm completion to handler

PAYMENT: On confirmation. Account details in secure envelope.

NOTE: Timeline is firm. Target has indicated intent to
move the package within 48 hours. Operate tonight."""

const CONTENT_CALLOWAY_PROFILE := """TARGET PROFILE: CALLOWAY, JORDAN B.
  Employer: Vantage Dynamics (Analytics Division)
  Clearance level (internal): Level 2
  Home address: [REDACTED — see network file]
  Network access: Home broadband, VPN to VD internal
  Household: Lives alone.
              One dependent — daughter, approx. 6 yrs.
  Schedule: Works late. Usually offline by 23:00.
  Risk assessment: LOW.
                   No prior security incidents.
                   Non-technical."""

const CONTENT_VD_NETWORK := """VANTAGE DYNAMICS — REMOTE ACCESS INFRASTRUCTURE

  VPN Gateway:      10.88.241.7
  External-facing:  203.0.113.44
  Auth method:      Certificate + MFA (6-digit, 30s rotation)
  Calloway device:  vd-jbc-0042
  Certificate:      calloway_jbc.pem [attached to this archive]
  MFA:              Handled via secondary channel.
                    Cipher will provide live tokens on request.

  Internal structure — relevant paths:
    /internal/projects/        [accessible via Calloway credentials]
    /internal/projects/vd-secure/calloway_jb/    [TARGET]"""

const CONTENT_TARGET_MAP := """TARGET ARCHIVE — KNOWN STRUCTURE
  /internal/projects/vd-secure/calloway_jb/
    [contents unknown — client provided path only]
    [estimated size: 4-6 GB based on network traffic analysis]

  NOTE: Path is non-standard. Does not appear in the
  published org chart for Vantage Dynamics internal
  infrastructure. Either set up by the target or
  assisted by an internal contact."""

const CONTENT_CERT_PEM := """-----BEGIN CERTIFICATE-----
MIIDazCCAlOgAwIBAgIUXk9vJcBn2jQpLmN8RwFt4YeH1KswDQYJKoZIhvcNAQEL
[CERTIFICATE DATA — DO NOT DISTRIBUTE]
-----END CERTIFICATE-----"""

const CONTENT_README := """If you are reading this you are probably not
Jordan Calloway.

This archive contains documentation of safety
failures in the VD-MED-7 device line — specifically
the firmware update applied in manufacturing batches
2019-Q3 through 2020-Q2.

There are 14 confirmed deaths in the US alone
attributable to the failure mode. Internal
communications confirm that Engineering flagged
the failure risk in February 2019. The decision
to proceed was made at the executive level.

This material is being staged for delivery to
a journalist and to the relevant federal
regulatory body.

If Jordan Calloway is dead when you read this,
the archive needs to reach:
  contacts/journalist_contact.gpg
  contacts/regulatory_contact.gpg

The decryption key is not stored here.

Do not destroy this archive."""

const CONTENT_ARCHIVE_INDEX := """ARCHIVE INDEX — J. CALLOWAY

package_01/   Engineering risk assessments, Feb-Apr 2019
              Internal memos flagging firmware failure mode.
              12 documents.

package_02/   Executive sign-off chain, May 2019
              Decision to proceed with manufacturing run.
              Email threads + meeting minutes. 8 documents.

package_03/   Post-market incident reports, 2019-2021
              Death and injury reports cross-referenced
              with affected batch numbers. 34 documents.

package_04/   Internal suppression communications, 2021-2022
              Evidence of deliberate non-disclosure to
              regulatory bodies. 19 documents.

package_05_FINAL/
              Compiled evidence package with index,
              cross-references, and narrative summary.
              Formatted for handoff. 1 document (94 pp).

contacts/
              journalist_contact.gpg   [ENCRYPTED]
              regulatory_contact.gpg   [ENCRYPTED]"""

const CONTENT_BASH_HISTORY := """ls /internal/projects/
ls /internal/projects/vd-secure/
cd /internal/projects/vd-secure/calloway_jb/
gpg --encrypt --recipient [REDACTED] contacts_backup.tar.gz
rsync -avz package_05_FINAL/ ../package_05_FINAL/
ls -la"""

const CONTENT_GPG := """-----BEGIN PGP MESSAGE-----

[ENCRYPTED CONTENT — KEY NOT AVAILABLE]

-----END PGP MESSAGE-----"""

const CONTENT_VPN_CONFIG := """# vd-endpoint — pre-staged
# created: [4 days ago]
remote 203.0.113.44 1194
cert calloway_jbc.pem
auth-user-pass"""

const CONTENT_ENDPOINTS := CONTENT_VPN_CONFIG


# ============================================================================
# VARIABLES
# ============================================================================

var current_path: String = "/home/ghost"
var _remote_session: bool = false
var _archive_wiped: bool = false
var _brief_extracted: bool = false

var _local_tree: Dictionary = {
	"home": {
		"ghost": {
			".config": {
				"vpn": {
					"endpoints.conf": CONTENT_VPN_CONFIG
				}
			},
			"downloads": {},
			"notes": {},
			"scrub_logs.sh": "[EXECUTABLE]"
		}
	}
}

var _remote_tree: Dictionary = {
	"home": {
		"jcalloway": {
			"documents": {},
			"downloads": {},
			".bash_history": CONTENT_BASH_HISTORY,
			".ssh": {
				"authorized_keys": "[PERMISSION_DENIED]",
				"id_rsa": "[PERMISSION_DENIED]"
			}
		}
	},
	"internal": {
		"projects": {
			"analytics_q3": "[PERMISSION_DENIED]",
			"analytics_q4": "[PERMISSION_DENIED]",
			"client_reporting": "[PERMISSION_DENIED]",
			"dev_ops_staging": "[PERMISSION_DENIED]",
			"hr_compliance": "[PERMISSION_DENIED]",
			"vd-secure": {
				"calloway_jb": {
					"README_DO_NOT_OPEN.txt": CONTENT_README,
					"archive_index.txt": CONTENT_ARCHIVE_INDEX,
					"package_01": {},
					"package_02": {},
					"package_03": {},
					"package_04": {},
					"package_05_FINAL": {},
					"contacts": {
						"journalist_contact.gpg": CONTENT_GPG,
						"regulatory_contact.gpg": CONTENT_GPG
					}
				}
			}
		}
	}
}


# ============================================================================
# METHODS
# ============================================================================

func _get_active_tree() -> Dictionary:
	return _remote_tree if _remote_session else _local_tree


func _resolve_path(path: String) -> String:
	# Handle home directory shortcut
	if path.begins_with("~/"):
		path = "/home/ghost/" + path.substr(2)
	
	# Handle relative paths
	if path == "..":
		# Go to parent directory
		var parts: PackedStringArray = current_path.split("/")
		var filtered_parts: Array[String] = []
		for s in parts:
			if s != "":
				filtered_parts.append(s)
		if filtered_parts.size() > 0:
			filtered_parts.remove_at(filtered_parts.size() - 1)
		if filtered_parts.size() == 0:
			return "/"
		return "/" + "/".join(filtered_parts)
	
	if path == ".":
		return current_path
	
	# If path doesn't start with "/", treat as relative
	if not path.begins_with("/"):
		if current_path == "/":
			path = "/" + path
		else:
			path = current_path + "/" + path
	
	# Strip trailing slash unless it's root
	if path != "/" and path.ends_with("/"):
		path = path.substr(0, path.length() - 1)
	
	return path


func _navigate_to(path: String) -> Variant:
	var parts: PackedStringArray = path.split("/")
	var filtered_parts: Array[String] = []
	for s in parts:
		if s != "":
			filtered_parts.append(s)
	
	var current: Variant = _get_active_tree()
	
	for segment in filtered_parts:
		if not current is Dictionary:
			return "FILE"
		
		if not current.has(segment):
			return null
		
		var value: Variant = current[segment]
		
		if value == "[PERMISSION_DENIED]":
			return "PERMISSION_DENIED"
		
		if value is String and value != "[DIR]":
			# It's a file, can't navigate into it unless it's the last segment
			if segment != filtered_parts[filtered_parts.size() - 1]:
				return "FILE"
		
		current = value
	
	return current


func list(path: String) -> Variant:
	var resolved_path: String = _resolve_path(path)
	var result: Variant = _navigate_to(resolved_path)
	
	if result == null:
		return null
	
	if result == "PERMISSION_DENIED":
		return "PERMISSION_DENIED"
	
	if result == "FILE":
		return "FILE"
	
	if not result is Dictionary:
		return null
	
	# Build list of entries, appending "/" to directories
	var entries: Array[String] = []
	for key in result.keys():
		var value: Variant = result[key]
		if value is Dictionary:
			entries.append(key + "/")
		else:
			entries.append(key)
	
	return entries


func read_file(path: String) -> Variant:
	var resolved_path: String = _resolve_path(path)
	
	# Split path to get parent directory and filename
	var parts: PackedStringArray = resolved_path.split("/")
	var filtered_parts: Array[String] = []
	for s in parts:
		if s != "":
			filtered_parts.append(s)
	
	if filtered_parts.size() == 0:
		return "IS_DIR"
	
	var filename: String = filtered_parts[filtered_parts.size() - 1]
	
	# Get parent path
	var parent_parts: Array = []
	for i in range(filtered_parts.size() - 1):
		parent_parts.append(filtered_parts[i])
	
	var parent_path: String = "/" + "/".join(parent_parts) if parent_parts.size() > 0 else "/"
	var parent: Variant = _navigate_to(parent_path)
	
	if parent == null or not parent is Dictionary:
		return null
	
	if not parent.has(filename):
		return null
	
	var value: Variant = parent[filename]
	
	if value == "[PERMISSION_DENIED]":
		return "PERMISSION_DENIED"
	
	if value is Dictionary:
		return "IS_DIR"
	
	if value == "[EXECUTABLE]":
		return "[EXECUTABLE]"
	
	return value


func file_exists(path: String) -> bool:
	var resolved_path: String = _resolve_path(path)
	
	# Split path to get parent directory and filename
	var parts: PackedStringArray = resolved_path.split("/")
	var filtered_parts: Array[String] = []
	for s in parts:
		if s != "":
			filtered_parts.append(s)
	
	if filtered_parts.size() == 0:
		return true  # Root always exists
	
	var filename: String = filtered_parts[filtered_parts.size() - 1]
	
	# Get parent path
	var parent_parts: Array = []
	for i in range(filtered_parts.size() - 1):
		parent_parts.append(filtered_parts[i])
	
	var parent_path: String = "/" + "/".join(parent_parts) if parent_parts.size() > 0 else "/"
	var parent: Variant = _navigate_to(parent_path)
	
	if parent == null or not parent is Dictionary:
		return false
	
	return parent.has(filename)


func populate_brief() -> void:
	var downloads: Dictionary = _local_tree["home"]["ghost"]["downloads"]
	downloads["brief_calloway"] = {
		"calloway_jordan_profile.txt": CONTENT_CALLOWAY_PROFILE,
		"vantage_dynamics_network.txt": CONTENT_VD_NETWORK,
		"target_archive_map.txt": CONTENT_TARGET_MAP,
		"objectives.txt": CONTENT_OBJECTIVES,
		"calloway_jbc.pem": CONTENT_CERT_PEM
	}
	downloads["brief_calloway_vd.tar.gz"] = "[EXTRACTED]"
	_brief_extracted = true


func wipe_archive() -> void:
	var vd_secure: Dictionary = _remote_tree["internal"]["projects"]["vd-secure"]
	vd_secure.erase("calloway_jb")
	_archive_wiped = true


func add_decryption_key(key_string: String) -> void:
	var ghost_home: Dictionary = _local_tree["home"]["ghost"]
	ghost_home["calloway_key.txt"] = key_string + "\nreceived: [session time]"


func on_file_read(path: String) -> void:
	if path.ends_with("README_DO_NOT_OPEN.txt"):
		GameState.set_flag("ghost_read_readme", true)
	
	if path.ends_with("archive_index.txt"):
		GameState.set_flag("ghost_read_index", true)
	
	if "brief_calloway" in path and GameState.objective_stage < 2:
		GameState.advance_stage(2)


func on_directory_entered(path: String) -> void:
	if "calloway_jb" in path and not GameState.archive_located:
		GameState.archive_located = true
		GameState.advance_stage(4)
		ScriptManager.fire_event("calloway_aware")


func get_completions(partial: String) -> Array[String]:
	# Split into directory part and filename prefix
	var last_slash: int = partial.rfind("/")
	var dir_part: String = ""
	var file_prefix: String = partial
	
	if last_slash >= 0:
		dir_part = partial.substr(0, last_slash + 1)
		file_prefix = partial.substr(last_slash + 1)
	
	# List the directory
	var list_path: String = dir_part if dir_part != "" else "."
	var entries: Variant = list(list_path)
	
	if entries == null or not entries is Array:
		return []
	
	# Filter entries that match the prefix
	var completions: Array[String] = []
	for entry in entries:
		if entry.begins_with(file_prefix):
			completions.append(dir_part + entry)
	
	return completions


func set_remote_session(active: bool) -> void:
	_remote_session = active
	if active:
		current_path = "/home/jcalloway"
	else:
		current_path = "/home/ghost"
