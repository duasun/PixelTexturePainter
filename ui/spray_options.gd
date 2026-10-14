extends GridContainer
signal setting_changed(key: String, value: Variant)

func _ready() -> void:
	$Opacity.value_changed.connect(func(v: float): setting_changed.emit("opacity",v/100.0))
	$Flow.value_changed.connect(func(v: float): setting_changed.emit("spray_flow",v/100.0))
	$Particles.value_changed.connect(func(v: float): setting_changed.emit("spray_particles", int(v)))
	$Spacing.value_changed.connect(func(v: float): setting_changed.emit("spray_spacing", v))
	$Rate.value_changed.connect(func(v: float): setting_changed.emit("spray_rate", v))
	$Distance.value_changed.connect(func(v: float): setting_changed.emit("spray_distance", v / 100.0))
