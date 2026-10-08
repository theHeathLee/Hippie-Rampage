@tool
extends StaticBody3D

# A half pipe: two curved quarter-pipe walls facing each other across a flat
# bottom (the ground), with a deck and metal coping along each lip. Open at
# both ends, so drive in lengthways and carve up the walls.
#
# The mesh and collision are generated in code (and previewed in the
# editor), so shape it with the exports below.

@export var length: float = 16.0:
	set(value):
		length = value
		_rebuild()
# Width of the flat bottom between the two curves.
@export var flat_width: float = 6.0:
	set(value):
		flat_width = value
		_rebuild()
@export var radius: float = 4.0:
	set(value):
		radius = value
		_rebuild()
# How far round the curve goes at the lip. Keep below the bus's
# MAX_FLOOR_ANGLE (80) so the whole wall stays drivable.
@export_range(30.0, 85.0) var lip_angle: float = 78.0:
	set(value):
		lip_angle = value
		_rebuild()
@export var deck_width: float = 1.5:
	set(value):
		deck_width = value
		_rebuild()
@export var segments: int = 16:
	set(value):
		segments = value
		_rebuild()
@export var color: Color = Color("b388eb"):
	set(value):
		color = value
		_rebuild()

const COPING_RADIUS = 0.12

var _parts: Array[Node] = []

func _ready():
	_rebuild()

func _rebuild():
	if not is_node_ready():
		return
	for part in _parts:
		part.queue_free()
	_parts.clear()

	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = 0.7
	# Normals are set explicitly, so draw both sides rather than relying on winding.
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	var coping := StandardMaterial3D.new()
	coping.albedo_color = Color("d9d9d9")
	coping.metallic = 0.8
	coping.roughness = 0.3

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for side in [-1.0, 1.0]:
		_add_quarter_pipe(st, faces, side)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = surface
	_add_part(mesh_instance)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_add_part(collision)

	# Metal coping pipe along each lip.
	var lip = _lip()
	for side in [-1.0, 1.0]:
		var pipe := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = COPING_RADIUS
		cylinder.bottom_radius = COPING_RADIUS
		cylinder.height = length
		cylinder.material = coping
		pipe.mesh = cylinder
		pipe.rotation.z = PI / 2.0
		pipe.position = Vector3(0, lip.y, side * lip.x)
		_add_part(pipe)

func _add_part(node: Node):
	add_child(node)
	_parts.append(node)

# Lip position in the cross-section: x = distance from the centre line, y = height.
func _lip() -> Vector2:
	var a = deg_to_rad(lip_angle)
	return Vector2(flat_width / 2.0 + radius * sin(a), radius * (1.0 - cos(a)))

# Cross-section profile of one wall, from the bottom of the curve to the
# outer edge of the deck. Points are (distance from centre, height), with a
# surface normal for each.
func _profile() -> Array:
	var points := []
	var a_max = deg_to_rad(lip_angle)
	for i in segments + 1:
		var a = a_max * i / segments
		points.append([Vector2(flat_width / 2.0 + radius * sin(a), radius * (1.0 - cos(a))), Vector2(-sin(a), cos(a))])
	var lip = _lip()
	points.append([lip, Vector2.UP])
	points.append([Vector2(lip.x + deck_width, lip.y), Vector2.UP])
	return points

# Builds one wall: curved face + deck, outer wall, and end caps.
# `side` is -1 or +1 for which side of the centre line (along Z) it sits on.
func _add_quarter_pipe(st: SurfaceTool, faces: PackedVector3Array, side: float):
	var half = length / 2.0
	var to_3d = func(p: Vector2, x: float) -> Vector3: return Vector3(x, p.y, side * p.x)
	var normal_3d = func(n: Vector2) -> Vector3: return Vector3(0, n.y, side * n.x)

	var profile = _profile()
	# Curved face and deck, one strip of quads along the length.
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i][0]
		var p1: Vector2 = profile[i + 1][0]
		if p0.is_equal_approx(p1):
			continue
		var n0 = normal_3d.call(profile[i][1])
		var n1 = normal_3d.call(profile[i + 1][1])
		_quad(st, faces,
			to_3d.call(p0, -half), to_3d.call(p0, half), to_3d.call(p1, half), to_3d.call(p1, -half),
			[n0, n0, n1, n1])

	# Outer wall straight down from the deck edge.
	var outer: Vector2 = profile[-1][0]
	var out_normal = Vector3(0, 0, side)
	_quad(st, faces,
		to_3d.call(outer, -half), to_3d.call(outer, half),
		to_3d.call(Vector2(outer.x, 0), half), to_3d.call(Vector2(outer.x, 0), -half),
		[out_normal, out_normal, out_normal, out_normal])

	# End caps: the cross-section polygon at each end.
	var polygon := PackedVector2Array()
	for point in profile:
		if polygon.is_empty() or not polygon[-1].is_equal_approx(point[0]):
			polygon.append(point[0])
	polygon.append(Vector2(outer.x, 0))
	var triangles = Geometry2D.triangulate_polygon(polygon)
	for x in [-half, half]:
		var cap_normal = Vector3(signf(x), 0, 0)
		for t in range(0, triangles.size(), 3):
			var tri = [to_3d.call(polygon[triangles[t]], x), to_3d.call(polygon[triangles[t + 1]], x), to_3d.call(polygon[triangles[t + 2]], x)]
			for v in tri:
				st.set_normal(cap_normal)
				st.add_vertex(v)
			faces.append_array(PackedVector3Array(tri))

func _quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normals: Array):
	var verts = [a, b, c, a, c, d]
	var norms = [normals[0], normals[1], normals[2], normals[0], normals[2], normals[3]]
	for i in 6:
		st.set_normal(norms[i])
		st.add_vertex(verts[i])
	faces.append_array(PackedVector3Array(verts))
