extends CharacterBody3D

# --- Movement Constants ---
const ACCELERATION = 10.0
const FRICTION = 8.0
const MAX_SPEED = 10.0
const GRAVITY = 14.0

# Steering: max turn rate reached at full speed. Car cannot turn in place.
const TURN_SPEED = 2.5
# Traction: how fast the velocity direction snaps to the facing direction (grip).
const TRACTION = 7.0

# --- Boost Constants ---
const BOOST_ACCELERATION = 40.0
const BOOST_MAX_SPEED = 25.0
const BOOST_DECAY_RATE = 10.0

# --- Drift Constants ---
# Low traction during drift so the car slides sideways (skid/fishtail).
const DRIFT_TRACTION = 1.2
const DRIFT_TURN_SPEED = 3.5
const BRAKE_DECELERATION = 12.0

# --- Variables ---
var speed = 0.0
var is_drifting = false
var current_limit = 0.0

# --- Audio References ---
@onready var engine_sound: AudioStreamPlayer3D = $enginesound
@onready var drift_sound: AudioStreamPlayer3D = $driftsound
@onready var boost_sound: AudioStreamPlayer3D = $boostsound

func _ready():
	current_limit = MAX_SPEED

func _physics_process(delta: float):
	is_drifting = Input.is_action_pressed("move_handbrake")
	var is_boosting = Input.is_action_pressed("move_boost")

	# Gravity — only dampen Y on flat ground; on slopes let move_and_slide handle it
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		var floor_normal = get_floor_normal()
		if floor_normal.y > 0.95:
			velocity.y = move_toward(velocity.y, 0, GRAVITY * delta)

	var throttle = Input.get_axis("move_up", "move_down")
	var steering = Input.get_axis("move_left", "move_right")

	if is_drifting:
		handle_drift_movement(throttle, steering, delta)
	else:
		handle_normal_movement(throttle, steering, delta, is_boosting)

	# Engine Sound
	if abs(speed) > 0.5:
		if not engine_sound.is_playing():
			engine_sound.play()
		var pitch_scale = 0.8 + abs(speed) / MAX_SPEED * 1.2
		engine_sound.pitch_scale = clamp(pitch_scale, 0.8, 2.0)
	elif engine_sound.is_playing():
		engine_sound.stop()

	move_and_slide()

# --- Movement Functions ---

func handle_normal_movement(throttle: float, steering: float, delta: float, is_boosting: bool):
	if drift_sound.is_playing():
		drift_sound.stop()

	var current_accel = ACCELERATION
	var target_limit = MAX_SPEED

	if is_boosting:
		if not boost_sound.is_playing():
			boost_sound.play()
		current_accel = BOOST_ACCELERATION
		target_limit = BOOST_MAX_SPEED
	elif boost_sound.is_playing():
		boost_sound.stop()

	current_limit = lerp(current_limit, target_limit, BOOST_DECAY_RATE * delta)

	# Acceleration / friction
	if throttle != 0.0:
		speed += throttle * current_accel * delta
		speed = clamp(speed, -current_limit, current_limit)
	else:
		speed = move_toward(speed, 0, FRICTION * delta)

	# Speed-dependent steering: turn rate scales with how fast we're moving.
	# This prevents turning in place — the bus must be moving to steer.
	var horiz_speed = Vector3(velocity.x, 0, velocity.z).length()
	var speed_factor = clamp(horiz_speed / MAX_SPEED, 0.0, 1.0)
	if abs(steering) > 0.01 and speed_factor > 0.02:
		var steer_dir = sign(speed) if abs(speed) > 0.1 else 1.0
		rotate_y(steering * TURN_SPEED * speed_factor * steer_dir * delta)

	# Traction: blend current velocity toward the facing direction.
	# On slopes, project the desired velocity along the floor so the bus rides up naturally.
	var forward = -transform.basis.z
	var desired = Vector3(forward.x * speed, 0.0, forward.z * speed)
	if is_on_floor():
		var floor_normal = get_floor_normal()
		if floor_normal.y < 0.99:
			desired = desired.slide(floor_normal)
	velocity.x = lerp(velocity.x, desired.x, TRACTION * delta)
	velocity.z = lerp(velocity.z, desired.z, TRACTION * delta)
	if is_on_floor() and get_floor_normal().y < 0.99:
		velocity.y = lerp(velocity.y, desired.y, TRACTION * delta)


func handle_drift_movement(throttle: float, steering: float, delta: float):
	if not drift_sound.is_playing() and abs(speed) > 0.5:
		drift_sound.play()
	if boost_sound.is_playing():
		boost_sound.stop()

	# Allow throttle while drifting (helps sustain the slide)
	if throttle != 0.0:
		speed += throttle * ACCELERATION * delta
		speed = clamp(speed, -MAX_SPEED, MAX_SPEED)
	else:
		speed = move_toward(speed, 0, BRAKE_DECELERATION * delta)

	# Drift steering still requires movement, but is more aggressive
	var horiz_speed = Vector3(velocity.x, 0, velocity.z).length()
	var speed_factor = clamp(horiz_speed / MAX_SPEED, 0.0, 1.0)
	if abs(steering) > 0.01 and speed_factor > 0.02:
		var steer_dir = sign(speed) if abs(speed) > 0.1 else 1.0
		rotate_y(steering * DRIFT_TURN_SPEED * speed_factor * steer_dir * delta)

	# Low traction: velocity only weakly follows the new heading, causing the slide.
	var forward = -transform.basis.z
	var desired = Vector3(forward.x * speed, 0.0, forward.z * speed)
	if is_on_floor():
		var floor_normal = get_floor_normal()
		if floor_normal.y < 0.99:
			desired = desired.slide(floor_normal)
	velocity.x = lerp(velocity.x, desired.x, DRIFT_TRACTION * delta)
	velocity.z = lerp(velocity.z, desired.z, DRIFT_TRACTION * delta)
	if is_on_floor() and get_floor_normal().y < 0.99:
		velocity.y = lerp(velocity.y, desired.y, DRIFT_TRACTION * delta)
