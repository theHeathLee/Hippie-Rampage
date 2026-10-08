extends StaticBody3D

# A ramp that gives the bus a free burst of speed when it drives onto it.

func _ready():
	$BoostZone.body_entered.connect(_on_boost_zone_body_entered)

func _on_boost_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("ramp_boost"):
		body.ramp_boost()
