extends SceneTree
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label)

func run() -> void:
	var progress := BackgroundJob.JobProgress.new()
	var model := ModelGeometry.new()
	model.positions = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	model.normals = PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	model.uvs = PackedVector2Array([Vector2(0.1,0.1),Vector2(0.3,0.1),Vector2(0.1,0.3)])
	model.materials = PackedInt32Array([0])
	model.objects = PackedInt32Array([0])
	model.build_cache()
	var doc := PaintDocument.new()
	doc.initialize(64,64,Color.TRANSPARENT)
	doc.geometry = model
	var tile := doc.selected_layer().tile_at(Vector2i.ZERO)
	tile.set_pixel(11,11,Color.RED)
	var moved := ModelGeometry.from_data(model.serialized())
	for i in moved.uvs.size(): moved.uvs[i] += Vector2(0.4,0)
	moved.build_cache()
	var reproject := ProjectTransforms.reproject_uv(progress,doc,moved)
	check(reproject.get("transferred",false),"UV change transfers existing paint")
	var result_layer: PaintLayer = reproject.layers[doc.active_layer]
	check(result_layer.tiles.has(Vector2i.ZERO) and result_layer.tiles[Vector2i.ZERO].get_pixel(36,11).r > 0.9,"Moved UV face samples original paint")
	check(result_layer.tiles[Vector2i.ZERO].get_pixel(11,11).a == 0.0,"Old atlas position is cleared after transfer")
	var resized := ProjectTransforms.resize(progress,doc,128,128)
	check(resized.width == 128 and resized.height == 128,"Resize changes both dimensions")
	check(resized.layers[doc.active_layer].tiles[Vector2i.ZERO].get_pixel(22,22).r > 0.9,"Nearest-neighbor resize preserves pixel art")
	var uv_mask := UVRaster.selection(model,PackedInt32Array([0]),Vector2i(64,64))
	check(model.uvs[0].is_equal_approx(Vector2(0.1,0.1)),"Editing a UV copy never mutates the original geometry")
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in 64:
		for x in 64:
			if uv_mask[Vector2i.ZERO].get_pixel(x,y).a > 0: image.set_pixel(x,y,Color.RED)
	var dilated := ProjectTransforms.dilate_uv(progress,image,model,1)
	check(dilated.image.get_pixel(6,8).r > 0.9 and dilated.image.get_pixel(6,8).a > 0.9,"Export margin extends UV edge color")
	var cube := ModelGeometry.demo()
	var side := cube.ray_hit(Vector3(5,0,0),Vector3.LEFT)
	var symmetric := cube.mirrored_hit(side,1)
	check(not symmetric.is_empty() and symmetric.position.x < 0.0,"Model-space X symmetry finds the opposite surface")
	check(symmetric.is_empty() or side.uv != symmetric.uv,"Symmetric 3D surfaces have independent UV destinations")
	var painted_doc := PaintDocument.new()
	painted_doc.initialize(128,128,Color.TRANSPARENT)
	painted_doc.geometry = UVUnwrapper.unwrap(cube,128,128,45,1).geometry
	var right_hit := painted_doc.geometry.ray_hit(Vector3(5,0,0),Vector3.LEFT)
	var left_hit := painted_doc.geometry.mirrored_hit(right_hit,1)
	var painter := PaintEngine.new()
	root.add_child(painter)
	painter.set_process(false)
	var history := PaintHistory.new()
	painter.setup(painted_doc,history)
	painter.tool = "brush"
	painter.brush_size = 3
	painter.color = Color.RED
	painter.begin(right_hit.uv,painted_doc.geometry.islands[right_hit.face],right_hit.face)
	painter.append_symmetry(left_hit.uv,painted_doc.geometry.islands[left_hit.face],1)
	painter.end()
	while painter.active: painter._process(0)
	var right_pixel := Vector2i(right_hit.uv*Vector2(128,128))
	var left_pixel := Vector2i(left_hit.uv*Vector2(128,128))
	var right_tile := painted_doc.selected_layer().tiles.get(Vector2i(right_pixel.x/64,right_pixel.y/64))
	var left_tile := painted_doc.selected_layer().tiles.get(Vector2i(left_pixel.x/64,left_pixel.y/64))
	check(right_tile != null and left_tile != null and right_tile.get_pixel(right_pixel.x%64,right_pixel.y%64).r > 0.9 and left_tile.get_pixel(left_pixel.x%64,left_pixel.y%64).r > 0.9,"One stroke paints both mirrored 3D surfaces")
	check(history.actions.size() == 1,"Symmetric stroke commits as one Undo action")
	print("TRANSFORM CHECKS: %d passed / %d; failures: %d" % [checks-failures,checks,failures])
	quit(1 if failures else 0)
