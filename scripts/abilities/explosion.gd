extends Ability

@export var shapecast: ShapeCast3D

func client_prediction_start():
	super()

	
	playerComponent.accept_server_corrections = false
	correctionTimer.start()
	shared()

func server_execution_start():
	super()
	shapecast.add_exception(characterBody)
	
	shared()
	
	shapecast.force_shapecast_update()
	
	for body in shapecast.collision_result:
		var character = body["collider"] as CharacterBody3D

		if !character:
			continue
		
		var direction = character.global_position - characterBody.global_position
		direction.y += 1.2
		direction = direction.normalized()

		character.velocity += direction * 10

		if Server.client_state_history.has(int(character.name)) and Server.client_state_history[int(character.name)].size() > 0:
			Server.send_server_correction(
				Network.get_UDP_peer_from_client_id(character.name.to_int()),
				character.name.to_int(),
				character.global_position,
				character.velocity,
				Server.client_state_history[int(character.name)][0]["sequence"],
				true # isImpulse
			)
	

func shared():
	characterBody.velocity = Vector3(0, 1, 0) * 12

func multicast_notif():
	super()

func _ready() -> void:
	super ()
