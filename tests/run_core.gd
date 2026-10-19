extends SceneTree
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test_output")
	var progress := BackgroundJob.JobProgress.new()
	var model := ModelGeometry.demo()
	var hit := model.ray_hit(Vector3(0, 0.5, 5), Vector3.FORWARD)
	check(not hit.is_empty(), "BVH hits visible crate surface")
	for resolution in [32, 128, 4096]:
		var begin := Time.get_ticks_usec()
		var unwrap := UVUnwrapper.unwrap(model, resolution, resolution, 45, 1)
		check(not unwrap.has("error"), "UV generation %d" % resolution)
		if not unwrap.has("error"):
			var valid := true
			for uv in unwrap.geometry.uvs:
				valid = valid and uv.is_finite() and uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1
			check(valid, "UV bounds %d" % resolution)
			print("UV %d: %.2f ms, %d islands" % [resolution, (Time.get_ticks_usec() - begin) / 1000.0, unwrap.islands])
	var tiny_tiles := {}
	UVRaster.triangle(tiny_tiles,PackedVector2Array([Vector2(10.1,10.1),Vector2(10.3,10.1),Vector2(10.1,10.3)]),Vector2i(64,64),Color.WHITE)
	check(tiny_tiles.has(Vector2i.ZERO) and tiny_tiles[Vector2i.ZERO].get_pixel(10,10).a == 1.0,"Subpixel UV triangles still receive a paintable texel")
	var neighbor_tiles := {}
	UVRaster.triangle(neighbor_tiles,PackedVector2Array([Vector2(12.1,10.1),Vector2(12.3,10.1),Vector2(12.1,10.3)]),Vector2i(64,64),Color.WHITE)
	check(neighbor_tiles.has(Vector2i.ZERO) and neighbor_tiles[Vector2i.ZERO].get_pixel(12,10).a == 1.0
		and tiny_tiles[Vector2i.ZERO].get_pixel(12,10).a == 0.0 and neighbor_tiles[Vector2i.ZERO].get_pixel(10,10).a == 0.0,
		"Conservative coverage respects the padding between UV islands")
	var pack_sizes: Array[Vector2i] = []
	for i in 80: pack_sizes.append(Vector2i(3+i%9,4+(i*7)%11))
	var packed := UVMaxRects.pack(pack_sizes,Vector2i(128,128))
	var valid_pack := packed.size() == pack_sizes.size()
	for i in packed.size():
		valid_pack = valid_pack and Rect2i(Vector2i.ZERO,Vector2i(128,128)).encloses(packed[i])
		for j in range(i+1,packed.size()):
			if packed[i].intersects(packed[j]): valid_pack = false
	check(valid_pack,"Optimized UV packing keeps every chart inside atlas without overlap")
	var doc := PaintDocument.new()
	doc.initialize(64, 64, Color("303d50"))
	doc.geometry = UVUnwrapper.unwrap(model, 64, 64, 45, 1).geometry
	var history := PaintHistory.new()
	var painter := PaintEngine.new()
	root.add_child(painter)
	painter.set_process(false)
	painter.setup(doc, history)
	painter.brush_size = 1
	painter.color = Color.RED
	var original := doc.compose_tile(Vector2i.ZERO).get_data()
	painter.begin(Vector2(10.5, 10.5) / 64.0)
	painter.append(Vector2(20.5, 10.5) / 64.0)
	painter.end()
	while painter.active:
		painter._process(0.0)
	var painted := doc.compose_tile(Vector2i.ZERO).get_data()
	check(doc.selected_layer().tiles[Vector2i.ZERO].get_pixel(15, 10).r > 0.99, "Interpolated pixel stroke")
	check(doc.selected_layer().tiles[Vector2i.ZERO].get_pixel(15, 11).a == 0, "One texel brush has no antialias fringe")
	check(history.actions.size() == 1, "One stroke equals one undo")
	history.undo(doc)
	check(doc.compose_tile(Vector2i.ZERO).get_data() == original, "Undo restores exact bytes")
	history.redo(doc)
	check(doc.compose_tile(Vector2i.ZERO).get_data() == painted, "Redo restores exact bytes")
	var gradient := PaintOperations.gradient(progress, doc, PackedInt32Array(), {"uv": Vector2(2.5, 10.5) / 64.0, "face": -1}, {"uv": Vector2(2.5, 30.5) / 64.0}, 7, Color.WHITE, Color.BLACK, false)
	var ramp: Image = gradient.command.after[Vector2i.ZERO]
	for y in range(10, 17):
		check(absf(ramp.get_pixel(2, y).r - (1.0 - (y - 10) / 6.0)) <= 1.1 / 255.0, "7px gradient sample %d" % y)
	check(ramp.get_pixel(2, 9).r > 0.99 and ramp.get_pixel(2, 17).r < 0.01, "Gradient clamps outside its seven samples")
	var narrow_doc := PaintDocument.new()
	narrow_doc.initialize(64, 64, Color.BLACK)
	var grad_start := {"uv": Vector2(32.5, 10.5) / 64.0, "face": -1}
	var grad_end := {"uv": Vector2(32.5, 30.5) / 64.0, "face": -1}
	var narrow := PaintOperations.gradient(progress, narrow_doc, PackedInt32Array(), grad_start, grad_end, 7, Color.WHITE, Color.BLACK, false, 4)
	var wide := PaintOperations.gradient(progress, narrow_doc, PackedInt32Array(), grad_start, grad_end, 7, Color.WHITE, Color.BLACK, false, 12)
	var narrow_tile: Image = narrow.command.after[Vector2i.ZERO]
	var wide_tile: Image = wide.command.after[Vector2i.ZERO]
	check(narrow_tile.get_pixel(35, 13).a == 0.0 and wide_tile.get_pixel(35, 13).a > 0.99, "Gradient Size changes painted width from 4 to 12 px")
	check(narrow_tile.get_pixel(32, 13).a > 0.99 and wide_tile.get_pixel(32, 13).a > 0.99, "Both gradient sizes keep the stroke center")
	var corner_model := ModelGeometry.new()
	corner_model.positions = PackedVector3Array([
		Vector3(0,0,0), Vector3(1,0,0), Vector3(0,0,1),
		Vector3(0,0,0), Vector3(0,0,1), Vector3(0,1,0)])
	corner_model.normals = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.RIGHT,Vector3.RIGHT,Vector3.RIGHT])
	corner_model.uvs = PackedVector2Array([
		Vector2(0.1,0.1),Vector2(0.4,0.1),Vector2(0.1,0.4),
		Vector2(0.6,0.1),Vector2(0.9,0.1),Vector2(0.6,0.4)])
	corner_model.materials = PackedInt32Array([0,0])
	corner_model.objects = PackedInt32Array([0,0])
	corner_model.build_cache()
	var ao_doc := PaintDocument.new()
	ao_doc.initialize(64,64,Color.WHITE)
	ao_doc.geometry = corner_model
	var wrap_doc := PaintDocument.new()
	wrap_doc.initialize(64,64,Color.WHITE)
	wrap_doc.geometry = corner_model
	painter.setup(wrap_doc,PaintHistory.new())
	painter.tool = "brush"
	painter.brush_size = 12
	painter.color = Color.RED
	painter.selection = UVRaster.selection(corner_model,PackedInt32Array([0,1]),Vector2i(64,64))
	painter.selection_active = true
	painter.edge_wrap_faces = {0:true,1:true}
	painter.edge_wrap = false
	painter.begin(Vector2(0.115,0.19),corner_model.islands[0],0)
	painter.end()
	while painter.active: painter._process(0.0)
	var unwrapped_alpha := wrap_doc.selected_layer().tile_at(Vector2i.ZERO,false,false).get_pixel(44,9).a
	wrap_doc = PaintDocument.new()
	wrap_doc.initialize(64,64,Color.WHITE)
	wrap_doc.geometry = corner_model
	painter.setup(wrap_doc,PaintHistory.new())
	painter.tool = "brush"
	painter.brush_size = 12
	painter.color = Color.RED
	painter.selection = UVRaster.selection(corner_model,PackedInt32Array([0,1]),Vector2i(64,64))
	painter.selection_active = true
	painter.edge_wrap_faces = {0:true,1:true}
	painter.edge_wrap = true
	painter.edge_wrap_camera_position = Vector3(2,2,2)
	painter.edge_wrap_visible_only = true
	painter.begin(Vector2(0.115,0.19),corner_model.islands[0],0)
	painter.end()
	while painter.active: painter._process(0.0)
	var wrapped_alpha := wrap_doc.selected_layer().tile_at(Vector2i.ZERO,false,false).get_pixel(44,9).a
	check(unwrapped_alpha == 0.0 and wrapped_alpha > 0.0,"Wrap toggle paints a touched neighboring face across a UV seam")
	var wrap_hit := corner_model.surface_at_uv(Vector2(0.115,0.19),corner_model.islands[0],0)
	check(corner_model.edge_wrap_targets(0,wrap_hit.position,12,Vector2i(64,64),{0:true,1:true},Vector3(-2,2,2),true).is_empty(),"Wrap avoids a neighboring face hidden behind the model")
	check(corner_model.edge_wrap_targets(0,wrap_hit.position,12,Vector2i(64,64),{0:true},Vector3(2,2,2),true).is_empty(),"Wrap stays within the selected faces")
	var shape_doc := PaintDocument.new()
	shape_doc.initialize(64,64,Color.WHITE)
	shape_doc.geometry = corner_model
	painter.setup(shape_doc,PaintHistory.new())
	painter.tool = "line"
	painter.brush_size = 12
	painter.edge_wrap = true
	painter.edge_wrap_camera_position = Vector3(2,2,2)
	painter.edge_wrap_visible_only = true
	painter.begin(Vector2(0.115,0.15),corner_model.islands[0],0)
	painter.append(Vector2(0.115,0.25),corner_model.islands[0],0)
	painter.end()
	while painter.active: painter._process(0.0)
	check(shape_doc.selected_layer().tile_at(Vector2i.ZERO,false,false).get_pixel(44,9).a > 0.0,"Line tool also wraps its drawn edge across the UV seam")
	var spray_wrap_doc := PaintDocument.new()
	spray_wrap_doc.initialize(64,64,Color.WHITE)
	spray_wrap_doc.geometry = corner_model
	painter.setup(spray_wrap_doc,PaintHistory.new())
	painter.tool = "spray"
	painter.brush_size = 12
	painter.spray_particles = 60
	painter.spray_flow = 1.0
	painter.opacity = 1.0
	painter.color = Color.RED
	painter.edge_wrap = true
	painter.edge_wrap_camera_position = Vector3(2,2,2)
	painter.edge_wrap_visible_only = true
	painter.begin(Vector2(0.115,0.19),corner_model.islands[0],0)
	check(painter._symmetry_paths.size() > 0,"Spray Wrap queues the touched neighboring face")
	painter.end()
	while painter.active: painter._process(0.0)
	var spray_wrap_tile := spray_wrap_doc.selected_layer().tile_at(Vector2i.ZERO,false,false)
	var spray_wrapped_pixels := 0
	for spray_y in range(5,18):
		for spray_x in range(38,56):
			if spray_wrap_tile.get_pixel(spray_x,spray_y).a > 0.0: spray_wrapped_pixels += 1
	check(spray_wrapped_pixels > 0,"Spray paints the visible adjacent face across the UV seam")
	var noise_doc := PaintDocument.new()
	noise_doc.initialize(64,64,Color.GRAY)
	var flat := Image.create(16,16,false,Image.FORMAT_RGBA8)
	flat.fill(Color(0.5,0.5,0.5))
	noise_doc.effects.noise = 0.8
	noise_doc.effects.noise_density = 0.0
	check(ProjectIO.apply_effects(flat,Vector2i.ZERO,noise_doc).get_data() == flat.get_data(),"Zero noise coverage leaves the texture unchanged")
	noise_doc.effects.noise_density = 1.0
	noise_doc.effects.noise_grain = 3
	noise_doc.effects.noise_seed = 42
	var grains := ProjectIO.apply_effects(flat,Vector2i.ZERO,noise_doc)
	check(grains.get_pixel(0,0) == grains.get_pixel(2,2) and grains.get_pixel(0,0) != grains.get_pixel(3,0),"Grain size groups deterministic pixel noise into cells")
	check(grains.get_data() == ProjectIO.apply_effects(flat,Vector2i.ZERO,noise_doc).get_data(),"Pixel noise is stable between preview and repeated exports")
	noise_doc.effects.noise_mode = 1
	var dark_grains := ProjectIO.apply_effects(flat,Vector2i.ZERO,noise_doc)
	noise_doc.effects.noise_mode = 2
	var light_grains := ProjectIO.apply_effects(flat,Vector2i.ZERO,noise_doc)
	check(dark_grains.get_pixel(0,0).r < flat.get_pixel(0,0).r and light_grains.get_pixel(0,0).r > flat.get_pixel(0,0).r,"Noise tone can make only dark or only light specks")
	noise_doc.effects.noise_mode = 3
	var color_grains := ProjectIO.apply_effects(flat,Vector2i.ZERO,noise_doc)
	check(color_grains.get_pixel(0,0).r != color_grains.get_pixel(0,0).g,"Color noise varies channels independently")
	var model_start := {"uv": Vector2(0.13,0.15), "face": 0}
	var model_end := {"uv": Vector2(0.13,0.25), "face": 0}
	var model_narrow := PaintOperations.gradient(progress,ao_doc,PackedInt32Array([0]),model_start,model_end,7,Color.WHITE,Color.BLACK,false,4)
	var model_wide := PaintOperations.gradient(progress,ao_doc,PackedInt32Array([0]),model_start,model_end,7,Color.WHITE,Color.BLACK,false,12)
	check(model_narrow.command.after[Vector2i.ZERO].get_pixel(12,12).a == 0.0 and model_wide.command.after[Vector2i.ZERO].get_pixel(12,12).a > 0.99, "Gradient Size also changes width on a 3D face")
	var ao_narrow := PaintOperations.cavity_ao(progress, ao_doc, 1.0, 6, 0.0, 0)
	var ao_wide := PaintOperations.cavity_ao(progress, ao_doc, 1.0, 12, 0.0, 0)
	check(ao_narrow.samples > 0 and not ao_narrow.layer.tiles.is_empty(), "AO rays detect nearby occluding geometry")
	var ao_tile: Image = ao_narrow.layer.tiles.get(Vector2i.ZERO)
	var ao_wide_tile: Image = ao_wide.layer.tiles.get(Vector2i.ZERO)
	check(ao_tile.get_pixel(8,15).a > 0.05 and ao_tile.get_pixel(15,15).a == 0.0 and ao_wide_tile.get_pixel(15,15).a > 0.0, "AO radius controls its pixel reach without solid edge wedges")
	var ao_soft := PaintOperations.cavity_ao(progress, ao_doc, 0.5, 6, 0.0, 2)
	check(ao_soft.layer.tiles[Vector2i.ZERO].get_pixel(10,15).a < ao_tile.get_pixel(10,15).a, "AO strength and sharp falloff reduce edge shadow")
	var detached := ModelGeometry.new()
	detached.positions = PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(0,0,1),Vector3(0.2,0.1,0.2),Vector3(0.6,0.1,0.2),Vector3(0.2,0.1,0.6)])
	detached.uvs = PackedVector2Array([Vector2(0.1,0.1),Vector2(0.8,0.1),Vector2(0.1,0.8),Vector2(0.8,0.8),Vector2(0.9,0.8),Vector2(0.8,0.9)])
	detached.materials = PackedInt32Array([0,0])
	detached.objects = PackedInt32Array([0,1])
	detached.build_cache()
	ao_doc.geometry = detached
	var detached_ao := PaintOperations.cavity_ao(progress,ao_doc,1.0,32,0.0,0)
	var detached_tile: Image = detached_ao.layer.tiles[Vector2i.ZERO]
	check(detached_tile.get_pixel(20,20).a > detached_tile.get_pixel(35,10).a + 0.2,"AO darkens a surface below separate geometry with no shared edge")
	ao_doc.geometry = corner_model
	var edge_geometry := ModelGeometry.new()
	edge_geometry.positions = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	edge_geometry.uvs = PackedVector2Array([Vector2(0.2,0.2),Vector2(0.8,0.2),Vector2(0.2,0.8)])
	edge_geometry.materials = PackedInt32Array([0])
	edge_geometry.objects = PackedInt32Array([0])
	edge_geometry.build_cache()
	var edge_doc := PaintDocument.new()
	edge_doc.initialize(64,64,Color.TRANSPARENT)
	edge_doc.geometry = edge_geometry
	var crisp_edges := PaintOperations.edge_layer(progress,edge_doc,1,Color.WHITE)
	var two_pixel_edges := PaintOperations.edge_layer(progress,edge_doc,2,Color.WHITE)
	var one_pixel_tile: Image = crisp_edges.layer.tiles[Vector2i.ZERO]
	var two_pixel_tile: Image = two_pixel_edges.layer.tiles[Vector2i.ZERO]
	check(one_pixel_tile.get_pixel(30,13).a > 0.0 and one_pixel_tile.get_pixel(30,14).a == 0.0,"Edge thickness 1 px paints exactly one row on a flat face")
	check(two_pixel_tile.get_pixel(30,13).a > 0.0 and two_pixel_tile.get_pixel(30,14).a > 0.0 and two_pixel_tile.get_pixel(30,15).a == 0.0,"Edge thickness 2 px paints exactly two rows on a flat face")
	var zero_noise := PaintOperations.edge_layer(progress,edge_doc,1,Color.WHITE,6,0.0,1.0)
	var scattered_edges := PaintOperations.edge_layer(progress,edge_doc,1,Color.WHITE,6,1.0,1.0)
	var flat_scatter := PaintOperations.edge_layer(progress,edge_doc,1,Color.WHITE,6,1.0,0.0)
	var edge_tile: Image = scattered_edges.layer.tiles[Vector2i.ZERO]
	check(zero_noise.layer.tiles[Vector2i.ZERO].get_data() == crisp_edges.layer.tiles[Vector2i.ZERO].get_data(),"Zero edge noise preserves the original clean line")
	check(crisp_edges.layer.tiles[Vector2i.ZERO].get_pixel(30,18).a == 0.0 and edge_tile.get_pixel(30,18).a > 0.0,"Edge scatter extends beyond the solid geometry line")
	check(edge_tile.get_pixel(30,15).a > edge_tile.get_pixel(30,18).a and edge_tile.get_pixel(30,8).a == 0.0,"Edge falloff fades into the face without spilling outside its triangle")
	check(flat_scatter.layer.tiles[Vector2i.ZERO].get_pixel(30,18).a > edge_tile.get_pixel(30,18).a,"Falloff control changes scatter strength at the outer edge")
	var repeat_scatter := PaintOperations.edge_layer(progress,edge_doc,1,Color.WHITE,6,1.0,1.0)
	check(repeat_scatter.layer.tiles[Vector2i.ZERO].get_data() == edge_tile.get_data(),"Edge noise is deterministic between previews and baking")
	var split_quad := ModelGeometry.new()
	split_quad.positions = PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(0,0,1),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1)])
	split_quad.uvs = PackedVector2Array([Vector2(0.1,0.1),Vector2(0.9,0.1),Vector2(0.1,0.9),Vector2(0.9,0.1),Vector2(0.9,0.9),Vector2(0.1,0.9)])
	split_quad.materials = PackedInt32Array([0,0])
	split_quad.objects = PackedInt32Array([0,0])
	split_quad.build_cache()
	var quad_scatter := {}
	PaintOperations._edge_scatter(quad_scatter,split_quad,split_quad.islands[0],{},Vector2(6.4,6.4),Vector2(57.6,6.4),Vector2i(64,64),2,25,1.0,1.0,Color.WHITE)
	var quad_tile: Image = quad_scatter.get(Vector2i.ZERO)
	check(split_quad.islands[0] == split_quad.islands[1] and quad_tile != null and quad_tile.get_pixel(50,25).a > 0.0,
		"Edge scatter stays continuous across triangles in the same UV island")
	check(quad_tile != null and quad_tile.get_pixel(2,25).a == 0.0,"Edge scatter stays inside the UV island")
	var ao_4k := PaintDocument.new()
	ao_4k.initialize(4096,4096,Color.WHITE)
	ao_4k.geometry = corner_model
	var gradient_started := Time.get_ticks_usec()
	var gradient_big := PaintOperations.gradient(progress,ao_4k,PackedInt32Array([0]),model_start,model_end,7,Color.WHITE,Color.BLACK,false,12)
	print("4K face gradient: %.2f ms; %d sparse tiles" % [(Time.get_ticks_usec() - gradient_started) / 1000.0,gradient_big.command.after.size()])
	check(gradient_big.command.after.size() > 0 and gradient_big.command.after.size() < 128, "4K gradient Size limits modified tiles to a narrow band")
	var ao_started := Time.get_ticks_usec()
	var ao_big := PaintOperations.cavity_ao(progress,ao_4k,0.65,64,0.5,1)
	print("4K cavity AO: %.2f ms; %d sparse tiles" % [(Time.get_ticks_usec() - ao_started) / 1000.0,ao_big.layer.tiles.size()])
	check(ao_big.samples > 0 and ao_big.layer.tiles.size() > 0, "4K AO samples geometry and produces a baked layer")
	corner_model.positions[5] = Vector3(0,-1,0)
	corner_model.build_cache()
	check(PaintOperations.cavity_ao(progress, ao_doc, 1.0, 6, 0.0, 0).layer.tiles.is_empty(), "AO does not darken outward corners")
	# Frozen clone source, including source pixels overwritten earlier in the same stroke.
	var clone_doc := PaintDocument.new()
	clone_doc.initialize(64, 64, Color.BLACK)
	var source := clone_doc.selected_layer().tile_at(Vector2i.ZERO)
	for x in 64:
		source.fill_rect(Rect2i(x, 0, 1, 64), Color(x / 63.0, 0, 0, 1))
	painter.setup(clone_doc, PaintHistory.new())
	painter.tool = "clone"
	painter.clone_source = Vector2i(2, 10)
	painter.begin(Vector2(10.5, 10.5) / 64.0)
	painter.append(Vector2(23.5, 10.5) / 64.0)
	painter.end()
	while painter.active:
		painter._process(0.0)
	check(absf(clone_doc.selected_layer().tile_at(Vector2i.ZERO).get_pixel(22, 10).r - 14.0 / 63.0) < 1.1 / 255.0, "Clone samples immutable pre-stroke pixels")
	# Save round trip with sparse masks and a non-default effect.
	doc.selected_layer().mask_enabled = true
	doc.selected_layer().tile_at(Vector2i.ZERO, true).fill_rect(Rect2i(0,0,4,4), Color.BLACK)
	doc.effects.steps = 8
	var path := ProjectSettings.globalize_path("res://test_output/roundtrip.rtpaint")
	var saved := ProjectIO.save_project(progress, doc, path)
	check(not saved.has("error"), "Project saves")
	var loaded := ProjectIO.load_project(progress, path)
	check(not loaded.has("error"), "Project reopens")
	if loaded.has("document"):
		check(loaded.document.compose_tile(Vector2i.ZERO).get_data() == doc.compose_tile(Vector2i.ZERO).get_data(), "Save/load preserves composite pixels exactly")
		check(loaded.document.geometry.uvs == doc.geometry.uvs, "Save/load preserves edited UV coordinates")
		check(loaded.document.effects.steps == 8, "Save/load preserves effect settings")
	var obj_path := ProjectSettings.globalize_path("res://test_output/model.obj")
	ProjectIO.export_obj(doc.geometry, obj_path)
	var imported := ModelIO.load_model(progress, obj_path)
	check(imported.has("geometry") and imported.geometry.face_count() == doc.geometry.face_count(), "OBJ export/import preserves triangles")
	if imported.has("geometry"):
		check(not imported.geometry.ray_hit(Vector3(0,0.5,5), Vector3.FORWARD).is_empty(), "OBJ winding remains outward")
	# Texture fill must leave unselected texels unchanged.
	var pattern := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pattern.fill(Color.BLUE)
	pattern.set_pixel(0, 0, Color.RED)
	var filled := PaintOperations.texture_fill(progress, doc, PackedInt32Array([0, 1]), pattern, {"angle": 0.0, "scale": 1.0, "offset": Vector2.ZERO})
	check(filled.has("command") and not filled.command.after.is_empty(), "Texture fill produces selected tiles")
	# 4K brush changes are sparse and independent of the full texture area.
	var large := PaintDocument.new()
	large.initialize(4096, 4096, Color.BLACK)
	var large_history := PaintHistory.new()
	painter.setup(large, large_history)
	painter.tool = "brush"
	painter.brush_size = 8
	painter.color = Color.WHITE
	var clock := Time.get_ticks_usec()
	painter.begin(Vector2(0.45, 0.5))
	painter.append(Vector2(0.55, 0.5))
	painter.end()
	var peak := 0.0
	while painter.active:
		painter._process(0.0)
		peak = maxf(peak, painter.last_work_ms)
	var elapsed := (Time.get_ticks_usec() - clock) / 1000.0
	check(large.selected_layer().tiles.size() < 30, "4K stroke allocates only touched tiles")
	check(large_history.memory_bytes < 1048576, "4K stroke undo stays below 1 MiB")
	print("4K stroke: %.2f ms total; %.2f ms peak processing slice; %d tiles; %.2f KiB undo" % [elapsed, peak, large.selected_layer().tiles.size(), large_history.memory_bytes / 1024.0])
	var pbr_started := Time.get_ticks_usec()
	var pbr_preview := PBRPreview.build(progress,large)
	print("4K lit preview: %.2f ms; %d maps" % [(Time.get_ticks_usec()-pbr_started)/1000.0,pbr_preview.maps.size()])
	check(pbr_preview.maps.size() == 5 and pbr_preview.simple and not pbr_preview.maps.has("albedo") and pbr_preview.maps.roughness.get_size() == Vector2i.ONE,"Lit preview reuses live Albedo and chooses lightweight lighting for empty material maps")
	additional_checks(painter, progress)
	var report := {"checks": checks, "failures": failures, "stroke_4k_ms": elapsed, "peak_slice_ms": peak, "undo_bytes": large_history.memory_bytes, "godot": Engine.get_version_info().string}
	var report_file := FileAccess.open("res://test_output/core_results.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	print("CORE CHECKS: %d passed / %d; failures: %d" % [checks - failures, checks, failures])
	painter.free()
	quit(1 if failures else 0)

func drain(painter: PaintEngine) -> void:
	painter.end()
	while painter.active:
		painter._process(0.0)

func additional_checks(painter: PaintEngine, progress: BackgroundJob.JobProgress) -> void:
	var doc := PaintDocument.new()
	doc.initialize(64, 64, Color.BLACK)
	var layer := doc.selected_layer()
	layer.tile_at(Vector2i.ZERO).fill(Color.WHITE)
	layer.opacity = 0.5
	layer.mask_enabled = true
	layer.tile_at(Vector2i.ZERO, true).fill(Color.WHITE)
	var half := doc.compose_tile(Vector2i.ZERO).get_pixel(4, 4)
	check(absf(half.r - 0.5) < 0.01, "Layer opacity composes correctly with mask")
	layer.tile_at(Vector2i.ZERO, true).set_pixel(4, 4, Color.BLACK)
	layer.invalidate(Vector2i.ZERO)
	check(doc.compose_tile(Vector2i.ZERO).get_pixel(4, 4).r == 0, "Mask edit invalidates prepared composite")
	layer.opacity = 0.25
	check(absf(doc.compose_tile(Vector2i.ZERO).get_pixel(5, 5).r - 0.25) < 0.01, "Opacity change refreshes cached tiles")
	# Save embedded fill/stamp assets and direction, not just the painted result.
	doc.geometry = ModelGeometry.demo()
	doc.pattern_image = Image.create(3, 2, false, Image.FORMAT_RGBA8)
	doc.pattern_image.fill(Color.DARK_RED)
	doc.stamp_image = doc.pattern_image.duplicate()
	doc.stamp_region = Rect2i(1,0,2,2)
	doc.stamp_name = "sample.png"
	doc.pattern_settings.angle = 90.0
	doc.reference_image = Image.create(2,2,false,Image.FORMAT_RGBA8)
	doc.reference_image.fill(Color.GREEN)
	doc.reference_name = "reference.png"
	doc.reference_state = {"x":23.0,"y":41.0,"width":220.0,"height":180.0,"opacity":0.6,"locked":true,"visible":false}
	var path := ProjectSettings.globalize_path("res://test_output/assets.rtpaint")
	ProjectIO.save_project(progress, doc, path)
	var loaded := ProjectIO.load_project(progress, path)
	check(loaded.has("document") and loaded.document.pattern_image.get_data() == doc.pattern_image.get_data(), "Pattern image survives project save")
	check(loaded.has("document") and loaded.document.stamp_image.get_data() == doc.stamp_image.get_data(), "Stamp image survives project save")
	check(loaded.has("document") and loaded.document.stamp_region == doc.stamp_region and loaded.document.stamp_name == doc.stamp_name, "Stamp crop and source label survive project save")
	check(loaded.has("document") and loaded.document.pattern_settings.angle == 90.0, "Pattern direction survives project save")
	check(loaded.has("document") and loaded.document.reference_image.get_data() == doc.reference_image.get_data() and loaded.document.reference_name == "reference.png", "Reference image is embedded in the project")
	check(loaded.has("document") and loaded.document.reference_state == doc.reference_state, "Reference visibility, placement, zoom, opacity and lock survive project save")
	doc.effects.steps = 4
	doc.effects.brightness = 0.1
	var png_path := ProjectSettings.globalize_path("res://test_output/export.png")
	var png := ProjectIO.export_png(progress, doc, png_path)
	check(not png.has("error"), "PNG texture exports")
	var png_image := Image.load_from_file(png_path)
	png_image.convert(Image.FORMAT_RGBA8)
	check(png_image.get_data() == ProjectIO.apply_effects(doc.compose_tile(Vector2i.ZERO), Vector2i.ZERO, doc).get_data(), "PNG export includes layer masks, opacity and effects exactly")
	# Full-atlas pair plus a third, overlapping island: clipping must use the selected island.
	var geometry := ModelGeometry.new()
	geometry.positions = PackedVector3Array([Vector3(0,0,0),Vector3(0,1,0),Vector3(1,0,0),Vector3(1,0,0),Vector3(0,1,0),Vector3(1,1,0)])
	geometry.normals = PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
	geometry.uvs = PackedVector2Array([Vector2.ZERO,Vector2(0,1),Vector2(0.5,0),Vector2(0.5,0),Vector2(0,1),Vector2(0.5,1)])
	geometry.objects = PackedInt32Array([0,0])
	geometry.materials = PackedInt32Array([0,0])
	geometry.islands = PackedInt32Array([0,0])
	geometry.build_cache()
	var clipped := PaintDocument.new()
	clipped.initialize(64, 64, Color.BLACK)
	clipped.geometry = geometry
	painter.setup(clipped, PaintHistory.new())
	painter.tool = "brush"
	painter.brush_size = 16
	painter.opacity = 1.0
	painter.color = Color.RED
	painter.begin(Vector2(30.5, 30.5) / 64.0, 0, 0)
	drain(painter)
	var tile := clipped.selected_layer().tile_at(Vector2i.ZERO)
	check(tile.get_pixel(30,30).r > 0.99 and tile.get_pixel(35,30).a == 0.0, "3D brush clips to hit island, preserving neighboring atlas texels")
	# Manual face selection intersects automatic island coverage.
	var restriction := Image.create(64,64,false,Image.FORMAT_RGBA8)
	restriction.fill(Color.TRANSPARENT)
	restriction.fill_rect(Rect2i(0,0,64,16),Color.WHITE)
	painter.selection = {Vector2i.ZERO: restriction}
	painter.selection_active = true
	painter.color = Color.BLUE
	painter.begin(Vector2(28.5,15.5)/64.0,0,0)
	drain(painter)
	tile = clipped.selected_layer().tile_at(Vector2i.ZERO)
	check(tile.get_pixel(28,15).b > 0.99 and tile.get_pixel(28,16).a == 0, "3D island mask intersects manual selection")
	# Every changed pattern pixel must be inside its selection; a 90-degree turn is exact.
	var pattern := Image.create(2,2,false,Image.FORMAT_RGBA8)
	pattern.fill(Color.BLUE)
	pattern.fill_rect(Rect2i(0,0,1,2),Color.RED)
	var fill_doc := PaintDocument.new()
	fill_doc.initialize(64,64,Color.BLACK)
	fill_doc.geometry = geometry
	var result := PaintOperations.texture_fill(progress, fill_doc, PackedInt32Array([0,1]), pattern, {"angle":90.0,"scale":1.0,"offset":Vector2.ZERO})
	tile = result.command.after[Vector2i.ZERO]
	check(tile.get_pixel(4,4).r > 0.99 and tile.get_pixel(4,5).b > 0.99, "90 degree texture rotation turns columns into exact rows")
	check(tile.get_pixel(40,4).a == 0, "Texture fill preserves unselected atlas pixels")
	# Different UV islands share a physical edge; unfolding preserves that edge.
	geometry.uvs[3] = Vector2(0.7,0.1)
	geometry.uvs[4] = Vector2(0.7,0.8)
	geometry.uvs[5] = Vector2(0.95,0.8)
	geometry.islands = PackedInt32Array([0,1])
	geometry.build_cache()
	var unfolded := PaintOperations._unfold(geometry, PackedInt32Array([0,1]), 0, Vector2(64,64))
	check(unfolded.has(1) and unfolded[0][2].distance_to(unfolded[1][0]) < 0.0001 and unfolded[0][1].distance_to(unfolded[1][1]) < 0.0001, "Gradient unfolding joins physical edges across UV gaps")
	# Spray hold, bounded footprint, frozen settings and exact undo.
	var spray := PaintDocument.new()
	spray.initialize(64,64,Color.BLACK)
	var undo := PaintHistory.new()
	painter.setup(spray, undo)
	painter.tool = "spray"
	painter.brush_size = 12
	painter.spray_distance = 2.0
	painter.spray_particles = 16
	painter.spray_rate = 20.0
	painter.color = Color.WHITE
	painter.opacity = 1.0
	check(painter.footprint_size() == 24, "Spray distance controls actual cursor footprint")
	painter.begin(Vector2(32.5,32.5)/64.0)
	painter._spray_seed = 934
	painter._process(0.0)
	var initial := spray.selected_layer().tile_at(Vector2i.ZERO).get_data()
	painter.brush_size = 2
	painter.color = Color.RED
	painter._process(0.1)
	check(spray.selected_layer().tile_at(Vector2i.ZERO).get_data() != initial, "Stationary spray continues while held")
	check(painter.footprint_size() == 24, "Changing settings does not alter queued stroke footprint")
	drain(painter)
	var correct := true
	var count := 0
	tile = spray.selected_layer().tile_at(Vector2i.ZERO)
	for y in 64:
		for x in 64:
			var c := tile.get_pixel(x,y)
			if c.a > 0:
				count += 1
				correct = correct and Vector2(x+0.5-32,y+0.5-32).length() <= 12.0 and is_equal_approx(c.r,c.g)
	check(count > 10 and correct, "Spray deposits discrete particles inside cursor with frozen color")
	var painted := tile.get_data()
	undo.undo(spray)
	check(spray.selected_layer().tiles.is_empty(), "Whole spray stroke undoes in one action")
	undo.redo(spray)
	check(spray.selected_layer().tile_at(Vector2i.ZERO).get_data() == painted, "Spray redo preserves random particles exactly")
	# Leaving the mesh or crossing a UV seam must not replay old spray bursts.
	painter.setup(spray,PaintHistory.new())
	painter.tool = "spray"
	painter.begin(Vector2(0.2,0.2),0,0)
	painter.append_symmetry(Vector2(0.8,0.8),0,1)
	check(painter._symmetry_paths.has(1), "Spray tracks the current mirrored point")
	painter.append(Vector2(0.6,0.6),1,1)
	check(painter._symmetry_paths.is_empty() and painter._points.size() == painter._read+1, "Changing UV islands drops stale mirrored spray and queued bursts")
	painter.append_symmetry(Vector2(0.7,0.7),1,1)
	painter.break_path()
	check(painter._last.x < -90000 and painter._symmetry_paths.is_empty() and painter._points.size() == painter._read, "Leaving the mesh stops timed spray and discards queued old positions")
	drain(painter)
	var blur_doc := PaintDocument.new()
	blur_doc.initialize(64,64,Color.TRANSPARENT)
	blur_doc.selected_layer().tile_at(Vector2i.ZERO).set_pixel(32,32,Color.WHITE)
	var directional := PaintOperations.directional_blur_layer(progress,blur_doc,blur_doc.selected_layer().id,16,0.0,1.0)
	var directional_tile: Image = directional.tiles[Vector2i.ZERO]
	check(directional_tile.get_pixel(28,32).a > 0.0 and directional_tile.get_pixel(32,28).a == 0.0, "Directional blur spreads along the chosen angle only")
	var selection_mask := Image.create(64,64,false,Image.FORMAT_RGBA8)
	selection_mask.fill(Color.TRANSPARENT)
	selection_mask.set_pixel(28,32,Color.WHITE)
	var selected_blur := PaintOperations.directional_blur_layer(progress,blur_doc,blur_doc.selected_layer().id,16,0.0,1.0,{Vector2i.ZERO:selection_mask})
	check(selected_blur.tiles[Vector2i.ZERO].get_pixel(28,32).a > 0.0 and selected_blur.tiles[Vector2i.ZERO].get_pixel(36,32).a == 0.0, "Directional blur respects the face selection mask")
	check(PaintOperations.directional_blur_layer(progress,blur_doc,blur_doc.selected_layer().id,16,0.0,0.0).changed.is_empty(), "Zero directional blur strength leaves paint unchanged")
	var directional_4k := PaintDocument.new()
	directional_4k.initialize(4096,4096,Color.TRANSPARENT)
	directional_4k.selected_layer().tile_at(Vector2i(30,30)).set_pixel(32,32,Color.WHITE)
	var big_directional := PaintOperations.directional_blur_layer(progress,directional_4k,directional_4k.selected_layer().id,64,45.0,0.8)
	check(not big_directional.changed.is_empty() and big_directional.changed.size() <= 9,"4K directional blur touches only painted tiles and their neighbors")
	var cancelled := BackgroundJob.JobProgress.new()
	cancelled.cancel()
	check(UVUnwrapper.unwrap(geometry,64,64,45,1,cancelled).get("cancelled",false), "UV generation honours cancellation")
	# Real GLB round trip exercises the runtime importer, including transforms and UVs.
	var node := MeshInstance3D.new()
	node.mesh = geometry.to_mesh()
	var loader := GLTFDocument.new()
	var state := GLTFState.new()
	var err := loader.append_from_scene(node, state)
	var glb_path := ProjectSettings.globalize_path("res://test_output/model.glb")
	if err == OK:
		err = loader.write_to_filesystem(state, glb_path)
	check(err == OK, "GLB test fixture exports")
	if err == OK:
		var imported := ModelIO.load_model(progress, glb_path)
		check(imported.has("geometry") and imported.geometry.face_count() == 2 and imported.geometry.has_uv, "Runtime GLB import restores UV geometry")
	node.free()
