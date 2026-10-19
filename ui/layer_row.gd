extends HBoxContainer
signal selected(id: String)
signal visibility_requested(id: String, on: bool)
signal lock_requested(id: String, on: bool)
signal rename_requested(id: String, title: String)
signal context_requested(id: String, position: Vector2i)
const EYE = preload("res://assets/tools/eye.svg")
const EYE_OFF = preload("res://assets/tools/eye_off.svg")
const LOCK = preload("res://assets/tools/lock.svg")
const LOCK_OPEN = preload("res://assets/tools/lock_open.svg")
var layer_id := ""
var _title := ""
func _ready() -> void:
	$Eye.pressed.connect(func(): visibility_requested.emit(layer_id,not $Eye.button_pressed))
	$Lock.pressed.connect(func(): lock_requested.emit(layer_id,$Lock.button_pressed))
	$Title.pressed.connect(func(): selected.emit(layer_id))
	$Title.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click: begin_rename())
	for control in [self,$Eye,$Lock,$Title,$Channel]:
		control.gui_input.connect(_context_input)
	$Name.text_submitted.connect(_rename)
	$Name.focus_exited.connect(func():
		if $Name.visible: _rename($Name.text))
func configure(layer: PaintLayer, active: bool) -> void:
	layer_id = layer.id
	_title = layer.title
	$Title.text = layer.title
	$Title.set_pressed_no_signal(active)
	$Title.tooltip_text = layer.title + " · " + PaintChannels.label(layer.channel) + " · double-click or F2 to rename"
	$Eye.set_pressed_no_signal(not layer.visible)
	$Eye.icon = EYE if layer.visible else EYE_OFF
	$Eye.tooltip_text = "Hide layer" if layer.visible else "Show layer"
	$Lock.set_pressed_no_signal(layer.locked)
	$Lock.icon = LOCK if layer.locked else LOCK_OPEN
	$Lock.tooltip_text = "Unlock painting on this layer" if layer.locked else "Lock painting on this layer"
	$Channel.text = PaintChannels.label(layer.channel).left(5).to_upper()
func begin_rename() -> void:
	$Title.hide()
	$Name.text = _title
	$Name.show()
	$Name.grab_focus()
	$Name.select_all()
func _rename(value: String) -> void:
	$Name.hide()
	$Title.show()
	value = value.strip_edges().left(128)
	if not value.is_empty() and value != _title: rename_requested.emit(layer_id,value)

func _context_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		context_requested.emit(layer_id,Vector2i(DisplayServer.mouse_get_position()))
		accept_event()
