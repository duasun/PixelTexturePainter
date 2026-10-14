extends SceneTree
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func ready_document(scene: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while scene.document == null or scene.jobs.busy() or not scene.tiles.is_settled():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			check(false, "Document initialization timed out")
			quit(1)
			return

func run() -> void:
	var scene = load("res://scenes/main_window.tscn").instantiate()
	scene.settings_enabled = false
	root.add_child(scene)
	root.size = Vector2i(1440,900)
	scene.get_node("%Autosave").stop()
	await ready_document(scene)
	var model_view: ModelView = scene.model_view
	var zoom_point: Vector2 = model_view.display.size * 0.5
	var zoom_hit: Dictionary = model_view._hit(zoom_point)
	check(not zoom_hit.is_empty(), "Camera zoom test starts on a visible model surface")
	if not zoom_hit.is_empty():
		var surface_point: Vector3 = zoom_hit.position
		var original_camera: Vector3 = model_view.camera.position
		var original_distance: float = model_view.distance
		var original_near: float = model_view.camera.near
		var original_screen: Vector2 = model_view.camera.unproject_position(surface_point)
		var model_wheel := InputEventMouseButton.new()
		model_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		model_wheel.pressed = true
		model_wheel.position = zoom_point
		model_view._input_display(model_wheel)
		check(is_equal_approx(model_view.distance, original_distance * ModelView.ZOOM_STEP) and model_view.camera.near < original_near, "Wheel zoom uses smaller steps and brings the near plane closer")
		check(model_view.camera.unproject_position(surface_point).distance_to(original_screen) < 1.0, "Zoom keeps the surface under the cursor")
		for i in 220: model_view._zoom_at(zoom_point, true)
		var toward_surface: Vector3 = (surface_point - original_camera).normalized()
		var remaining: float = (surface_point - model_view.camera.position).dot(toward_surface)
		check(remaining > 0.0 and model_view.camera.near < remaining and model_view.distance < original_distance * 0.001, "Close zoom stops before crossing the surface and keeps it unclipped")
		model_wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		var closest_distance: float = model_view.distance
		model_view._input_display(model_wheel)
		check(model_view.distance > closest_distance, "Wheel down moves away from the surface")
		model_view.frame_model()
	var tool_before_navigation: String = scene.painter.tool
	var orbit_press := InputEventMouseButton.new()
	orbit_press.button_index = MOUSE_BUTTON_RIGHT
	orbit_press.pressed = true
	orbit_press.position = zoom_point
	model_view._input_display(orbit_press)
	check(model_view._orbit and model_view.display.has_focus(), "Right mouse hold activates 3D navigation focus")
	var navigate := InputEventKey.new()
	navigate.keycode = KEY_A
	navigate.physical_keycode = KEY_A
	navigate.pressed = true
	var target_before_navigation: Vector3 = model_view.target
	Input.parse_input_event(navigate)
	await process_frame
	model_view._process(0.05)
	check(model_view.target != target_before_navigation and scene.painter.tool == tool_before_navigation, "RMB+A moves camera left without switching to Spray")
	var release_a: InputEventKey = navigate.duplicate()
	release_a.pressed = false
	Input.parse_input_event(release_a)
	await process_frame
	var down_key := InputEventKey.new()
	down_key.keycode = KEY_Q
	down_key.physical_keycode = KEY_Q
	down_key.pressed = true
	model_view._input(down_key)
	var height_before: float = model_view.target.y
	model_view._process(0.05)
	check(model_view.target.y < height_before, "RMB+Q moves down in world space")
	down_key.pressed = false
	model_view._input(down_key)
	var up_key := InputEventKey.new()
	up_key.keycode = KEY_E
	up_key.physical_keycode = KEY_E
	up_key.pressed = true
	model_view._input(up_key)
	height_before = model_view.target.y
	model_view._process(0.05)
	check(model_view.target.y > height_before, "RMB+E moves up in world space without selecting Eraser")
	up_key.pressed = false
	model_view._input(up_key)
	var forward_key := InputEventKey.new()
	forward_key.keycode = KEY_W
	forward_key.physical_keycode = KEY_W
	forward_key.pressed = true
	model_view._input(forward_key)
	var forward_start: Vector3 = model_view.target
	var forward_direction: Vector3 = -model_view.camera.basis.z
	model_view._process(0.02)
	check((model_view.target - forward_start).dot(forward_direction) > 0.0, "RMB+W moves camera forward")
	forward_key.pressed = false
	model_view._input(forward_key)
	var backward_key := InputEventKey.new()
	backward_key.keycode = KEY_S
	backward_key.physical_keycode = KEY_S
	backward_key.pressed = true
	model_view._input(backward_key)
	var backward_start: Vector3 = model_view.target
	model_view._process(0.02)
	check((model_view.target - backward_start).dot(forward_direction) < 0.0, "RMB+S moves camera backward without selecting faces")
	backward_key.pressed = false
	model_view._input(backward_key)
	var right_key := InputEventKey.new()
	right_key.keycode = KEY_D
	right_key.physical_keycode = KEY_D
	right_key.pressed = true
	model_view._input(right_key)
	var origin: Vector3 = model_view.target
	model_view._process(0.02)
	var normal_step: float = model_view.target.distance_to(origin)
	model_view.target = origin
	model_view._update_camera()
	var fast_key := InputEventKey.new()
	fast_key.keycode = KEY_SHIFT
	fast_key.physical_keycode = KEY_SHIFT
	fast_key.pressed = true
	model_view._input(fast_key)
	model_view._process(0.02)
	check(normal_step > 0.0 and model_view.target.distance_to(origin) > normal_step * 2.9, "Shift makes RMB+WASD navigation three times faster")
	fast_key.pressed = false
	model_view._input(fast_key)
	orbit_press.pressed = false
	model_view._input_display(orbit_press)
	var stopped_at: Vector3 = model_view.target
	model_view._process(0.05)
	check(model_view.target == stopped_at and model_view._navigation_keys.is_empty(), "Releasing RMB stops camera movement immediately")
	Input.parse_input_event(navigate.duplicate())
	await process_frame
	check(scene.painter.tool == "spray", "A still selects Spray when RMB is not held")
	Input.parse_input_event(release_a.duplicate())
	await process_frame
	scene.get_node("%ToolBar").select(tool_before_navigation)
	model_view.frame_model()
	await process_frame
	var bar = scene.get_node("%MenuBar")
	var undo_button: Button = scene.model_view.get_node("Header/Undo")
	var redo_button: Button = scene.model_view.get_node("Header/Redo")
	check(undo_button.icon != null and redo_button.icon != null and not undo_button.tooltip_text.is_empty() and not redo_button.tooltip_text.is_empty(), "Visible Undo/Redo buttons have icons and shortcuts in tooltips")
	check(undo_button.get_global_rect().end.x <= redo_button.global_position.x and redo_button.get_global_rect().end.x <= scene.model_view.get_node("Header/Frame").global_position.x and undo_button.disabled and redo_button.disabled, "Undo/Redo sit left of Frame and start disabled")
	check(bar.get_node("File").get_popup().item_count == 18, "File menu contains project/import/export/exit and recent project actions")
	check(bar.get_node("Help").get_popup().get_item_text(0).begins_with("About") and bar.get_node("File").get_popup().get_theme_font_size("font_size") >= 14, "Help/About exists and menus use readable text")
	bar.get_node("Help").get_popup().id_pressed.emit(0)
	check(scene.get_node("%About").visible and scene.get_node("%About").dialog_text.contains("Retro Texture Painter"), "About menu opens editable scene dialog")
	scene.get_node("%About").hide()
	check(scene.get_node("%Inspector").global_position.y < scene.model_view.global_position.y and scene.get_node("%Inspector").get_global_rect().end.y > scene.get_node("%PalettePanel").global_position.y, "Inspector spans the height beside the paint workspace")
	check(scene.get_node("%MapSelector").global_position.y > scene.model_view.display.global_position.y and scene.get_node("%MapSelector").get_global_rect().end.x <= scene.model_view.get_global_rect().end.x, "Map selector sits in the model view's lower right corner")
	check(scene.get_node("%ToolOptions/Size/Center/Display").get_theme_font_size("font_size") == 12, "Tool setting controls use compact 12px font")
	var palette_rect: Rect2 = scene.get_node("%PalettePanel").get_global_rect()
	var model_rect: Rect2 = scene.model_view.get_global_rect()
	scene.set_process(false)
	scene.get_node("%JobBar").show()
	await process_frame
	check(scene.get_node("%PalettePanel").get_global_rect().is_equal_approx(palette_rect) and scene.model_view.get_global_rect().is_equal_approx(model_rect), "Job progress appears without moving palette swatches or model view")
	scene.get_node("%JobBar").hide()
	scene.set_process(true)
	var tool: String = scene.painter.tool
	var revision: int = scene.document.revision
	var uv := Vector2(0.2,0.2)
	var point: Vector2 = scene.uv_canvas._origin() + uv * Vector2(scene.document.width,scene.document.height) * scene.uv_canvas.zoom
	var pixel := Vector2i(uv * Vector2(scene.document.width,scene.document.height))
	var before: PackedByteArray = scene.document.compose_tile(Vector2i.ZERO).get_data()
	var expected: Color = scene.document.compose_tile(Vector2i.ZERO).get_pixelv(pixel)
	scene._setting("color", Color.MAGENTA)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.alt_pressed = true
	click.pressed = true
	click.position = point
	scene.uv_canvas._gui_input(click)
	check(scene.painter.color.is_equal_approx(Color.MAGENTA), "Alt press waits to distinguish eyedropper click from opacity drag")
	click.pressed = false
	scene.uv_canvas._gui_input(click)
	check(scene.painter.color.is_equal_approx(expected), "Alt+click picks color through actual UV input handler")
	check(scene.painter.tool == tool and not scene.painter.active, "Quick picker leaves current tool active and does not begin a stroke")
	check(scene.document.revision == revision and scene.document.compose_tile(Vector2i.ZERO).get_data() == before, "Quick picker does not modify pixels or undo history")
	check(Vector2i(scene.model_view.display_material.get_shader_parameter("cursor_pixel")) == pixel and scene.uv_canvas._cursor_hit.uv.is_equal_approx(uv), "Both views target the clicked texel")
	# Mouse events on NumberField distinguish a click from a horizontal scrub.
	var field: NumberField = scene.get_node("%ToolOptions/Size")
	field.set_value(7)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	field._on_input(press)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(10,0)
	field._on_input(move)
	press.pressed = false
	field._on_input(press)
	check(field.value == 12 and scene.painter.brush_size == 12, "Horizontal drag changes numeric control and painter")
	check(not field.editor.visible, "Horizontal drag does not open text editor")
	press.pressed = true
	field._on_input(press)
	press.pressed = false
	field._on_input(press)
	check(field.editor.visible, "Click opens numeric text entry")
	field._commit_text("7")
	check(field.value == 7 and scene.painter.brush_size == 7, "Typed number applies exactly")
	# Modifier drags adjust tool settings without starting a paint stroke.
	var gesture := InputEventMouseButton.new()
	gesture.button_index = MOUSE_BUTTON_LEFT
	gesture.ctrl_pressed = true
	gesture.pressed = true
	gesture.position = point
	scene.uv_canvas._gui_input(gesture)
	var drag := InputEventMouseMotion.new()
	drag.ctrl_pressed = true
	drag.position = point + Vector2(30, 0)
	drag.relative = Vector2(30, 0)
	scene.uv_canvas._gui_input(drag)
	gesture.pressed = false
	gesture.position = drag.position
	scene.uv_canvas._gui_input(gesture)
	check(field.value == 17 and scene.painter.brush_size == 17, "Ctrl+left drag increases brush size in UV view")
	check(scene.document.revision == revision and scene.document.compose_tile(Vector2i.ZERO).get_data() == before, "Ctrl size drag does not paint or create undo history")
	gesture.ctrl_pressed = false
	gesture.alt_pressed = true
	gesture.pressed = true
	gesture.position = point
	scene.uv_canvas._gui_input(gesture)
	drag.ctrl_pressed = false
	drag.alt_pressed = true
	drag.position = point + Vector2(-60, 0)
	drag.relative = Vector2(-60, 0)
	scene.uv_canvas._gui_input(drag)
	gesture.pressed = false
	gesture.position = drag.position
	scene.uv_canvas._gui_input(gesture)
	check(is_equal_approx(scene.painter.opacity, 0.7) and scene.get_node("%ToolOptions/Opacity").value == 70, "Alt+left drag changes opacity in UV view")
	check(scene.painter.color.is_equal_approx(expected) and scene.document.revision == revision, "Alt opacity drag neither picks color nor paints")
	gesture.alt_pressed = false
	gesture.ctrl_pressed = true
	gesture.pressed = true
	gesture.position = scene.model_view.display.size * 0.5
	scene.model_view._input_display(gesture)
	drag.alt_pressed = false
	drag.ctrl_pressed = true
	drag.position = gesture.position + Vector2(15, 0)
	drag.relative = Vector2(15, 0)
	scene.model_view._input_display(drag)
	gesture.pressed = false
	gesture.position = drag.position
	scene.model_view._input_display(gesture)
	check(field.value == 22 and scene.painter.brush_size == 22, "Ctrl+left drag changes brush size in 3D model view")
	check(scene.document.revision == revision and scene.document.compose_tile(Vector2i.ZERO).get_data() == before, "3D gesture skips paint interpolation and preserves texture")
	scene.get_node("%ToolBar").select("clone")
	gesture.pressed = true
	gesture.position = point
	scene.uv_canvas._gui_input(gesture)
	gesture.pressed = false
	scene.uv_canvas._gui_input(gesture)
	check(scene.painter.clone_source == pixel, "Short Ctrl+click still sets clone source")
	scene.get_node("%ToolBar").select("brush")
	field.set_value(7)
	press.pressed = true
	field._on_input(press)
	move.relative = Vector2(10,0)
	move.shift_pressed = true
	field._on_input(move)
	press.pressed = false
	field._on_input(press)
	check(field.value == 8, "Shift drag gives fine numeric adjustment")
	scene.get_node("%ToolBar").select("spray")
	check(scene.painter.tool == "spray" and scene.get_node("%SprayOptions").visible, "Spray tool reveals its scene-based controls")
	await process_frame
	check(scene.get_node("%SprayOptions/Distance").global_position.y > scene.get_node("%SprayOptions/Opacity").global_position.y and scene.get_node("%SprayOptions/Distance").get_global_rect().end.x < scene.get_node("%Inspector").global_position.x, "Spray controls occupy two fully visible rows")
	gesture.ctrl_pressed = false
	gesture.alt_pressed = true
	gesture.pressed = true
	gesture.position = point
	scene.uv_canvas._gui_input(gesture)
	drag.ctrl_pressed = false
	drag.alt_pressed = true
	drag.position = point - Vector2(40, 0)
	drag.relative = Vector2(-40, 0)
	scene.uv_canvas._gui_input(drag)
	gesture.pressed = false
	gesture.position = drag.position
	scene.uv_canvas._gui_input(gesture)
	check(is_equal_approx(scene.painter.opacity, 0.5) and scene.get_node("%SprayOptions/Opacity").value == 50, "Alt drag controls spray opacity and synchronizes both fields")
	scene.get_node("%SprayOptions/Distance").set_value(200)
	check(scene.painter.spray_distance == 2.0 and scene.painter.footprint_size() == 16, "Spray distance updates the actual pixel footprint")
	scene.get_node("%ToolBar").select("gradient")
	var length_before: int = scene.gradient_length
	var gradient_size_before: int = scene.painter.brush_size
	gesture.alt_pressed = false
	gesture.ctrl_pressed = true
	gesture.pressed = true
	gesture.position = point
	scene.uv_canvas._gui_input(gesture)
	drag.alt_pressed = false
	drag.ctrl_pressed = true
	drag.position = point + Vector2(21, 0)
	drag.relative = Vector2(21, 0)
	scene.uv_canvas._gui_input(drag)
	gesture.pressed = false
	gesture.position = drag.position
	scene.uv_canvas._gui_input(gesture)
	check(scene.painter.brush_size == gradient_size_before + 7 and scene.get_node("%ToolOptions/Size").value == scene.painter.brush_size and scene.gradient_length == length_before, "Ctrl drag adjusts gradient Size without changing Length")
	scene.get_node("%ToolOptions/Size").set_value(12)
	scene._surface_input("begin", {"uv": Vector2(0.25, 0.25), "face": -1}, 0, false)
	scene._surface_input("move", {"uv": Vector2(0.25, 0.50), "face": -1}, 0, false)
	check(scene.uv_canvas.shape_preview_kind == "line" and scene.uv_canvas.shape_preview_size == 12 and int(scene.model_view.display_material.get_shader_parameter("shape_preview_mode")) == 1, "Gradient drag previews its configured Size in both views")
	scene.get_node("%ToolBar").select("brush")
	check(scene.uv_canvas.shape_preview_kind.is_empty(), "Switching tools clears the gradient guide")
	var file_menu: PopupMenu = bar.get_node("File").get_popup()
	file_menu.id_pressed.emit(14)
	check(scene.get_node("%Discard").visible and scene._pending_discard == "Quit", "Exit menu protects unsaved project")
	scene.get_node("%Discard").hide()
	scene.document.saved_revision = scene.document.revision
	file_menu.id_pressed.emit(0)
	check(scene.get_node("%NewDialog").visible, "New project menu opens dialog")
	scene.get_node("%NewDialog/Form/Dimensions/Width").set_value(64)
	scene.get_node("%NewDialog/Form/Dimensions/Height").set_value(128)
	scene.get_node("%NewDialog").hide()
	scene._new_from_dialog()
	await ready_document(scene)
	check(scene.document.width == 64 and scene.document.height == 128, "New project accepts rectangular texture dimensions")
	check(scene.document.layers[0].tiles.is_empty(), "New project creates a blank texture")
	scene._start_new(16,16,"Minimum texture")
	await ready_document(scene)
	check(scene.document.width == 16 and scene.document.geometry.has_uv, "Minimum 16px project gets a valid UV layout")
	check(scene.theme.default_font.get_font_name().contains("Verdana"), "UI resolves installed Verdana font")
	# Palette clicks choose independent slots; same-color and eyedropper states stay clear.
	var palette = scene.get_node("%PalettePanel")
	var primary = palette.get_node("Scroll/Grid").get_child(3)
	var secondary = palette.get_node("Scroll/Grid").get_child(6)
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	primary._gui_input(press)
	press.button_index = MOUSE_BUTTON_RIGHT
	secondary._gui_input(press)
	check(scene.painter.color == scene.document.palette[3] and scene.color_b == scene.document.palette[6], "Palette left click selects primary and right click secondary")
	check(primary.text == "1" and secondary.text == "2", "Palette labels identify both selections")
	primary._gui_input(press)
	check(primary.text == "1 2", "Same swatch can be both current colors")
	scene._setting("color", Color("aabbcc"))
	check(palette.primary_index == -1 and palette.get_node("Header/Primary").text == "1", "Eyedropper color outside palette keeps primary readout")
	var toolbar = scene.get_node("%ToolBar")
	toolbar.get_node("Compact").button_pressed = true
	check(toolbar.get_node("Tools/Brush").text.is_empty() and not toolbar.get_node("Tools/Brush").tooltip_text.is_empty() and toolbar.get_node("Tools/Brush").icon != null, "Compact toolbar keeps icon and tooltip")
	toolbar.get_node("Compact").button_pressed = false
	check(toolbar.get_node("Tools/Brush").text == "Brush", "Expanded toolbar restores text")
	var old_uvs: PackedVector2Array = scene.document.geometry.uvs.duplicate()
	scene.get_node("%UVView").button_pressed = false
	await process_frame
	check(not scene.get_node("%UVPane").visible, "UV toggle hides entire pane")
	scene._action("ToggleUV")
	check(scene.get_node("%UVPane").visible and scene.document.geometry.uvs == old_uvs, "UV toggle restores pane without changing coordinates")
	scene.selection_mode = 1
	scene._select_surface({"face":0}, 0)
	await ready_document(scene)
	var original: PackedInt32Array = scene.selected_faces.duplicate()
	var key := InputEventKey.new()
	key.pressed = true
	key.ctrl_pressed = true
	key.keycode = KEY_PERIOD
	scene._unhandled_key_input(key)
	await ready_document(scene)
	check(scene.selected_faces.size() > original.size(), "Ctrl+. expands selection via key handler")
	var first_ring: PackedInt32Array = scene.selected_faces.duplicate()
	scene._unhandled_key_input(key)
	await ready_document(scene)
	key.keycode = KEY_COMMA
	scene._unhandled_key_input(key)
	await ready_document(scene)
	check(scene.selected_faces == first_ring, "Ctrl+, restores previous selection ring")
	scene._unhandled_key_input(key)
	await ready_document(scene)
	scene._unhandled_key_input(key)
	check(scene.selected_faces == original, "Shrink stops at original selection")
	scene._resize_selection(true)
	scene.jobs.progress.cancel()
	await ready_document(scene)
	check(scene.selected_faces == original and scene.uv_canvas.selected_faces == original, "Cancelling selection growth restores original selection and visible mask")
	scene._clear_selection()
	# Bucket input uses flood fill without selection, including UV clicks.
	scene.document.layers[0].tile_at(Vector2i.ZERO).fill_rect(Rect2i(8,0,1,16),Color.BLACK)
	scene.get_node("%ToolBar").select("fill")
	scene._setting("color", Color.RED)
	scene._surface_input("begin", {"uv":Vector2(0.1,0.1),"face":-1}, 0, false)
	await ready_document(scene)
	var painted: Image = scene.document.selected_layer().tiles[Vector2i.ZERO]
	check(painted.get_pixel(1,1) == Color.RED and painted.get_pixel(10,1).a == 0, "Bucket click fills connected color, not entire model")
	check(not undo_button.disabled and redo_button.disabled, "Undo icon enables after a paint action")
	undo_button.pressed.emit()
	check(not redo_button.disabled and not scene.document.selected_layer().tiles.has(Vector2i.ZERO), "Undo icon reverses the paint action and enables Redo")
	redo_button.pressed.emit()
	check(scene.document.selected_layer().tiles[Vector2i.ZERO].get_pixel(1,1) == Color.RED and redo_button.disabled, "Redo icon restores the paint action")
	var old_palette: PackedColorArray = scene.document.palette.duplicate()
	scene._job_completed("palette", {"palette":PackedColorArray([Color.RED,Color.BLUE]),"name":"Two colors"})
	scene._action("Undo")
	check(scene.document.palette == old_palette and palette.colors == old_palette, "Palette import undo refreshes document and swatches")
	scene._action("Redo")
	check(scene.document.palette.size() == 2 and palette.colors.size() == 2, "Palette import redo restores new swatches")
	# Stamp tab opens with the tool, and a dragged image region drives the actual brush.
	var stamp_image := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	stamp_image.fill(Color.RED)
	stamp_image.fill_rect(Rect2i(4,0,4,4), Color.BLUE)
	var stamp_path := ProjectSettings.globalize_path("res://test_output/ui_stamp.png")
	stamp_image.save_png(stamp_path)
	scene._file_action = "stencil"
	scene._file_selected(stamp_path)
	check(scene.painter.tool == "stencil" and scene.get_node("%Inspector").current_tab == 4 and scene.document.stamp_region == Rect2i(0,0,8,4), "Loading a stamp opens its inspector and defaults to full image")
	var stamp_panel = scene.get_node("%StampPanel")
	var crop = stamp_panel.get_node("Preview")
	var bounds: Rect2 = crop._image_rect()
	var crop_press := InputEventMouseButton.new()
	crop_press.button_index = MOUSE_BUTTON_LEFT
	crop_press.pressed = true
	crop_press.position = bounds.position + Vector2(4.5 / 8.0, 0.5 / 4.0) * bounds.size
	crop._gui_input(crop_press)
	var crop_move := InputEventMouseMotion.new()
	crop_move.position = bounds.position + Vector2(7.5 / 8.0, 3.5 / 4.0) * bounds.size
	crop._gui_input(crop_move)
	crop_press.pressed = false
	crop_press.position = crop_move.position
	crop._gui_input(crop_press)
	check(scene.document.stamp_region == Rect2i(4,0,4,4) and stamp_panel.get_node("Fields/W").value == 4, "Dragging on stamp preview selects source pixels precisely")
	check(scene.painter.stencil_region == scene.document.stamp_region and stamp_panel.get_node("SelectedPreview").texture != null, "Crop reaches paint engine and selected-area preview")
	scene._setting("brush_size", 8)
	scene._setting("opacity", 0.5)
	var before_stamp: PackedByteArray = scene.document.selected_layer().tiles[Vector2i.ZERO].get_data()
	var stamp_hit := {"uv": Vector2(0.5,0.5), "face": -1}
	scene._surface_input("begin", stamp_hit, 0, false)
	scene._surface_input("end", stamp_hit, 0, false)
	while scene.painter.active:
		await process_frame
	var stamped: Image = scene.document.selected_layer().tiles[Vector2i.ZERO]
	check(stamped.get_pixel(8,8).b > 0.9 and stamped.get_pixel(8,8).r < 0.1 and is_equal_approx(stamped.get_pixel(8,8).a, 128.0 / 255.0), "Stamp paints only cropped blue pixels at selected opacity")
	scene._action("Undo")
	check(scene.document.selected_layer().tiles[Vector2i.ZERO].get_data() == before_stamp, "Undo removes the cropped stamp stroke")
	scene._action("Undo")
	check(scene.document.stamp_region == Rect2i(0,0,8,4) and stamp_panel.region == scene.document.stamp_region, "Undo restores previous stamp crop in inspector")
	var zoom_anchor: Vector2 = crop._image_rect().get_center()
	var anchor_pixel: Vector2i = crop._pixel_at(zoom_anchor)
	var original_extent: Vector2 = crop._image_rect().size
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = zoom_anchor
	crop._gui_input(wheel)
	check(crop._image_rect().size.x > original_extent.x and crop._pixel_at(zoom_anchor) == anchor_pixel, "Stamp wheel zooms around the cursor without shifting its source pixel")
	var pan_before: Vector2 = crop._image_rect().position
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	middle.position = zoom_anchor
	crop._gui_input(middle)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.position = zoom_anchor + Vector2(16,-8)
	pan_motion.relative = Vector2(16,-8)
	crop._gui_input(pan_motion)
	middle.pressed = false
	middle.position = pan_motion.position
	crop._gui_input(middle)
	check(crop._image_rect().position.is_equal_approx(pan_before + pan_motion.relative) and not crop._panning, "Middle drag pans the zoomed stamp image")
	var zoom_bounds: Rect2 = crop._image_rect()
	crop_press.pressed = true
	crop_press.position = zoom_bounds.position + Vector2(3.5 / 8.0, 0.5 / 4.0) * zoom_bounds.size
	crop._gui_input(crop_press)
	crop_move.position = zoom_bounds.position + Vector2(5.5 / 8.0, 2.5 / 4.0) * zoom_bounds.size
	crop._gui_input(crop_move)
	crop_press.pressed = false
	crop_press.position = crop_move.position
	crop._gui_input(crop_press)
	check(scene.document.stamp_region == Rect2i(3,0,3,3), "Left drag keeps pixel-accurate crop coordinates after zoom and pan")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	crop._gui_input(wheel)
	check(crop._image_rect().size.is_equal_approx(original_extent), "Wheel down returns the stamp view to fit scale")
	# The Effects button bakes a concave corner into a regular editable Albedo layer.
	scene._start_new(64,64,"AO scene")
	await ready_document(scene)
	var ao_model := ModelGeometry.new()
	ao_model.positions = PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(0,0,1),Vector3(0,0,0),Vector3(0,0,1),Vector3(0,1,0)])
	ao_model.normals = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.RIGHT,Vector3.RIGHT,Vector3.RIGHT])
	ao_model.uvs = PackedVector2Array([Vector2(0.1,0.1),Vector2(0.4,0.1),Vector2(0.1,0.4),Vector2(0.6,0.1),Vector2(0.9,0.1),Vector2(0.6,0.4)])
	ao_model.materials = PackedInt32Array([0,0])
	ao_model.objects = PackedInt32Array([0,0])
	ao_model.build_cache()
	scene.document.geometry = ao_model
	scene.model_view.set_geometry(ao_model)
	var ao_layer_count: int = scene.document.layers.size()
	scene.get_node("%Effects/AOStrength").set_value(100)
	scene.get_node("%Effects/AORadius").set_value(8)
	scene.get_node("%Effects/AOGenerate").pressed.emit()
	await ready_document(scene)
	check(scene.document.layers.size() == ao_layer_count + 1 and scene.document.selected_layer().title == "Cavity AO" and scene.document.selected_layer().channel == "albedo", "Effects button adds baked AO as editable Albedo layer")
	check(scene.document.compose_tile(Vector2i.ZERO).get_pixel(8,15).r < scene.document.compose_tile(Vector2i.ZERO).get_pixel(16,15).r, "Baked AO visibly darkens the inner corner")
	scene._action("Undo")
	check(scene.document.layers.size() == ao_layer_count, "AO bake undoes as one layer action")
	# Inspector sections start collapsed, and geometry adjustments show a temporary preview.
	var effects = scene.get_node("%Effects")
	check(not effects.get_node("AOSection").button_pressed and not effects.get_node("AOStrength").visible,"Effects start collapsed")
	effects.get_node("AOSection").button_pressed = true
	check(effects.get_node("AOStrength").visible and effects.open_sections().AOSection,"An effect section expands with saved state")
	var preview_revision: int = scene.document.revision
	effects.get_node("AOStrength").set_value(80)
	effects.get_node("AOStrength").value_committed.emit(80)
	await ready_document(scene)
	check(scene._geometry_preview_layer != null and scene.document.layers.size() == ao_layer_count+1 and scene.document.revision == preview_revision,"AO slider release previews without writing history")
	effects.get_node("AOGenerate").pressed.emit()
	check(scene._geometry_preview_layer == null and scene.document.revision > preview_revision and scene.document.layers.size() == ao_layer_count+1,"Bake commits the visible AO preview once")
	scene._action("Undo")
	# The eye and padlock belong to each row; no duplicate controls occupy the properties area.
	var layers = scene.get_node("%Layers")
	var row = layers.rows[scene.document.selected_layer().id]
	check(row.get_node("Eye") != null and row.get_node("Lock") != null and layers.get_node_or_null("Visibility") == null and layers.get_node_or_null("Locked") == null,"Each layer row contains eye and lock icons")
	row.get_node("Lock").button_pressed = true
	row.get_node("Lock").pressed.emit()
	check(scene.document.selected_layer().locked,"Row padlock locks painting on that layer")
	scene._action("Undo")
	check(not scene.document.selected_layer().locked,"Padlock change is undoable")
	# Normal generation reads Height data and switches to its new editable map.
	scene._select_channel("height")
	scene.document.selected_layer().tile_at(Vector2i.ZERO).set_pixel(10,10,Color.WHITE)
	effects.get_node("NormalGenerate").pressed.emit()
	await ready_document(scene)
	check(scene.document.current_channel() == "normal" and scene.document.selected_layer().tiles.size() > 0,"Generate Normal creates a painted Normal layer from Height")
	scene._action("Undo")
	scene._select_channel("albedo")
	var before_reset: Color = scene.document.compose_tile(Vector2i.ZERO).get_pixel(30,30)
	scene._action("ResetMap")
	check(scene.document.compose_tile(Vector2i.ZERO).get_pixel(30,30).a == 0.0,"Reset current map erases all its layer paint")
	scene._action("Undo")
	check(scene.document.compose_tile(Vector2i.ZERO).get_pixel(30,30).is_equal_approx(before_reset),"Undo restores the complete map")
	# Blur preview replaces only the selected layer's display and applies in one Undo step.
	scene._start_new(64,64,"Blur scene")
	await ready_document(scene)
	scene.document.selected_layer().tile_at(Vector2i.ZERO).set_pixel(30,30,Color.WHITE)
	preview_revision = scene.document.revision
	effects.get_node("BlurRadius").value_committed.emit(3)
	await ready_document(scene)
	check(scene._blur_preview_layer_id == scene.document.selected_layer().id and scene.document.revision == preview_revision and scene.document.selected_layer().tiles[Vector2i.ZERO].get_pixel(29,30).a > 0.0,"Blur slider release previews the whole layer without history")
	effects.get_node("BlurApply").pressed.emit()
	check(scene._blur_preview_layer_id.is_empty() and scene.document.revision > preview_revision,"Apply commits blur as one action")
	scene._action("Undo")
	check(scene.document.selected_layer().tiles[Vector2i.ZERO].get_pixel(29,30).a == 0.0 and scene.document.selected_layer().tiles[Vector2i.ZERO].get_pixel(30,30).a == 1.0,"Undo restores sharp layer paint")
	var report := {"checks": checks,"failures": failures}
	var output := FileAccess.open("res://test_output/ui_results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("UI CHECKS: %d passed / %d; failures: %d" % [checks-failures,checks,failures])
	scene.document.saved_revision = scene.document.revision
	quit(1 if failures else 0)
