extends SceneTree
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	var progress := BackgroundJob.JobProgress.new()
	var doc := PaintDocument.new()
	doc.initialize(64,64,Color("253041"))
	var bottom := doc.layers[1]
	bottom.tile_at(Vector2i.ZERO).set_pixel(8,8,Color.RED)
	var top := PaintLayer.new()
	top.title = "Top"
	top.opacity = 0.5
	top.tile_at(Vector2i.ZERO).set_pixel(8,8,Color.BLUE)
	doc.layers.append(top)
	doc.active_layer = 2
	var before := doc.compose_tile(Vector2i.ZERO).get_pixel(8,8)
	var merged := LayerFlatten.down(progress,doc,top.id)
	check(merged.has("layers") and merged.layers.size() == 2,"Flatten down merges only the clicked layer and the one below")
	if merged.has("layers"):
		doc.layers.assign(merged.layers)
		check(doc.compose_tile(Vector2i.ZERO).get_pixel(8,8).is_equal_approx(before),"Flatten down preserves the visible color")
		check(doc.layers[0].title == "Base color","Flatten down preserves unrelated layers")
	var hidden := PaintLayer.new()
	hidden.visible = false
	hidden.title = "Hidden reference"
	hidden.tile_at(Vector2i.ZERO).set_pixel(9,9,Color.GREEN)
	doc.layers.append(hidden)
	var upper := PaintLayer.new()
	upper.tile_at(Vector2i.ZERO).set_pixel(9,9,Color.YELLOW)
	doc.layers.append(upper)
	check(not LayerFlatten.can_down(doc,upper.id),"Flatten down refuses different visibility")
	var sample := doc.compose_tile(Vector2i.ZERO).get_pixel(9,9)
	var all := LayerFlatten.all_visible(progress,doc)
	check(all.has("layers") and all.layers.size() == 2,"Flatten all combines visible layers and keeps hidden layers separate")
	if all.has("layers"):
		doc.layers.assign(all.layers)
		check(doc.compose_tile(Vector2i.ZERO).get_pixel(9,9).is_equal_approx(sample),"Flatten all keeps the same visible result")
		check(doc.layers[1].title == "Hidden reference","Hidden layer survives flatten all")
	var normal := PaintLayer.new()
	normal.channel = "normal"
	normal.base_color = Color8(128,128,255)
	doc.layers.append(normal)
	var normal_top := PaintLayer.new()
	normal_top.channel = "normal"
	normal_top.tile_at(Vector2i.ZERO).set_pixel(3,3,Color.WHITE)
	doc.layers.append(normal_top)
	var multi := LayerFlatten.all_visible(progress,doc)
	check(multi.has("layers") and multi.layers.size() == 3,"Flatten all keeps Albedo and Normal maps separate")
	var ten := PaintDocument.new()
	ten.initialize(1024,1024,Color.BLACK)
	for i in 9:
		var empty := PaintLayer.new()
		ten.layers.append(empty)
	var started := Time.get_ticks_usec()
	for i in 256: ten.compose_tile(Vector2i(i%16,i/16))
	var compose_ms := (Time.get_ticks_usec()-started)/1000.0
	started = Time.get_ticks_usec()
	var preview := PBRPreview.build(progress,ten)
	var lit_ms := (Time.get_ticks_usec()-started)/1000.0
	print("10-layer 1024 compose: %.2f ms / 256 tiles; lit-map preparation: %.2f ms" % [compose_ms,lit_ms])
	check(preview.maps.size() == 5 and lit_ms < 1000.0,"Light preparation skips empty Albedo and material maps")
	var rough := PaintLayer.new()
	rough.channel = "roughness"
	rough.tile_at(Vector2i.ZERO).set_pixel(0,0,Color8(128,128,128))
	ten.layers.append(rough)
	ten.active_layer = ten.layers.size()-1
	var full_preview := PBRPreview.build(progress,ten)
	check(not full_preview.simple and full_preview.maps.has("albedo") and full_preview.maps.roughness.get_size() == Vector2i(1024,1024),"Painted material maps keep Albedo visible when another map is being edited")
	print("FLATTEN/PERF CHECKS: %d passed / %d; failures: %d" % [checks-failures,checks,failures])
	quit(1 if failures else 0)
