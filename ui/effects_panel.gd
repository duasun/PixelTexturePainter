extends VBoxContainer
signal effect_changed(key: String, value: Variant)
signal section_changed
var refreshing := false
const SETTINGS := {"Steps": "steps", "Dither": "dither", "Brightness": "brightness", "Contrast": "contrast", "Saturation": "saturation", "Noise": "noise"}
const SECTIONS := {
	"SectionStepsLabel": ["StepsLabel","Steps","DitherLabel","Dither"],
	"SectionBrightnessLabel": ["BrightnessLabel","Brightness","ContrastLabel","Contrast","SaturationLabel","Saturation"],
	"SectionNoiseLabel": ["NoiseLabel","Noise","Palette","Reset"],
	"EdgeSection": ["EdgeLabel","EdgeWidth","Edges","EdgeMaskInvert","EdgeMask"],
	"AOSection": ["AOInfo","AOStrengthLabel","AOStrength","AORadiusLabel","AORadius","AODepthLabel","AODepth","AOFalloffLabel","AOFalloff","AOGenerate","AOMaskInvert","AOMask"],
	"NormalSection": ["NormalInfo","NormalStrengthLabel","NormalStrength","NormalGenerate"],
	"BlurSection": ["BlurInfo","BlurRadiusLabel","BlurRadius","BlurPreview","BlurApply","BlurCancel"]}

func _ready() -> void:
	for node_name in SETTINGS:
		get_node(node_name).value_changed.connect(func(v: float):
			if not refreshing: effect_changed.emit(SETTINGS[node_name], int(v) if node_name == "Steps" else v / 100.0))
	$Palette.toggled.connect(func(v: bool):
		if not refreshing: effect_changed.emit("palette", v))
	$Reset.pressed.connect(func(): effect_changed.emit("reset", null))
	for heading in SECTIONS:
		get_node(heading).toggled.connect(func(_on: bool): _show_section(heading); section_changed.emit())
		_show_section(heading)

func _show_section(heading: String) -> void:
	var opened: bool = get_node(heading).button_pressed
	for name in SECTIONS[heading]: get_node(name).visible = opened
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
	for name in SETTINGS:
		get_node(name).set_deferred("mouse_filter", Control.MOUSE_FILTER_STOP)
		get_node(name).modulate.a = 1.0 if channel == "albedo" else 0.45
	$Palette.disabled = channel != "albedo"
	$Reset.disabled = channel != "albedo"

func refresh(doc: PaintDocument) -> void:
	refreshing = true
	for node_name in SETTINGS:
		var v: float = doc.effects[SETTINGS[node_name]]
		get_node(node_name).set_value(v if node_name == "Steps" else v * 100, false)
	$Palette.button_pressed = doc.effects.palette
	refreshing = false
