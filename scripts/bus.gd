extends CharacterBody3D

# --- Movement Constants ---
const ACCELERATION = 10.0
const FRICTION = 8.0
const TURN_SPEED = 3.0
const MAX_SPEED = 10.0       # Normal Top speed
const GRAVITY = 14.0

# --- Boost Constants ---
const BOOST_ACCELERATION = 40.0
const BOOST_MAX_SPEED = 25.0
const BOOST_DECAY_RATE = 10.0 # Controls smoothness of speed limit decay

# --- Handbrake/Drift Constants ---
const DRIFT_FRICTION = 0.1   # Lower for more fishtailing
const DRIFT_TURN_SPEED = 2.5 # Higher for more aggressive rotation
const BRAKE_DECELERATION = 15.0
const TRACTION_REGAIN_RATE = 8.0 # Controls how fast side momentum decays after drift

# --- Variables ---
var speed = 0.0          # Current forward/backward speed
var forward_vector: Vector3 # The direction the car is currently facing
var is_drifting = false
var current_limit = 0.0  # The current effective top speed (smoothly interpolated)
var lateral_velocity = Vector3.ZERO # Stores side momentum for decay

# --- Audio References ---
@onready var engine_sound: AudioStreamPlayer3D = $enginesound
@onready var drift_sound: AudioStreamPlayer3D = $driftsound
@onready var boost_sound: AudioStreamPlayer3D = $boostsound

func _ready():
	# Initialize the direction and speed limit
	forward_vector = -transform.basis.z
	current_limit = MAX_SPEED 

func _physics_process(delta: float):
	# Check for Handbrake/Boost Input
	is_drifting = Input.is_action_pressed("move_handbrake")
	var is_boosting = Input.is_action_pressed("move_boost") 

	# 1. Capture Lateral Velocity
	var side_vector = transform.basis.x
	
	if is_drifting:
		# If drifting, capture the current side momentum for later use
		lateral_velocity = side_vector * velocity.dot(side_vector)
	
	# 2. Apply Gravity (Only affects the Y-axis)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = move_toward(velocity.y, 0, GRAVITY * delta)

	# 3. Handle Input
	var throttle = Input.get_axis("move_up", "move_down")
	var steering = Input.get_axis("move_left", "move_right")
	
	# 4. Apply Forces based on State
	if is_drifting:
		handle_drift_movement(throttle, steering, delta)
	else:
		handle_normal_movement(throttle, steering, delta, is_boosting)

	# 5. Engine Sound Control
	if abs(speed) > 0.5:
		if not engine_sound.is_playing():
			engine_sound.play()
		# Adjust pitch based on absolute speed (prevents pitch dropping when reversing)
		var pitch_scale = 0.8 + abs(speed) / MAX_SPEED * 1.2
		engine_sound.pitch_scale = clamp(pitch_scale, 0.8, 2.0)
	elif engine_sound.is_playing():
		engine_sound.stop()

	# 6. Execute Movement
	move_and_slide()

# --- Separate Functions for Clarity ---

func handle_normal_movement(throttle: float, steering: float, delta: float, is_boosting: bool):
	
	# Stop drift sound if it was playing (leaving drift state)
	if drift_sound.is_playing():
		drift_sound.stop()
		
	# Determine the acceleration rate and target max speed limit
	var current_accel = ACCELERATION
	var target_limit = MAX_SPEED
	
	if is_boosting:
		# Start boost sound
		if not boost_sound.is_playing():
			boost_sound.play()
			
		current_accel = BOOST_ACCELERATION
		target_limit = BOOST_MAX_SPEED
	elif boost_sound.is_playing():
		boost_sound.stop()
	
	# Interpolate the current speed limit towards the target limit (smooth boost decay)
	current_limit = lerp(current_limit, target_limit, BOOST_DECAY_RATE * delta)
	
	# Normal Steering
	if steering != 0.0:
		rotate_y(-steering * TURN_SPEED * delta)
		forward_vector = -transform.basis.z
	
	# Acceleration/Friction
	if throttle != 0.0:
		speed += throttle * current_accel * delta
		# Clamp speed using the smoothly changing current_limit
		speed = clamp(speed, -current_limit, current_limit) 
	else:
		speed = move_toward(speed, 0, FRICTION * delta)

	# Normal Velocity Calculation (Movement only on X and Z axes)
	velocity.x = forward_vector.x * speed
	velocity.z = forward_vector.z * speed
	
	# Smooth Traction Regain (FIX for instant snapping)
	if lateral_velocity.length_squared() > 0.01:
		# Decay the lateral velocity over time (smoothly regaining traction)
		lateral_velocity = lateral_velocity.lerp(Vector3.ZERO, TRACTION_REGAIN_RATE * delta)
	else:
		lateral_velocity = Vector3.ZERO

	# Apply the remaining side momentum to the total velocity
	velocity += lateral_velocity


func handle_drift_movement(throttle: float, steering: float, delta: float):
	
	# Play drift sound if it's not already playing and the car is moving
	if not drift_sound.is_playing() and abs(speed) > 0.5:
		drift_sound.play()
		
	# Stop boost sound if it was playing
	if boost_sound.is_playing():
		boost_sound.stop()
		
	# 1. Drastically Slow Down (Brake)
	speed = move_toward(speed, 0, BRAKE_DECELERATION * delta)
	
	# 2. Apply Drift Steering (Uses the increased DRIFT_TURN_SPEED for fishtailing)
	if steering != 0.0:
		rotate_y(-steering * DRIFT_TURN_SPEED * delta)
		forward_vector = -transform.basis.z
		
	# 3. Velocity Calculation
	
	var current_vel_xz = Vector3(velocity.x, 0, velocity.z)
	
	# Rapidly pull the velocity towards the cube's forward direction (braking effect)
	velocity.x = move_toward(velocity.x, forward_vector.x * speed, BRAKE_DECELERATION * delta)
	velocity.z = move_toward(velocity.z, forward_vector.z * speed, BRAKE_DECELERATION * delta)

	# Apply low friction to lateral motion (allows sliding/fishtailing)
	var side_vector = transform.basis.x 
	velocity -= side_vector * current_vel_xz.dot(side_vector) * DRIFT_FRICTION * delta
