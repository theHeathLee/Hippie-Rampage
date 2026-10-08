extends StaticBody3D

@onready var head = $Head
@onready var muzzle = $Head/Muzzle
@onready var timer = $ShotTimer

# Preload the bullet scene (drag the .tscn file here)
var bullet_scene = preload("res://scenes/bullet.tscn")
#@export var bullet_scene: PackedScene
var player = null

func _ready():
	# Find the player in the scene
	player = get_tree().get_first_node_in_group("player")
	timer.timeout.connect(_shoot)

func _process(_delta):
	if player:
		# Make the head look at the player's position
		var target_pos = player.global_position
		# We keep the Y position the same if we only want it to rotate horizontally, 
		# or leave it as is for full 3D aiming.
		head.look_at(target_pos, Vector3.UP)

func _shoot():
	var bullet = bullet_scene.instantiate()
	# Add bullet to the main scene, not as a child of the rotating turret
	get_tree().root.add_child(bullet)
	
	# Position the bullet at the muzzle
	bullet.global_transform = muzzle.global_transform
	# Tell the bullet which way to fly
	bullet.direction = -muzzle.global_transform.basis.z.normalized()
