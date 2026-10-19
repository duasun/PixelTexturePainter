class_name TileDisplay
extends Node
## Only dirty 64px blocks are composited. GPU pages are 256px, at most 256 layers at 4K.
signal refreshed
const PAGE := 256
var document: PaintDocument
var texture_array: Texture2DArray
var pages: Array[Image] = []
var columns := 1
var dirty: Dictionary = {}
var urgent: Dictionary = {}
var upload_pending: Dictionary = {}
var _queue: Array[Vector2i] = []
var _urgent_queue: Array[Vector2i] = []
var last_work_ms := 0.0
var last_upload_bytes := 0
var _palette_colors := PackedColorArray()
var _palette_texture: ImageTexture

func setup(doc: PaintDocument) -> void:
	document = doc
	columns = ceili(doc.width / float(PAGE))
	var rows := ceili(doc.height / float(PAGE))
	pages.clear()
	dirty.clear()
	urgent.clear()
	upload_pending.clear()
	_queue.clear()
	_urgent_queue.clear()
	for i in columns * rows:
		var img := Image.create(PAGE, PAGE, false, Image.FORMAT_RGBA8)
		img.fill(doc.layers[0].base_color if doc.current_channel() == "albedo" else PaintChannels.background(doc.current_channel()))
		pages.append(img)
	texture_array = Texture2DArray.new()
	texture_array.create_from_images(pages)
	mark(doc.all_keys(), false)

func mark(keys: Array[Vector2i], priority := true) -> void:
	for key in keys:
		if priority:
			if not urgent.has(key):
				urgent[key] = true
				_urgent_queue.append(key)
		else:
			if not dirty.has(key):
				dirty[key] = true
				_queue.append(key)

func _process(_delta: float) -> void:
	if document == null or (dirty.is_empty() and urgent.is_empty() and upload_pending.is_empty()):
		return
	var start := Time.get_ticks_usec()
	while (not _urgent_queue.is_empty() or not _queue.is_empty()) and Time.get_ticks_usec() - start < 4000:
		var key: Vector2i = _urgent_queue.pop_back() if not _urgent_queue.is_empty() else _queue.pop_back()
		if not urgent.has(key) and not dirty.has(key):
			continue
		urgent.erase(key)
		dirty.erase(key)
		var composed := document.compose_tile(key)
		var page_xy := Vector2i(key.x >> 2, key.y >> 2)
		var index := page_xy.y * columns + page_xy.x
		pages[index].blit_rect(composed, Rect2i(0, 0, 64, 64), Vector2i(key.x % 4, key.y % 4) * 64)
		upload_pending[index] = true
	last_upload_bytes = 0
	var count := 0
	for index in upload_pending.keys():
		texture_array.update_layer(pages[index], index)
		upload_pending.erase(index)
		last_upload_bytes += PAGE * PAGE * 4
		count += 1
		if count >= 4:
			break
	last_work_ms = (Time.get_ticks_usec() - start) / 1000.0
	refreshed.emit()

func apply_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter("pages", texture_array)
	material.set_shader_parameter("texture_size", Vector2(document.width, document.height))
	material.set_shader_parameter("page_columns", columns)
	var effects := document.effective_effects() if document.current_channel() == "albedo" else PaintDocument.new().effective_effects()
	for key in effects:
		if not str(key).ends_with("_enabled"): material.set_shader_parameter("fx_" + key, effects[key])
	if _palette_texture == null or _palette_colors != document.palette:
		_palette_colors = document.palette.duplicate()
		_palette_texture = ImageTexture.create_from_image(PaletteLookup.build(_palette_colors))
	var small := document.palette.slice(0,32)
	small.resize(32)
	material.set_shader_parameter("palette_colors", small)
	material.set_shader_parameter("palette_count", document.palette.size())
	material.set_shader_parameter("palette_tree", _palette_texture)

func is_settled() -> bool:
	return dirty.is_empty() and urgent.is_empty() and upload_pending.is_empty()
