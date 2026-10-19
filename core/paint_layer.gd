class_name PaintLayer
extends RefCounted
## Sparse 64x64 CPU tiles. Missing color tiles use base_color; missing masks are white.
const TILE := 64
var id: String = str(Time.get_ticks_usec())
var title := "Paint layer"
var effect_kind := ""
var effect_source_id := ""
var channel := "albedo"
var visible := true
var locked := false
var opacity := 1.0
var blend_mode := 0
var base_color := Color.TRANSPARENT
var tiles: Dictionary = {}
var masks: Dictionary = {}
var pattern_tiles: Dictionary = {}
var pattern_image: Image
var pattern_faces := PackedInt32Array()
var pattern_settings: Dictionary = {}
var mask_enabled := false
var _prepared: Dictionary = {}
var _prepared_opacity := -1.0
var _prepared_mask := false

func invalidate(key: Vector2i) -> void:
	_prepared.erase(key)

func prepared_tile(key: Vector2i) -> Image:
	if not is_equal_approx(_prepared_opacity, opacity) or _prepared_mask != mask_enabled:
		_prepared.clear()
		_prepared_opacity = opacity
		_prepared_mask = mask_enabled
	var source := tile_at(key, false, false)
	if pattern_tiles.has(key):
		source = pattern_tiles[key].duplicate()
		if tiles.has(key): source.blend_rect(tiles[key],Rect2i(0,0,64,64),Vector2i.ZERO)
	if opacity >= 1.0 and (not mask_enabled or not masks.has(key)):
		return source
	if _prepared.has(key):
		return _prepared[key]
	var data := source.get_data()
	var mask_data: PackedByteArray = masks[key].get_data() if mask_enabled and masks.has(key) else PackedByteArray()
	for i in range(3, data.size(), 4):
		var alpha := data[i] * opacity
		if not mask_data.is_empty():
			alpha *= mask_data[i - 3] / 255.0
		data[i] = roundi(alpha)
	var prepared := Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, data)
	_prepared[key] = prepared
	return prepared

func tile_at(key: Vector2i, mask := false, create := true) -> Image:
	var bank: Dictionary = masks if mask else tiles
	if bank.has(key):
		return bank[key]
	var result := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	result.fill(Color.WHITE if mask else base_color)
	if create:
		bank[key] = result
	return result

func metadata() -> Dictionary:
	var faces: Array[int] = []
	for face in pattern_faces: faces.append(face)
	return {"id": id, "title": title, "channel": channel, "visible": visible, "locked": locked,
		"effect_kind": effect_kind, "effect_source_id": effect_source_id,
		"opacity": opacity, "blend_mode": blend_mode,
		"base": base_color.to_html(true), "mask_enabled": mask_enabled,
		"pattern_faces":faces, "pattern_settings":pattern_settings.duplicate(true)}

static func from_metadata(data: Dictionary) -> PaintLayer:
	var layer := PaintLayer.new()
	layer.id = data.get("id", layer.id)
	layer.title = data.get("title", "Layer")
	layer.effect_kind = str(data.get("effect_kind",""))
	if not data.has("effect_kind"):
		match layer.title:
			"Edge highlights": layer.effect_kind = "edges"
			"Cavity AO": layer.effect_kind = "ao"
			"From Height": layer.effect_kind = "normal"
	layer.effect_source_id = str(data.get("effect_source_id",""))
	layer.channel = str(data.get("channel", "albedo"))
	if not layer.channel in PaintChannels.IDS: layer.channel = "albedo"
	layer.visible = data.get("visible", true)
	layer.locked = data.get("locked", false)
	layer.opacity = clampf(float(data.get("opacity", 1.0)), 0.0, 1.0)
	layer.blend_mode = clampi(int(data.get("blend_mode", 0)), 0, 2)
	layer.base_color = Color.html(data.get("base", "00000000"))
	layer.mask_enabled = data.get("mask_enabled", false)
	var faces: Variant = data.get("pattern_faces",[])
	if faces is Array:
		for face in faces: layer.pattern_faces.append(int(face))
	layer.pattern_settings = data.get("pattern_settings",{}).duplicate(true)
	return layer

func copy_layer() -> PaintLayer:
	var result := from_metadata(metadata())
	for key in tiles:
		result.tiles[key] = tiles[key].duplicate()
	for key in masks:
		result.masks[key] = masks[key].duplicate()
	for key in pattern_tiles:
		result.pattern_tiles[key] = pattern_tiles[key].duplicate()
	result.pattern_image = pattern_image
	return result
