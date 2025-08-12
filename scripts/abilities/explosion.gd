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
		direction.y += 0.7
		direction = direction.normalized()


		character.velocity += direction * 10
	

func shared():
	characterBody.velocity = Vector3(0, 1, 0) * 12

func _ready() -> void:
	super()
	
