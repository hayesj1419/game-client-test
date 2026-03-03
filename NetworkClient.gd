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

# Input sequencing and buffer for reconciliation
# Buffer entries: {seq, input, tick_sent} — tick_sent is the _prediction_tick when the input was sent
var _next_seq: int = 0
var _input_buffer: Array = []
var _last_acked_seq: int = 0

# Monotonic prediction tick counter (increments at 20 Hz in _apply_local_prediction)
var _prediction_tick: int = 0
# Value of _prediction_tick when the most recent new ackedSeq was received
var _ack_received_tick: int = 0

# HUD Variables
var last_snapshot_tick: int = -1
var last_snapshot_age_ms: float = 0.0
var last_entity_count: int = 0

var last_render_position: Vector2 = Vector2.ZERO
var last_authoritative_position: Vector2 = Vector2.ZERO
var last_correction_distance: float = 0.0

# Player declaration
var player_id: String = ""

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
		player_id = json["playerId"]
		print("CLIENT bound to player_id:", json["playerId"])
		return

	# ✅ THEN HANDLE SNAPSHOTS
	if not json.has("tick"):
		push_error("Snapshot missing tick")
		return

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
		if p["id"] == player_id:
			server_position = pos
			var new_acked_seq: int = p.get("ackedSeq", 0)
			if new_acked_seq > _last_acked_seq:
				_last_acked_seq = new_acked_seq
			# Reset on every snapshot so in_flight stays bounded to one snapshot interval
			_ack_received_tick = _prediction_tick
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

	_next_seq += 1
	_input_buffer.append({"seq": _next_seq, "input": current_input, "tick_sent": _prediction_tick})

	var input_message := {
		"type": "input",
		"seq": _next_seq,
		"x": int(current_input.x),
		"y": int(current_input.y)
	}

	socket.send_text(JSON.stringify(input_message))

func get_interpolated_position(player_id: String) -> Vector2:
	var local_id = player_id
	
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

	prediction_tick_accumulator += delta

	while prediction_tick_accumulator >= 1.0 / 20.0:
		prediction_tick_accumulator -= 1.0 / 20.0
		_prediction_tick += 1

func _apply_reconciliation():
	if not has_predicted_position:
		return

	# Discard inputs the server has already acknowledged
	_input_buffer = _input_buffer.filter(func(e): return e["seq"] > _last_acked_seq)

	var sim_pos := server_position
	var speed_per_tick: float = 0.1

	# Use the buffer when we have unacked inputs with known send times.
	# Otherwise (nothing acked yet, or all inputs acked) predict ahead using
	# last_sent_input for the ticks elapsed since the last snapshot — this keeps
	# in_flight bounded to one snapshot interval (~1 tick at 20 Hz).
	if _input_buffer.size() > 0 and _last_acked_seq > 0:
		# Re-simulate each buffer entry for the ticks it was active.
		# Each entry runs from its tick_sent until the next entry's tick_sent (or now).
		for i in range(_input_buffer.size()):
			var entry = _input_buffer[i]
			var tick_end: int = _input_buffer[i + 1]["tick_sent"] if i + 1 < _input_buffer.size() else _prediction_tick
			var ticks: int = max(0, tick_end - (entry["tick_sent"] as int))
			var input: Vector2 = entry["input"]
			if input.length() > 1:
				input = input.normalized()
			sim_pos += input * speed_per_tick * ticks
	else:
		# No unacked buffer entries (or nothing acked yet) — predict ahead using
		# last_sent_input for the ticks since the last snapshot.
		# Include the sub-tick accumulator so this updates smoothly at frame rate,
		# not in discrete 20 Hz steps.
		var in_flight: float = float(_prediction_tick - _ack_received_tick) + (prediction_tick_accumulator * 20.0)
		var input := last_sent_input
		if input.length() > 1:
			input = input.normalized()
		sim_pos += input * speed_per_tick * in_flight

	last_correction_distance = sim_pos.distance_to(server_position)
	predicted_position = sim_pos
