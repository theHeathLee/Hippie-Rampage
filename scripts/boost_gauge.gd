extends Control

# Speedometer-style dial on the HUD showing the bus's boost meter.
# Fills cyan -> orange as it charges, and pulses hot pink while boosting.

# Dial runs clockwise from lower-left round to lower-right, leaving a gap
# at the bottom for the label.
const START_ANGLE = PI * 5.0 / 6.0
const SWEEP = PI * 4.0 / 3.0
const TICKS = 10
const TRACK_WIDTH = 14.0

const LOW_COLOR = Color("38bdf8")
const HIGH_COLOR = Color("fb923c")
const BOOSTING_COLOR = Color("ff3d9a")

var _bus: CharacterBody3D
var _shown := 0.0  # smoothed fill fraction, 0..1
var _time := 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float):
	_time += delta
	if not _bus:
		_bus = get_tree().get_first_node_in_group("player")
	if _bus:
		_shown = lerpf(_shown, _bus.boost_meter / _bus.BOOST_MAX, 10.0 * delta)
	queue_redraw()

func _draw():
	var center = size / 2.0
	var radius = minf(size.x, size.y) / 2.0 - TRACK_WIDTH
	var boosting = _bus != null and _bus.is_boosting
	var full = _shown > 0.99

	# Backing disc and empty track.
	draw_circle(center, radius + TRACK_WIDTH, Color(0, 0, 0, 0.45))
	draw_arc(center, radius, START_ANGLE, START_ANGLE + SWEEP, 64, Color(1, 1, 1, 0.15), TRACK_WIDTH, true)

	# Filled portion.
	var fill_color = LOW_COLOR.lerp(HIGH_COLOR, _shown)
	if boosting or full:
		var pulse = 0.5 + 0.5 * sin(_time * (14.0 if boosting else 6.0))
		fill_color = (BOOSTING_COLOR if boosting else HIGH_COLOR).lerp(Color.WHITE, pulse * 0.35)
	if _shown > 0.005:
		draw_arc(center, radius, START_ANGLE, START_ANGLE + SWEEP * _shown, 64, fill_color, TRACK_WIDTH, true)

	# Tick marks.
	for i in TICKS + 1:
		var direction = Vector2.from_angle(START_ANGLE + SWEEP * i / TICKS)
		var inner = radius - TRACK_WIDTH * (1.4 if i % 5 == 0 else 1.0)
		draw_line(center + direction * inner, center + direction * (radius - TRACK_WIDTH * 0.6), Color(1, 1, 1, 0.6), 2.0, true)

	# Needle.
	var needle = Vector2.from_angle(START_ANGLE + SWEEP * _shown)
	draw_line(center, center + needle * (radius - TRACK_WIDTH * 1.2), Color.WHITE, 4.0, true)
	draw_circle(center, 8.0, Color.WHITE)
	draw_circle(center, 4.0, fill_color)

	# Label and percentage in the gap at the bottom.
	var font = get_theme_default_font()
	var label_width = size.x
	draw_string(font, Vector2(0, center.y + radius * 0.55), "BOOST", HORIZONTAL_ALIGNMENT_CENTER, label_width, 18, Color.WHITE)
	draw_string(font, Vector2(0, center.y + radius * 0.85), "%d%%" % roundi(_shown * 100.0), HORIZONTAL_ALIGNMENT_CENTER, label_width, 22, fill_color)
