extends Control

@onready var listen: Button = $CanvasLayer/HBoxContainer/Listen
@onready var client: Button = $CanvasLayer/HBoxContainer/Client
@onready var server: Button = $CanvasLayer/HBoxContainer/Server
@onready var dummy: Button = $CanvasLayer/HBoxContainer/DummyClient
@onready var time: Label = $CanvasLayer/Label

func _ready() -> void:
	listen.pressed.connect(Network.create_listen_server)
	client.pressed.connect(Network.create_client)
	server.pressed.connect(Network.create_server)
	dummy.pressed.connect(Network.create_dummy_client)
	
	SignalBus.joined_game.connect(on_joined_game)
func _process(_delta: float) -> void:
	time.text = "lobby: %s. Server: %s" % [Network.lobbyTime, Network.serverLobbyTime]

func on_joined_game(_id: int) -> void:
	$CanvasLayer/HBoxContainer.visible = false
