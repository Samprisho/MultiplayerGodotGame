#player.gd
extends CharacterBody3D
class_name Player

@onready var timer: Timer = $Timer

@export var accelaration: float = 50
@export var constantBraking: float = 10

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree():
	set_multiplayer_authority(name.to_int())

func _ready():
	pass

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	var motion = Vector2(
		Input.get_action_strength("MoveRight") - Input.get_action_strength("MoveLeft"),
		Input.get_action_strength("MoveBackward") - Input.get_action_strength("MoveForward"))
		
	if Network.udpClient and Network.udpClient.is_socket_connected():
		var packet_data = PackedByteArray()
		
		packet_data.append(Network.PacketType.MOVEMENT_INPUT)
		packet_data.append_array(PackedByteArray([int(motion.x), int(motion.y)]))
		
		Network.udpClient.put_packet(packet_data)
	
	
	server_move(delta, motion)

 
func calculate_movement(delta: float, motion: Vector2):
	var calculatedVelocity = Vector3(0,0,0)
	
	# Braking
	calculatedVelocity.x = velocity.x - (velocity.x * delta * constantBraking)
	calculatedVelocity.z = velocity.z - (velocity.z * delta * constantBraking)
	
	# Gravity
	calculatedVelocity.y = velocity.y - (delta * gravity)
	
	var basisX = basis.x * motion.x
	var basisZ = basis.z * motion.y
	var direction = (basisX + basisZ).normalized()
	
	calculatedVelocity += direction * accelaration * delta
	return calculatedVelocity

func server_move(delta: float, motion: Vector2) -> Vector3:
	var velocityToApply = calculate_movement(delta, motion)
	velocity = velocityToApply
	move_and_slide()
	return position
