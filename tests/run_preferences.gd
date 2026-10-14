extends SceneTree

var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label)

func ready_document(scene: Node) -> void:
	var deadline := Time.get_ticks_msec()+30000
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			check(false,"Project startup timed out")
			return
	for i in 3: await process_frame

func run() -> void:
	var config_path := ProjectSettings.globalize_path("res://test_output/preferences_test.cfg")
	var project_path := ProjectSettings.globalize_path("res://test_output/preferences_last.rtpaint")
	DirAccess.remove_absolute(config_path)
	var scene = load("res://scenes/main_window.tscn").instantiate()
	scene.settings_path = config_path
	root.add_child(scene)
	root.size = Vector2i(1440,900)
	scene.get_node("%Autosave").stop()
	await ready_document(scene)
	var header = scene.get_node("Margin/Layout/Header")
	check(header.get_child_count() == 3 and scene.get_node_or_null("%Save") == null and scene.get_node_or_null("%Export") == null,"Top bar contains only menus, brand and project title")
	for name in ["Undo","Redo","Frame","Wires","Ortho","Light"]:
		var button: Button = scene.model_view.get_node("Header/"+name)
		check(button.icon != null and button.text.is_empty() and not button.tooltip_text.is_empty(),"Model "+name+" is an icon with tooltip")
	for name in ["Shape","Dither","Mirror"]:
		var button: Button = scene.get_node("%ToolOptions/"+name)
		check(button.icon != null and button.text.is_empty() and not button.tooltip_text.is_empty(),"Brush "+name+" is an icon with tooltip")
	check(scene.get_node("%ToolBar/Compact").button_pressed and scene.get_node("%ToolBar/Tools").columns == 2,"Compact two-column toolbar is default")
	var start := {"uv":Vector2(0.2,0.2),"face":-1}
	var finish := {"uv":Vector2(0.6,0.65),"face":-1}
	var mode := 1
	for tool in ["line","rect","ellipse"]:
		scene.get_node("%ToolBar").select(tool)
		var before: int = scene.document.selected_layer().tiles.size()
		if tool == "line":
			var canvas: UVCanvas = scene.uv_canvas
			var origin: Vector2 = canvas._origin()
			var scale: Vector2 = Vector2(scene.document.width,scene.document.height)*canvas.zoom
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = origin+start.uv*scale
			canvas._gui_input(press)
			var motion := InputEventMouseMotion.new()
			motion.position = origin+finish.uv*scale
			canvas._gui_input(motion)
		else:
			scene._surface_input("begin",start,0,false)
			scene._surface_input("move",finish,0,false)
		check(scene.uv_canvas.shape_preview_kind == tool and int(scene.model_view.display_material.get_shader_parameter("shape_preview_mode")) == mode,"Dragging "+tool+" previews in UV and model views")
		check(scene.document.selected_layer().tiles.size() == before,"Preview of "+tool+" does not paint before mouse release")
		if tool == "line":
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = scene.uv_canvas._origin()+finish.uv*Vector2(scene.document.width,scene.document.height)*scene.uv_canvas.zoom
			scene.uv_canvas._gui_input(release)
		else:
			scene._surface_input("end",finish,0,false)
		while scene.painter.active: await process_frame
		check(scene.uv_canvas.shape_preview_kind.is_empty() and int(scene.model_view.display_material.get_shader_parameter("shape_preview_mode")) == 0,"Preview of "+tool+" clears after commit")
		mode += 1
	var stamp := Image.create(8,4,false,Image.FORMAT_RGBA8)
	stamp.fill(Color.RED)
	stamp.fill_rect(Rect2i(4,0,4,4),Color.BLUE)
	var stamp_path := ProjectSettings.globalize_path("res://test_output/preferences_stamp.png")
	stamp.save_png(stamp_path)
	scene._file_action = "stencil"
	scene._file_selected(stamp_path)
	scene.get_node("%StampPanel/Fields/X").set_value(2)
	scene.get_node("%StampPanel/Fields/W").set_value(3)
	check(scene.document.stamp_region == Rect2i(2,0,3,4),"Stamp crop is editable before saving")
	var pattern := Image.create(4,4,false,Image.FORMAT_RGBA8)
	pattern.fill(Color("55aa77"))
	var pattern_path := ProjectSettings.globalize_path("res://test_output/preferences_pattern.png")
	pattern.save_png(pattern_path)
	scene._file_action = "pattern"
	scene._file_selected(pattern_path)
	scene.get_node("%Pattern/Angle").set_value(90)
	scene.get_node("%Pattern/Scale").set_value(125)
	scene.get_node("%Pattern/OffsetX").set_value(3)
	scene.get_node("%Pattern/OffsetY").set_value(-2)
	scene._commit_effects()
	check(scene.document.pattern_settings.angle == 90.0 and scene.document.pattern_settings.scale == 1.25,"Pattern transform updates project state")
	scene._action("Undo")
	check(scene.document.pattern_settings.angle == 0.0 and scene.get_node("%Pattern/Angle").value == 0.0,"Undo restores Pattern settings in inspector")
	scene._action("Redo")
	check(scene.document.pattern_settings.angle == 90.0 and scene.get_node("%Pattern/Angle").value == 90.0,"Redo restores Pattern settings in inspector")
	var progress := BackgroundJob.JobProgress.new()
	scene._sync_assets()
	check(ProjectIO.save_project(progress,scene.document,project_path).has("path"),"Test project saved for last-project restore")
	scene.document.path = project_path
	scene.get_node("%ToolBar/Compact").button_pressed = false
	scene.get_node("%ToolOptions/Size").set_value(17)
	scene.get_node("%ToolOptions/Falloff").set_value(55)
	scene.get_node("%ToolOptions/Shape").button_pressed = true
	scene.get_node("%ToolOptions/Dither").button_pressed = true
	scene.get_node("%ToolOptions/Mirror").button_pressed = true
	scene.get_node("%ToolBar").select("spray")
	scene.get_node("%SprayOptions/Opacity").set_value(35)
	scene.get_node("%SprayOptions/Flow").set_value(7.5)
	scene.get_node("%SprayOptions/Particles").set_value(24)
	scene.model_view.get_node("Header/Wires").button_pressed = true
	scene.model_view.get_node("Header/Ortho").button_pressed = true
	scene.get_node("%Effects/AOStrength").set_value(42)
	scene.get_node("%Effects/AORadius").set_value(11)
	scene.get_node("%Effects/AOFalloff").select(2)
	scene.get_node("%Effects/NormalStrength").set_value(175)
	scene.get_node("%Effects/BlurRadius").set_value(9)
	scene.get_node("%Effects/AOSection").button_pressed = true
	scene.get_node("%Effects/BlurSection").button_pressed = true
	scene.get_node("%UV/Padding").set_value(5)
	scene.get_node("%Inspector").current_tab = 4
	await process_frame
	var preview = scene.get_node("%StampPanel/Preview")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = preview._image_rect().get_center()
	preview._gui_input(wheel)
	scene.get_node("%UVView").button_pressed = false
	scene.get_node("%MainDock").split_offset = -160
	scene.get_node("%MainSplit").split_offset = -380
	scene._remember_project(project_path)
	scene._save_preferences()
	var stored := ConfigFile.new()
	check(stored.load(config_path) == OK and stored.get_value("files","last_project","") == project_path and stored.get_value("spray","flow",0) == 7.5,"Config saves last project and spray settings")
	root.remove_child(scene); scene.free()
	var reopened = load("res://scenes/main_window.tscn").instantiate()
	reopened.settings_path = config_path
	root.add_child(reopened)
	reopened.get_node("%Autosave").stop()
	await ready_document(reopened)
	check(reopened.document.path == project_path and reopened.document.title == "Field crate","Startup reopens last project")
	check(reopened.document.stamp_image != null and reopened.document.stamp_region == Rect2i(2,0,3,4) and reopened.get_node("%StampPanel").source != null,"Last project restores embedded stamp and crop")
	check(reopened.document.pattern_image != null and reopened.document.pattern_settings.angle == 90.0 and reopened.document.pattern_settings.scale == 1.25 and reopened.get_node("%Pattern/OffsetY").value == -2.0,"Last project restores Pattern image and transform")
	check(reopened.get_node("%Inspector").current_tab == 4 and reopened.get_node("%StampPanel/Preview").view_state().zoom > 1.0,"Last inspector tab and stamp zoom restore")
	check(reopened.get_node("%Effects/AOStrength").value == 42 and reopened.get_node("%Effects/AORadius").value == 11 and reopened.get_node("%Effects/AOFalloff").selected == 2 and reopened.get_node("%UV/Padding").value == 5,"Inspector effect and UV controls restore")
	check(reopened.get_node("%Effects/NormalStrength").value == 175 and reopened.get_node("%Effects/BlurRadius").value == 9 and reopened.get_node("%Effects/AOSection").button_pressed and reopened.get_node("%Effects/BlurSection").button_pressed and not reopened.get_node("%Effects/NormalSection").button_pressed,"Effect settings and expanded sections restore")
	check(not reopened.get_node("%ToolBar/Compact").button_pressed and reopened.painter.tool == "spray" and reopened.painter.brush_size == 17,"Toolbar mode, tool and size restore")
	check(reopened.painter.shape == 1 and reopened.painter.dither and reopened.painter.mirror,"Shape, dither and UV mirror restore")
	check(is_equal_approx(reopened.painter.falloff,0.55),"Brush falloff restores from config")
	check(is_equal_approx(reopened.painter.opacity,0.35) and is_equal_approx(reopened.painter.spray_flow,0.075) and reopened.painter.spray_particles == 24,"Spray controls restore")
	check(reopened.model_view.get_node("Header/Wires").button_pressed and reopened.model_view.get_node("Header/Ortho").button_pressed and not reopened.get_node("%UVView").button_pressed,"View toggles restore")
	check(reopened.get_node("%MainDock").split_offset == -160 and reopened.get_node("%MainSplit").split_offset == -380,"Panel sizes restore")
	check(not reopened.get_node("%MenuBar/File").get_popup().is_item_disabled(2),"File menu offers last project")
	reopened._action("ToggleRestoreLast")
	reopened._save_preferences()
	root.remove_child(reopened); reopened.free()
	var sample = load("res://scenes/main_window.tscn").instantiate()
	sample.settings_path = config_path
	root.add_child(sample)
	sample.get_node("%Autosave").stop()
	await ready_document(sample)
	check(sample.document.path.is_empty() and sample.document.title == "Field crate","Disabling reopen starts the sample while retaining last-project path")
	sample.document.saved_revision = sample.document.revision
	print("PREFERENCES CHECKS: %d passed / %d; failures: %d" % [checks-failures,checks,failures])
	quit(1 if failures else 0)
