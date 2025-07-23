#network.gd
extends Node
 
const IP_ADDRESS = "127.0.0.1"
const PORT = 9000
const MAX_CLIENTS = 12

const MOVEMENT_PORT = 8089

# Maps UDP remote port (as seen by server) to ENet client ID
var MapUDPToClient: Dictionary = {}
# Maps ENet client ID to UDP peer object
var MapClientToUDP: Dictionary = {}

var udpServer: UDPServer
# AKA, the clients connected to the server
var udpPeers: Array[PacketPeerUDP] = []

var udpClient: PacketPeerUDP

var serverLobbyTime: int = 0
var lobbyTime: int = 0

enum PacketType {
	TIME_SYNC,
	MOVEMENT_INPUT,
	MOVEMENT_UPDATE,
	CLIENT_ASSOCIATION,
}

func create_client() -> void:
	Client.create_client()

func create_server() -> void:
	Server.create_server()

func create_listen_server() -> void:
	Server.create_listen_server()

func _ready() -> void:
	multiplayer.connected_to_server.connect(_client_connected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _physics_process(delta: float) -> void:
	lobbyTime += 1
	
	if multiplayer.is_server():
		serverLobbyTime += 1
	
	# If we are a client, process info from server
	if udpClient and udpClient.is_socket_connected():
		Client.client_process(delta)
	
	# REEAAALLLY trying to make sure that only the server listens from clients
	if udpServer and udpServer.is_listening() and multiplayer.is_server():
		Server.server_process(delta)

func _process(delta: float) -> void:
	pass

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
	
	# Only the server should spawn players for new connections
	if multiplayer.is_server():
		Server.spawn_player(id)

func _on_peer_disconnected(id: int):
	print("Peer disconnected: ", id)
	
	# Clean up UDP associations for this client
	if multiplayer.is_server():
		var udp_peer = MapClientToUDP.get(id)
		if udp_peer:
			var remote_port = udp_peer.get_packet_port()
			MapUDPToClient.erase(remote_port)
			MapClientToUDP.erase(id)
	
	Server.remove_player(id)
	
func _client_connected():
	print("I've connected")

func resetTime():
	lobbyTime = 0
	serverLobbyTime = 0

func get_client_id_from_UDP_peer(udp_peer: PacketPeerUDP) -> int:
	var remote_port = udp_peer.get_packet_port()
	return MapUDPToClient.get(remote_port, -1)

func get_UDP_peer_from_client_id(client_id: int) -> PacketPeerUDP:
	return MapClientToUDP.get(client_id, null)

func associate_udp_with_client(udp_peer: PacketPeerUDP, client_id: int):
	var remote_port = udp_peer.get_packet_port()
	
	# Store both mappings for easy lookup
	MapUDPToClient[remote_port] = client_id
	MapClientToUDP[client_id] = udp_peer
	
	print("Server: Associated UDP remote port %s with client ID %s" % [remote_port, client_id])
