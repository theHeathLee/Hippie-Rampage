extends RigidBody3D

# --- Movement Constants ---
const MOVE_FORCE = 15.0         # Force applied to keep the pedestrian moving
const CHANGE_INTERVAL = 2.0     # Base time interval to change direction
const CAR_SIMULATED_MASS = 1000.0 # Simulates the heavy mass of the player's cube car

# --- Variables ---
var time_to_change = 0.0

func _ready():
	# Set the initial movement direction
	change_direction()

func _physics_process(delta: float):
	# Only apply movement if the object isn't currently airborne or rolling from impact
	if linear_velocity.length_squared() < 0.1 or linear_velocity.y < 0.1: 
		
		# Apply a constant force in the current direction to simulate walking/wandering
		# We rotate the force vector by the current Y-rotation of the body
		apply_central_force(Vector3(0, 0, MOVE_FORCE).rotated(Vector3.UP, rotation.y))
		
		# Timer to change direction
		time_to_change -= delta
		if time_to_change <= 0:
			change_direction()

func change_direction():
	# Rotate the pedestrian randomly (only on the Y-axis, as X/Z are locked in the Inspector)
	rotation.y = randf_range(0, 2 * PI)
	# Reset the timer with some randomness
	time_to_change = CHANGE_INTERVAL + randf_range(0, 1.0) 

# --- Collision Logic (Reacting to the Car) ---

# This function is called when the RigidBody3D collides with another physics body.
func _on_body_entered(body: Node3D):
	# Check if the colliding body is the player's car cube (CharacterBody3D)
	if body is CharacterBody3D and body.name == "Cube":
		
		# To simulate the car's weight, we calculate an impulse based on the car's speed and our simulated mass.
		
		# 1. Get the car's velocity
		# We assume the car's script has a 'velocity' property (which CharacterBody3D does)
		var car_velocity = body.velocity
		
		# 2. Calculate the total momentum magnitude (P = mass * velocity)
		# Using a large simulated mass makes the impact dramatic
		var momentum = car_velocity * CAR_SIMULATED_MASS
		
		# 3. Calculate the Impulse
		# Impulse magnitude is the momentum, scaled down by a factor (0.1) to tune the launch strength.
		var impulse_magnitude = momentum.length() * 0.1 
		var impulse_direction = car_velocity.normalized()
		
		# Apply the impulse to the center of the pedestrian, launching it away from the impact
		apply_central_impulse(impulse_direction * impulse_magnitude)

		# Optional: Add rotational spin (Torque) for a ragdoll-like effect
		# The cross product finds a vector perpendicular to the direction of travel, causing rotation.
		var torque_direction = Vector3.UP.cross(impulse_direction)
		apply_torque_impulse(torque_direction * impulse_magnitude * 0.05)
