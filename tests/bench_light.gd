extends SceneTree
## Manual GPU check on the current device; reports steady-state frame time, not a pass/fail limit.

func _init() -> void:
	call_deferred("run")

func _settle(scene: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Light benchmark timed out")
			quit(1)
			return

func _sample_frames(count: int) -> float:
	for i in 8: await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	for i in count: await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec()-start)/1000.0/count

func run() -> void:
	root.size = Vector2i(1440,900)
	var scene = load("res://scenes/main_window.tscn").instantiate()
	scene.settings_enabled = false
	root.add_child(scene)
	scene.get_node("%Autosave").stop()
	scene._start_new(1024,1024,"Lighting benchmark")
	await _settle(scene)
	for i in 8: scene.document.layers.append(PaintLayer.new())
	scene._refresh_metadata()
	var unlit := await _sample_frames(30)
	scene.model_view.get_node("Header/Light").button_pressed = true
	await _settle(scene)
	var lit := await _sample_frames(30)
	var rough := PaintLayer.new()
	rough.channel = "roughness"
	rough.tile_at(Vector2i.ZERO).set_pixel(0,0,Color.GRAY)
	scene.document.layers.append(rough)
	scene.document.revision += 1
	await process_frame
	await _settle(scene)
	var pbr := await _sample_frames(30)
	print("LIGHT BENCH: 10 Albedo layers, 1024², 1440×900 — unlit %.2f ms/frame, simple light %.2f ms/frame, PBR %.2f ms/frame" % [unlit,lit,pbr])
	quit(0)
