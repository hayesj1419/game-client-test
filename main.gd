extends Node2D

@onready var network := NetworkClient
@onready var player := $Player




func _ready():
	print("Main sees NetworkClient at:", network.get_path())
	var hud = preload("res://DebugHUD.tscn").instantiate()
	add_child(hud)

	
func _process(delta):
	if network.player_id == "":
		return
	if not network.last_known_positions.has(network.player_id):
		return
	
	var render_pos = network.get_interpolated_position(network.player_id)
	
	var server_pos = network.get_interpolated_position(network.player_id)
	$Player/Sprite2D.position = server_pos + $Player.predicted_offset
	
	# --- HUD Instrumentation ---
	network.last_render_position = render_pos
	network.last_authoritative_position = server_pos
	network.last_correction_distance = render_pos.distance_to(server_pos)
