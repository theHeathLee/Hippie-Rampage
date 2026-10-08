@tool
extends Node3D

# A building made of stacked blocks. The blocks stay frozen (a solid wall)
# until the player boosts into the building, then they unfreeze and the
# building topples away from the bus.
#
# The blocks are generated in code (and previewed in the editor), so tweak
# the building with the exports below rather than editing child nodes.

@export_range(1, 12) var floors: int = 5:
	set(value):
		floors = value
		_rebuild()
@export_range(1, 6) var blocks_wide: int = 2:
	set(value):
		blocks_wide = value
		_rebuild()
@export_range(1, 6) var blocks_deep: int = 2:
	set(value):
		blocks_deep = value
		_rebuild()
@export var block_size: Vector3 = Vector3(2.0, 1.5, 2.0):
	set(value):
		block_size = value
		_rebuild()
@export var color: Color = Color(1, 1, 1):
	set(value):
		color = value
		_rebuild()
@export var block_mass: float = 1.0
# How hard the bus smashes the ground-floor blocks it hits, relative to its speed.
@export var impact_strength: float = 1.0
# How fast the building starts tipping over: roughly the top's speed as a
# fraction of the bus's speed.
@export var topple_strength: float = 1.0
# Burst of debris thrown out when the building collapses.
@export var particles_debris: PackedScene

const BUILDING_TEXTURE = preload("res://assets/textures/building.svg")

var _blocks: Array[RigidBody3D] = []
var _collapsed := false
var _area: Area3D

func _ready():
	_rebuild()
	if Engine.is_editor_hint():
		return

	# Trigger zone a bit bigger than the building, so a boosting bus knocks it
	# down just before touching it rather than stopping dead.
	var size = _footprint()
	_area = Area3D.new()
	var area_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x + 1.5, floors * block_size.y, size.z + 1.5)
	area_shape.shape = box
	area_shape.position.y = floors * block_size.y / 2.0
	_area.add_child(area_shape)
	add_child(_area)

# Checked every frame rather than on entering the zone, so boosting while
# already pressed up against the building still knocks it down.
func _physics_process(_delta: float):
	if Engine.is_editor_hint() or _collapsed or not _area:
		return
	for body in _area.get_overlapping_bodies():
		if body.is_in_group("player") and body.is_boosting:
			_collapse(body)
			return

func _footprint() -> Vector3:
	return Vector3(blocks_wide * block_size.x, 0.0, blocks_deep * block_size.z)

func _rebuild():
	if not is_node_ready():
		return
	for block in _blocks:
		block.queue_free()
	_blocks.clear()

	var material := StandardMaterial3D.new()
	material.albedo_texture = BUILDING_TEXTURE
	material.albedo_color = color
	var mesh := BoxMesh.new()
	mesh.size = block_size
	mesh.material = material
	var shape := BoxShape3D.new()
	shape.size = block_size
	# Low friction so the blocks separate as the building falls instead of sliding as one lump.
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.4
	physics_material.bounce = 0.1

	var size = _footprint()
	for y in floors:
		for x in blocks_wide:
			for z in blocks_deep:
				var block := RigidBody3D.new()
				block.mass = block_mass
				block.freeze = true
				block.physics_material_override = physics_material
				block.position = Vector3(
					(x + 0.5) * block_size.x - size.x / 2.0,
					(y + 0.5) * block_size.y,
					(z + 0.5) * block_size.z - size.z / 2.0)
				var mesh_instance := MeshInstance3D.new()
				mesh_instance.mesh = mesh
				block.add_child(mesh_instance)
				var collision := CollisionShape3D.new()
				collision.shape = shape
				block.add_child(collision)
				add_child(block)
				_blocks.append(block)

func _spawn_debris(at: Vector3):
	if not particles_debris:
		return
	var debris: GPUParticles3D = particles_debris.instantiate()
	get_tree().current_scene.add_child(debris)
	debris.global_position = at
	debris.emitting = true
	debris.finished.connect(debris.queue_free)

func _collapse(body: CharacterBody3D) -> void:
	_collapsed = true
	Score.add_hit()
	# Debris where the bus hits, and a second burst from the base as it comes down.
	_spawn_debris(body.global_position.lerp(global_position, 0.5) + Vector3.UP)
	_spawn_debris(global_position + Vector3.UP)

	var hit_velocity: Vector3 = body.velocity
	hit_velocity.y = 0.0
	var speed = hit_velocity.length()
	var direction = hit_velocity / speed if speed > 0.1 else Vector3.FORWARD
	var height = floors * block_size.y

	# Start the whole building rotating forward around its far bottom edge,
	# like a tree being felled. Gravity takes it from there, and the blocks
	# break apart when they hit the ground.
	var size = _footprint()
	var half_depth = 0.5 * (abs(direction.x) * size.x + abs(direction.z) * size.z)
	var pivot = global_position + direction * half_depth
	var tip_rate = Vector3.UP.cross(direction) * topple_strength * maxf(speed, 4.0) / height

	for block in _blocks:
		block.freeze = false
		var velocity = tip_rate.cross(block.global_position - pivot)
		# Ground-floor blocks near the bus get smashed out and up as well.
		if block.position.y < block_size.y:
			var offset = block.global_position - body.global_position
			offset.y = 0.0
			var smash = impact_strength / (1.0 + offset.length_squared() * 0.1)
			velocity += (hit_velocity + Vector3.UP * speed * 0.3) * smash
		velocity += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * speed * 0.1
		block.linear_velocity = velocity
		block.angular_velocity = tip_rate + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
