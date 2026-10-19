extends HBoxContainer
signal options_changed

func _ready() -> void:
	$Mode.item_selected.connect(func(_index: int): options_changed.emit())
	$Tolerance.value_changed.connect(func(_value: float): options_changed.emit())

func mode() -> int:
	return $Mode.selected

func tolerance() -> float:
	return float($Tolerance.value)/100.0

func set_options(selected_mode: int, value: float) -> void:
	$Mode.select(clampi(selected_mode,0,2))
	$Tolerance.set_value(clampf(value,0.0,1.0)*100.0,false)
