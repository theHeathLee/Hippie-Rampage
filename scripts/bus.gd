extends CharacterBody3D

# --- Movement Constants ---
const ACCELERATION = 10.0  # How fast the car speeds up
const FRICTION = 8.0     # How fast the car slows down when not accelerating
const TURN_SPEED = 3.0     # How fast the car rotates (in radians per second)
const MAX_SPEED = 10.0   # Top speed (forward and backward)
const GRAVITY = 14.0     # Godot's default 3D gravity value

# --- Variables ---
var speed = 0.0          # Current forward/backward speed
var forward_vector: Vector3 # The direction the car is currently facing

func _ready():
	# Initialize the forward direction to where the car starts facing (usually -Z)
	forward_vector = -transform.basis.z

func _physics_process(delta: float):
	# 1. Apply Gravity (Only affects the Y-axis)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		# Prevents "floating" and ensures the cube firmly sticks to the floor
		velocity.y = move_toward(velocity.y, 0, GRAVITY * delta)

	# 2. Handle Input
	# Uses the custom input names configured in Project Settings
	var throttle = Input.get_axis("move_up", "move_down")   # Forward/Backward (-1.0 to 1.0)
	var steering = Input.get_axis("move_left", "move_right") # Left/Right (-1.0 to 1.0)
	
	# 3. Handle Steering (Rotation)
	if steering != 0.0:
		# Rotate the cube on the Y-axis (yaw)
		# We multiply by -1 to make 'move_right' turn right (positive rotation)
		rotate_y(-steering * TURN_SPEED * delta)
		
		# Update the forward vector based on the new rotation
		forward_vector = -transform.basis.z
	
	# 4. Handle Acceleration/Braking
	if throttle != 0.0:
		# Accelerate based on input and delta time
		speed += throttle * ACCELERATION * delta
		# Clamp the speed to prevent it from exceeding the set max speed
		speed = clamp(speed, -MAX_SPEED, MAX_SPEED) 
	else:
		# Apply friction to smoothly slow the car down when no throttle is applied
		speed = move_toward(speed, 0, FRICTION * delta)

	# 5. Calculate Final Velocity
	# The X and Z velocity components are determined by the current speed 
	# and the direction the cube is facing (forward_vector).
	velocity.x = forward_vector.x * speed
	velocity.z = forward_vector.z * speed
	
	# 6. Execute Movement
	# This is the crucial function that moves the body and handles collisions with the floor.
	move_and_slide()
