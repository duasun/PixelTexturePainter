extends HBoxContainer
signal setting_changed(key: String, value: Variant)
var _brush_shape := 0

func _ready() -> void:
	$Size.value_changed.connect(func(v: float): setting_changed.emit("brush_size", int(v)))
	$Opacity.value_changed.connect(func(v: float): setting_changed.emit("opacity", v / 100.0))
	$Falloff.value_changed.connect(func(v: float): setting_changed.emit("falloff", v / 100.0))
	$Shape.toggled.connect(func(on: bool): _brush_shape = 1 if on else 0; setting_changed.emit("shape", _brush_shape))
	$Dither.toggled.connect(func(v: bool): setting_changed.emit("dither", v))
	$Mirror.toggled.connect(func(v: bool): setting_changed.emit("mirror", v))
	for axis in ["SymX","SymY","SymZ"]:
		get_node(axis).toggled.connect(func(_on: bool): setting_changed.emit("symmetry_axes",symmetry_axes()))
	$Tolerance.value_changed.connect(func(v: float): setting_changed.emit("fill_tolerance",v/100.0))
	$Contiguous.toggled.connect(func(v: bool): setting_changed.emit("fill_contiguous",v))
	$Length.value_changed.connect(func(v: float): setting_changed.emit("gradient_length", int(v)))

func set_shape(value: int) -> void:
	_brush_shape = clampi(value, 0, 1)
	$Shape.set_pressed_no_signal(_brush_shape == 1)

func symmetry_axes() -> int:
	return (1 if $SymX.button_pressed else 0) | (2 if $SymY.button_pressed else 0) | (4 if $SymZ.button_pressed else 0)

func set_symmetry_axes(axes: int) -> void:
	$SymX.set_pressed_no_signal(bool(axes & 1))
	$SymY.set_pressed_no_signal(bool(axes & 2))
	$SymZ.set_pressed_no_signal(bool(axes & 4))

func set_tool(tool: String) -> void:
	$Size.maximum = 64 if tool in ["smudge","blur"] else 256
	$Size.set_value(minf($Size.value,$Size.maximum))
	$Opacity.visible = tool != "spray"
	$OpacityLabel.visible = tool != "spray"
	$Falloff.visible = tool in ["brush", "eraser", "clone", "smudge", "blur", "line", "rect", "ellipse"]
	$FalloffLabel.visible = $Falloff.visible
	$Active.text = tool.capitalize().to_upper()
	$Length.visible = tool == "gradient"
	$LengthLabel.visible = tool == "gradient"
	$Tolerance.visible = tool == "fill"
	$ToleranceLabel.visible = tool == "fill"
	$Contiguous.visible = tool == "fill"
	$Shape.disabled = tool in ["spray", "stencil"]
	$Shape.set_pressed_no_signal(true if tool == "spray" else false if tool == "stencil" else _brush_shape == 1)
	for axis in ["SymX","SymY","SymZ"]: get_node(axis).disabled = tool not in ["brush","eraser","stencil","spray","smudge","blur"]
	$SymmetryLabel.modulate.a = 1.0 if tool in ["brush","eraser","stencil","spray","smudge","blur"] else 0.45
