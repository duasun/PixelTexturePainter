class_name NumberField
extends HBoxContainer
signal value_changed(value: float)
signal value_committed(value: float)
@export var value := 1.0
@export var minimum := 0.0
@export var maximum := 100.0
@export var step := 1.0
@export var suffix := ""
var _down := false
var _travel := 0.0
var _accumulated := 0.0
@onready var display: Button = $Center/Display
@onready var editor: LineEdit = $Center/Editor

func _ready() -> void:
	$Minus.pressed.connect(func(): set_value(value - step); value_committed.emit(value))
	$Plus.pressed.connect(func(): set_value(value + step); value_committed.emit(value))
	display.gui_input.connect(_on_input)
	editor.text_submitted.connect(_commit_text)
	editor.focus_exited.connect(func():
		if editor.visible: _commit_text(editor.text))
	_refresh()

func set_value(number: float, emit := true) -> void:
	var next := clampf(snappedf(number, step), minimum, maximum)
	if is_equal_approx(value, next):
		return
	value = next
	if is_node_ready():
		_refresh()
	if emit:
		value_changed.emit(value)

func _refresh() -> void:
	display.text = (str(roundi(value)) if step >= 1.0 else String.num(value, 2)) + suffix
	display.tooltip_text = (tooltip_text + "\n" if not tooltip_text.is_empty() else "") + "Click to type · drag left/right · Shift for fine adjustment · wheel to step"

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_down = true
				_travel = 0.0
				_accumulated = value
			else:
				_down = false
				if _travel < 4.0:
					editor.text = str(value)
					editor.show()
					editor.grab_focus()
					editor.select_all()
				else:
					value_committed.emit(value)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			set_value(value + step * (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1))
			value_committed.emit(value)
			accept_event()
	elif event is InputEventMouseMotion and _down:
		_travel += absf(event.relative.x)
		if _travel >= 4.0:
			_accumulated += event.relative.x * step * (0.1 if event.shift_pressed else 0.5)
			set_value(_accumulated)
			accept_event()

func _commit_text(text: String) -> void:
	editor.hide()
	if text.is_valid_float():
		set_value(float(text))
		value_committed.emit(value)
