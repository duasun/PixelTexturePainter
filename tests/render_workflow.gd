extends SceneTree
func _init() -> void: call_deferred("run")
func settle(scene: Node) -> void:
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled(): await process_frame
	for i in 8: await process_frame
func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/"+path)
func run() -> void:
	var scene = load("res://scenes/main_window.tscn").instantiate(); scene.settings_enabled = false; root.add_child(scene)
	scene.get_node("%Autosave").stop(); root.size = Vector2i(1440,900)
	await settle(scene)
	scene.get_node("%ToolBar/Compact").button_pressed = true
	scene.get_node("%ToolBar").select("spray")
	scene.get_node("%ToolOptions/Size").set_value(32)
	scene.get_node("%SprayOptions/Opacity").set_value(20)
	scene.get_node("%SprayOptions/Flow").set_value(10)
	scene.get_node("%SprayOptions/Particles").set_value(60)
	await settle(scene)
	var hit: Dictionary = scene.model_view._hit(scene.model_view.display.size*0.5)
	scene._hover(hit,true)
	await settle(scene)
	await capture("workflow_spray.png")
	scene.get_node("%ToolBar").select("select")
	scene._hover(hit,true)
	await settle(scene)
	await capture("workflow_wires.png")
	print("DOCK before ",scene.get_node("%PalettePanel").size," offset ",scene.get_node("%MainDock").split_offset)
	scene.get_node("%MainDock").split_offset -= 50
	await settle(scene)
	print("DOCK after ",scene.get_node("%PalettePanel").size," offset ",scene.get_node("%MainDock").split_offset)
	scene._select_channel("roughness")
	scene.get_node("%ToolBar").select("brush")
	scene._setting("color",Color(0.2,0.2,0.2))
	scene.painter.begin(Vector2(0.75,0.2)); scene.painter.end()
	while scene.painter.active: await process_frame
	await settle(scene)
	await capture("workflow_maps.png")
	# Capture all three non-destructive shape previews before mouse release.
	var model_hit: Dictionary = scene.model_view._hit(scene.model_view.display.size*0.5)
	var drag_hit: Dictionary = model_hit.duplicate()
	drag_hit.uv = (model_hit.uv + Vector2(0.09,0.06)).clamp(Vector2.ZERO,Vector2(0.999,0.999))
	for shape in ["line","rect","ellipse"]:
		scene.get_node("%ToolBar").select(shape)
		scene._surface_input("begin",model_hit,0,true)
		scene._surface_input("move",drag_hit,0,true)
		for frame in 4: await process_frame
		await capture("workflow_preview_"+shape+".png")
		scene._surface_input("end",drag_hit,0,true)
		while scene.painter.active: await process_frame
	# Real-frame latency with local effect brushes on a 4K atlas.
	var doc := PaintDocument.new(); doc.initialize(4096,4096,Color("345678")); doc.geometry = scene.document.geometry
	scene._set_document(doc)
	await settle(scene)
	var results: Dictionary = {}
	for tool in ["smudge","blur","spray"]:
		scene.get_node("%ToolBar").select(tool)
		scene.painter.brush_size = 64; scene.painter.opacity = 0.3
		scene._hover({},false)
		await create_timer(0.5).timeout
		var latencies: Array[float] = []
		var work: Array[float] = []
		scene.painter.begin(Vector2(0.2,0.5))
		for i in 90:
			var start := Time.get_ticks_usec()
			scene._hover({"uv":Vector2(0.2+i/400.0,0.5),"face":-1},false)
			scene.painter.append(Vector2(0.2+i/400.0,0.5))
			await process_frame
			latencies.append((Time.get_ticks_usec()-start)/1000.0)
			work.append(scene.painter.last_work_ms+scene.tiles.last_work_ms)
		scene.painter.end()
		while scene.painter.active: await process_frame
		latencies.sort(); work.sort()
		results[tool] = {"frame_p95_ms":latencies[85],"cpu_p95_ms":work[85]}
	var file := FileAccess.open("res://test_output/workflow_render_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	print("WORKFLOW PERFORMANCE ",JSON.stringify(results))
	scene.document.saved_revision = scene.document.revision
	quit()
