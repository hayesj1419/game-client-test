extends CanvasLayer



@onready var network := NetworkClient

@onready var tick_label := $PanelContainer/VBoxContainer/Ticks
@onready var age_label := $PanelContainer/VBoxContainer/SnapshotAge
@onready var entities_label := $PanelContainer/VBoxContainer/Entities
@onready var render_pos_label := $PanelContainer/VBoxContainer/RenderPos
@onready var auth_pos_label := $PanelContainer/VBoxContainer/AuthPos
@onready var correction_label := $PanelContainer/VBoxContainer/Correction

var frame_count := 0
var local_time := 0.0


func _ready():
	print("DebugHUD ready!")
	
	tick_label.text = "HUD: ACTIVE"
	age_label.text = ""
	entities_label.text = ""
	render_pos_label.text = ""
	auth_pos_label.text = ""
	correction_label.text = ""
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	frame_count += 1
	local_time += delta
	
	# --- HUD Liveness ---
	tick_label.text = "HUD ACTIVE | Frame: %d" % frame_count
	age_label.text = "Local Time: %.2f" % local_time
	
	# --- Connection State ---
	if network == null:
		entities_label.text = "Network: NULL"
		render_pos_label.text = ""
		auth_pos_label.text = ""
		correction_label.text = ""
		return
	
	var socket_state := "N/A"
	if network.socket != null:
		socket_state = _socket_state_to_string(
			network.socket.get_ready_state()
		)
		
	entities_label.text = "Socket State: %s" % socket_state
	render_pos_label.text = "Server URL: %s" % network.server_url
	auth_pos_label.text = "Player ID: %s" % (
		network.player_id.substr(0, 8)
		if network.player_id != ""
		else "N/A"
	)
	
	correction_label.text = ""

func _socket_state_to_string(state: int) -> String:
	match state:
		WebSocketPeer.STATE_CONNECTING: return "CONNECTING"
		WebSocketPeer.STATE_OPEN: return "OPEN"
		WebSocketPeer.STATE_CLOSING: return "CLOSING"
		WebSocketPeer.STATE_CLOSED: return "CLOSED"
		_: return "UNKNOWN"
