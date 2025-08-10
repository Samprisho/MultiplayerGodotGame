extends Node
class_name Ability

@export var characterBody: CharacterBody3D
@export var playerComponent: PlayerComponent
@export var inputs: Array[String]

func can_activate() -> bool:
	return true

func client_activate():
	if !can_activate():
		return

	print("Client ",  multiplayer.get_unique_id(), " rpc to server")
	rpc("owner_client_rpc_server")

func server_activate():
	pass

@rpc("any_peer", "call_local", "unreliable_ordered")
func multicast_activate(id: int):
	# We only want to run this on every other client
	if multiplayer.get_unique_id() == multiplayer.get_remote_sender_id() \
		or id == multiplayer.get_unique_id():
		return
	

	print("Multi cast to: ", multiplayer.get_unique_id(), " from ", id)

@rpc("any_peer", "call_local", "unreliable_ordered")
func owner_client_rpc_server():
	if multiplayer.is_server():
		print("I'm the server, I recieved this rpc from: ", multiplayer.get_remote_sender_id())
		rpc("multicast_activate", multiplayer.get_remote_sender_id())
