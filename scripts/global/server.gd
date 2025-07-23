extends Node

# array structure: time (tick number), motion x, motion y
var recordedMovement: Dictionary = {}
var deltaTime: float = 0

func create_server() -> void:
	print("Creating server")
	
	Network.udpClient = null
	Network.resetTime()
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(Network.PORT, Network.MAX_CLIENTS)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("Server created on port ", Network.PORT)
		start_udp_server()
	else:
		print("Failed to create server: ", error)

func create_listen_server() -> void:
	print("Creating listen server...")
	
	Network.udpClient = null
	
	Network.resetTime()
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(Network.PORT, Network.MAX_CLIENTS)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("Server: Listen server created on port ", Network.PORT)
		start_udp_server()
		# Only spawn the host player - clients will be spawned when they connect
		spawn_player(1)
	else:
		print("Server: Failed to create listen server: ", error)

func server_process(delta: float):
	deltaTime = delta
	
	Network.udpServer.poll()
	if Network.udpServer.is_connection_available():
		var udpPeer: PacketPeerUDP = Network.udpServer.take_connection()
		print("Server: Accepted UDP client: %s:%s" %
			[udpPeer.get_packet_ip(), udpPeer.get_packet_port()])
		Network.udpPeers.append(udpPeer)
	
	for client in Network.udpPeers:
		if client.get_available_packet_count() > 0:
			var array_bytes = client.get_packet()
			server_process_udp_packet(client, array_bytes)
		server_send_current_state_to_client(delta, client)


func start_udp_server():
	print("Server: attempting to start udp server...")
	Network.udpServer = UDPServer.new()
	Network.udpServer.listen(Network.MOVEMENT_PORT)
	print("Server: UDP server on %s:%s up and running" % 
	[Network.IP_ADDRESS, Network.MOVEMENT_PORT])

func server_send_current_state_to_client(delta: float, client: PacketPeerUDP):
	var id: int = Network.get_client_id_from_UDP_peer(client)
	var players: Node = get_tree().current_scene.get_node_or_null("Players")
	
	if !players:
		printerr("COULDN'T FIND PLAYERS NODE")
		return
	
	var packet = PackedByteArray()
	packet.append(Network.PacketType.MOVEMENT_UPDATE)
	for player: Player in players.get_children():
		packet.append_array(var_to_bytes(int(player.name)))
		packet.append_array(var_to_bytes(player.position))
		
	
	client.put_packet(packet)
	

func server_process_udp_packet(
	client: PacketPeerUDP, packet_data: PackedByteArray):
		
	var packet_type = packet_data[0]
	
	match packet_type:
		Network.PacketType.TIME_SYNC:
			server_handle_time_sync(client, packet_data)
		Network.PacketType.MOVEMENT_INPUT:
			server_handle_movement_input(client, packet_data)
		Network.PacketType.CLIENT_ASSOCIATION:
			server_handle_client_association(client, packet_data)

func server_handle_time_sync(
	client: PacketPeerUDP, packet_part: PackedByteArray):
	pass

func server_handle_client_association(
	client: PacketPeerUDP, packet_data: PackedByteArray):
	
	# Extract the client ID from the packet
	var client_id_bytes = packet_data.slice(1)  # Skip the packet type byte
	var client_id = bytes_to_var(client_id_bytes)
	
	# Associate this UDP peer with the client ID
	Network.associate_udp_with_client(client, client_id)
	print("Server: Associated UDP client %s:%s with ENet client %s" % 
		[client.get_packet_ip(), client.get_packet_port(), client_id])

func server_handle_movement_input(
	client: PacketPeerUDP, packet_part: PackedByteArray):
	
	# Get the client ID from the UDP peer
	var client_id = Network.get_client_id_from_UDP_peer(client)
	
	if client_id != -1:
		var motion: Vector2 = Vector2(
			packet_part[1] if packet_part[1] != 255 else -1,
			packet_part[2] if packet_part[2] != 255 else -1,
		)
		# Store movement for this client
		if not recordedMovement.has(client_id):
			recordedMovement[client_id] = []
		recordedMovement[client_id].append({
			"time": Network.serverLobbyTime,
			"motion": motion as Vector2
		})
		
		var player: Player = get_tree().current_scene.get_node(
			"Players").get_node_or_null(str(client_id))
		
		if !player:
			printerr("erm...this player doesn't exist, %s")
		
		player.server_move(deltaTime, motion)
		
	else:
		print("Server: Received movement from unassociated UDP client %s:%s" % 
			[client.get_packet_ip(), client.get_packet_port()])

func spawn_player(id: int):
	if get_node_or_null(str(id)):
		return
	var player = preload("res://scenes/Player.tscn").instantiate()

	get_tree().current_scene.get_node("Players").call_deferred("add_child", player)
	if player:
		player.name = str(id)

func remove_player(id: int):
	print("attempting to remove player %s" % id)
	var player = get_tree().current_scene.get_node_or_null(str(id))
	if player:
		player.queue_free()
	
	# Clean up recorded movement for this player
	if recordedMovement.has(id):
		recordedMovement.erase(id)

func server_send_time_sync():
	if multiplayer.is_server():
		for client in Network.udpPeers:
			var packet : PackedByteArray = PackedByteArray()
			
			packet.append(Network.PacketType.TIME_SYNC)
			packet.append(Network.serverLobbyTime)
			
			client.put_packet(packet)

# Helper function to send data to a specific client via UDP
func send_to_client_udp(client_id: int, packet_data: PackedByteArray):
	var udp_peer = Network.get_UDP_peer_from_client_id(client_id)
	if udp_peer:
		udp_peer.put_packet(packet_data)
	else:
		print("Server: No UDP peer found for client %s" % client_id)
