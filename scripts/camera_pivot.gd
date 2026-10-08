extends Node3D

# GTA-style chase camera: sits low behind the vehicle and swings round
# to follow its heading with a little lag.

# --- Camera Tracking Settings ---
# Assign the bus here in the Inspector.
@export var target_node: CharacterBody3D
# Position follow: smaller = more lag/damping.
@export_range(0.01, 1.0) var smooth_speed: float = 0.2
# Heading follow: smaller = camera swings round more lazily in turns and drifts.
@export_range(0.01, 1.0) var rotation_speed: float = 0.06
# How far above the vehicle's origin the camera aims.
@export var height_offset: float = 1.2

@onready var spring_arm: SpringArm3D = $SpringArm3D

func _ready():
	if target_node:
		# Don't let the spring arm collide with the bus itself.
		spring_arm.add_excluded_object(target_node.get_rid())
		# Start behind the bus instead of swinging round on the first frames.
		global_position = target_node.global_position + Vector3.UP * height_offset
		rotation.y = target_node.global_rotation.y

func _physics_process(_delta: float):
	if target_node:
		# 1. Smoothly drag the pivot to a point just above the bus.
		var target_position = target_node.global_position + Vector3.UP * height_offset
		global_position = global_position.lerp(target_position, smooth_speed)

		# 2. Turn the pivot to match the bus's heading. The spring arm points
		#    out of the pivot's +Z, and the bus drives along -Z, so this keeps
		#    the camera behind it.
		rotation.y = lerp_angle(rotation.y, target_node.global_rotation.y, rotation_speed)
