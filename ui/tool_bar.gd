extends VBoxContainer
signal tool_selected(tool: String)
signal compact_changed(compact: bool)
const TOOLS := ["brush", "spray", "smudge", "blur", "eraser", "picker", "fill", "select", "lasso", "line", "rect", "ellipse", "gradient", "stencil", "clone"]
var _labels: Dictionary = {}

func _ready() -> void:
	for tool in TOOLS:
		_labels[tool] = get_node("Tools/"+tool.capitalize()).text
		get_node("Tools/"+tool.capitalize()).pressed.connect(func(): select(tool))
	$Compact.toggled.connect(set_compact)
	set_compact($Compact.button_pressed)

func set_compact(compact: bool) -> void:
	custom_minimum_size.x = 82 if compact else 124
	$Tools.columns = 2 if compact else 1
	$Compact.text = "" if compact else "Compact"
	$Compact.tooltip_text = "Expand toolbar" if compact else "Compact toolbar: icons only"
	$Heading.visible = not compact
	for tool in TOOLS:
		var button: Button = get_node("Tools/"+tool.capitalize())
		button.custom_minimum_size.x = 39 if compact else 124
		button.text = "" if compact else _labels[tool]
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	compact_changed.emit(compact)

func select(tool: String, emit := true) -> void:
	for tool_name in TOOLS:
		get_node("Tools/"+tool_name.capitalize()).set_pressed_no_signal(tool == tool_name)
	if emit:
		tool_selected.emit(tool)
