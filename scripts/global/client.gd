# Modified client.gd
extends Node

var cl_interp_pos_speed: float = 30
var cl_interp_rot_speed: float = 60


func create_client() -> void:
	print("Client: Creating client...")
	
	Network.udpServer = null
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(Network.IP_ADDRESS, Network.PORT)
	
	if error == OK:
		Network.resetTime()
		multiplayer.multiplayer_peer = peer
		Network.udpClient = PacketPeerUDP.new()
		
		var udpError = Network.udpClient.connect_to_host(
			Network.IP_ADDRESS, Network.MOVEMENT_PORT)
		
		if udpError == OK:
			print("Client: Connected to %s" % [Network.IP_ADDRESS])
			client_send_udp_association_packet()
			SignalBus.joined_game.emit(multiplayer.multiplayer_peer.get_unique_id())
		else:
			print("ENet peer %s connected, but the UDP FAILED!!!!" %
			[multiplayer.multiplayer_peer.get_unique_id()])

	else:
		print("Failed to connect: ", error)

func client_process(_delta: float):
	# Process ALL available packets in one frame to prevent buffer buildup
	var packets_processed = 0
	var max_packets_per_frame = 20  # Safety limit
	
	while Network.udpClient.get_available_packet_count() > 0 \
	and packets_processed < max_packets_per_frame:
		
		var array_bytes = Network.udpClient.get_packet()
		var packet_type = array_bytes[0]
		
		match packet_type:
			Network.PacketType.MOVEMENT_UPDATE:
				client_movement_update(array_bytes)
			Network.PacketType.SERVER_CORRECTION:
				client_handle_server_correction(array_bytes)
		
		packets_processed += 1
	
	# Warn if we're getting too many packets
	if packets_processed >= max_packets_per_frame:
		print("Warning: Packet processing limit reached, %d packets remaining" % 
			Network.udpClient.get_available_packet_count())

func client_movement_update(array_bytes: PackedByteArray):
	var offset: int = 1
	
	while offset < array_bytes.size():
		var id: int = array_bytes.decode_var(offset)
		offset += array_bytes.decode_var_size(offset)
		var pos: Vector3 = array_bytes.decode_var(offset)
		offset += array_bytes.decode_var_size(offset)
		var rot: Vector3 = array_bytes.decode_var(offset)
		offset += array_bytes.decode_var_size(offset)
		
		var Chara: CharacterBody3D = get_tree().current_scene.get_node(
			"Players").get_node_or_null(str(id))
		
		if !Chara:
			return
		
		var player: PlayerComponent = Chara.get_node("PlayerComponent")
		if !player:
			return
		
		if id != multiplayer.multiplayer_peer.get_unique_id():
			# For other players, just interpolate to server position
			player.CharacterBody.position = lerp(
				player.CharacterBody.position, pos,  (get_physics_process_delta_time() * cl_interp_pos_speed)
			)
			
			player.CharacterBody.global_rotation = Vector3(
				lerp_angle(player.CharacterBody.rotation.x, rot.x, get_physics_process_delta_time() * cl_interp_rot_speed),
				lerp_angle(player.CharacterBody.rotation.y, rot.y, get_physics_process_delta_time() * cl_interp_rot_speed),
				lerp_angle(player.CharacterBody.rotation.z, rot.z, get_physics_process_delta_time() * cl_interp_rot_speed)
			)
			
			

		else:
			# For local player, only apply if there's a big discrepancy
			# (Most corrections should come via SERVER_CORRECTION packets)
			if player.CharacterBody.position.distance_to(pos) > 5.0:
				print("Emergency position correction: ", player.CharacterBody.position.distance_to(pos))
				player.CharacterBody.position = pos
			DebugDraw3D.draw_sphere(pos)

func client_handle_server_correction(array_bytes: PackedByteArray):
	"""Handle authoritative server corrections for local player"""
	var offset: int = 1
	
	# Decode player ID
	var player_id: int = array_bytes.decode_var(offset)
	offset += array_bytes.decode_var_size(offset)
	
	# Only apply corrections to our own player
	if player_id != multiplayer.multiplayer_peer.get_unique_id():
		return
	
	# Decode server position
	var server_position: Vector3 = array_bytes.decode_var(offset)
	offset += array_bytes.decode_var_size(offset)
	
	# Decode server velocity
	var server_velocity: Vector3 = array_bytes.decode_var(offset)
	offset += array_bytes.decode_var_size(offset)
	
	# Decode sequence number this correction refers to
	var sequence_number: int = array_bytes.decode_var(offset)
	offset += array_bytes.decode_var_size(offset)
	
	# Get our player and apply the correction
	var player: PlayerComponent = get_tree().current_scene.get_node(
		"Players").get_node_or_null(str(player_id)).get_node("PlayerComponent")
	
	if player:
		player.receive_server_correction(
			server_position, 
			server_velocity, 
			sequence_number
		)

func client_send_udp_association_packet():
	var packet = PackedByteArray()
	packet.append(Network.PacketType.CLIENT_ASSOCIATION)
	
	var client_id = multiplayer.get_unique_id()
	packet.append_array(var_to_bytes(client_id))
	
	Network.udpClient.put_packet(packet)
	print("Client: Sent UDP association packet with ENet ID: %s" % client_id)
