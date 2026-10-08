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
# Boost meter: filled by drifting, drained by boosting.
const BOOST_MAX = 100.0
const BOOST_DRAIN_RATE = 33.0      # meter per second while boosting (~3 s from full)
const DRIFT_CHARGE_RATE = 6.0      # meter per second, per m/s of sideways slide

# --- Drift Constants ---
# Low traction during drift so the car slides sideways (skid/fishtail).
const DRIFT_TRACTION = 1.2
const DRIFT_TURN_SPEED = 3.5
const BRAKE_DECELERATION = 12.0

# --- Ramp / Slope Constants ---
# Driving over a boost ramp gives a free burst of speed for this long.
const RAMP_BOOST_TIME = 1.0
# Steepest surface the bus can drive on (half pipe walls go up to ~78 degrees).
const MAX_FLOOR_ANGLE = 80.0
# How quickly the bus tilts to match the surface under it, and back to level in the air.
const TILT_SPEED_GROUND = 12.0
const TILT_SPEED_AIR = 2.0
# Leaving a surface steeper than this while going up counts as launching off
# a half pipe wall: the bus goes straight up and spins round to drop back in.
const VERT_LAUNCH_NORMAL_Y = 0.5   # floor normal y; 0.5 = 60 degrees
# Small push back into the pipe on a vert launch, so the bus (2 long) lands
# on the wall rather than perched on the lip.
const VERT_LAUNCH_INWARD_SPEED = 1.5

# --- Push Constants ---
# How hard the bus shoves loose physics objects (rubble, knocked-over rednecks), per unit of speed.
const PUSH_STRENGTH = 0.15

# --- Variables ---
var speed = 0.0
var is_drifting = false
# True only while actually boosting (button held, meter not empty, not drifting).
# Buildings check this to decide whether to collapse.
var is_boosting = false
var boost_meter = 0.0
var _ramp_boost_timer = 0.0
var _was_on_floor = true
var _last_floor_normal = Vector3.UP
var _air_spin_left = 0.0
var _air_spin_rate = 0.0
var _tilt = Quaternion.IDENTITY
var _mesh_rest: Transform3D
var _collider_rest: Transform3D
var current_limit = 0.0

# --- Audio References ---
@onready var engine_sound: AudioStreamPlayer3D = $enginesound
@onready var drift_sound: AudioStreamPlayer3D = $driftsound
@onready var boost_sound: AudioStreamPlayer3D = $boostsound
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collider: CollisionShape3D = $collider

func _ready():
	current_limit = MAX_SPEED
	floor_max_angle = deg_to_rad(MAX_FLOOR_ANGLE)
	# Hug curved surfaces like the half pipe instead of skipping off them.
	floor_snap_length = 0.4
	_mesh_rest = mesh.transform
	_collider_rest = collider.transform

# Called by boost ramps: a free burst of speed that doesn't use the boost meter.
func ramp_boost():
	_ramp_boost_timer = RAMP_BOOST_TIME
	current_limit = BOOST_MAX_SPEED
	if speed >= 0.0:
		speed = max(speed, BOOST_MAX_SPEED * 0.8)
	else:
		speed = min(speed, -BOOST_MAX_SPEED * 0.8)

func _physics_process(delta: float):
	is_drifting = Input.is_action_pressed("move_handbrake")
	is_boosting = Input.is_action_pressed("move_boost") and not is_drifting and boost_meter > 0.0
	if is_boosting:
		boost_meter = max(boost_meter - BOOST_DRAIN_RATE * delta, 0.0)

	# Gravity — only dampen Y on flat ground; on slopes let move_and_slide handle it
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		var floor_normal = get_floor_normal()
		if floor_normal.y > 0.95:
			velocity.y = move_toward(velocity.y, 0, GRAVITY * delta)

	_ramp_boost_timer = max(_ramp_boost_timer - delta, 0.0)
	apply_slope_physics(delta)

	# Forward is -Z: up gives positive speed, right gives a clockwise (negative) yaw.
	var throttle = Input.get_axis("move_down", "move_up")
	var steering = Input.get_axis("move_right", "move_left")

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
	push_loose_bodies()
	tilt_to_surface(delta)

	# Drifting charges the boost meter: the harder the bus slides sideways, the faster it fills.
	if is_drifting and is_on_floor():
		var slide_speed = abs(velocity.dot(global_basis.x))
		boost_meter = min(boost_meter + slide_speed * DRIFT_CHARGE_RATE * delta, BOOST_MAX)

# Keep `speed` honest on slopes and in the air, so the bus slows climbing,
# rolls back down steep walls, and lands with the speed it actually has.
func apply_slope_physics(delta: float):
	var forward = -global_basis.z
	if is_on_floor():
		var floor_normal = get_floor_normal()
		var forward_on_floor = forward.slide(floor_normal).normalized()
		if not _was_on_floor:
			# Just landed: carry over the real velocity along the surface.
			speed = velocity.dot(forward_on_floor)
		# Gravity pulls the bus back down the slope it's facing.
		speed += GRAVITY * Vector2(floor_normal.x, floor_normal.z).dot(Vector2(forward.x, forward.z)) * delta
		_last_floor_normal = floor_normal
		_air_spin_left = 0.0
	else:
		if _was_on_floor and _last_floor_normal.y < VERT_LAUNCH_NORMAL_Y and velocity.y > 0.0:
			vert_launch()
		if _air_spin_left > 0.0:
			var step = min(_air_spin_rate * delta, _air_spin_left)
			rotate_y(step)
			_air_spin_left -= step
			forward = -global_basis.z
		# In the air, speed follows the actual horizontal velocity.
		speed = Vector2(velocity.x, velocity.z).dot(Vector2(forward.x, forward.z))
	_was_on_floor = is_on_floor()

# Launching off the top of a half pipe wall: swap the momentum carrying the
# bus out over the lip for a small push back in, so it goes up and drops back
# onto the wall, and spin it 180 degrees in the air so it lands facing down.
func vert_launch():
	var outward = Vector3(-_last_floor_normal.x, 0.0, -_last_floor_normal.z).normalized()
	velocity -= outward * (velocity.dot(outward) + VERT_LAUNCH_INWARD_SPEED)
	var air_time = max(2.0 * velocity.y / GRAVITY, 0.3)
	_air_spin_left = PI
	_air_spin_rate = PI / (air_time * 0.8)

# Tilt the body mesh and collider to sit flat on ramps and half pipe walls.
# The body itself only ever yaws, so steering and the camera are unaffected.
func tilt_to_surface(delta: float):
	var target_up = get_floor_normal() if is_on_floor() else Vector3.UP
	var local_up = (global_basis.inverse() * target_up).normalized()
	var target = Quaternion(Vector3.UP, local_up)
	var rate = TILT_SPEED_GROUND if is_on_floor() else TILT_SPEED_AIR
	_tilt = _tilt.slerp(target, min(rate * delta, 1.0))
	var tilt_transform = Transform3D(Basis(_tilt), Vector3.ZERO)
	mesh.transform = tilt_transform * _mesh_rest
	collider.transform = tilt_transform * _collider_rest

# Shove unfrozen rigid bodies out of the way instead of stopping dead against them.
func push_loose_bodies():
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		if body is RigidBody3D and not body.freeze:
			body.apply_central_impulse(-collision.get_normal() * abs(speed) * PUSH_STRENGTH * body.mass)

# --- Movement Functions ---

func handle_normal_movement(throttle: float, steering: float, delta: float, boosting: bool):
	if drift_sound.is_playing():
		drift_sound.stop()

	var current_accel = ACCELERATION
	var target_limit = MAX_SPEED

	if boosting or _ramp_boost_timer > 0.0:
		if not boost_sound.is_playing():
			boost_sound.play()
		current_accel = BOOST_ACCELERATION
		target_limit = BOOST_MAX_SPEED
	elif boost_sound.is_playing():
		boost_sound.stop()

	current_limit = lerp(current_limit, target_limit, BOOST_DECAY_RATE * delta)

	# Acceleration / friction. Coasting friction only on near-flat ground, so the
	# bus rolls freely on slopes and half pipe walls under gravity.
	if throttle != 0.0:
		speed += throttle * current_accel * delta
		speed = clamp(speed, -current_limit, current_limit)
	elif is_on_floor() and get_floor_normal().y > 0.98:
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
			desired = desired.slide(floor_normal).normalized() * desired.length()
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
			desired = desired.slide(floor_normal).normalized() * desired.length()
	velocity.x = lerp(velocity.x, desired.x, DRIFT_TRACTION * delta)
	velocity.z = lerp(velocity.z, desired.z, DRIFT_TRACTION * delta)
	if is_on_floor() and get_floor_normal().y < 0.99:
		velocity.y = lerp(velocity.y, desired.y, DRIFT_TRACTION * delta)
