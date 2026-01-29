extends Node2D

@onready var network := Network
@onready var player := $Player

var player_id : String = ""


func _ready():
	print("Main sees NetworkClient at:", network.get_path())
	var hud = preload("res://DebugHUD.tscn").instantiate()
	add_child(hud)

	
func _process(delta):
	if player_id == "":
		return
	if not network.last_known_positions.has(player_id):
		return
	
	var render_pos = network.get_interpolated_position(player_id)
	
	var server_pos = network.get_interpolated_position(player_id)
	$Player/Sprite2D.position = server_pos + $Player.predicted_offset
	
	# --- HUD Instrumentation ---
	network.last_render_position = render_pos
	network.last_authoritative_position = server_pos
	network.last_correction_distance = render_pos.distance_to(server_pos)
