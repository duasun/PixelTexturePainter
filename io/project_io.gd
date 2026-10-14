class_name ProjectIO
extends RefCounted
const VERSION := 2

static func save_project(progress: BackgroundJob.JobProgress, doc: PaintDocument, path: String) -> Dictionary:
	var temporary := path + ".tmp"
	var zip := ZIPPacker.new()
	var err := zip.open(temporary)
	if err != OK:
		return {"error": "Cannot write project: " + error_string(err)}
	var layer_meta: Array = []
	var colors: Array = []
	for c in doc.palette:
		colors.append(c.to_html(true))
	for i in doc.layers.size():
		var layer := doc.layers[i]
		var meta := layer.metadata()
		meta["tiles"] = []
		meta["masks"] = []
		meta["pattern_tiles"] = []
		for kind in ["tiles","masks","pattern_tiles"]:
			var bank: Dictionary = layer.tiles if kind == "tiles" else layer.masks if kind == "masks" else layer.pattern_tiles
			for key in bank:
				if progress.report(float(i) / doc.layers.size(), "Saving layer %d / %d" % [i + 1, doc.layers.size()]):
					zip.close()
					DirAccess.remove_absolute(temporary)
					return {"cancelled": true}
				var name := "layers/%d/%s/%d_%d.png" % [i, kind, key.x, key.y]
				meta[kind].append([key.x, key.y, name])
				if _write(zip, name, bank[key].save_png_to_buffer()) != OK:
					return _archive_error(zip)
		if layer.pattern_image != null:
			var image_path := "layers/%d/pattern.png" % i
			meta["pattern_image"] = image_path
			if _write(zip,image_path,layer.pattern_image.save_png_to_buffer()) != OK: return _archive_error(zip)
		layer_meta.append(meta)
	var manifest := {"format": "retro-texture-painter", "version": VERSION, "title": doc.title,
		"width": doc.width, "height": doc.height, "layers": layer_meta, "active_layer": doc.active_layer,
		"effects": doc.effects, "palette": colors, "palette_name": doc.palette_name,
		"primary_color": doc.primary_color.to_html(true), "secondary_color": doc.secondary_color.to_html(true),
		"revision": doc.revision, "pattern_settings": doc.pattern_settings, "uv_export_padding":doc.uv_export_padding,
		"stamp_region": [doc.stamp_region.position.x, doc.stamp_region.position.y, doc.stamp_region.size.x, doc.stamp_region.size.y],
		"stamp_name": doc.stamp_name, "stamp_rotation": doc.stamp_rotation}
	if _write(zip, "manifest.json", JSON.stringify(manifest, "\t").to_utf8_buffer()) != OK:
		return _archive_error(zip)
	if doc.geometry != null:
		if _write(zip, "geometry.bin", var_to_bytes(doc.geometry.serialized())) != OK:
			return _archive_error(zip)
	if doc.stamp_image != null:
		if _write(zip, "stamp.png", doc.stamp_image.save_png_to_buffer()) != OK:
			return _archive_error(zip)
	if doc.pattern_image != null:
		if _write(zip, "pattern.png", doc.pattern_image.save_png_to_buffer()) != OK:
			return _archive_error(zip)
	err = zip.close()
	if err != OK:
		return {"error": "Could not finish project archive."}
	# Replace only after a completed archive is readable. Preserve previous good save.
	var check := ZIPReader.new()
	if check.open(temporary) != OK or not check.file_exists("manifest.json"):
		return {"error": "Project verification failed; previous save was preserved."}
	check.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".bak")
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			return {"error": "Cannot replace project; close applications using the file."}
	err = DirAccess.rename_absolute(temporary, path)
	if err != OK:
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.rename_absolute(path + ".bak", path)
		return {"error": "Could not install new save. Previous save restored."}
	return {"path": path, "revision": doc.revision}

static func _write(zip: ZIPPacker, name: String, bytes: PackedByteArray) -> Error:
	if bytes.is_empty():
		return ERR_FILE_CORRUPT
	var error := zip.start_file(name)
	if error != OK:
		return error
	error = zip.write_file(bytes)
	var close_error := zip.close_file()
	return error if error != OK else close_error

static func _archive_error(zip: ZIPPacker) -> Dictionary:
	zip.close()
	return {"error": "Could not write project contents. Check available disk space. Previous save was preserved."}

static func load_project(progress: BackgroundJob.JobProgress, path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {"error": "This project could not be opened."}
	var data: Variant = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
	if not data is Dictionary or data.get("format") != "retro-texture-painter" or not int(data.get("version",0)) in [1,VERSION]:
		zip.close()
		return {"error": "Unsupported or damaged project format."}
	if int(data.get("width", 0)) < 16 or int(data.get("width", 0)) > 4096 or int(data.get("height", 0)) < 16 or int(data.get("height", 0)) > 4096:
		zip.close()
		return {"error": "Invalid texture dimensions."}
	if not data.get("layers") is Array or data.layers.is_empty() or data.layers.size() > 32:
		zip.close()
		return {"error": "Invalid layer list."}
	var doc := PaintDocument.new()
	doc.title = data.get("title", "Untitled")
	doc.width = int(data.width)
	doc.height = int(data.height)
	doc.path = path
	doc.effects.merge(data.get("effects", {}), true)
	doc.pattern_settings.merge(data.get("pattern_settings", {}), true)
	doc.uv_export_padding = clampi(int(data.get("uv_export_padding",2)),0,16)
	var stamp_bounds: Variant = data.get("stamp_region", [0, 0, 0, 0])
	if stamp_bounds is Array and stamp_bounds.size() == 4:
		doc.stamp_region = Rect2i(int(stamp_bounds[0]), int(stamp_bounds[1]), int(stamp_bounds[2]), int(stamp_bounds[3]))
	doc.stamp_name = str(data.get("stamp_name", "Embedded stamp")).left(128)
	doc.stamp_rotation = clampf(float(data.get("stamp_rotation",0.0)),-180.0,180.0)
	for asset in ["stamp", "pattern"]:
		if zip.file_exists(asset + ".png"):
			var image := Image.new()
			if image.load_png_from_buffer(zip.read_file(asset + ".png")) != OK or image.get_width() > 4096 or image.get_height() > 4096:
				zip.close()
				return {"error": "Invalid embedded texture."}
			image.convert(Image.FORMAT_RGBA8)
			doc.set(asset + "_image", image)
	if doc.stamp_image != null:
		var full := Rect2i(Vector2i.ZERO, doc.stamp_image.get_size())
		if doc.stamp_region.size.x <= 0 or doc.stamp_region.size.y <= 0:
			doc.stamp_region = full
		else:
			doc.stamp_region = doc.stamp_region.intersection(full)
			if not doc.stamp_region.has_area(): doc.stamp_region = full
	var palette_data: Variant = data.get("palette", [])
	if data.has("palette") and (not palette_data is Array or palette_data.size() < 1 or palette_data.size() > PaletteIO.MAX_COLORS):
		zip.close()
		return {"error": "Invalid project palette size."}
	if palette_data is Array and palette_data.size() >= 1 and palette_data.size() <= PaletteIO.MAX_COLORS:
		doc.palette.clear()
		for color in palette_data:
			if not color is String or not PaletteIO._hex(color, [6,8]):
				zip.close()
				return {"error": "Invalid project palette color."}
			doc.palette.append(Color.html(color))
	doc.palette_name = str(data.get("palette_name", "Project palette")).left(128)
	for property in ["primary_color", "secondary_color"]:
		var value: Variant = data.get(property)
		if value is String and PaletteIO._hex(value, [6,8]):
			doc.set(property, Color.html(value))
	for i in data.layers.size():
		var meta: Dictionary = data.layers[i]
		var layer := PaintLayer.from_metadata(meta)
		for kind in ["tiles", "masks", "pattern_tiles"]:
			var bank: Dictionary = layer.tiles if kind == "tiles" else layer.masks if kind == "masks" else layer.pattern_tiles
			for entry in meta.get(kind, []):
				var key := Vector2i(int(entry[0]), int(entry[1]))
				if key.x < 0 or key.y < 0 or key.x >= ceili(doc.width / 64.0) or key.y >= ceili(doc.height / 64.0):
					zip.close()
					return {"error": "Invalid tile coordinates."}
				var image := Image.new()
				if image.load_png_from_buffer(zip.read_file(entry[2])) != OK or image.get_size() != Vector2i(64, 64):
					zip.close()
					return {"error": "A project image is damaged."}
				image.convert(Image.FORMAT_RGBA8)
				bank[key] = image
		if meta.has("pattern_image"):
			var pattern := Image.new()
			if pattern.load_png_from_buffer(zip.read_file(str(meta.pattern_image))) != OK or pattern.get_width()>4096 or pattern.get_height()>4096:
				zip.close()
				return {"error":"A pattern layer image is damaged."}
			pattern.convert(Image.FORMAT_RGBA8)
			layer.pattern_image = pattern
		doc.layers.append(layer)
		progress.report(float(i + 1) / (data.layers.size() + 1), "Restoring layers…")
	if zip.file_exists("geometry.bin"):
		var geometry_data: Variant = bytes_to_var(zip.read_file("geometry.bin"))
		if not geometry_data is Dictionary:
			zip.close()
			return {"error": "Invalid model data."}
		doc.geometry = ModelGeometry.from_data(geometry_data)
		var count := doc.geometry.positions.size()
		if count == 0 or count % 3 != 0 or doc.geometry.uvs.size() != count or doc.geometry.normals.size() != count or doc.geometry.objects.size() != floori(count / 3.0) or doc.geometry.materials.size() != floori(count / 3.0):
			zip.close()
			return {"error": "Incomplete model data."}
		doc.geometry.build_cache()
	doc.active_layer = clampi(int(data.get("active_layer", 0)), 0, doc.layers.size() - 1)
	zip.close()
	return {"document": doc}

static func export_png(progress: BackgroundJob.JobProgress, doc: PaintDocument, path: String) -> Dictionary:
	var result := render_image(progress, doc)
	if not result.has("image"): return result
	if doc.uv_export_padding > 0 and doc.geometry != null and doc.geometry.has_uv:
		result = ProjectTransforms.dilate_uv(progress,result.image,doc.geometry,doc.uv_export_padding)
		if not result.has("image"): return result
	progress.report(0.98, "Writing PNG…")
	var error: Error = result.image.save_png(path)
	return {"path": path} if error == OK else {"error": "PNG export failed: " + error_string(error)}

static func render_image(progress: BackgroundJob.JobProgress, doc: PaintDocument, channel := "") -> Dictionary:
	if channel.is_empty(): channel = doc.current_channel()
	doc = doc.read_copy()
	var image := Image.create(doc.width, doc.height, false, Image.FORMAT_RGBA8)
	var keys := doc.all_keys()
	for i in keys.size():
		if progress.report(float(i) / keys.size(), "Rendering export…"):
			return {"cancelled": true}
		var tile := doc.compose_tile(keys[i], channel)
		if channel == "albedo" and doc.effects != {"steps": 0, "dither": 0.0, "brightness": 0.0, "contrast": 1.0, "saturation": 1.0, "noise": 0.0, "palette": false}:
			tile = apply_effects(tile, keys[i] * 64, doc)
		image.blit_rect(tile, Rect2i(0, 0, 64, 64), keys[i] * 64)
	return {"image": image}

static func apply_effects(image: Image, origin: Vector2i, doc: PaintDocument) -> Image:
	var data := image.get_data()
	var fx := doc.effects
	var lookup := doc.get_palette_lookup() if fx.palette else null
	var bayer := [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5]
	for y in image.get_height():
		for x in image.get_width():
			var i := (y * image.get_width() + x) * 4
			var c := Vector3(data[i], data[i + 1], data[i + 2]) / 255.0
			c = (c - Vector3.ONE * 0.5) * float(fx.contrast) + Vector3.ONE * (0.5 + float(fx.brightness))
			var lum := c.dot(Vector3(0.299, 0.587, 0.114))
			c = (Vector3.ONE * lum).lerp(c, float(fx.saturation))
			var p := origin + Vector2i(x, y)
			c += Vector3.ONE * ((p.x * 13 + p.y * 57) % 17 / 16.0 - 0.5) * float(fx.noise)
			var d: float = (bayer[(p.y % 4) * 4 + p.x % 4] / 16.0 - 0.46875) * float(fx.dither)
			if int(fx.steps) > 1:
				var levels := float(fx.steps) - 1.0
				for axis in 3:
					c[axis] = floorf(clampf(c[axis] + d / levels, 0.0, 1.0) * levels + 0.5) / levels
			if fx.palette:
				c = lookup.nearest(c + Vector3.ONE * d / 8.0)
			for axis in 3:
				data[i + axis] = roundi(clampf(c[axis], 0.0, 1.0) * 255)
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)

static func export_obj(model: ModelGeometry, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot write model."}
	file.store_line("# Retro Texture Painter — current UV layout")
	for p in model.positions:
		file.store_line("v %.9f %.9f %.9f" % [p.x, p.y, p.z])
	for uv in model.uvs:
		file.store_line("vt %.9f %.9f" % [uv.x, 1.0 - uv.y])
	for f in model.face_count():
		var a := f * 3 + 1
		file.store_line("f %d/%d %d/%d %d/%d" % [a, a, a + 2, a + 2, a + 1, a + 1])
	return {"path": path}
