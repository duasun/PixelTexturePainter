extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func settle(scene: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Timed out")
			quit(1)
			return
	for i in 6: await process_frame

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/" + path)

func run() -> void:
	var scene = load("res://scenes/main_window.tscn").instantiate()
	scene.settings_enabled = false
	root.add_child(scene)
	scene.get_node("%Autosave").stop()
	root.size = Vector2i(1440,900)
	await settle(scene)
	var loaded := PaletteIO.load_palette(BackgroundJob.JobProgress.new(), "res://test_output/lospec/endesga-32.hex")
	scene._job_completed("palette",loaded)
	scene.get_node("%PalettePanel")._chosen(1,0)
	scene.get_node("%PalettePanel")._chosen(2,18)
	var hit: Dictionary = scene.model_view._hit(scene.model_view.display.size * 0.5)
	scene.selection_mode = 0
	scene._select_surface(hit,0)
	await settle(scene)
	await capture("features_selection.png")
	scene.get_node("%UVView").button_pressed = false
	scene.get_node("%ToolBar/Compact").button_pressed = true
	await settle(scene)
	await capture("features_compact.png")
	scene.model_view.get_node("Header/Light").button_pressed = true
	await settle(scene)
	check(scene.model_view.display_material.get_shader_parameter("pbr_enabled"),"Lit PBR preview activates after its maps finish")
	await capture("features_pbr.png")
	scene.model_view.get_node("Header/Light").button_pressed = false
	var palette_panel: Node = scene.get_node("%PalettePanel")
	palette_panel.get_node("EditActions/Add").pressed.emit()
	for frame in 3: await process_frame
	check(palette_panel.get_node("ColorDialog").visible,"Plus button opens palette color picker")
	palette_panel.get_node("ColorDialog").hide()
	root.size = Vector2i(1280,760)
	scene.get_node("%ToolBar").select("spray")
	scene.get_node("%UVView").button_pressed = true
	await settle(scene)
	await capture("features_minimum.png")
	check(scene.get_node("%PalettePanel").get_global_rect().end.y <= scene.size.y, "Palette fits at minimum window size with spray controls")
	# Validate shader nearest-color search against CPU for 256 colors and varied texels.
	var doc := PaintDocument.new()
	doc.initialize(64,64,Color.BLACK)
	doc.palette.clear()
	for i in 256: doc.palette.append(Color8((i*71)%256,(i*19)%256,(i*43)%256))
	doc.effects.palette = true
	var source := doc.selected_layer().tile_at(Vector2i.ZERO)
	for y in 64:
		for x in 64: source.set_pixel(x,y,Color8((x*7+y*3)%256,(x*13+y*11)%256,(x*23+y*5)%256))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64,64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect := TextureRect.new()
	var white := Image.create(1,1,false,Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	rect.texture = ImageTexture.create_from_image(white)
	rect.size = Vector2(64,64)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/canvas.gdshader")
	rect.material = material
	viewport.add_child(rect)
	var tiles := TileDisplay.new()
	root.add_child(tiles)
	tiles.setup(doc)
	tiles.apply_to(material)
	while not tiles.is_settled(): await process_frame
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var gpu := viewport.get_texture().get_image()
	var cpu := ProjectIO.apply_effects(source,Vector2i.ZERO,doc)
	var mismatches := 0
	for y in 64:
		for x in 64:
			var a := gpu.get_pixel(x,y)
			var b := cpu.get_pixel(x,y)
			if absf(a.r-b.r) > 0.005 or absf(a.g-b.g) > 0.005 or absf(a.b-b.b) > 0.005: mismatches += 1
	check(mismatches == 0, "GPU 256-color search matches CPU; mismatched pixels: %d" % mismatches)
	gpu.save_png("res://test_output/palette_gpu.png")
	for count in [1,16,32,1024]:
		doc.palette.clear()
		for i in count: doc.palette.append(Color8((i*71)%256,(i*19+floori(i/256.0)*53)%256,(i*43+floori(i/256.0)*11)%256))
		tiles.apply_to(material)
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		gpu = viewport.get_texture().get_image()
		cpu = ProjectIO.apply_effects(source,Vector2i.ZERO,doc)
		mismatches = 0
		for y in 64:
			for x in 64:
				var a := gpu.get_pixel(x,y)
				var b := cpu.get_pixel(x,y)
				if absf(a.r-b.r) > 0.005 or absf(a.g-b.g) > 0.005 or absf(a.b-b.b) > 0.005: mismatches += 1
		check(mismatches == 0, "GPU %d-color palette matches CPU; mismatched pixels: %d" % [count,mismatches])
	doc.effects.palette = false
	doc.effects.noise = 0.65
	doc.effects.noise_density = 0.35
	doc.effects.noise_grain = 3
	doc.effects.noise_mode = 3
	doc.effects.noise_seed = 42
	tiles.apply_to(material)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	gpu = viewport.get_texture().get_image()
	cpu = ProjectIO.apply_effects(source,Vector2i.ZERO,doc)
	mismatches = 0
	for y in 64:
		for x in 64:
			var a := gpu.get_pixel(x,y)
			var b := cpu.get_pixel(x,y)
			if absf(a.r-b.r) > 0.005 or absf(a.g-b.g) > 0.005 or absf(a.b-b.b) > 0.005: mismatches += 1
	check(mismatches == 0,"GPU Pixel Noise matches PNG export across grain cells; mismatched pixels: %d" % mismatches)
	# Exercise native export on the real background worker with the renderer running.
	var path := ProjectSettings.globalize_path("res://test_output/background_export.glb")
	scene._file_action = "export_model"
	scene._file_selected(path)
	await settle(scene)
	check(FileAccess.file_exists(path), "Background GLB export completes with renderer running")
	print("RENDER FEATURE FAILURES: ",failures)
	scene.document.saved_revision = scene.document.revision
	quit(1 if failures else 0)
