extends HBoxContainer
signal setting_changed(key: String, value: Variant)

func _ready() -> void:
	$Opacity.value_changed.connect(func(value: float): setting_changed.emit("opacity",value/100.0))
	$Strength.value_changed.connect(func(value: float): setting_changed.emit("spray_strength",value/100.0))
