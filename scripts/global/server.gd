# Modified server.gd
extends Node

# Store client input history for reconciliation
var client_input_history: Dictionary = {}  # client_id -> Array of inputs
var client_state_history: Dictionary = {}  # client_id -> Array of states
var deltaTime: float = 0

# Correction sending frequency (don't send every frame)
var correction_interval: int = 30  # Send corrections every 5 frames
var correction_counter: int = 0

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
		SignalBus.joined_game.emit(0)
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
		spawn_player(1)
		SignalBus.joined_game.emit(1)
	else:
		print("Server: Failed to create listen server: ", error)

func server_process(delta: float):
	deltaTime = delta
	correction_counter += 1
	
	Network.udpServer.poll()
	if Network.udpServer.is_connection_available():
		var udpPeer: PacketPeerUDP = Network.udpServer.take_connection()
		print("Server: Accepted UDP client: %s:%s" %
			[udpPeer.get_packet_ip(), udpPeer.get_packet_port()])
		Network.udpPeers.append(udpPeer)
	
	for client in Network.udpPeers:
		# Process ALL packets from each client
		var packets_processed = 0
		var max_packets = 10
		
		while client.get_available_packet_count() > 0 and packets_processed < max_packets:
			var array_bytes = client.get_packet()
			server_process_udp_packet(client, array_bytes)
			packets_processed += 1
		
		if packets_processed >= max_packets:
			print(
				"Warning: Client sending too many packets: ",
				Network.get_client_id_from_UDP_peer(client)
			)
		
		server_send_current_state_to_client(delta, client)

func start_udp_server():
	print("Server: attempting to start udp server...")
	Network.udpServer = UDPServer.new()
	Network.udpServer.listen(Network.MOVEMENT_PORT)
	print("Server: UDP server on %s:%s up and running" % 
	[Network.IP_ADDRESS, Network.MOVEMENT_PORT])

func server_send_current_state_to_client(_delta: float, client: PacketPeerUDP):
	var players: Node = get_tree().current_scene.get_node_or_null("Players")
	
	if !players:
		printerr("COULDN'T FIND PLAYERS NODE")
		return
	
	var packet = PackedByteArray()
	packet.append(Network.PacketType.MOVEMENT_UPDATE)
	
	for player: CharacterBody3D in players.get_children():
		packet.append_array(var_to_bytes(int(player.name)))
		packet.append_array(var_to_bytes(player.position))
		packet.append_array(var_to_bytes(player.global_rotation))
	
	client.put_packet(packet)

func server_process_udp_packet(client: PacketPeerUDP, packet_data: PackedByteArray):
	var packet_type = packet_data[0]
	
	match packet_type:
		Network.PacketType.TIME_SYNC:
			server_handle_time_sync(client, packet_data)
		Network.PacketType.PLAYER_INPUT:
			server_handle_player_input(client, packet_data)
		Network.PacketType.CLIENT_ASSOCIATION:
			server_handle_client_association(client, packet_data)

func server_handle_time_sync(_client: PacketPeerUDP, _packet_part: PackedByteArray):
	pass

func server_handle_client_association(client: PacketPeerUDP, packet_data: PackedByteArray):
	var client_id_bytes = packet_data.slice(1)
	var client_id = bytes_to_var(client_id_bytes)
	
	Network.associate_udp_with_client(client, client_id)
	
	# Initialize history buffers for this client
	client_input_history[client_id] = []
	client_state_history[client_id] = []
	
	print("Server: Associated UDP client %s:%s with ENet client %s" % 
		[client.get_packet_ip(), client.get_packet_port(), client_id])

func server_handle_player_input(client: PacketPeerUDP, packet_data: PackedByteArray):
	var client_id = Network.get_client_id_from_UDP_peer(client)
	
	if client_id == -1:
		print("Server: Received movement from unassociated UDP client")
		return
	
	var offset = 1
	
	# Decode sequence number
	var sequence_number: int = bytes_to_var(packet_data.slice(offset, offset + 8))
	offset += 8
	
	# Decode motion
	var motion_x = float(packet_data[offset]) / 127.0
	if motion_x > 1.0:
		motion_x = -1
	
	offset += 1
	
	var motion_y = float(packet_data[offset]) / 127.0
	if motion_y > 1.0:
		motion_y = -1
	
	offset += 1
	var motion: Vector2 = Vector2(motion_x, motion_y)
	
	var rotation: Vector3 = bytes_to_var(packet_data.slice(offset, offset + 16)) as Vector3
	offset += 16
	
	var wants_jump: bool = bool(packet_data[offset])
	offset += 1
	
	# Store input in historys
	var input_record = {
		"sequence": sequence_number,
		"motion": motion,
		"rotation": rotation,
		"wants_to_jump": wants_jump,
		"timestamp": Network.serverLobbyTime
	}
	
	if not client_input_history.has(client_id):
		client_input_history[client_id] = []
	client_input_history[client_id].append(input_record)
	
	# Keep only recent history (last 2 seconds)
	var cutoff_time = Network.serverLobbyTime - 120
	while (client_input_history[client_id].size() > 0 and 
		   client_input_history[client_id][0].timestamp < cutoff_time):
		client_input_history[client_id].pop_front()
	
	# Apply movement on server
	var player: PlayerComponent = get_tree().current_scene.get_node("Players")\
	.get_node_or_null(str(client_id)).get_node("PlayerComponent")
	
	if !player:
		printerr("Player doesn't exist: %s" % client_id)
		return
	
	var _old_position = player.CharacterBody.position
	var _old_velocity = player.CharacterBody.velocity
	
	player.CharacterBody.global_rotation = rotation
	
	var player_input = PlayerComponent.PlayerInput.new(
		motion,
		Network.lobbyTime,
		sequence_number,
		rotation,
		wants_jump
	)
	
	player.server_move(deltaTime, player_input)
	
	# Store authoritative state
	var state_record = {
		"sequence": sequence_number,
		"position": player.CharacterBody.position,
		"velocity": player.CharacterBody.velocity,
		"timestamp": Network.serverLobbyTime
	}
	
	if not client_state_history.has(client_id):
		client_state_history[client_id] = []
	client_state_history[client_id].append(state_record)
	
	# Keep only recent state history
	while (client_state_history[client_id].size() > 0 and 
		   client_state_history[client_id][0].timestamp < cutoff_time):
		client_state_history[client_id].pop_front()
	
	# Send correction if needed (not every frame to reduce bandwidth)
	if correction_counter % correction_interval == 0:
		send_server_correction(
			client, 
			client_id, 
			player.CharacterBody.position, 
			player.CharacterBody.velocity, 
			sequence_number
		)

func send_server_correction(
	client: PacketPeerUDP, 
	client_id: int, 
	position: Vector3, 
	velocity: Vector3, 
	sequence: int
	):
	"""Send authoritative correction to client"""
	var packet = PackedByteArray()
	packet.append(Network.PacketType.SERVER_CORRECTION)
	
	# Pack player ID
	packet.append_array(var_to_bytes(client_id))
	
	# Pack server position
	packet.append_array(var_to_bytes(position))
	
	# Pack server velocity
	packet.append_array(var_to_bytes(velocity))
	
	# Pack sequence number this correction refers to
	packet.append_array(var_to_bytes(sequence))
	
	client.put_packet(packet)

func spawn_player(id: int):
	if get_tree().current_scene.get_node("Players").get_node_or_null(str(id)):
		return
		
	var player = preload("res://scenes/Player.tscn").instantiate()
	get_tree().current_scene.get_node("Players")\
	.call_deferred("add_child", player)
	
	if player:
		player.name = str(id)

func remove_player(id: int):
	print("attempting to remove player %s" % id)
	var player = get_tree().current_scene.get_node("Players")\
	.get_node_or_null(str(id))
	
	if player:
		player.queue_free()
	
	# Clean up history for this player
	if client_input_history.has(id):
		client_input_history.erase(id)
	if client_state_history.has(id):
		client_state_history.erase(id)

func send_to_client_udp(client_id: int, packet_data: PackedByteArray):
	var udp_peer = Network.get_UDP_peer_from_client_id(client_id)
	if udp_peer:
		udp_peer.put_packet(packet_data)
	else:
		print("Server: No UDP peer found for client %s" % client_id)
