extends Area3D

var speed = 20.0
var direction = Vector3.FORWARD

func _physics_process(delta):
	# Move forward in the direction it was spawned
	global_position += direction * speed * delta


func _on_body_entered(body):
	if body.is_in_group("player"):
		print("player hit!")
	
	queue_free()
