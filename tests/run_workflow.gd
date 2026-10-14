extends SceneTree
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label)
func drain(painter: PaintEngine) -> void:
	painter.end()
	while painter.active: painter._process(0.0)
func settle(scene: Node) -> void:
	var limit := Time.get_ticks_msec()+30000
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled():
		await process_frame
		if Time.get_ticks_msec() > limit: check(false,"Timed out"); quit(1); return
	for i in 4: await process_frame
func run() -> void:
	var doc := PaintDocument.new()
	doc.initialize(128,64,Color.BLACK)
	doc.layers[0].tile_at(Vector2i.ZERO).fill(Color.WHITE)
	var painter := PaintEngine.new()
	root.add_child(painter)
	painter.set_process(false)
	var history := PaintHistory.new()
	painter.setup(doc,history)
	painter.tool = "blur"; painter.brush_size = 12; painter.opacity = 1
	painter.begin(Vector2(64.5,32.5)/Vector2(128,64))
	drain(painter)
	var left := doc.compose_tile(Vector2i.ZERO).get_pixel(63,32)
	var right := doc.compose_tile(Vector2i(1,0)).get_pixel(0,32)
	check(left.r < 1 and left.r > 0 and right.r > 0 and right.r < 1,"Blur softens an edge across tile boundaries")
	check(doc.compose_tile(Vector2i.ZERO).get_pixel(20,32) == Color.WHITE,"Blur leaves pixels outside brush unchanged")
	var alpha_image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	alpha_image.fill(Color.TRANSPARENT); alpha_image.fill_rect(Rect2i(0,0,4,8),Color.RED)
	var softened := BrushFilters.blur(alpha_image)
	check(softened.get_pixel(4,4).a > 0 and softened.get_pixel(4,4).r > 0.98,"Blur preserves color at transparent edges")
	history.undo(doc)
	check(doc.selected_layer().tiles.is_empty(),"Blur undo restores sparse paint layer")
	painter.tool = "smudge"; painter.brush_size = 8
	painter.begin(Vector2(60.5,32.5)/Vector2(128,64))
	painter._process(0)
	painter.append(Vector2(69.5,32.5)/Vector2(128,64))
	drain(painter)
	check(doc.compose_tile(Vector2i(1,0)).get_pixel(4,32).r > 0,"Smudge drags white paint into black area")
	var dragged: PackedByteArray = doc.selected_layer().tiles[Vector2i(1,0)].get_data()
	history.undo(doc); history.redo(doc)
	check(doc.selected_layer().tiles[Vector2i(1,0)].get_data() == dragged,"Smudge redo is exact")
	history.undo(doc)
	painter.opacity = 0
	painter.begin(Vector2(60.5,32.5)/Vector2(128,64)); painter.append(Vector2(70.5,32.5)/Vector2(128,64)); drain(painter)
	check(doc.selected_layer().tiles.is_empty(),"Zero-strength smudge does not paint")
	doc.initialize(64,64,Color.BLACK)
	painter.setup(doc,PaintHistory.new())
	painter.tool = "spray"; painter.brush_size = 24; painter.spray_particles = 100; painter.spray_distance = 1
	painter.opacity = 0.2; painter.spray_flow = 0.4; painter.color = Color.WHITE; painter._spray_seed = 12345
	var uv := Vector2(32.5,32.5)/64.0
	var preview := painter.spray_preview(uv,-1)
	painter.begin(uv)
	painter._process(0)
	var painted := doc.selected_layer().tile_at(Vector2i.ZERO)
	var exact := true
	for y in 24:
		for x in 24:
			if (preview.get_pixel(x,y).a > 0) != (painted.get_pixel(x+20,y+20).a > 0): exact = false
	check(exact,"Spray preview matches the exact first-burst pixel positions")
	for i in 30: painter._process(0.1)
	drain(painter)
	var maximum := 0.0
	for y in 64:
		for x in 64: maximum = maxf(maximum,painted.get_pixel(x,y).a)
	check(maximum <= 0.205 and maximum > 0.1,"Spray opacity caps the entire held stroke")
	var shape := Image.create(64,64,false,Image.FORMAT_RGBA8)
	shape.fill(Color.TRANSPARENT); shape.fill_rect(Rect2i(0,0,32,64),Color.WHITE)
	painter.selection_active = true; painter.selection = {Vector2i.ZERO:shape}
	preview = painter.spray_preview(uv,-1)
	var clipped := true
	for y in 24:
		for x in range(12,24):
			if preview.get_pixel(x,y).a > 0: clipped = false
	check(clipped,"Spray preview clips to selected texels")
	# Separate data channels remain independent and survive saving/export.
	doc.initialize(32,32,Color("336699"))
	doc.geometry = UVUnwrapper.unwrap(ModelGeometry.demo(),32,32,45,1).geometry
	for channel in PaintChannels.IDS.slice(1):
		var channel_layer := PaintLayer.new(); channel_layer.channel = channel; channel_layer.title = channel
		channel_layer.base_color = Color(0.3,0.3,0.3) if PaintChannels.scalar(channel) else PaintChannels.background(channel)
		doc.layers.append(channel_layer)
	doc.active_layer = 3
	doc.effects.brightness = 0.2
	var progress := BackgroundJob.JobProgress.new()
	var rough := ProjectIO.render_image(progress,doc,"roughness")
	check(absf(rough.image.get_pixel(1,1).r-0.3) < 0.01,"Data map ignores Albedo color effects")
	check(doc.compose_tile(Vector2i.ZERO,"albedo").get_pixel(1,1).to_html(false) == "336699","Other map layers do not contaminate Albedo")
	var path := ProjectSettings.globalize_path("res://test_output/channels.rtpaint")
	ProjectIO.save_project(progress,doc,path)
	var restored := ProjectIO.load_project(progress,path)
	check(restored.has("document") and restored.document.layers[3].channel == "metallic" and restored.document.current_channel() == "metallic","Map identities and active map survive project save/load")
	var legacy_meta := doc.layers[0].metadata()
	legacy_meta.erase("channel")
	var legacy_path := ProjectSettings.globalize_path("res://test_output/legacy_v1.rtpaint")
	var legacy_zip := ZIPPacker.new()
	legacy_zip.open(legacy_path)
	ProjectIO._write(legacy_zip,"manifest.json",JSON.stringify({"format":"retro-texture-painter","version":1,"width":32,"height":32,"layers":[legacy_meta]}).to_utf8_buffer())
	legacy_zip.close()
	var legacy := ProjectIO.load_project(progress,legacy_path)
	check(legacy.has("document") and legacy.document.current_channel() == "albedo" and legacy.document.compose_tile(Vector2i.ZERO).get_pixel(1,1).to_html(false) == "336699","Version 1 projects without map metadata still load as Albedo")
	var exported := ModelExport.export_maps(progress,doc,ProjectSettings.globalize_path("res://test_output/maps.png"))
	check(exported.has("paths") and exported.paths.size() == 7,"Export all maps writes seven independent PNG maps")
	var glb := ProjectSettings.globalize_path("res://test_output/channels.glb")
	check(not ModelExport.save(progress,doc,glb).has("error"),"GLB exports all supported material maps")
	var state := GLTFState.new(); var loader := GLTFDocument.new()
	var error := loader.append_from_file(glb,state)
	check(error == OK,"Exported PBR model imports")
	if error == OK:
		var material: StandardMaterial3D = state.get_materials()[0]
		check(material.normal_enabled and material.normal_texture != null and material.roughness_texture != null and material.metallic_texture != null and material.ao_texture != null and material.emission_texture != null,"GLB keeps normal, roughness, metallic, AO and emission textures")
		check(material.albedo_texture.get_image().get_pixel(1,1).to_rgba32() == ProjectIO.render_image(progress,doc,"albedo").image.get_pixel(1,1).to_rgba32(),"GLB always uses Albedo as base color while another map is active")
	var material_import := ModelIO.load_model(progress,glb,128,128)
	check(material_import.has("imported_layers") and material_import.imported_layers.size() >= 5,"Import transfers source material maps to a new UV atlas")
	if material_import.has("imported_layers"):
		check(material_import.geometry.has_uv and not material_import.imported_layers[0].tiles.is_empty(),"Imported material keeps UV coverage and paint tiles")
	var preview_maps := PBRPreview.build(progress,doc)
	check(preview_maps.has("maps") and preview_maps.maps.size() == 6,"Lit preview builds all six material maps")
	var mask_result := PaintOperations.geometry_mask(progress,doc,"edges",{"width":2,"invert":false})
	check(mask_result.has("masks") and not mask_result.masks.is_empty(),"Geometry edges can generate a paint-layer mask")
	var pattern_doc := PaintDocument.new()
	pattern_doc.initialize(128,128,Color.BLACK)
	pattern_doc.geometry = UVUnwrapper.unwrap(ModelGeometry.demo(),128,128,45,1).geometry
	var pattern_image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	pattern_image.fill(Color.RED)
	pattern_image.set_pixel(1,0,Color.GREEN)
	var pattern_faces := PackedInt32Array([0])
	var pattern_result := PaintOperations.pattern_layer(progress,pattern_doc,pattern_faces,pattern_image,{"angle":0.0,"scale":1.0,"offset":Vector2.ZERO})
	check(pattern_result.has("layer") and not pattern_result.layer.pattern_tiles.is_empty(),"Texture fill creates an editable pattern layer")
	if pattern_result.has("layer"):
		pattern_doc.layers.append(pattern_result.layer)
		pattern_doc.active_layer = pattern_doc.layers.size()-1
		var sample_key: Vector2i = pattern_result.layer.pattern_tiles.keys()[0]
		pattern_result.layer.tile_at(sample_key).set_pixel(1,1,Color.BLUE)
		var changed_pattern := PaintOperations.rerender_pattern(progress,pattern_doc,pattern_result.layer.id,pattern_image,{"angle":90.0,"scale":1.0,"offset":Vector2.ZERO})
		check(changed_pattern.has("layer") and changed_pattern.layer.tiles[sample_key].get_pixel(1,1) == Color.BLUE,"Pattern rotation preserves manual paint above it")
		pattern_doc.layers[pattern_doc.active_layer] = changed_pattern.layer
		var pattern_path := ProjectSettings.globalize_path("res://test_output/pattern.rtpaint")
		ProjectIO.save_project(progress,pattern_doc,pattern_path)
		var pattern_restored := ProjectIO.load_project(progress,pattern_path)
		check(pattern_restored.has("document") and pattern_restored.document.selected_layer().pattern_image != null and not pattern_restored.document.selected_layer().pattern_tiles.is_empty(),"Pattern source and transform survive project save/load")
		var replaced_pattern := ProjectTransforms.replace_color(progress,pattern_doc,Color.RED,Color.YELLOW,0.0)
		check(replaced_pattern.changed > 0 and replaced_pattern.layers[pattern_doc.active_layer].pattern_image.get_pixel(0,0) == Color.YELLOW,"Global color replace also updates editable pattern source")
	# Real scene layout, controls, layer row actions and key routing.
	var scene = load("res://scenes/main_window.tscn").instantiate(); scene.settings_enabled = false; root.add_child(scene)
	root.size = Vector2i(1440,900); scene.get_node("%Autosave").stop()
	await settle(scene)
	var palette_count: int = scene.document.palette.size()
	var custom_color := Color("c7378a")
	scene._palette_change("add",-1,custom_color)
	check(scene.document.palette.size() == palette_count+1 and scene.document.primary_color == custom_color,"Plus palette action adds and selects a new color")
	var palette_path := ProjectSettings.globalize_path("res://test_output/custom_palette.rtpaint")
	ProjectIO.save_project(progress,scene.document,palette_path)
	var palette_restored := ProjectIO.load_project(progress,palette_path)
	check(palette_restored.has("document") and palette_restored.document.palette[palette_count] == custom_color,"Added palette color persists in saved project")
	scene._palette_change("edit",palette_count,Color("32bada"))
	check(scene.document.palette[palette_count] == Color("32bada") and scene.document.primary_color == Color("32bada"),"Palette edit updates selected primary color")
	scene._palette_change("remove",palette_count,Color.TRANSPARENT)
	check(scene.document.palette.size() == palette_count,"Palette remove changes the project palette")
	scene._action("Undo")
	check(scene.document.palette.size() == palette_count+1,"Palette removal supports Undo")
	var palette_height: float = scene.get_node("%PalettePanel").size.y
	var inspector_width: float = scene.get_node("%Inspector").size.x
	for tool in ["spray","gradient","brush","smudge","blur"]:
		scene.get_node("%ToolBar").select(tool)
		scene._refresh_metadata()
		await settle(scene)
		check(is_equal_approx(scene.get_node("%PalettePanel").size.y,palette_height),"Palette height stays fixed for "+tool)
		check(is_equal_approx(scene.get_node("%Inspector").size.x,inspector_width),"Inspector width stays fixed for %s (%.1f to %.1f)" % [tool, inspector_width, scene.get_node("%Inspector").size.x])
	scene.get_node("%ToolBar/Compact").button_pressed = true
	await settle(scene)
	check(scene.get_node("%ToolBar/Tools").columns == 2,"Compact toolbar uses two columns")
	scene.get_node("%MainDock").split_offset -= 30
	await settle(scene)
	check(scene.get_node("%PalettePanel").size.y > palette_height+20,"Palette divider changes its height")
	var resized_height: float = scene.get_node("%PalettePanel").size.y
	scene.get_node("%MainSplit").split_offset -= 40
	await settle(scene)
	check(scene.get_node("%Inspector").size.x > inspector_width+30,"Inspector divider changes its width")
	var resized_width: float = scene.get_node("%Inspector").size.x
	for index in 4:
		scene.get_node("%Inspector").current_tab = index
		await settle(scene)
		check(is_equal_approx(scene.get_node("%Inspector").size.x,resized_width) and is_equal_approx(scene.get_node("%PalettePanel").size.y,resized_height),"Switching inspector tabs preserves panel dimensions")
	scene.get_node("%Inspector").current_tab = 0
	var layer: PaintLayer = scene.document.selected_layer()
	var row = scene.get_node("%Layers").rows[layer.id]
	row.get_node("Eye").button_pressed = true; row.get_node("Eye").pressed.emit()
	check(not layer.visible,"Eye button hides its layer")
	scene._action("Undo")
	check(layer.visible,"Layer visibility supports undo")
	row.begin_rename(); row._rename("Custom details")
	check(layer.title == "Custom details","Inline layer rename applies")
	scene._action("Undo")
	check(layer.title != "Custom details","Layer rename supports undo")
	scene._select_channel("roughness")
	await settle(scene)
	check(scene.document.current_channel() == "roughness" and scene.get_node("%MapSelector").selected == 1,"Map selector creates and selects roughness layer")
	scene._action("Undo")
	await settle(scene)
	check(scene.document.current_channel() == "albedo","Undo adding a map restores previous active layer")
	var tab := InputEventKey.new(); tab.pressed = true; tab.keycode = KEY_TAB
	scene._input(tab)
	check(scene.model_view.get_node("Display/Viewport/World/Wires").visible,"Tab turns on model wireframe")
	scene._input(tab)
	check(not scene.model_view.get_node("Display/Viewport/World/Wires").visible,"Tab turns wireframe off")
	scene.get_node("%ToolBar").select("select")
	var hit: Dictionary = scene.model_view._hit(scene.model_view.display.size*0.5)
	scene._hover(hit,true)
	check(scene.model_view.get_node("Display/Viewport/World/Hover").mesh != null,"Select mode previews the surface under the cursor")
	while scene.document.layers.size() < 32: scene.document.layers.append(PaintLayer.new())
	scene._layer_action("duplicate",null)
	check(scene.document.layers.size() == 32,"Duplicating at the layer limit cannot create an unloadable project")
	print("WORKFLOW CHECKS: %d passed / %d; failures: %d" % [checks-failures,checks,failures])
	var report := FileAccess.open("res://test_output/workflow_results.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	scene.document.saved_revision = scene.document.revision
	quit(1 if failures else 0)
