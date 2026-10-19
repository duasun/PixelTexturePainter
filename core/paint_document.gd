class_name PaintDocument
extends RefCounted

var title := "Untitled"
var width := 128
var height := 128
var layers: Array[PaintLayer] = []
var active_layer := 0
var editing_mask := false
var geometry: ModelGeometry
var effects: Dictionary = {"steps": 0, "dither": 0.0, "brightness": 0.0,
	"contrast": 1.0, "saturation": 1.0, "noise": 0.0, "noise_density": 1.0,
	"noise_grain": 1, "noise_mode": 0, "noise_seed": 0, "palette": false}
var palette := PackedColorArray([
	Color("17202e"), Color("303d50"), Color("566a7f"), Color("9bafbd"),
	Color("e4e9df"), Color("ffffff"), Color("8b434d"), Color("de6c64"),
	Color("eea765"), Color("f4d58d"), Color("536d45"), Color("91ac65"),
	Color("276961"), Color("52cbb1"), Color("528fc5"), Color("9d83bc")])
var path := ""
var palette_name := "Retro 16"
var primary_color := Color("eea765")
var secondary_color := Color.BLACK
var revision := 0
var saved_revision := 0
var stamp_image: Image
var stamp_region := Rect2i()
var stamp_name := ""
var stamp_rotation := 0.0
var reference_image: Image
var reference_name := ""
var reference_state: Dictionary = {"x":12.0,"y":90.0,"width":300.0,"height":325.0,"opacity":1.0,"locked":false,"visible":true}
var pattern_image: Image
var custom_pattern_image: Image
var pattern_settings: Dictionary = {"angle": 0.0, "scale": 1.0, "offset_x": 0.0, "offset_y": 0.0}
var uv_export_padding := 2
var palette_lookup: PaletteLookup
var lookup_colors := PackedColorArray()

func get_palette_lookup() -> PaletteLookup:
	if palette_lookup == null or lookup_colors != palette:
		lookup_colors = palette.duplicate()
		palette_lookup = PaletteLookup.new(palette)
	return palette_lookup

func initialize(w: int, h: int, color: Color) -> void:
	width = clampi(w, 16, 4096)
	height = clampi(h, 16, 4096)
	layers.clear()
	var base := PaintLayer.new()
	base.title = "Base color"
	base.base_color = color
	layers.append(base)
	var detail := PaintLayer.new()
	detail.title = "Paint 01"
	layers.append(detail)
	active_layer = 1

func selected_layer() -> PaintLayer:
	return layers[clampi(active_layer, 0, layers.size() - 1)]

func current_channel() -> String:
	return selected_layer().channel if not layers.is_empty() else "albedo"

func has_channel(channel: String) -> bool:
	for layer in layers:
		if layer.channel == channel: return true
	return false

func tile_extent() -> Vector2i:
	return Vector2i(ceili(width / 64.0), ceili(height / 64.0))

func all_keys() -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	var extent := tile_extent()
	for y in extent.y:
		for x in extent.x:
			keys.append(Vector2i(x, y))
	return keys

func compose_tile(key: Vector2i, channel := "") -> Image:
	if channel.is_empty(): channel = current_channel()
	var result := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	result.fill(PaintChannels.background(channel))
	for layer in layers:
		if layer.channel != channel or not layer.visible or layer.opacity <= 0.0:
			continue
		if layer.base_color.a <= 0.0 and not layer.tiles.has(key) and not layer.pattern_tiles.has(key):
			continue
		var source := layer.prepared_tile(key)
		if layer.blend_mode == 0:
			result.blend_rect(source, Rect2i(0, 0, 64, 64), Vector2i.ZERO)
		else:
			var data := source.get_data()
			var dst := result.get_data()
			for i in range(0, data.size(), 4):
				var alpha := data[i + 3] / 255.0
				if alpha <= 0.0:
					continue
				var da := dst[i + 3] / 255.0
				var out_a := alpha + da * (1.0 - alpha)
				for c in 3:
					var s := data[i + c] / 255.0
					var d := dst[i + c] / 255.0
					if layer.blend_mode == 1:
						s = lerpf(s, s * d, da)
					elif layer.blend_mode == 2:
						s = lerpf(s, minf(1.0, s + d), da)
					dst[i + c] = roundi(clampf((s * alpha + d * da * (1.0 - alpha)) / out_a, 0.0, 1.0) * 255.0)
				dst[i + 3] = roundi(out_a * 255.0)
			result = Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, dst)
	if PaintChannels.scalar(channel):
		result.convert(Image.FORMAT_L8)
		result.convert(Image.FORMAT_RGBA8)
	return result

func read_copy() -> PaintDocument:
	# Images are shared read-only; the worker owns dictionaries and composite caches.
	var result := PaintDocument.new()
	result.width = width
	result.height = height
	result.active_layer = active_layer
	result.editing_mask = editing_mask
	result.geometry = geometry
	result.effects = effects.duplicate(true)
	result.uv_export_padding = uv_export_padding
	result.palette = palette.duplicate()
	for layer in layers:
		var copy := PaintLayer.from_metadata(layer.metadata())
		copy.tiles = layer.tiles.duplicate()
		copy.masks = layer.masks.duplicate()
		copy.pattern_tiles = layer.pattern_tiles.duplicate()
		copy.pattern_image = layer.pattern_image
		result.layers.append(copy)
	return result

func snapshot() -> PaintDocument:
	var result := PaintDocument.new()
	result.title = title
	result.width = width
	result.height = height
	result.active_layer = active_layer
	result.editing_mask = editing_mask
	result.geometry = geometry
	result.effects = effects.duplicate(true)
	result.uv_export_padding = uv_export_padding
	result.palette = palette.duplicate()
	result.palette_name = palette_name
	result.primary_color = primary_color
	result.secondary_color = secondary_color
	result.revision = revision
	result.stamp_image = stamp_image
	result.stamp_region = stamp_region
	result.stamp_name = stamp_name
	result.stamp_rotation = stamp_rotation
	result.reference_image = reference_image
	result.reference_name = reference_name
	result.reference_state = reference_state.duplicate(true)
	result.pattern_image = pattern_image
	result.custom_pattern_image = custom_pattern_image
	result.pattern_settings = pattern_settings.duplicate(true)
	for layer in layers:
		result.layers.append(layer.copy_layer())
	return result
