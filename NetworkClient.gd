extends Node

#---- Config ----
@export var server_url: String = "ws://localhost:5177/ws"


# ---- Web Socket ----
var socket := WebSocketPeer.new()

# ---- Snapshot Buffer ----
var snapshots: Array = []

# How many snapshots to keep (avoid unbounded growth)
const MAX_SNAPSHOTS := 20


func _ready():
	print("NewtworkClient starting...")
	connect_to_server()

func connect_to_server():
	var err = socket.connect_to_url(server_url)
	if err != OK:
		push_error("Failed to connect to server")
	else:
		print("Connecting to server:", server_url)

var last_state := -1

func _process(_delta):
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
	
	if not json.has("tick"):
		push_error("Snapshot missing tick")
		return
		
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
	
	# Only send if there is actual input
	if input_x == 0 and input_y == 0:
		return
		
	print("Input:", input_x, input_y)
	
	var input_message := {
		"type": "input",
		"x": input_x,
		"y": input_y
	}
	
	var json_text := JSON.stringify(input_message)
	socket.send_text(json_text)
