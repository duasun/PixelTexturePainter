extends HBoxContainer
signal load_requested
signal crop_requested
signal rotation_changed(angle: float)
signal rotation_committed(angle: float)

func _ready() -> void:
	$Load.pressed.connect(func(): load_requested.emit())
	$Crop.pressed.connect(func(): crop_requested.emit())
	$Rotation.value_changed.connect(func(value: float): rotation_changed.emit(value))
	$Rotation.value_committed.connect(func(value: float): rotation_committed.emit(value))

func set_source(image: Image, title: String) -> void:
	$Name.text = title if image != null else "No stamp"
	$Name.tooltip_text = $Name.text

func set_stamp_rotation(value: float) -> void:
	$Rotation.set_value(value,false)
