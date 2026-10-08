@tool
extends RigidBody3D

# A blocky, Minecraft-style person who wanders around until the bus hits them.
# The body parts and their pixel-art skins are generated in code (and
# previewed in the editor), so pick the look with the exports below.

enum Outfit { CASUAL, SUIT, POLICE }

@export var outfit: Outfit = Outfit.CASUAL:
	set(value):
		outfit = value
		_rebuild()
# Picks skin tone, hair and clothing colours. Same seed = same look.
@export var look_seed: int = 1:
	set(value):
		look_seed = value
		_rebuild()
@export var walk_speed: float = 1.5

# Size of one skin pixel in metres. Minecraft people are 32 pixels tall.
const PX = 1.8 / 32.0
# Skin texture resolution per box face. 24 divides evenly by 4, 8 and 12,
# so every face's pixels come out as whole texels.
const CELL = 24
# Wander inside this square so people stay off the boundary walls.
const AREA_LIMIT = 52.0

const SKIN_TONES = [Color("f1c7a5"), Color("e0ac83"), Color("c68642"), Color("8d5524"), Color("5c3a21")]
const HAIR_COLORS = [Color("2b1d14"), Color("4a2f1b"), Color("8a5a2b"), Color("d8b45a"), Color("a33b1d"), Color("9a9a9a")]
const SHIRT_COLORS = [Color("e63946"), Color("f4a261"), Color("2a9d8f"), Color("e9c46a"), Color("8e7dbe"), Color("ffffff"), Color("4caf50")]
const PANTS_COLORS = [Color("3d5a80"), Color("4a3b2a"), Color("2f2f2f"), Color("6b705c")]
const SUIT_COLORS = [Color("2f3136"), Color("1f2a44"), Color("111111"), Color("4a3a2e")]
const TIE_COLORS = [Color("c1121f"), Color("1d4ed8"), Color("15803d"), Color("7e22ce"), Color("d4a017")]
const POLICE_BLUE = Color("1f3a73")
const POLICE_DARK = Color("16264a")
const GOLD = Color("e0b100")
const BLACK = Color("161616")
const WHITE = Color("f2f2f2")

# Materials shared between people who look the same.
static var _material_cache := {}

var _skin: Color
var _hair: Color
var _shirt: Color
var _pants: Color
var _tie: Color

var _model: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D

var _heading := 0.0
var _turn_timer := 0.0
var _walk_phase := 0.0
var _hit := false

func _ready():
	_rebuild()
	if Engine.is_editor_hint():
		return

	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	mass = 2.0

	# Body collision, lifted a touch off the ground so walking doesn't snag on the floor.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10 * PX, 30 * PX, 6 * PX)
	shape.shape = box
	shape.position.y = 17 * PX
	add_child(shape)

	# Trigger zone wider than the body, so the hit registers before the bus touches them.
	var area := Area3D.new()
	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(1.4, 32 * PX, 1.4)
	area_shape.shape = area_box
	area_shape.position.y = 16 * PX
	area.add_child(area_shape)
	add_child(area)
	area.body_entered.connect(_on_area_body_entered)

	_heading = randf() * TAU
	rotation.y = _heading
	_walk_phase = randf() * TAU

func _physics_process(delta: float):
	if Engine.is_editor_hint() or _hit:
		return

	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_heading = randf() * TAU
		_turn_timer = randf_range(2.0, 5.0)
	# Head back towards the middle if wandering off towards the walls.
	if absf(global_position.x) > AREA_LIMIT or absf(global_position.z) > AREA_LIMIT:
		_heading = atan2(global_position.x, global_position.z)
	rotation.y = lerp_angle(rotation.y, _heading, 3.0 * delta)

	# Turn around when bumping into a building, a redneck or another person.
	var collision = move_and_collide(-global_basis.z * walk_speed * delta)
	if collision:
		_heading = rotation.y + PI + randf_range(-0.8, 0.8)
		_turn_timer = randf_range(2.0, 5.0)

	# Swing arms and legs in opposite pairs.
	_walk_phase += delta * walk_speed * 5.0
	var swing = sin(_walk_phase)
	_left_leg.rotation.x = swing * 0.6
	_right_leg.rotation.x = -swing * 0.6
	_left_arm.rotation.x = -swing * 0.5
	_right_arm.rotation.x = swing * 0.5

func _on_area_body_entered(body: Node3D) -> void:
	if _hit or not body.is_in_group("player"):
		return
	_hit = true
	Score.add_hit()

	var bus_velocity: Vector3 = body.velocity
	bus_velocity.y = 0.0
	var away = global_position - body.global_position
	away.y = 0.0
	away = away.normalized()
	freeze = false
	linear_velocity = bus_velocity * 1.2 + away * 3.0 + Vector3.UP * (4.0 + bus_velocity.length() * 0.4)
	angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0
	# Arms up in panic.
	_left_arm.rotation.x = PI * 0.9
	_right_arm.rotation.x = PI * 0.85
	_left_leg.rotation.x = 0.4
	_right_leg.rotation.x = -0.4

# --- Model ---

func _pick_colors():
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed
	_skin = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	_hair = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
	match outfit:
		Outfit.CASUAL:
			_shirt = SHIRT_COLORS[rng.randi() % SHIRT_COLORS.size()]
			_pants = PANTS_COLORS[rng.randi() % PANTS_COLORS.size()]
		Outfit.SUIT:
			_shirt = SUIT_COLORS[rng.randi() % SUIT_COLORS.size()]
			_pants = _shirt
			_tie = TIE_COLORS[rng.randi() % TIE_COLORS.size()]
		Outfit.POLICE:
			_shirt = POLICE_BLUE
			_pants = POLICE_DARK

func _rebuild():
	if not is_node_ready():
		return
	if _model:
		_model.queue_free()
	_pick_colors()

	_model = Node3D.new()
	add_child(_model)
	# Legs and arms hang from pivots at the hip and shoulder so they can swing.
	_left_leg = _add_limb("leg", Vector3(-2, 12, 0))
	_right_leg = _add_limb("leg", Vector3(2, 12, 0))
	_add_part("body", Vector3i(8, 12, 4), Vector3(0, 18, 0), _model)
	_left_arm = _add_limb("arm", Vector3(-6, 24, 0))
	_right_arm = _add_limb("arm", Vector3(6, 24, 0))
	_add_part("head", Vector3i(8, 8, 8), Vector3(0, 28, 0), _model)

func _add_limb(part: String, pivot_px: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_px * PX
	_model.add_child(pivot)
	_add_part(part, Vector3i(4, 12, 4), Vector3(0, -6, 0), pivot)
	return pivot

func _add_part(part: String, size_px: Vector3i, center_px: Vector3, parent: Node3D):
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size_px) * PX
	mesh.material = _material_for(part, size_px)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = center_px * PX
	parent.add_child(mesh_instance)

func _material_for(part: String, size_px: Vector3i) -> StandardMaterial3D:
	var key = "%s|%d|%s|%s|%s|%s|%s" % [part, outfit, _skin.to_html(), _hair.to_html(), _shirt.to_html(), _pants.to_html(), str(_tie)]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(_paint_skin(part, size_px))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material_cache[key] = material
	return material

# Godot's BoxMesh maps a texture as a 3x2 grid, one cell per face:
#   row 0: +Z back | +X right side | -Z front
#   row 1: -X left side | +Y top | -Y bottom
# People face -Z, so the front cell is the face/chest.
func _paint_skin(part: String, s: Vector3i) -> Image:
	var image := Image.create_empty(CELL * 3, CELL * 2, false, Image.FORMAT_RGBA8)
	var faces = [
		["back", Vector2i(0, 0), Vector2i(s.x, s.y)],
		["right", Vector2i(1, 0), Vector2i(s.z, s.y)],
		["front", Vector2i(2, 0), Vector2i(s.x, s.y)],
		["left", Vector2i(0, 1), Vector2i(s.z, s.y)],
		["top", Vector2i(1, 1), Vector2i(s.x, s.z)],
		["bottom", Vector2i(2, 1), Vector2i(s.x, s.z)],
	]
	for face in faces:
		var cell: Vector2i = face[1]
		var dims: Vector2i = face[2]
		var texel = Vector2i(CELL / dims.x, CELL / dims.y)
		for y in dims.y:
			for x in dims.x:
				var color = _pixel(part, face[0], x, y, dims.x)
				image.fill_rect(Rect2i(cell * CELL + Vector2i(x, y) * texel, texel), color)
	return image

# Colour of one skin pixel. x runs left to right as you look at the face,
# y runs top to bottom.
func _pixel(part: String, face: String, x: int, y: int, width: int) -> Color:
	# On the side faces, how many pixels back from the front this column is.
	var from_front = width - 1 - x if face == "right" else x
	var police = outfit == Outfit.POLICE
	match part:
		"head":
			if face == "bottom":
				return _skin
			if police:
				if face == "top" or y == 0:
					return POLICE_BLUE
				if y == 1:
					return GOLD if face == "front" and (x == 3 or x == 4) else POLICE_BLUE
				if y == 2 and face == "front":
					return BLACK
			if face == "top":
				return _hair
			if face == "back":
				return _hair if y < 6 else _skin
			if face == "left" or face == "right":
				if y < 2 or (y < 5 and from_front > 3):
					return _hair
				return _skin
			# Front: hair line, eyes, mouth.
			if not police and (y == 0 or (y == 1 and (x == 0 or x == 7))):
				return _hair
			if y == 4:
				if x == 1 or x == 6:
					return WHITE
				if x == 2 or x == 5:
					return Color("3b2a20")
			if y == 6 and (x == 3 or x == 4):
				return _skin.darkened(0.35)
			return _skin
		"body":
			if police:
				if y >= 10 and face != "top" and face != "bottom":
					return GOLD if face == "front" and (x == 3 or x == 4) and y == 10 else BLACK
				if face == "front":
					if y == 2 and x == 5:
						return GOLD
					if y == 4 and (x == 1 or x == 2 or x == 5 or x == 6):
						return POLICE_DARK
				return _shirt
			if outfit == Outfit.SUIT and face == "front":
				if (x == 3 or x == 4) and y <= 8:
					return _tie if y >= 1 or x == 3 else _tie.darkened(0.3)
				if (x == 2 or x == 5) and y <= 4:
					return WHITE
				if x == 3 and (y == 9 or y == 11):
					return _shirt.lightened(0.25)
			if outfit == Outfit.CASUAL and face == "front" and y == 0 and (x == 3 or x == 4):
				return _skin
			return _shirt
		"arm":
			if face == "bottom" or (face != "top" and y >= 9):
				return _skin
			if outfit == Outfit.SUIT and y == 8:
				return WHITE
			return _shirt
		"leg":
			if face == "bottom" or (face != "top" and y >= 10):
				return BLACK if outfit != Outfit.CASUAL else Color("5a3d2b")
			return _pants
	return Color.MAGENTA
