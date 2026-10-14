extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test_output")
	var scene = load("res://scenes/main_window.tscn").instantiate()
	scene.settings_enabled = false
	root.add_child(scene)
	scene.get_node("%Autosave").stop()
	root.size = Vector2i(1440, 900)
	var deadline := Time.get_ticks_msec() + 30000
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Startup timed out")
			quit(1)
			return
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/workspace.png")
	print("RENDER: workspace screenshot saved")
	scene.get_node("%ToolOptions/Size").set_value(7)
	scene._setting("shape", 1)
	scene.get_node("%ToolOptions").set_shape(1)
	var hit: Dictionary = scene.model_view._hit(scene.model_view.display.size * 0.5)
	if hit.is_empty():
		push_error("No model hit for cursor check")
		quit(1)
		return
	scene._hover(hit, true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/cursor_3d.png")
	print("CURSOR TEXEL: ", scene.model_view.display_material.get_shader_parameter("cursor_pixel"), " / SIZE: ", scene.painter.footprint_size())
	# Cursor location remains synchronized in both views at large pixel zoom.
	scene.uv_canvas.zoom = 12.0
	scene.uv_canvas.pan = (Vector2.ONE * 0.5 - hit.uv) * Vector2(scene.document.width, scene.document.height) * 12.0
	scene.uv_canvas._layout()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/cursor_detail.png")
	var preview_stamp := Image.create(8,4,false,Image.FORMAT_RGBA8)
	preview_stamp.fill(Color("ea8f54"))
	preview_stamp.fill_rect(Rect2i(4,0,4,4),Color("54ceb8"))
	scene.get_node("%StampPanel").set_source(preview_stamp,"Sample stamp",Rect2i(4,0,4,4))
	for index in range(1, 5):
		scene.get_node("%Inspector").current_tab = index
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test_output/inspector_%d.png" % index)
		if index == 4:
			var preview = scene.get_node("%StampPanel/Preview")
			var pivot: Vector2 = preview._image_rect().get_center()
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			wheel.position = pivot
			for n in 4: preview._gui_input(wheel)
			var middle := InputEventMouseButton.new()
			middle.button_index = MOUSE_BUTTON_MIDDLE
			middle.pressed = true
			middle.position = pivot
			preview._gui_input(middle)
			var motion := InputEventMouseMotion.new()
			motion.position = pivot + Vector2(30,-12)
			motion.relative = Vector2(30,-12)
			preview._gui_input(motion)
			middle.pressed = false
			preview._gui_input(middle)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://test_output/stamp_zoom.png")
	scene.get_node("%Inspector").current_tab = 0
	scene.get_node("%ToolBar").select("gradient")
	scene.get_node("%ToolOptions/Size").set_value(12)
	scene._surface_input("begin",hit,0,true)
	var gradient_end: Dictionary = hit.duplicate()
	gradient_end.uv = hit.uv + Vector2(0.08,0.10)
	scene._surface_input("move",gradient_end,0,true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/gradient_preview.png")
	scene.get_node("%ToolBar").select("brush")
	scene.get_node("%ToolBar").select("spray")
	scene.get_node("%ToolOptions/Size").set_value(24)
	scene._hover(hit, true)
	# Let the FPS display recover after the preceding GPU screenshot readbacks.
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/spray_workspace.png")
	scene.get_node("%ToolBar").select("brush")
	var large := PaintDocument.new()
	large.initialize(4096, 4096, Color("536576"))
	large.geometry = scene.document.geometry
	large.title = "4K performance check"
	scene._set_document(large)
	while not scene.tiles.is_settled():
		await process_frame
	var latencies: Array[float] = []
	var slices: Array[float] = []
	scene.painter.brush_size = 16
	scene.painter.shape = 0
	scene.painter.begin(Vector2(0.2, 0.5))
	for i in 120:
		var start := Time.get_ticks_usec()
		scene.painter.append(Vector2(0.2 + i / 240.0, 0.5))
		await process_frame
		latencies.append((Time.get_ticks_usec() - start) / 1000.0)
		slices.append(scene.painter.last_work_ms + scene.tiles.last_work_ms)
	scene.painter.end()
	while scene.painter.active or not scene.tiles.is_settled():
		await process_frame
	latencies.sort()
	slices.sort()
	var report := {"renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "frame_median_ms": latencies[60], "frame_p95_ms": latencies[114], "cpu_work_p95_ms": slices[114], "godot": Engine.get_version_info().string}
	var report_file := FileAccess.open("res://test_output/render_results.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	print("RENDER BENCHMARK ", JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/workspace_4k.png")
	# A larger loaded palette must not turn brush strokes into a full palette scan per fragment.
	large.palette.clear()
	for i in 256: large.palette.append(Color8((i*71)%256,(i*19)%256,(i*43)%256))
	large.effects.palette = true
	scene._apply_materials()
	await create_timer(1.0).timeout
	latencies.clear()
	scene.painter.begin(Vector2(0.2,0.7))
	for i in 120:
		var start := Time.get_ticks_usec()
		scene.painter.append(Vector2(0.2+i/240.0,0.7))
		await process_frame
		latencies.append((Time.get_ticks_usec()-start)/1000.0)
	scene.painter.end()
	while scene.painter.active or not scene.tiles.is_settled(): await process_frame
	latencies.sort()
	report["palette_256_frame_median_ms"] = latencies[60]
	report["palette_256_frame_p95_ms"] = latencies[114]
	report_file.seek(0)
	report_file.store_string(JSON.stringify(report,"\t"))
	print("PALETTE BENCHMARK ",JSON.stringify(report))
	scene.document.saved_revision = scene.document.revision
	quit()
