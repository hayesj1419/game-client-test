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
const INTERPOLATION_DELAY := 0.1

# Track local time
var local_time := 0.0


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
	# Update local time every frame
	local_time += _delta
	
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

	_store_snapshot(json)


func _store_snapshot(snapshot: Dictionary):
	
	snapshot["time"] = Time.get_ticks_msec() / 1000.0
	snapshots.append(snapshot)
	
	# Keep snapshots ordered by tick
	snapshots.sort_custom(func(a, b):
		return a["time"] < b["time"]
		)
	
	# Trim buffer
	if snapshots.size() > MAX_SNAPSHOTS:
		snapshots.pop_front()
	for p in snapshot["players"]:
		last_known_positions[p["id"]] = Vector2(p["x"], p["y"])
		
	print("Snapshot received (tick=%s)" % snapshot["tick"])

func _send_input():
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	
	var input_x := 0
	var input_y := 0
	
	if Input.is_action_pressed("ui_right"):
		input_x += 1
	if Input.is_action_pressed("ui_left"):
		input_x -= 1
	if Input.is_action_pressed("ui_down"):
		input_y += 1
	if Input.is_action_pressed("ui_up"):
		input_y -= 1
		
	
	var input_message := {
		"type": "input",
		"x": input_x,
		"y": input_y
	}
	
	var json_text := JSON.stringify(input_message)
	socket.send_text(json_text)

func get_interpolated_position(player_id: String) -> Vector2:
	if snapshots.size() < 2:
		return last_known_positions.get(player_id, Vector2.ZERO)
	
	var render_time = local_time - INTERPOLATION_DELAY
	render_time = max(render_time, snapshots[0]["time"])
	
	var older
	var newer
	
	for i in range(snapshots.size() - 1):
		if snapshots[i]["time"] <= render_time and snapshots[i + 1]["time"] >= render_time:
			older = snapshots[i]
			newer = snapshots[i + 1]
			break
	
	if older == null or newer == null:
		return last_known_positions.get(player_id, Vector2.ZERO)

	
	var t0 = older["time"]
	var t1 = newer["time"]
	
	# Guard against identical timestamps
	if t1 == t0:
		return last_known_positions.get(player_id, Vector2.ZERO)
		
	var alpha = (render_time - t0) / (t1 -t0)
	
	for p0 in older["players"]:
		if p0["id"] == player_id:
			for p1 in newer["players"]:
				if p1["id"] == player_id:
					return Vector2(
						lerp(p0["x"], p1["x"], alpha),
						lerp(p0["y"], p1["y"], alpha)
					)
	return last_known_positions.get(player_id, Vector2.ZERO)
