class_name PaletteSwatch
extends Button
signal chosen(slot: int)
signal edit_requested
var color := Color.WHITE
var marks := ""
var _configured := false

func _ready() -> void:
	button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT

func configure(value: Color, selection: String) -> void:
	if _configured and color == value and marks == selection:
		return
	_configured = true
	color = value
	marks = selection
	text = selection
	var style := StyleBoxFlat.new()
	style.bg_color = value
	style.set_border_width_all(2 if not selection.is_empty() else 1)
	style.border_color = Color.WHITE if not selection.is_empty() else Color(0,0,0,0.45)
	style.shadow_color = Color.BLACK
	style.shadow_size = 2 if not selection.is_empty() else 0
	for state in ["normal","pressed","hover","hover_pressed"]:
		add_theme_stylebox_override(state, style)
	tooltip_text = "#%s · Left click: color 1 · Right click: color 2" % value.to_html(value.a < 1.0).to_upper()
	queue_redraw()

func _draw() -> void:
	if not marks.is_empty():
		draw_rect(Rect2(Vector2.ONE*3,size-Vector2.ONE*6),Color.BLACK,false,1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			edit_requested.emit()
			accept_event()
			return
		chosen.emit(1 if event.button_index == MOUSE_BUTTON_LEFT else 2)
		accept_event()
