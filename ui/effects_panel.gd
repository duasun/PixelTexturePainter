extends VBoxContainer
signal effect_changed(key: String, value: Variant)
signal section_changed
var refreshing := false
const PERCENT_SETTINGS := {"Brightness": "brightness", "Contrast": "contrast", "Saturation": "saturation", "Noise": "noise", "NoiseDensity": "noise_density"}
const INTEGER_SETTINGS := {"NoiseGrain": "noise_grain", "NoiseSeedRow/NoiseSeed": "noise_seed"}
const SECTIONS := {
	"SectionBrightnessLabel": ["BrightnessLabel","Brightness","ContrastLabel","Contrast","SaturationLabel","Saturation"],
	"SectionNoiseLabel": ["NoiseLabel","Noise","NoiseDensityLabel","NoiseDensity","NoiseGrainLabel","NoiseGrain","NoiseModeLabel","NoiseMode","NoiseSeedLabel","NoiseSeedRow"],
	"SectionPaletteLabel": ["Palette","Reset"],
	"EdgeSection": ["EdgeLabel","EdgeWidthLabel","EdgeWidth","EdgeScatterLabel","EdgeScatter","EdgeNoiseLabel","EdgeNoise","EdgeFalloffLabel","EdgeFalloff","Edges"],
	"AOSection": ["AOInfo","AOStrengthLabel","AOStrength","AORadiusLabel","AORadius","AODepthLabel","AODepth","AOFalloffLabel","AOFalloff","AOGenerate"],
	"NormalSection": ["NormalInfo","NormalStrengthLabel","NormalStrength","NormalGenerate"],
	"BlurSection": ["BlurInfo","BlurRadiusLabel","BlurRadius","BlurPreview","BlurApply","BlurCancel"]}

func _ready() -> void:
	for node_name in PERCENT_SETTINGS:
		get_node(node_name).value_changed.connect(func(v: float):
			if not refreshing:
				effect_changed.emit(PERCENT_SETTINGS[node_name], v / 100.0))
	for node_name in INTEGER_SETTINGS:
		get_node(node_name).value_changed.connect(func(v: float):
			if not refreshing: effect_changed.emit(INTEGER_SETTINGS[node_name], int(v)))
	$NoiseMode.item_selected.connect(func(index: int):
		if not refreshing: effect_changed.emit("noise_mode", index))
	$NoiseSeedRow/NoiseReseed.pressed.connect(func():
		var current := int($NoiseSeedRow/NoiseSeed.value)
		$NoiseSeedRow/NoiseSeed.set_value((current + randi_range(1, 9999)) % 10000))
	$Palette.toggled.connect(func(v: bool):
		if not refreshing: effect_changed.emit("palette", v))
	$Reset.pressed.connect(func(): effect_changed.emit("reset", null))
	for heading in SECTIONS:
		get_node(heading).toggled.connect(func(_on: bool): _show_section(heading); section_changed.emit())
		_show_section(heading)

func _show_section(heading: String) -> void:
	var opened: bool = get_node(heading).button_pressed
	for control_name in SECTIONS[heading]: get_node(control_name).visible = opened
	get_node(heading).text = ("▼ " if opened else "▶ ") + get_node(heading).text.substr(2)

func open_sections() -> Dictionary:
	var state := {}
	for heading in SECTIONS: state[heading] = get_node(heading).button_pressed
	return state

func restore_sections(state: Dictionary) -> void:
	for heading in SECTIONS:
		get_node(heading).set_pressed_no_signal(bool(state.get(heading,false)))
		_show_section(heading)

func set_channel(channel: String) -> void:
	$Hint.text = "Live Albedo preview · included in PNG export" if channel == "albedo" else "Albedo adjustments unavailable on this map · map generators below"
	for control_name in PERCENT_SETTINGS.keys() + INTEGER_SETTINGS.keys():
		get_node(control_name).set_deferred("mouse_filter", Control.MOUSE_FILTER_STOP)
		get_node(control_name).modulate.a = 1.0 if channel == "albedo" else 0.45
	$NoiseMode.disabled = channel != "albedo"
	$NoiseSeedRow/NoiseReseed.disabled = channel != "albedo"
	$Palette.disabled = channel != "albedo"
	$Reset.disabled = channel != "albedo"

func refresh(doc: PaintDocument) -> void:
	refreshing = true
	for node_name in PERCENT_SETTINGS:
		var v: float = doc.effects[PERCENT_SETTINGS[node_name]]
		get_node(node_name).set_value(v * 100, false)
	for node_name in INTEGER_SETTINGS:
		get_node(node_name).set_value(float(doc.effects[INTEGER_SETTINGS[node_name]]), false)
	$NoiseMode.select(clampi(int(doc.effects.noise_mode), 0, 3))
	$Palette.button_pressed = doc.effects.palette
	refreshing = false
