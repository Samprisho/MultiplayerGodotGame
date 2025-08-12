extends Node
class_name Ability

var characterBody: CharacterBody3D
var playerComponent: PlayerComponent

@export var cost: int = 10
@export var inputs: Array[String]

var correctionTimer: Timer = Timer.new()
var correctionInterval: float = 0.5

var isActive: bool = false

func can_activate() -> bool:
	return true

func should_end() -> bool:
	return false

func local_request_activate():
	if !can_activate():
		return

	print("Client ",  multiplayer.get_unique_id(), " rpc to server")
	rpc("owner_client_rpc_server")

	client_prediction_start()

@rpc("any_peer", "call_local", "unreliable_ordered")
func owner_client_rpc_server():
	if multiplayer.is_server():
		print("I'm the server, I recieved this rpc from: ", multiplayer.get_remote_sender_id())
		if can_activate():
			print("Server activating ability for client: ", multiplayer.get_remote_sender_id())
			server_execution_start()
			rpc("multicast_activate", multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_local", "unreliable_ordered")
func multicast_activate(id: int):
	# We only want to run this on every other client
	if multiplayer.get_unique_id() == multiplayer.get_remote_sender_id() or \
	 id == multiplayer.get_unique_id():
		return

	print("Multi cast to: ", multiplayer.get_unique_id(), " from ", id)
	server_execution_start()

func client_prediction_start():
	isActive = true

func client_prediction_logic(_delta = 0.0):
	
	if should_end() || not isActive:
		print("Ending ability prediction for client: ", multiplayer.get_unique_id())
		client_prediction_end()
		return

func client_prediction_end():
	isActive = false

func server_execution_start():
	isActive = true

func server_execution_logic(_delta = 0.0):
	
	if should_end() || not isActive:
		print("Ending ability execution for server")
		server_execution_end()
		return
	

func server_execution_end():
	isActive = false

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
