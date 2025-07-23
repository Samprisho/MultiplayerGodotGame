extends Control

@onready var listen: Button = $HBoxContainer/Listen
@onready var client: Button = $HBoxContainer/Client
@onready var server: Button = $HBoxContainer/Server
@onready var time: Label = $Label

func _ready() -> void:
	listen.pressed.connect(Network.create_listen_server)
	client.pressed.connect(Network.create_client)
	server.pressed.connect(Network.create_server)

func _process(delta: float) -> void:
	time.text = "lobby: %s. Server: %s" % [Network.lobbyTime, Network.serverLobbyTime]
