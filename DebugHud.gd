extends CanvasLayer

@export var network_client_path: NodePath

@onready var network := get_node(network_client_path)

@onready var tick_label := %Ticks
@onready var age_label := %SnapshotAge
@onready var entities_label := %Entities
@onready var render_pos_label := %RenderPos
@onready var auth_pos_label := %AuthPos
@onready var correction_label := %Correction

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if network == null:
		return
	
	tick_label.text = "HUD ACTIVE"
	print("Writing to label:", tick_label, " parent:", tick_label.get_parent())
	# --- Ticks ---
	# Tick_label.text = "Server Tick: %s" % network.last_snapshot_tick
	
	# --- Snapshot Age ---
	#age_label.text = "Snapshot Age: %.2f ms" % network.last_snapshot_age_ms
	
	# --- Entities ---
	#entities_label.text = "Entites: %d" % network.last_entity_count
	
	# --- Positions (local player) ---
	#render_pos_label.text = "Render Pos: %s" % str(network.last_render_position)
	#auth_pos_label.text = "Auth Pos: %s" % str(network.last_authoritative_position)
	
	# --- Correction ---
	#correction_label.text = "Correction Δ: %.3f" % network.last_correction_distance
