# Modified player.gd
extends CharacterBody3D
class_name Player

@export var camera: Camera3D
@export var mesh: MeshInstance3D
@export var accelaration: float = 50
@export var constantBraking: float = 10

var state_buffer: Array = []
var input_buffer: Array = []
var buffer_size: int = 120  # 2 seconds at 60fps
var sequence_counter: int = 0
var current_predicted_state: PlayerState

# Reconciliation threshold
var position_tolerance: float = 0.5
var velocity_tolerance: float = 1

# TODO: Make save data for settings
var mouseSensitivity: float = 0.002
var cameraClampLookUp: float = 80

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

## for the record, claude helped me with the player state and input
# stuff, which they made alongside the server correction and client
# side prediction and reconciliation. Yes, yes, I know I can already
# hear you calling me a vibe coder, which is fine, I won't deny that
# I would have taken a lot of time without AI, but I am making sure I understand
# the code written by Claude, besides, they are more than happy to explain it
# to me. I fairly certain I'll have a solid mastery of this topic in maybe
# the next 2 weeks, then I won't need AI for this!

## Who the fuck am I talking to???
# OH MY GOD WAIT...there's an arab funny addon in the aset library
# ...
# finally, something useful

# Client-side prediction data
class PlayerState:
	var position: Vector3
	var velocity: Vector3
	var timestamp: int
	var sequence_number: int
	
	func _init(
		pos: Vector3 = Vector3.ZERO, 
		vel: Vector3 = Vector3.ZERO,
		time: int = 0, 
		seq: int = 0
		):
		
		position = pos
		velocity = vel
		timestamp = time
		sequence_number = seq

class PlayerInput:
	var motion: Vector2
	var rotation: Vector3
	var timestamp: int
	var sequence_number: int
	
	func _init(
		input: Vector2, 
		time: int, 
		seq: int, 
		rot: Vector3
		):
			
		motion = input
		timestamp = time
		sequence_number = seq
		rotation = rot

# Prediction buffers


func _enter_tree():
	set_multiplayer_authority(name.to_int())


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	current_predicted_state = \
		PlayerState.new(global_position, velocity, Network.lobbyTime, 0)
	
	if multiplayer.multiplayer_peer.get_unique_id() == int(name):
		camera.make_current()
		mesh.visible = false

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	
	if event.is_action("Pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if event is InputEventMouseMotion \
	&& Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		
		rotate_y(-event.relative.x * mouseSensitivity)
		camera.rotate_x(-event.relative.y * mouseSensitivity)
		camera.rotation.x = clampf(
			camera.rotation.x, 
			-deg_to_rad(cameraClampLookUp), 
			deg_to_rad(cameraClampLookUp))
			

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	var motion = Vector2(
		Input.get_action_strength("MoveRight") - Input.get_action_strength("MoveLeft"),
		Input.get_action_strength("MoveBackward") - Input.get_action_strength("MoveForward"))
	
	# Create input record with sequence number
	var player_input = PlayerInput.new(motion, Network.lobbyTime, sequence_counter, global_rotation)
	
	# Store input in buffer
	add_to_input_buffer(player_input)
	
	# Send input to server with sequence number
	if Network.udpClient and Network.udpClient.is_socket_connected():
		send_input_to_server(player_input)
	
	# Apply movement locally (client-side prediction) using move_and_slide
	var predicted_state = simulate_movement_with_physics(player_input, delta)
	
	# Store predicted state
	add_to_state_buffer(predicted_state)
	current_predicted_state = predicted_state
	
	sequence_counter += 1
	
	# Clean old data periodically
	if sequence_counter % 60 == 0:  # Every second
		cleanup_old_data()

func simulate_movement_with_physics(
	input: PlayerInput, delta: float) -> PlayerState:
	
	"""Simulate movement using move_and_slide - MUST match server logic exactly"""
	# Store current state to restore later if needed
	var original_pos = global_position
	var original_vel = velocity
	
	# Apply the same movement logic as server_move
	var calculatedVelocity = calculate_movement(delta, input.motion, input.rotation)
	velocity = calculatedVelocity
	move_and_slide()
	
	# Create state record with the result
	var new_state = PlayerState.new(global_position, velocity, input.timestamp, input.sequence_number)
	
	return new_state

func simulate_movement_for_replay(
	state: PlayerState, input: PlayerInput, delta: float) -> PlayerState:
	
	"""Simulate movement for replay - temporarily sets position and velocity"""
	# Temporarily set position and velocity to the replay state
	var original_pos = global_position
	var original_vel = velocity
	
	global_position = state.position
	velocity = state.velocity
	
	# Apply movement
	var calculatedVelocity = calculate_movement(delta, input.motion, input.rotation)
	velocity = calculatedVelocity
	move_and_slide()
	
	# Create new state with results
	var new_state = PlayerState.new(global_position, velocity, input.timestamp, input.sequence_number)
	
	# Don't restore original position - we want to keep the replayed result
	return new_state

func add_to_state_buffer(state: PlayerState):
	state_buffer.append(state)
	if state_buffer.size() > buffer_size:
		state_buffer.pop_front()

func add_to_input_buffer(input: PlayerInput):
	input_buffer.append(input)
	if input_buffer.size() > buffer_size:
		input_buffer.pop_front()

func send_input_to_server(input: PlayerInput):
	var packet_data = PackedByteArray()
	packet_data.append(Network.PacketType.MOVEMENT_INPUT)
	
	# Pack sequence number
	packet_data.append_array(var_to_bytes(input.sequence_number))
	
	# Pack motion (convert to bytes properly)
	var motion_x = int(input.motion.x * 127) if input.motion.x >= 0  \
					else (256 + int(input.motion.x * 127))

	var motion_y = int(input.motion.y * 127) if input.motion.y >= 0 \
					else (256 + int(input.motion.y * 127))
	
	
	packet_data.append(motion_x)
	packet_data.append(motion_y)
	
	packet_data.append_array(var_to_bytes(input.rotation))
	
	Network.udpClient.put_packet(packet_data)

func receive_server_correction(
	server_position: Vector3, server_velocity: Vector3, server_sequence: int):
	
	"""Handle server correction with reconciliation using move_and_slide"""
	
	# Find the state that corresponds to this server correction
	var correction_index = -1
	for i in range(state_buffer.size()):
		if state_buffer[i].sequence_number == server_sequence:
			correction_index = i
			break
	
	if correction_index == -1:
		print("Server correction too old, sequence: ", server_sequence)
		# If too old, just snap to server position as emergency fallback
		global_position = server_position
		velocity = server_velocity
		return
	
	var old_state = state_buffer[correction_index]
	
	# Check if correction is significant enough
	var position_error = old_state.position.distance_to(server_position)
	var velocity_error = old_state.velocity.distance_to(server_velocity)
	
	if position_error < position_tolerance and velocity_error < velocity_tolerance:
		return  # No significant error
	
	print("Applying server correction. Pos error: %.2f, Vel error: %.2f" %
	 [position_error, velocity_error])
	
	# Apply server correction by creating corrected state
	var corrected_state = PlayerState.new(
		server_position, server_velocity, old_state.timestamp, server_sequence)
	state_buffer[correction_index] = corrected_state
	
	# Remove all states after the corrected one (they're now invalid)
	var states_to_remove = state_buffer.size() - correction_index - 1
	for i in range(states_to_remove):
		state_buffer.pop_back()
	
	# Find corresponding input index
	var input_index = -1
	for i in range(input_buffer.size()):
		if input_buffer[i].sequence_number == server_sequence:
			input_index = i
			break
	
	if input_index == -1:
		print("Could not find input for reconciliation")
		global_position = server_position
		velocity = server_velocity
		return
	
	# Set position to corrected server state
	global_position = server_position
	velocity = server_velocity
	
	# Replay all inputs from correction point to present using move_and_slide
	var assumed_delta = 1.0 / 60.0  # Assume 60fps for replay
	
	for i in range(input_index + 1, input_buffer.size()):
		var input_to_replay: PlayerInput = input_buffer[i]
		
		# Apply movement using the same physics
		var calculatedVelocity = \
			calculate_movement(assumed_delta, input_to_replay.motion, input_to_replay.rotation)
			
		velocity = calculatedVelocity
		move_and_slide()
		
		# Store the replayed state
		var replayed_state = PlayerState.new(
			global_position, 
			velocity,
			input_to_replay.timestamp, 
			input_to_replay.sequence_number)
		
		add_to_state_buffer(replayed_state)
	
	# Update our predicted state to match final result
	if state_buffer.size() > 0:
		current_predicted_state = state_buffer[-1]

func cleanup_old_data():
	var cutoff_time = Network.lobbyTime - 120  # Keep 2 seconds of data
	
	# Clean state buffer
	while state_buffer.size() > 0 and state_buffer[0].timestamp < cutoff_time:
		state_buffer.pop_front()
	
	# Clean input buffer  
	while input_buffer.size() > 0 and input_buffer[0].timestamp < cutoff_time:
		input_buffer.pop_front()

func calculate_movement(delta: float, motion: Vector2, rot: Vector3) -> Vector3:
	"""Calculate movement - this MUST match server logic exactly"""
	var calculatedVelocity = Vector3(0, 0, 0)
	
	# Braking
	calculatedVelocity.x = velocity.x - (velocity.x * delta * constantBraking)
	calculatedVelocity.z = velocity.z - (velocity.z * delta * constantBraking)
	
	# Gravity
	calculatedVelocity.y = velocity.y - (delta * gravity)
	
	var inputRot = rot.y
	
	var basisX = Vector3.RIGHT.rotated(up_direction, inputRot) * motion.x
	var basisZ = Vector3.FORWARD.rotated(up_direction, inputRot) * -motion.y
	var direction = (basisX + basisZ).normalized()
	
	calculatedVelocity += direction * accelaration * delta
	return calculatedVelocity

func server_move(delta: float, motion: Vector2, rot: Vector3) -> Vector3:
	"""Server-side movement - uses the same logic as client prediction"""
	var velocityToApply = calculate_movement(delta, motion, rot)
	velocity = velocityToApply
	move_and_slide()
	return position
