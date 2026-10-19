extends SceneTree
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var square := PackedVector2Array([Vector2(4,4),Vector2(12,4),Vector2(12,12),Vector2(4,12)])
	var mask := LassoSelection.uv_mask(square,Vector2i(16,16))
	check(mask.has(Vector2i.ZERO) and mask[Vector2i.ZERO].get_pixel(7,7).a > 0.9 and mask[Vector2i.ZERO].get_pixel(2,2).a == 0.0,"UV lasso closes and fills only its interior")
	var border := LassoSelection.boundary(mask,Vector2i(16,16))
	check(border.get_pixel(4,7).r > 0.9 and border.get_pixel(7,7).r == 0.0,"Marching ants boundary surrounds selected pixels")
	var edge_tile := Image.create(64,64,false,Image.FORMAT_RGBA8)
	edge_tile.fill(Color.BLACK)
	edge_tile.fill_rect(Rect2i(30,0,34,64),Color.WHITE)
	check(LassoSelection.snap_uv(Vector2(28,20),edge_tile,Vector2i.ZERO).x > 29.0,"UV lasso snaps nearby points to a strong color edge")
	var tip := Image.create(5,5,false,Image.FORMAT_RGBA8)
	tip.fill(Color.TRANSPARENT)
	tip.set_pixel(2,0,Color.WHITE)
	var rotated := BrushLibrary.rotated_tip(tip,5,90.0)
	check(rotated.get_pixel(4,2).a > 0.9 and rotated.get_pixel(2,0).a == 0.0,"Special brush tip rotates by 90 degrees")
	var saved := BrushLibrary.save_tip("Selection brush test",tip)
	check(saved.has("path") and BrushLibrary.load_tip(str(saved.get("path",""))) != null,"Drawn brush persists in user brush folder")
	if saved.has("path"): DirAccess.remove_absolute(ProjectSettings.globalize_path(str(saved.path)))
	var round_pattern := PaintEngine.spray_pattern(17,16,1,Color.WHITE,false,5,true)
	var square_pattern := PaintEngine.spray_pattern(17,16,1,Color.WHITE,false,5,false)
	check(square_pattern.points.size() > round_pattern.points.size() and round_pattern.points.size() > 1,"Spray supports larger round and square dots")
	var wand_doc := PaintDocument.new()
	wand_doc.initialize(16,16,Color.BLACK)
	var wand_tile := wand_doc.selected_layer().tile_at(Vector2i.ZERO)
	wand_tile.fill_rect(Rect2i(2,2,2,2),Color.WHITE)
	wand_tile.fill_rect(Rect2i(10,10,2,2),Color.WHITE)
	var wand_progress := BackgroundJob.JobProgress.new()
	var connected := MagicWandSelection.select(wand_progress,wand_doc,Vector2i(2,2),-1,0,0.0,{},0)
	check(connected.selection[Vector2i.ZERO].get_pixel(2,2).a > 0.9 and connected.selection[Vector2i.ZERO].get_pixel(10,10).a == 0.0,"Magic Wand selects only the connected color patch")
	var matching := MagicWandSelection.select(wand_progress,wand_doc,Vector2i(2,2),-1,1,0.0,{},0)
	check(matching.selection[Vector2i.ZERO].get_pixel(2,2).a > 0.9 and matching.selection[Vector2i.ZERO].get_pixel(10,10).a > 0.9,"Magic Wand selects matching color across separate patches")
	var added := MagicWandSelection.select(wand_progress,wand_doc,Vector2i(10,10),-1,0,0.0,connected.selection,1)
	check(added.selection[Vector2i.ZERO].get_pixel(2,2).a > 0.9 and added.selection[Vector2i.ZERO].get_pixel(10,10).a > 0.9,"Ctrl add keeps both Wand regions")
	var removed := MagicWandSelection.select(wand_progress,wand_doc,Vector2i(2,2),-1,0,0.0,added.selection,2)
	check(removed.selection[Vector2i.ZERO].get_pixel(2,2).a == 0.0 and removed.selection[Vector2i.ZERO].get_pixel(10,10).a > 0.9,"Alt subtract removes just the clicked Wand region")
	var scene: Control = load("res://scenes/main_window.tscn").instantiate()
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
	var popup: PopupPanel = scene.get_node("%StampPopup")
	scene.get_node("%StampOptions/Crop").pressed.emit()
	check(popup.visible,"Stamp crop button opens its popup without null-node error")
	popup.hide()
	scene.model_view.distance = 100.0
	scene._unhandled_key_input(_key(KEY_PERIOD))
	check(scene.model_view.distance < 100.0,"Period key focuses the model")
	var frame: Vector2 = scene.model_view.display.size
	var world_polygon := PackedVector2Array([Vector2.ZERO,Vector2(frame.x,0),frame,Vector2(0,frame.y)])
	var model_mask := LassoSelection.model_mask(BackgroundJob.JobProgress.new(),scene.document.geometry,world_polygon,Vector2i(scene.document.width,scene.document.height),frame,scene.model_view.camera.global_transform,scene.model_view.camera.get_camera_projection())
	check(not model_mask.is_empty(),"3D lasso projects visible model texels into a selection")
	scene.get_node("%ToolBar").select("select")
	scene.selection_mode = 1
	var face_hit: Dictionary = scene.model_view._hit(frame*0.5)
	if not face_hit.is_empty():
		scene._surface_input("begin",face_hit,0,true)
		while scene.jobs.busy(): await process_frame
		check(scene.selected_faces.size() == 1,"Click selects one face")
		scene._surface_input("begin",face_hit,2,true)
		while scene.jobs.busy(): await process_frame
		check(scene.selected_faces.is_empty(),"Ctrl+click subtracts a selected face")
		scene.get_node("%ToolBar").select("wand")
		check(scene.get_node("%WandOptions").visible and scene.get_node("%ToolBar/Tools/Wand").button_pressed,"Wand has its own visible toolbar options")
		scene.get_node("%WandOptions").set_options(2,0.0)
		scene.wand_mode = 2
		scene._surface_input("begin",face_hit,0,true)
		while scene.jobs.busy(): await process_frame
		check(scene.painter.selection_active and scene.get_node("%CloseSelection").visible,"Wand click selects the UV island and shows Close selection")
		scene._surface_input("begin",face_hit,4,true)
		while scene.jobs.busy(): await process_frame
		check(not scene.painter.selection_active and not scene.get_node("%CloseSelection").visible,"Alt+click subtracts the Wand selection without changing opacity")
		scene._surface_input("begin",face_hit,2,true)
		while scene.jobs.busy(): await process_frame
		check(scene.painter.selection_active,"Ctrl+click adds the Wand selection without changing brush size")
		scene.get_node("%CloseSelection").pressed.emit()
		check(scene.painter.tool == "brush" and scene.painter.selection_active,"Close selection returns to Brush and keeps the Wand mask")
		scene._clear_selection()
	scene.get_node("%ToolBar").select("lasso")
	check(scene.model_view.lasso_mode and scene.uv_canvas.lasso_mode,"Lasso is active in both model and UV views")
	scene._lasso_points = PackedVector2Array([Vector2(4,4),Vector2(12,4),Vector2(12,12),Vector2(4,12)])
	scene._lasso_from_model = false
	scene._close_lasso()
	while scene.jobs.busy(): await process_frame
	check(scene.painter.selection_active and scene.painter.selection[Vector2i.ZERO].get_pixel(8,8).a > 0.9 and scene.painter.selection[Vector2i.ZERO].get_pixel(2,2).a == 0.0,"Closing lasso installs restrictive paint mask")
	check(bool(scene.model_view.display_material.get_shader_parameter("selection_ants_enabled")) and bool(scene.uv_canvas.display_material.get_shader_parameter("selection_ants_enabled")),"Selection boundary appears in both views")
	var gradient := PaintOperations.gradient(BackgroundJob.JobProgress.new(),scene.document,PackedInt32Array(),{"uv":Vector2.ZERO,"face":-1},{"uv":Vector2(0.1,0.1),"face":-1},7,Color.WHITE,Color.BLACK,false,0,scene.painter.selection)
	check(gradient.command.after[Vector2i.ZERO].get_pixel(8,8).a > 0.9 and gradient.command.after[Vector2i.ZERO].get_pixel(2,2).a == 0.0,"Gradient cannot paint outside lasso")
	var texture := Image.create(2,2,false,Image.FORMAT_RGBA8)
	texture.fill(Color.RED)
	var pattern := PaintOperations.texture_fill(BackgroundJob.JobProgress.new(),scene.document,PackedInt32Array(),texture,{"angle":0.0,"scale":1.0,"offset":Vector2.ZERO},scene.painter.selection)
	check(pattern.command.after[Vector2i.ZERO].get_pixel(8,8).r > 0.9 and pattern.command.after[Vector2i.ZERO].get_pixel(2,2).a == 0.0,"Texture fill cannot paint outside lasso")
	scene.get_node("%ToolBar").select("brush")
	var history_before: int = scene.history.cursor
	scene.painter.begin(Vector2(50.0/scene.document.width,50.0/scene.document.height))
	check(scene.painter.selection_active,"Selection remains active after switching paint tools")
	scene.painter.end()
	while scene.painter.active: await process_frame
	check(scene.history.cursor == history_before,"Brush dab outside the lasso makes no paint command")
	scene._clear_selection()
	check(not scene.painter.selection_active and not bool(scene.model_view.display_material.get_shader_parameter("selection_ants_enabled")),"Clearing selection removes mask and marching ants")
	var editor = scene.get_node("%BrushEditor")
	editor.open_editor()
	editor.get_node("Body/Tools/Name").text = "UI brush test"
	editor.get_node("Body/Canvas").image.set_pixel(8,8,Color.WHITE)
	editor.confirmed.emit()
	editor.hide()
	check(scene.painter.brush_tip != null and scene.get_node("%BrushOptions/Tips").selected > 0,"Brush editor saves and selects a user brush")
	var brush_path: String = scene._brush_tip_path
	if brush_path.begins_with("user://"): DirAccess.remove_absolute(ProjectSettings.globalize_path(brush_path))
	var rotate_press := InputEventMouseButton.new()
	rotate_press.button_index = MOUSE_BUTTON_RIGHT
	rotate_press.pressed = true
	rotate_press.shift_pressed = true
	rotate_press.position = frame*0.5
	scene.model_view._input_display(rotate_press)
	var rotate_drag := InputEventMouseMotion.new()
	rotate_drag.relative = Vector2(40,0)
	rotate_drag.position = frame*0.5
	scene.model_view._input_display(rotate_drag)
	check(is_equal_approx(scene.painter.brush_angle,20.0),"Shift + right-drag rotates the active brush in 3D")
	rotate_press.pressed = false
	scene.model_view._input_display(rotate_press)
	scene.get_node("%ToolBar").select("spray")
	scene.get_node("%SprayOptions/DotSize").set_value(5)
	scene.get_node("%SprayOptions/DotShape").button_pressed = false
	check(scene.painter.spray_dot_size == 5 and not scene.painter.spray_dot_round,"Spray toolbar sets dot size and square shape")
	print("SELECTION CHECKS: %d / %d; failures: %d" % [checks-failures,checks,failures])
	quit(1 if failures else 0)

func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
