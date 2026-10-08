extends StaticBody3D

@export var particles_debris: PackedScene


func _on_area_3d_body_entered(body:Node3D) -> void:
    if body.is_in_group("player"):
        var debris = particles_debris.instantiate()
        get_tree().current_scene.add_child(debris)
        debris.global_position = global_position
        debris.emitting = true
        queue_free()
