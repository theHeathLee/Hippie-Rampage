extends RigidBody3D

var speed = 2.0
var walking = true
@onready var death_timer: Timer = $DeathTimer


func _physics_process(delta):
	if walking and freeze:
		global_position += -global_transform.basis.z * speed * delta


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.is_in_group("enemy"):
		var dir = (global_position - body.global_position).normalized()
		freeze = false
		apply_central_impulse(dir * 15.0 + Vector3.UP * 5.0)
		
		if body.is_in_group("player"):
			Score.add_hit()
			
		# We use a random vector so they don't always spin the same way
		#var random_spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		#apply_torque_impulse(random_spin * 20.0)
		
		#death_timer.start()


func _on_death_timer_timeout() -> void:
	queue_free()
