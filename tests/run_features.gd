extends SceneTree
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	var progress := BackgroundJob.JobProgress.new()
	var expected := PackedColorArray([Color("be4a2f"), Color("d77643")])
	for ext in ["hex", "gpl", "pal", "txt", "ase"]:
		var path: String = "res://test_output/lospec/endesga-32." + ext
		if FileAccess.file_exists(path):
			var parsed := PaletteIO.load_palette(progress, path)
			check(parsed.has("palette") and parsed.palette.size() == 32 and parsed.palette[0].to_rgba32() == expected[0].to_rgba32() and parsed.palette[1].to_rgba32() == expected[1].to_rgba32(), "Real Lospec " + ext + " decodes count, order and values")
	var json := '{"name":"Small","colors":["be4a2f","d77643"]}'
	var csv := '"Name, quoted",Author,be4a2f,d77643'
	check(PaletteIO.parse(json.to_utf8_buffer(), "json").palette == expected, "Lospec JSON")
	check(PaletteIO.parse(csv.to_utf8_buffer(), "csv").palette == expected, "Lospec CSV with quoted name")
	var png := Image.create(3, 1, false, Image.FORMAT_RGBA8)
	png.set_pixel(0, 0, expected[0]); png.set_pixel(1, 0, expected[1]); png.set_pixel(2, 0, Color.TRANSPARENT)
	check(PaletteIO.parse(png.save_png_to_buffer(), "png").palette == expected, "One-pixel PNG strip ignores transparency")
	png.resize(24, 8, Image.INTERPOLATE_NEAREST)
	check(PaletteIO.from_image(png).palette == expected, "Enlarged PNG deduplicates swatches in order")
	check(PaletteIO.parse("JASC-PAL\n0100\n2\n255 0 0".to_utf8_buffer(), "pal").has("error"), "Truncated palette rejected")
	check(PaletteIO.parse("not hex".to_utf8_buffer(), "hex").has("error"), "Invalid color rejected")
	var alpha := PaletteIO.parse("80ff0000".to_utf8_buffer(), "txt").palette[0] as Color
	check(alpha.r == 1 and alpha.g == 0 and is_equal_approx(alpha.a, 128.0 / 255), "Paint.NET AARRGGBB preserved")
	var doc := PaintDocument.new()
	doc.initialize(128, 64, Color.WHITE)
	var base := doc.layers[0]
	# A one-pixel wall separates same-color regions, including across a tile boundary.
	var wall := base.tile_at(Vector2i(1,0))
	wall.fill_rect(Rect2i(16,0,1,64), Color.BLACK)
	var fill := PaintFloodFill.run(progress, doc, Vector2i(10,20), -1, Color.RED)
	check(fill.command.after.size() == 2, "Flood crosses tile boundary")
	check(fill.command.after[Vector2i(1,0)].get_pixel(15,20) == Color.RED and fill.command.after[Vector2i(1,0)].get_pixel(16,20).a == 0 and fill.command.after[Vector2i(1,0)].get_pixel(17,20).a == 0, "Flood stops at color wall and leaves disconnected same-color region")
	check(doc.selected_layer().tiles.is_empty(), "Flood worker never mutates live document")
	var history := PaintHistory.new()
	for key in fill.command.after: doc.selected_layer().tiles[key] = fill.command.after[key]
	history.push(doc, fill.command)
	history.undo(doc)
	check(doc.selected_layer().tiles.is_empty(), "Flood undo restores sparse layer")
	history.redo(doc)
	check(doc.selected_layer().tiles[Vector2i.ZERO].get_pixel(0,0) == Color.RED, "Flood redo restores pixels")
	doc.initialize(16,16,Color.BLACK)
	var t := doc.layers[0].tile_at(Vector2i.ZERO)
	t.set_pixel(2,2,Color.WHITE); t.set_pixel(3,3,Color.WHITE)
	fill = PaintFloodFill.run(progress, doc, Vector2i(2,2), -1, Color.BLUE)
	check(fill.command.after[Vector2i.ZERO].get_pixel(2,2) == Color.BLUE and fill.command.after[Vector2i.ZERO].get_pixel(3,3).a == 0, "Diagonal pixels remain disconnected")
	doc.editing_mask = true
	doc.selected_layer().tile_at(Vector2i.ZERO, true).fill_rect(Rect2i(8,0,1,16), Color.BLACK)
	fill = PaintFloodFill.run(progress, doc, Vector2i(1,1), -1, Color.BLACK)
	check(fill.command.after[Vector2i.ZERO].get_pixel(7,1) == Color.BLACK and fill.command.after[Vector2i.ZERO].get_pixel(9,1) == Color.WHITE, "Mask flood matches mask pixels")
	var cancelled := BackgroundJob.JobProgress.new()
	cancelled.cancel()
	check(PaintFloodFill.run(cancelled, doc, Vector2i.ONE, -1, Color.BLACK).get("cancelled",false), "Flood cancellation produces no command")
	doc = PaintDocument.new()
	doc.initialize(4096,4096,Color.WHITE)
	var start := Time.get_ticks_usec()
	fill = PaintFloodFill.run(progress, doc, Vector2i(2048,2048), -1, Color.RED)
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	check(fill.command.after.size() == 4096, "4K uniform fill covers every tile")
	print("4K flood fill: %.2f ms" % elapsed)
	fill.clear()
	doc = PaintDocument.new()
	doc.initialize(64,64,Color("3478ad"))
	doc.geometry = UVUnwrapper.unwrap(ModelGeometry.demo(),64,64,45.0,1).geometry
	var seed_face := 0
	var seed_uv := (doc.geometry.uvs[0] + doc.geometry.uvs[1] + doc.geometry.uvs[2]) / 3.0
	fill = PaintFloodFill.run(progress, doc, Vector2i(seed_uv * 64), doc.geometry.islands[seed_face], Color.RED)
	var covered := 0
	for key in fill.command.after:
		var image: Image = fill.command.after[key]
		for y in 64:
			for x in 64:
				if image.get_pixel(x,y).a > 0: covered += 1
	check(covered > 0 and covered < 64 * 64 / 4, "Model bucket stays within clicked UV island")
	var grown := doc.geometry.grow_selection(PackedInt32Array([0]))
	check(grown.size() == doc.geometry.neighbors[0].size() + 1 and grown.has(0), "Selection grows exactly one shared-edge ring")
	for face in grown:
		check(doc.geometry.objects[face] == doc.geometry.objects[0], "Growth respects disconnected objects")
	# Palettes beyond 16 colors and both current colors survive project round-trip.
	doc.palette.clear()
	for i in 256: doc.palette.append(Color8(i, 255-i, (i*13)%256))
	doc.palette_name = "Large palette"
	var lookup := PaletteLookup.new(doc.palette)
	var correct := true
	for i in 200:
		var point := Vector3((i*37)%256,(i*91)%256,(i*19)%256)/255.0
		var best := INF
		var nearest := point
		for candidate in doc.palette:
			var v := Vector3(candidate.r,candidate.g,candidate.b)
			var distance := point.distance_squared_to(v)
			if distance < best - 0.0000001:
				best = distance
				nearest = v
		if not lookup.nearest(point).is_equal_approx(nearest): correct = false
	check(correct, "Balanced palette search agrees with exhaustive search")
	doc.primary_color = doc.palette[230]; doc.secondary_color = doc.palette[42]
	var path := ProjectSettings.globalize_path("res://test_output/features.rtpaint")
	check(not ProjectIO.save_project(progress, doc, path).has("error"), "Save project with 256-color palette")
	var loaded := ProjectIO.load_project(progress, path)
	check(loaded.has("document") and loaded.document.palette == doc.palette and loaded.document.primary_color == doc.primary_color and loaded.document.secondary_color == doc.secondary_color, "Palette and current colors survive project load")
	# Native glTF exporter round-trip checks geometry, UVs, texture and filtering.
	for extension in ["glb", "gltf"]:
		path = ProjectSettings.globalize_path("res://test_output/painted." + extension)
		var exported := ModelExport.save(progress, doc, path)
		check(not exported.has("error"), "Export " + extension)
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var error := gltf.append_from_file(path, state)
		check(error == OK and state.get_meshes().size() > 0, "Read exported " + extension)
		if error == OK:
			var materials := state.get_materials()
			check(materials.size() == 1 and materials[0].albedo_texture != null, extension + " includes painted material")
			if materials.size() > 0 and materials[0].albedo_texture != null:
				var exported_image: Image = materials[0].albedo_texture.get_image()
				check(exported_image.get_size() == Vector2i(64,64) and exported_image.get_pixel(10,10).to_rgba32() == Color("3478ad").to_rgba32(), extension + " preserves painted texels")
				check(materials[0].texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, extension + " keeps nearest filtering")
		var imported := ModelIO.load_model(progress, path)
		check(imported.has("geometry") and imported.geometry.face_count() == doc.geometry.face_count() and imported.geometry.has_uv, extension + " preserves triangle count and UVs")
		if imported.has("geometry"):
			check(imported.geometry.bounds.size.is_equal_approx(doc.geometry.bounds.size), extension + " preserves model dimensions")
	# Soft brush alpha is computed once per stroke; flat centre and feathered edge stay distinct.
	var painter := PaintEngine.new()
	painter.document = doc
	painter.history = PaintHistory.new()
	painter.brush_size = 9
	painter.falloff = 1.0
	painter.shape = 1
	painter._stroke_tool = "brush"
	painter._stroke_color = Color.WHITE
	painter._stroke_brush_size = 9
	painter._stroke_opacity = 1.0
	painter._stroke_shape = 1
	painter._stroke_falloff = 1.0
	painter._stroke_dither = false
	painter._mask = false
	painter._make_stamp()
	check(painter._stamp.get_pixel(4,4).a > painter._stamp.get_pixel(2,2).a and painter._stamp.get_pixel(2,2).a > 0.0,"Soft brush fades from center to edge")
	painter._stroke_falloff = 0.0
	painter._make_stamp()
	check(painter._stamp.get_pixel(4,4).a == painter._stamp.get_pixel(2,2).a,"Zero falloff keeps a hard pixel brush")
	painter.free()
	# Height-to-Normal samples across 64px tile seams and leaves flat areas sparse.
	var height_doc := PaintDocument.new()
	height_doc.initialize(128,64,Color.TRANSPARENT)
	var height_layer := PaintLayer.new()
	height_layer.channel = "height"
	height_layer.tile_at(Vector2i.ZERO).fill(Color8(128,128,128))
	height_layer.tiles[Vector2i.ZERO].set_pixel(63,20,Color.WHITE)
	height_doc.layers.append(height_layer)
	var normal := PaintOperations.normal_from_height(progress,height_doc,1.0)
	check(normal.layer.tiles.has(Vector2i.ZERO) and normal.layer.tiles.has(Vector2i(1,0)),"Normal generator crosses height tile boundary")
	check(normal.layer.tiles[Vector2i.ZERO].get_pixel(62,20).r < 0.5 and normal.layer.tiles[Vector2i(1,0)].get_pixel(0,20).r > 0.5,"Height ridge generates opposed X normals")
	check(normal.layer.tiles[Vector2i.ZERO].get_pixel(10,10).a == 0,"Flat Height pixels do not allocate Normal paint")
	# Whole-layer blur samples neighbors without changing the source document.
	var blur_doc := PaintDocument.new()
	blur_doc.initialize(128,64,Color.TRANSPARENT)
	var blur_layer := blur_doc.selected_layer()
	blur_layer.tile_at(Vector2i.ZERO).set_pixel(63,20,Color.WHITE)
	var blurred := PaintOperations.blur_layer(progress,blur_doc.read_copy(),blur_layer.id,3)
	check(blurred.changed.has(Vector2i.ZERO) and blurred.changed.has(Vector2i(1,0)),"Whole-layer blur reaches adjacent tiles")
	check(blurred.tiles[Vector2i(1,0)].get_pixel(0,20).a > 0 and blur_layer.tiles[Vector2i.ZERO].get_pixel(62,20).a == 0,"Blur result is previewable without mutating original pixels")
	print("FEATURE CHECKS: %d passed / %d; failures: %d" % [checks-failures,checks,failures])
	var report := FileAccess.open("res://test_output/feature_results.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"flood_4k_ms":elapsed},"\t"))
	quit(1 if failures else 0)
