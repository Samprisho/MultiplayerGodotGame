extends Control

@onready var listen: Button = $HBoxContainer/Listen
@onready var client: Button = $HBoxContainer/Client
@onready var server: Button = $HBoxContainer/Server
@onready var time: Label = $Label

func _ready() -> void:
	listen.pressed.connect(Network.create_listen_server)
	client.pressed.connect(Network.create_client)
	server.pressed.connect(Network.create_server)
	
	SignalBus.joined_game.connect(on_joined_game)
func _process(_delta: float) -> void:
	time.text = "lobby: %s. Server: %s" % [Network.lobbyTime, Network.serverLobbyTime]

func on_joined_game(_id: int) -> void:
	$HBoxContainer.visible = false
