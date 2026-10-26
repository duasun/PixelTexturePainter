extends VBoxContainer
signal effect_changed(key: String, value: Variant)
signal layer_effect_toggled(kind: String, enabled: bool)
signal section_changed
var refreshing := false
const LAYER_TOGGLES := {"AdjustmentsEnabled":"adjustments","NoiseEnabled":"noise","Palette":"palette","EdgesEnabled":"edges","AOEnabled":"ao","NormalEnabled":"normal","BlurEnabled":"blur","DirectionalEnabled":"directional"}
const PERCENT_SETTINGS := {"Brightness": "brightness", "Contrast": "contrast", "Saturation": "saturation", "Noise": "noise", "NoiseDensity": "noise_density"}
const INTEGER_SETTINGS := {"NoiseGrain": "noise_grain", "NoiseSeedRow/NoiseSeed": "noise_seed"}
const SECTIONS := {
	"SectionBrightnessLabel": ["AdjustmentsEnabled","BrightnessLabel","Brightness","ContrastLabel","Contrast","SaturationLabel","Saturation"],
	"SectionNoiseLabel": ["NoiseEnabled","NoiseLabel","Noise","NoiseDensityLabel","NoiseDensity","NoiseGrainLabel","NoiseGrain","NoiseModeLabel","NoiseMode","NoiseSeedLabel","NoiseSeedRow"],
	"SectionPaletteLabel": ["Palette","Reset"],
	"EdgeSection": ["EdgesEnabled","EdgeLabel","EdgeWidthLabel","EdgeWidth","EdgeScatterLabel","EdgeScatter","EdgeNoiseLabel","EdgeNoise","EdgeFalloffLabel","EdgeFalloff","Edges"],
	"AOSection": ["AOEnabled","AOInfo","AOStrengthLabel","AOStrength","AORadiusLabel","AORadius","AODepthLabel","AODepth","AOFalloffLabel","AOFalloff","AOGenerate"],
	"NormalSection": ["NormalEnabled","NormalInfo","NormalStrengthLabel","NormalStrength","NormalGenerate"],
	"BlurSection": ["BlurEnabled","BlurInfo","BlurRadiusLabel","BlurRadius","BlurPreview","BlurApply","BlurCancel"],
	"DirectionalSection": ["DirectionalEnabled","DirectionalInfo","DirectionalLengthLabel","DirectionalLength","DirectionalAngleLabel","DirectionalAngle","DirectionalStrengthLabel","DirectionalStrength","DirectionalPreview","DirectionalApply","DirectionalCancel"]}

func _ready() -> void:
	for node_name in LAYER_TOGGLES:
		get_node(node_name).toggled.connect(func(on: bool):
			if not refreshing: layer_effect_toggled.emit(LAYER_TOGGLES[node_name],on))
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
	$Hint.text = "Named FX layers stay on top · visible FX export to PNG" if channel == "albedo" else "Albedo FX unavailable on this map · generators below"
	for control_name in PERCENT_SETTINGS.keys() + INTEGER_SETTINGS.keys():
		get_node(control_name).set_deferred("mouse_filter", Control.MOUSE_FILTER_STOP)
		get_node(control_name).modulate.a = 1.0 if channel == "albedo" else 0.45
	$NoiseMode.disabled = channel != "albedo"
	$NoiseSeedRow/NoiseReseed.disabled = channel != "albedo"
	$Palette.disabled = channel != "albedo"
	$Reset.disabled = channel != "albedo"
	$AdjustmentsEnabled.disabled = channel != "albedo"
	$NoiseEnabled.disabled = channel != "albedo"
	for node_name in ["EdgesEnabled","AOEnabled","BlurEnabled","DirectionalEnabled"]:
		get_node(node_name).disabled = channel != "albedo"

func refresh(doc: PaintDocument) -> void:
	refreshing = true
	for node_name in PERCENT_SETTINGS:
		var key: String = PERCENT_SETTINGS[node_name]
		var kind := "noise" if key.begins_with("noise") else "adjustments"
		var layer := doc.effect_layer(kind)
		var v: float = float(layer.effect_settings.get(key,doc.effects[key])) if layer != null else float(doc.effects[key])
		get_node(node_name).set_value(v * 100, false)
	for node_name in INTEGER_SETTINGS:
		var key: String = INTEGER_SETTINGS[node_name]
		var layer := doc.effect_layer("noise")
		get_node(node_name).set_value(float(layer.effect_settings.get(key,doc.effects[key])) if layer != null else float(doc.effects[key]), false)
	var noise_layer := doc.effect_layer("noise")
	$NoiseMode.select(clampi(int(noise_layer.effect_settings.get("noise_mode",doc.effects.noise_mode)) if noise_layer != null else int(doc.effects.noise_mode), 0, 3))
	var controls := {"edges":{"EdgeWidth":"width","EdgeScatter":"scatter","EdgeNoise":"noise","EdgeFalloff":"falloff"},
		"ao":{"AOStrength":"strength","AORadius":"radius","AODepth":"depth"},
		"normal":{"NormalStrength":"strength"},"blur":{"BlurRadius":"radius"},
		"directional":{"DirectionalLength":"length","DirectionalAngle":"angle","DirectionalStrength":"strength"}}
	for kind in controls:
		var fx_layer := doc.effect_layer(kind)
		if fx_layer == null: continue
		for control_name in controls[kind]:
			var setting: String = controls[kind][control_name]
			if fx_layer.effect_settings.has(setting): get_node(control_name).set_value(float(fx_layer.effect_settings[setting]),false)
	var ao_layer := doc.effect_layer("ao")
	if ao_layer != null and ao_layer.effect_settings.has("falloff"): $AOFalloff.select(clampi(int(ao_layer.effect_settings.falloff),0,$AOFalloff.item_count-1))
	refresh_layer_toggles(doc)
	refreshing = false

func refresh_layer_toggles(doc: PaintDocument) -> void:
	for node_name in LAYER_TOGGLES:
		var kind: String = LAYER_TOGGLES[node_name]
		var active := false
		var layer := doc.effect_layer(kind)
		if layer != null: active = layer.visible
		elif kind in ["adjustments","noise","palette"]:
			active = bool(doc.effects.get("palette" if kind == "palette" else kind + "_enabled",false))
		get_node(node_name).set_pressed_no_signal(active)
