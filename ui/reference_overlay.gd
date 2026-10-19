extends Control
signal state_changed(state: Dictionary)

var _image: Image
var _dragging := false
var _opacity_dragging := false
var _restoring := false

func _ready() -> void:
	$Panel/Body/Header.gui_input.connect(_header_input)
	$Panel/Body/Image.gui_input.connect(_image_input)
	$Panel/Body/Header/Lock.toggled.connect(func(_locked: bool): _emit_state())
	$Panel/Body/Header/Hide.pressed.connect(toggle_display)
	$Panel/Body/OpacityRow/Opacity.drag_started.connect(func(): _opacity_dragging = true)
	$Panel/Body/OpacityRow/Opacity.value_changed.connect(func(value: float):
		$Panel/Body/Image.modulate.a = value / 100.0
		if not _opacity_dragging: _emit_state())
	$Panel/Body/OpacityRow/Opacity.drag_ended.connect(func(_changed: bool):
		_opacity_dragging = false
		_emit_state())

func set_source(image: Image, title: String, settings: Dictionary) -> void:
	_restoring = true
	_image = image
	$Panel/Body/Image.texture = ImageTexture.create_from_image(image) if image != null else null
	$Panel/Body/Header/Title.text = title if not title.is_empty() else "REFERENCE"
	$Panel/Body/Header/Title.tooltip_text = title
	position = Vector2(float(settings.get("x",12.0)),float(settings.get("y",90.0)))
	var initial_height := 260.0 if image == null else clampf(300.0*image.get_height()/maxf(1.0,image.get_width()),150.0,500.0)
	size = Vector2(float(settings.get("width",300.0)),float(settings.get("height",initial_height+65.0)))
	$Panel/Body/Header/Lock.set_pressed_no_signal(bool(settings.get("locked",false)))
	$Panel/Body/OpacityRow/Opacity.set_value_no_signal(clampf(float(settings.get("opacity",1.0))*100.0,10.0,100.0))
	$Panel/Body/Image.modulate.a = $Panel/Body/OpacityRow/Opacity.value/100.0
	visible = image != null and bool(settings.get("visible",true))
	_restoring = false

func state() -> Dictionary:
	return {"x":position.x,"y":position.y,"width":size.x,"height":size.y,
		"opacity":$Panel/Body/OpacityRow/Opacity.value/100.0,
		"locked":$Panel/Body/Header/Lock.button_pressed,"visible":visible}

func toggle_display() -> void:
	if _image == null: return
	visible = not visible
	_emit_state()

func _header_input(event: InputEvent) -> void:
	if $Panel/Body/Header/Lock.button_pressed: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not event.pressed: _emit_state()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var bounds := get_parent_control().size-size
		position = (position+event.relative).clamp(Vector2.ZERO,bounds.max(Vector2.ZERO))
		accept_event()

func _image_input(event: InputEvent) -> void:
	if $Panel/Body/Header/Lock.button_pressed: return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var factor := 1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.1
		var proposed := (size*factor).clamp(Vector2(160,150),Vector2(900,900))
		var ratio := proposed.x/size.x
		size = proposed
		position = (position+event.position*(1.0-ratio)).max(Vector2.ZERO)
		_emit_state()
		accept_event()

func _emit_state() -> void:
	if not _restoring: state_changed.emit(state())
