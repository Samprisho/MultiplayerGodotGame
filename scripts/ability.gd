extends Node
class_name Ability

var characterBody: CharacterBody3D
var playerComponent: PlayerComponent

@export var cost: int = 10
@export var inputs: Array[String]

var correctionTimer: Timer = Timer.new()
var correctionInterval: float = 1.5

var isActive: bool = false

func can_activate() -> bool:
	return true

func should_end() -> bool:
	return false

func local_request_activate():
	if !can_activate():
		return

	rpc("owner_client_rpc_server")

	client_prediction_start()

@rpc("any_peer", "call_local", "reliable")
func owner_client_rpc_server():
	if multiplayer.is_server():
		if can_activate():
			server_execution_start()
			rpc("multicast_activate", multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_local", "reliable")
func multicast_activate(id: int):
	# We only want to run this on every other client
	if multiplayer.get_unique_id() == multiplayer.get_remote_sender_id() or \
	 id == multiplayer.get_unique_id():
		return

	multicast_notif()


func client_prediction_start():
	isActive = true

func client_prediction_logic(_delta = 0.0):
	if should_end() || not isActive:
		client_prediction_end()
		return

func client_prediction_end():
	isActive = false

func server_execution_start():
	isActive = true

func server_execution_logic(_delta = 0.0):
	if should_end() || not isActive:
		server_execution_end()
		return
	

func server_execution_end():
	isActive = false

func multicast_notif():
	pass

func _physics_process(delta: float) -> void:
	if not isActive:
		return
	
	if multiplayer.is_server():
		server_execution_logic(delta)
	else:
		client_prediction_logic(delta)

func _ready() -> void:
	# Initialize the correction timer
	correctionTimer.wait_time = correctionInterval
	correctionTimer.one_shot = false
	correctionTimer.timeout.connect(_on_correction_timer_timeout)
	add_child(correctionTimer)

func _on_correction_timer_timeout():
	# Send a correction request to the server
	playerComponent.accept_server_corrections = true
