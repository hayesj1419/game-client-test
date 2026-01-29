extends Node

#---- Config ----
@export var server_url: String = "ws://localhost:5177/ws"


# ---- Web Socket ----
var socket := WebSocketPeer.new()

# ---- Last know position cache
var last_known_positions := {}

# ---- Snapshot Buffer ----
var snapshots: Array = []

# How many snapshots to keep (avoid unbounded growth)
const MAX_SNAPSHOTS := 20

# Interpolation Delay
const INTERPOLATION_DELAY_TICKS := 4

# Track last sent input
var last_sent_input := Vector2.ZERO

# Track predicted position
var predicted_position := Vector2.ZERO
var has_predicted_position := false

# Seperate current input from last sent input
var current_input := Vector2.ZERO

var prediction_tick_accumulator: float = 0.0

# Reconciliation variables
var server_position := Vector2.ZERO
var reconciliation_alpha: float = 0.15

# HUD Variables
var last_snapshot_tick: int = -1
var last_snapshot_age_ms: float = 0.0
var last_entity_count: int = 0

var last_render_position: Vector2 = Vector2.ZERO
var last_authoritative_position: Vector2 = Vector2.ZERO
var last_correction_distance: float = 0.0

func _ready():
	print("NetworkClient READY at:", get_path())
	connect_to_server()

func connect_to_server():
	var err = socket.connect_to_url(server_url)
	if err != OK:
		push_error("Failed to connect to server")
	else:
		print("Connecting to server:", server_url)

var last_state := -1

func _process(_delta):
	# Store live input for prediction
	current_input = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		current_input.x += 1
	if Input.is_action_pressed("ui_left"):
		current_input.x -= 1
	if Input.is_action_pressed("ui_down"):
		current_input.y += 1
	if Input.is_action_pressed("ui_up"):
		current_input.y -= 1
	# Required for WebSocket events to be processed
	socket.poll()
	
	var state = socket.get_ready_state()
	
	if state != last_state:
		print("WebSocket state changed:", state)
		last_state = state

	if state == WebSocketPeer.STATE_OPEN:
		_process_incoming_messages()
		_send_input()
	elif state == WebSocketPeer.STATE_CLOSED:
		print("WebSocket closed")
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CONNECTING:
		pass
	
	_apply_local_prediction(_delta)
	_apply_reconciliation()
	
func _process_incoming_messages():
	while socket.get_available_packet_count() > 0:
		var packet = socket.get_packet()
		var text = packet.get_string_from_utf8()
			
		_handle_message(text)

func _handle_message(text: String):
	var json = JSON.parse_string(text)
	if json == null:
		push_error("Invalid JSON received")
		return

	# ✅ HANDLE CONTROL MESSAGES FIRST
	if json.has("type") and json["type"] == "welcome":
		has_predicted_position = false
		get_node("/root/Main").player_id = json["playerId"]
		print("CLIENT bound to player_id:", json["playerId"])
		return

	# ✅ THEN HANDLE SNAPSHOTS
	if not json.has("tick"):
		push_error("Snapshot missing tick")
		return

	for p in json["players"]:
		p["id"] = p["Id"]
		p["x"] = p["X"]
		p["y"] = p["Y"]

	json["received_at_ms"] = Time.get_ticks_msec()
	_store_snapshot(json)


func _store_snapshot(snapshot: Dictionary):
	
	snapshots.append(snapshot)
	
	# Keep snapshots ordered by tick
	snapshots.sort_custom(func(a, b):
		return a["tick"] < b["tick"]
		)
	
	# Trim buffer
	if snapshots.size() > MAX_SNAPSHOTS:
		snapshots.pop_front()
	for p in snapshot["players"]:
		var pos := Vector2(p["x"], p["y"])
		last_known_positions[p["id"]] = pos
		
		# Seed local prediction from authoritative server state
		if p["id"] == get_node("/root/Main").player_id:
			server_position = pos
			has_predicted_position = true
			
	last_snapshot_tick = snapshot["tick"]
	last_entity_count = snapshot["players"].size()
	last_snapshot_age_ms = Time.get_ticks_msec() - snapshot["received_at_ms"]
	
func _send_input():
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	
	# Only send if input changed
	if current_input == last_sent_input:
		return
	
	last_sent_input = current_input
	
	var input_message := {
		"type": "input",
		"x": int(current_input.x),
		"y": int(current_input.y)
	}
	
	socket.send_text(JSON.stringify(input_message))

func get_interpolated_position(player_id: String) -> Vector2:
	var local_id = get_node("/root/Main").player_id
	
	if player_id == local_id and has_predicted_position:
		return predicted_position
		
	if snapshots.size() < 2:
		return last_known_positions.get(player_id, Vector2.ZERO)
	
	var latest_tick = snapshots.back()["tick"]
	var render_tick = latest_tick - INTERPOLATION_DELAY_TICKS
	print("latest:", latest_tick, "render:", render_tick, "buffer:", snapshots.size())
	
	var older
	var newer
	
	for i in range(snapshots.size() - 1):
		if snapshots[i]["tick"] <= render_tick and snapshots[i + 1]["tick"] >= render_tick:
			older = snapshots[i]
			newer = snapshots[i + 1]
			break
	
	if older == null or newer == null:
		return last_known_positions.get(player_id, Vector2.ZERO)

	
	var t0 = older["tick"]
	var t1 = newer["tick"]
	
	# Guard against identical timestamps
	if t1 == t0:
		return last_known_positions.get(player_id, Vector2.ZERO)
		
	var alpha = (render_tick - t0) / (t1 -t0)
	
	for p0 in older["players"]:
		if p0["id"] == player_id:
			for p1 in newer["players"]:
				if p1["id"] == player_id:
					return Vector2(
						lerp(p0["x"], p1["x"], alpha),
						lerp(p0["y"], p1["y"], alpha)
					)
	return last_known_positions.get(player_id, Vector2.ZERO)

func _apply_local_prediction(delta):
	if not has_predicted_position:
		return
	
	if current_input == Vector2.ZERO:
		return
	
	# Match server constants exactly
	var speed_per_tick: float = 0.1
	var tick_rate: float = 20.0
	var tick_duration := 1.0 / tick_rate
	
	# Accumulate frame time
	prediction_tick_accumulator += delta
	
	while prediction_tick_accumulator >= tick_duration:
		prediction_tick_accumulator -= tick_duration
		
		var input := current_input
		# Clamp input magnitude (same rule as server)
		if input.length() > 1:
			input = input.normalized()
	
		predicted_position += input * speed_per_tick

func _apply_reconciliation():
	if not has_predicted_position:
		return
	
	var error := server_position - predicted_position
	
	# If error is tiny, snap to avoid endless micro-jitter
	if error.length() < 0.01:
		predicted_position = server_position
		return
		
	predicted_position += error * reconciliation_alpha
