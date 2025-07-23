extends Node

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
			# Send a UDP packet to establish the connection and let server know our ENet ID
			client_send_udp_association_packet()
		else:
			print("ENet peer %s connected, but the UDP FAILED!!!!" %
			[multiplayer.multiplayer_peer.get_unique_id()])

	else:
		print("Failed to connect: ", error)

func client_process(delta: float):
	if Network.udpClient.get_available_packet_count() > 0:
		var array_bytes = Network.udpClient.get_packet()
		
		var packet_type = array_bytes[0]
		
		match packet_type:
			Network.PacketType.MOVEMENT_UPDATE:
				client_movement_update(array_bytes)

func client_movement_update(array_bytes: PackedByteArray):
	var offset: int = 1
	
	while offset < array_bytes.size():
		var id: int = array_bytes.decode_var(offset)
		offset += array_bytes.decode_var_size(offset)
		var pos: Vector3 = array_bytes.decode_var(offset)
		offset += array_bytes.decode_var_size(offset)
		
		# an int has 8 bytes (64 bits / 8 buts)
		# a vector has 16 bytes
		# so we offset by 24
		
		var player: Player = get_tree().current_scene.get_node(
			"Players").get_node_or_null(str(id))
		
		if player:
			if id != multiplayer.multiplayer_peer.get_unique_id():
				DebugDraw3D.draw_sphere(pos, 0.5, Color.RED)
				player.position = lerp(
					player.position, pos, get_physics_process_delta_time() * 12)
				
			else:
				if player.position.distance_to(pos) > 10:
					player.position = pos
				DebugDraw3D.draw_sphere(pos)

func client_send_udp_association_packet():
	# Send a special UDP packet that includes our ENet ID
	var packet = PackedByteArray()
	packet.append(Network.PacketType.CLIENT_ASSOCIATION)
	
	# Add our ENet multiplayer ID to the packet
	var client_id = multiplayer.get_unique_id()
	packet.append_array(var_to_bytes(client_id))
	
	Network.udpClient.put_packet(packet)
	print("Client: Sent UDP association packet with ENet ID: %s" % client_id)
