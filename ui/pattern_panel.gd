extends HBoxContainer
signal load_requested
signal apply_requested
signal custom_requested
signal mode_changed(mode: int)
signal settings_changed
signal transform_committed
var source: Image
var _texture: Image
var _custom: Image
var _first := Color.WHITE
var _second := Color.BLACK

func _ready() -> void:
	for pattern_mode in PatternLibrary.MODES: $Mode.add_item(pattern_mode)
	$Mode.item_selected.connect(func(index: int):
		_refresh_source()
		mode_changed.emit(index))
	$Load.pressed.connect(func(): load_requested.emit())
	$Edit.pressed.connect(func(): custom_requested.emit())
	$Apply.pressed.connect(func(): apply_requested.emit())
	for field in ["Angle","Scale"]:
		get_node(field).value_changed.connect(func(_value: float): settings_changed.emit())
		get_node(field).value_committed.connect(func(_value: float): transform_committed.emit())
	_refresh_source()

func mode() -> int:
	return $Mode.selected

func set_mode(index: int) -> void:
	$Mode.select(clampi(index,0,PatternLibrary.MODES.size()-1))
	_refresh_source()

func set_colors(first: Color, second: Color) -> void:
	_first = first
	_second = second
	_refresh_source()

func set_source(image: Image, title: String) -> void:
	_texture = image
	$Preview.tooltip_text = title if image != null else "Load a texture image"
	_refresh_source()

func set_custom_source(image: Image) -> void:
	_custom = image
	_refresh_source()

func set_editing_pattern(on: bool) -> void:
	$Apply.text = "Update layer" if on else "Fill selection"

func settings() -> Dictionary:
	return {"angle":$Angle.value,"scale":$Scale.value/100.0,"offset":Vector2.ZERO}

func restore_settings(saved: Dictionary) -> void:
	$Angle.set_value(float(saved.get("angle",0.0)),false)
	$Scale.set_value(float(saved.get("scale",1.0))*100.0,false)

func _refresh_source() -> void:
	var selected := mode()
	source = _texture if selected == 1 else _custom if selected == 8 else PatternLibrary.image_for(selected,_first,_second) if selected in [2,3,4,5,6,7] else null
	$Preview.texture = ImageTexture.create_from_image(source) if source != null else null
	$Preview.visible = selected != 0
	$Load.visible = selected == 1
	$Edit.visible = selected == 8
	for field in ["AngleLabel","Angle","ScaleLabel","Scale"]: get_node(field).visible = selected != 0
