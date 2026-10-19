extends SceneTree
var failures := 0
var checks := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func run() -> void:
	var brushes := BrushLibrary.list_brushes()
	check(brushes.size() >= 20,"Twenty bundled brush tips are available")
	for entry in brushes:
		check(BrushLibrary.load_tip(str(entry.path)) != null,"Brush tip loads: " + str(entry.name))
	var imported_tip := Image.create(4,4,false,Image.FORMAT_RGBA8)
	imported_tip.fill(Color.WHITE)
	var tip_file := ProjectSettings.globalize_path("res://test_output/user_brush_test.png")
	imported_tip.save_png(tip_file)
	var imported := BrushLibrary.import_tip(tip_file)
	check(imported.has("path") and BrushLibrary.load_tip(str(imported.get("path",""))) != null,"PNG brush imports into the persistent brush folder")
	if imported.has("path"): DirAccess.remove_absolute(ProjectSettings.globalize_path(str(imported.path)))
	for mode in range(2,8):
		var tile := PatternLibrary.image_for(mode,Color.RED,Color.BLUE)
		var colors := {}
		for y in 16:
			for x in 16: colors[tile.get_pixel(x,y).to_rgba32()] = true
		check(colors.size() == 2,"Built-in pattern has two colors: " + str(mode))
	var scene = load("res://scenes/main_window.tscn").instantiate()
	scene.settings_enabled = false
	root.add_child(scene)
	root.size = Vector2i(1440,900)
	scene.get_node("%Autosave").stop()
	var deadline := Time.get_ticks_msec()+30000
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			check(false,"Project startup completed")
			quit(1)
			return
	var options = scene.get_node("%BrushOptions")
	check(options.get_node("Tips").item_count >= 21,"Brush toolbar lists presets and default tip")
	options.set_selected_path(str(brushes[4].path))
	check(scene.painter.brush_tip != null,"Selecting a brush installs its mask")
	scene.get_node("%ToolBar").select("brush")
	scene._setting("brush_size",16)
	scene._setting("color",Color.RED)
	scene.painter.begin(Vector2(0.5,0.5))
	check(scene.painter._stamp.get_pixel(8,8).a == 0.0 and scene.painter._stamp.get_pixel(8,1).r > 0.9,"Brush stroke uses the chosen white mask tinted by the active color")
	scene.painter.end()
	while scene.painter.active: await process_frame
	scene.get_node("%ToolBar").select("spray")
	scene.get_node("%SprayOptions/Strength").set_value(60)
	check(is_equal_approx(scene.painter.spray_flow,0.6) and scene.painter.spray_particles == 21,"Strength combines spray density and buildup")
	scene.get_node("%ToolBar").select("fill")
	var fill = scene.get_node("%Pattern")
	fill.set_mode(2)
	check(fill.source != null and fill.visible,"Built-in grid is available in Fill toolbar")
	var editor = scene.get_node("%PatternEditor")
	editor.open_editor(null,Color.GREEN)
	editor.get_node("Body/Dimensions/Width").set_value(5,false)
	editor.get_node("Body/Dimensions/Height").set_value(7,false)
	editor.get_node("Body/Dimensions/New").pressed.emit()
	var canvas = editor.get_node("Body/Canvas")
	await process_frame
	var pixel_scale: float = floorf(minf(canvas.size.x/5.0,canvas.size.y/7.0))
	var canvas_origin: Vector2 = (canvas.size-Vector2(5,7)*pixel_scale)*0.5
	canvas._paint(canvas_origin+Vector2(1.5,2.5)*pixel_scale,false)
	canvas._paint(canvas_origin+Vector2(3.5,2.5)*pixel_scale,false)
	check(canvas.image.get_pixel(2,2) == Color.GREEN,"Custom pattern drawing bridges fast pointer movement")
	editor.confirmed.emit()
	editor.hide()
	check(scene.document.custom_pattern_image.get_size() == Vector2i(5,7) and fill.mode() == 8,"Custom canvas dimensions and selection are retained")
	var layers_before: int = scene.document.layers.size()
	scene._surface_input("begin",{"uv":Vector2(0.4,0.4),"face":0},0,true)
	while scene.jobs.busy(): await process_frame
	check(scene.document.layers.size() == layers_before+1 and scene.document.selected_layer().pattern_image.get_size() == Vector2i(5,7),"Fill bucket applies the custom pattern on a model surface")
	var output := ProjectSettings.globalize_path("res://test_output/custom_fill_test.rtpaint")
	var result := ProjectIO.save_project(BackgroundJob.JobProgress.new(),scene.document,output)
	check(result.has("path"),"Project containing custom pattern saves")
	var opened := ProjectIO.load_project(BackgroundJob.JobProgress.new(),output)
	check(opened.has("document") and opened.document.custom_pattern_image.get_pixel(1,2) == Color.GREEN,"Custom pattern pixels survive reopening")
	check(scene.get_node("%StampOptions").visible == false and scene.get_node("%Inspector").get_tab_count() == 3,"Stamp and Texture controls are outside the inspector")
	scene.size = Vector2(1280,800)
	for tool in ["brush","spray","fill","stencil","clone"]:
		scene.get_node("%ToolBar").select(tool)
		await process_frame
		var bar: Control = scene.get_node("Margin/Layout/MainSplit/LeftColumn/SettingsBar")
		check(bar.size.y == 30.0 and scene.get_node("%Inspector").get_global_rect().end.x <= 1280.0,"Tool settings fit one row at 1280 px: " + tool)
	print("FILL/BRUSH CHECKS: %d / %d; failures: %d" % [checks-failures,checks,failures])
	quit(1 if failures else 0)
