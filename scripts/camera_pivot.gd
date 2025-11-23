extends Node3D

# --- Camera Tracking Settings ---
# Assign your Cube node here in the Inspector!
@export var target_node: CharacterBody3D 
# Smooth speed: A smaller number = more lag/damping. (e.g., 0.1)
@export_range(0.01, 1.0) var smooth_speed: float = 0.1 

func _physics_process(delta: float):
	if target_node:
		# 1. Calculate the target position
		# We target the cube's position directly.
		var target_position = target_node.global_position

		# 2. Lerp the CameraPivot's position towards the target
		# This smoothly drags the entire camera system (Pivot, SpringArm, Camera)
		global_position = global_position.lerp(target_position, smooth_speed)

		# 3. DO NOT track rotation here. The CameraPivot's rotation remains fixed.
		
		# 4. Manually enforce the camera's angle (to look down at the car).
		# You only need this if the camera's initial rotation was not set, but 
		# it's safer to set the desired angle (e.g., X=-30 degrees) on the CameraPivot node itself.
		# If your CameraPivot's rotation is already fixed, this is unnecessary.extends Node3D
