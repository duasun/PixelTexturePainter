class_name PaletteIO
extends RefCounted
const MAX_COLORS := 1024
const MAX_BYTES := 16 * 1024 * 1024

static func load_palette(progress: BackgroundJob.JobProgress, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open palette file."}
	if file.get_length() > MAX_BYTES:
		return {"error": "Choose a palette file smaller than 16 MiB."}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	progress.report(0.1, "Reading palette…")
	return parse(bytes, path.get_extension().to_lower(), path.get_file().get_basename(), progress)

static func parse(bytes: PackedByteArray, extension: String, title := "Palette", progress: BackgroundJob.JobProgress = null) -> Dictionary:
	if bytes.size() > MAX_BYTES:
		return {"error": "Palette file is too large."}
	if extension == "png":
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			return {"error": "The PNG palette could not be decoded."}
		return from_image(image, title, progress)
	if extension == "ase":
		return _ase(bytes, title)
	var text := bytes.get_string_from_utf8().trim_prefix("\ufeff").replace("\r", "")
	var colors := PackedColorArray()
	if extension == "json":
		var data: Variant = JSON.parse_string(text)
		if not data is Dictionary or not data.get("colors") is Array:
			return {"error": "Expected Lospec JSON with a colors array."}
		title = str(data.get("name", title))
		for value in data.colors:
			if not value is String or not _hex(value.trim_prefix("#"), [6,8]):
				return {"error": "Invalid hex color in JSON palette."}
			colors.append(Color.html(value))
	elif extension == "csv":
		var values := _csv(text.strip_edges())
		if values.size() < 3:
			return {"error": "Expected Lospec CSV: name, author, colors…"}
		title = values[0]
		for value in values.slice(2):
			var color: String = value.strip_edges().trim_prefix("#")
			if not _hex(color, [6,8]):
				return {"error": "Invalid hex color in CSV palette."}
			colors.append(Color.html(color))
	elif extension == "pal":
		var rows := text.strip_edges().split("\n", false)
		if rows.size() < 3 or rows[0].strip_edges() != "JASC-PAL" or rows[1].strip_edges() != "0100":
			return {"error": "This PAL is not a JASC-PAL 0100 palette."}
		var count_text := rows[2].strip_edges()
		if not count_text.is_valid_int() or int(count_text) < 1 or int(count_text) > MAX_COLORS or rows.size() != int(count_text) + 3:
			return {"error": "Invalid JASC palette color count (1–1024 supported)."}
		for row in rows.slice(3):
			var rgb := _rgb(row)
			if rgb.is_empty():
				return {"error": "Invalid RGB entry in JASC palette."}
			colors.append(rgb[0])
	elif extension == "gpl":
		if not text.begins_with("GIMP Palette"):
			return {"error": "Invalid GIMP palette header."}
		for row in text.split("\n").slice(1):
			row = row.strip_edges()
			if row.begins_with("Name:"):
				title = row.substr(5).strip_edges()
			elif row.is_empty() or row.begins_with("#") or row.begins_with("Columns:"):
				continue
			else:
				var rgb := _rgb(row)
				if rgb.is_empty():
					return {"error": "Invalid RGB entry in GIMP palette."}
				colors.append(rgb[0])
	elif extension in ["hex", "txt"]:
		for row in text.split("\n"):
			row = row.strip_edges()
			if row.begins_with(";Palette Name:"):
				title = row.substr(14).strip_edges()
			if row.is_empty() or row.begins_with(";") or row.begins_with("//"):
				continue
			var value: String = row.trim_prefix("#")
			if row.begins_with("#") and not _hex(value, [6,8]):
				continue
			if not _hex(value, [6,8]):
				return {"error": "Invalid hex palette entry: " + row.left(40)}
			# Paint.NET uses AARRGGBB; Godot/HEX use RRGGBBAA.
			if extension == "txt" and value.length() == 8:
				value = value.substr(2) + value.left(2)
			colors.append(Color.html(value))
	else:
		return {"error": "Supported palettes: PNG, HEX, GPL, PAL, TXT, ASE, JSON and CSV."}
	return _finish(colors, title)

static func from_image(image: Image, title := "PNG palette", progress: BackgroundJob.JobProgress = null) -> Dictionary:
	if image.get_width() * image.get_height() > 16777216:
		return {"error": "PNG palette is larger than 16 megapixels."}
	image.convert(Image.FORMAT_RGBA8)
	var colors := PackedColorArray()
	var seen: Dictionary = {}
	# Row-major order works for 1px strips, grids and enlarged Lospec swatches.
	for y in image.get_height():
		if progress != null and progress.report(float(y) / image.get_height(), "Reading palette colors…"):
			return {"cancelled": true}
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.a == 0:
				continue
			var key := color.to_rgba32()
			if not seen.has(key):
				seen[key] = true
				colors.append(color)
				if colors.size() > MAX_COLORS:
					return {"error": "This image has more than 1024 colors. Choose a palette image, not a photograph."}
	return _finish(colors, title)

static func _finish(colors: PackedColorArray, title: String) -> Dictionary:
	if colors.is_empty() or colors.size() > MAX_COLORS:
		return {"error": "A palette must contain between 1 and 1024 colors."}
	return {"palette": colors, "name": title.strip_edges().left(128)}

static func _hex(value: String, lengths: Array) -> bool:
	if not value.length() in lengths:
		return false
	for c in value.to_lower():
		if not c in "0123456789abcdef":
			return false
	return true

static func _rgb(row: String) -> PackedColorArray:
	var parts := row.replace("\t", " ").split(" ", false)
	if parts.size() < 3:
		return PackedColorArray()
	for i in 3:
		if not parts[i].is_valid_int() or int(parts[i]) < 0 or int(parts[i]) > 255:
			return PackedColorArray()
	return PackedColorArray([Color8(int(parts[0]),int(parts[1]),int(parts[2]))])

static func _csv(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	var value := ""
	var quoted := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == '"':
			if quoted and i + 1 < text.length() and text[i + 1] == '"':
				value += '"'
				i += 1
			else:
				quoted = not quoted
		elif c == "," and not quoted:
			result.append(value)
			value = ""
		else:
			value += c
		i += 1
	result.append(value)
	return result if not quoted else PackedStringArray()

static func _ase(bytes: PackedByteArray, title: String) -> Dictionary:
	if bytes.size() < 12 or bytes.slice(0,4).get_string_from_ascii() != "ASEF":
		return {"error": "Invalid Adobe ASE header."}
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	stream.big_endian = true
	stream.seek(4)
	if stream.get_u16() != 1:
		return {"error": "Unsupported Adobe ASE version."}
	stream.get_u16()
	var blocks := stream.get_u32()
	if blocks > 8192:
		return {"error": "Too many ASE blocks."}
	var colors := PackedColorArray()
	for block in blocks:
		if stream.get_available_bytes() < 6:
			return {"error": "Truncated ASE block header."}
		var kind := stream.get_u16()
		var length := stream.get_u32()
		if length > stream.get_available_bytes():
			return {"error": "Truncated ASE block."}
		var end := stream.get_position() + length
		if kind == 1:
			if length < 2:
				return {"error": "Invalid ASE color entry."}
			var name_length := stream.get_u16()
			if stream.get_position() + name_length * 2 + 4 > end:
				return {"error": "Invalid ASE color name."}
			stream.seek(stream.get_position() + name_length * 2)
			var mode := bytes.slice(stream.get_position(), stream.get_position()+4).get_string_from_ascii()
			stream.seek(stream.get_position()+4)
			if mode == "RGB " and stream.get_position()+14 <= end:
				var r := stream.get_float()
				var g := stream.get_float()
				var b := stream.get_float()
				if not is_finite(r) or not is_finite(g) or not is_finite(b) or minf(r,minf(g,b)) < 0 or maxf(r,maxf(g,b)) > 1:
					return {"error": "Invalid ASE RGB values."}
				colors.append(Color(r,g,b))
			elif mode == "Gray" and stream.get_position()+6 <= end:
				var gray := stream.get_float()
				if not is_finite(gray) or gray < 0 or gray > 1:
					return {"error": "Invalid ASE grayscale value."}
				colors.append(Color(gray,gray,gray))
			else:
				return {"error": "Use an RGB ASE palette (Lospec export). CMYK/Lab ASE is not supported."}
		stream.seek(end)
	return _finish(colors, title)
