extends Node

var hits := 0
var _label: Label

func _ready():
	var canvas = CanvasLayer.new()
	add_child(canvas)

	_label = Label.new()
	_label.text = "Score: 0"
	_label.add_theme_font_size_override("font_size", 32)
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.position = Vector2(-160, 20)
	canvas.add_child(_label)

func add_hit():
	hits += 1
	_label.text = "Score: %d" % hits
