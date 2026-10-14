extends VBoxContainer
signal action_requested(action: String, value: Variant)

func _ready() -> void:
	$Generate.pressed.connect(func(): action_requested.emit("generate", {"angle": $Angle.value, "padding": int($Padding.value)}))
	$Inspect.pressed.connect(func(): action_requested.emit("inspect",null))
	$ExportPadding.value_changed.connect(func(value: float): action_requested.emit("export_padding",int(value)))
	$Rotate.pressed.connect(func(): action_requested.emit("rotate", 90.0))
	$Snap.pressed.connect(func(): action_requested.emit("snap", null))
	for direction_name in ["Left", "Right", "Up", "Down"]:
		get_node("Move/" + direction_name).pressed.connect(func():
			var delta: Vector2 = {"Left": Vector2.LEFT, "Right": Vector2.RIGHT, "Up": Vector2.UP, "Down": Vector2.DOWN}[direction_name]
			action_requested.emit("move", delta * $MoveStep.value))
