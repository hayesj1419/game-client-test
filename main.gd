extends Node2D

@onready var network := Network
@onready var player := $Player

var player_id : String = ""


func _ready():
	print("Main sees NetworkClient at:", network.get_path())

	
func _process(delta):
	if player_id == "":
		return
	if not network.last_known_positions.has(player_id):
		return

	var server_pos = network.get_interpolated_position(player_id)
	$Player/Sprite2D.position = server_pos + $Player.predicted_offset
