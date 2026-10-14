extends Control
## Composition root: child signals come up; document and view calls go down.
const PBR_PREVIEW = preload("res://paint/pbr_preview.gd")
var document: PaintDocument
var history := PaintHistory.new()
var selected_faces := PackedInt32Array()
var _selection_steps: Array[PackedInt32Array] = []
var _selection_before := PackedInt32Array()
var _steps_before: Array[PackedInt32Array] = []
var gradient_length := 7
var fill_tolerance := 0.0
var fill_contiguous := true
var symmetry_axes := 0
var color_b := Color.BLACK
var selection_mode := 0
var _gradient_start: Dictionary = {}
var _gradient_end: Dictionary = {}
var _file_action := ""
var _pending_discard := ""
var _pending_uv: Dictionary = {}
var _uv_preview_before: Dictionary = {}
var _effect_before: Dictionary = {}
var _pattern_before: Dictionary = {}
var _saved_stamp_view: Dictionary = {}
var _saved_stamp_view_path := ""
var _blur_preview_layer_id := ""
var _blur_original_tiles: Dictionary = {}
var _blur_changed: Array[Vector2i] = []
var _blur_job_layer_id := ""
var _blur_wanted_radius := 0
var _blur_apply_when_ready := false
var _geometry_preview_layer: PaintLayer
var _geometry_preview_kind := ""
var _geometry_preview_signature: Array = []
var _geometry_requested_kind := ""
var _geometry_requested_signature: Array = []
var _geometry_job_signature: Array = []
var _last_saved_autosave_revision := -1
var _perf_clock := 0.0
var _pbr_preview_revision := -1
var _recovery_path := "user://recovery.rtpaint"
var _cursor_hit: Dictionary = {}
var _cursor_from_model := false
var _gesture_mode := ""
var _gesture_hit: Dictionary = {}
var _gesture_modifiers := 0
var _gesture_from_model := false
var _gesture_initial := 0.0
var _gesture_x := 0.0
var _gesture_travel := 0.0
var _gesture_dragging := false
var _replaying_gesture_click := false
var _spray_preview_texture: ImageTexture
var _spray_mirror_texture: ImageTexture
var _mode_before_fullscreen := Window.MODE_WINDOWED
var _stamp_source_texture: ImageTexture
var _stamp_source_image: Image
var _stamp_rotation_editing := false
var _stamp_rotation_before := 0.0
var settings_enabled := true
var settings_path := "user://painter.cfg"
var _preferences := PainterConfig.new()
var _restoring_preferences := false
var _last_project_path := ""
var _reopen_last := true
@onready var painter: PaintEngine = %PaintEngine
@onready var tiles: TileDisplay = %TileDisplay
@onready var jobs: BackgroundJob = %Jobs
@onready var model_view: ModelView = %ModelView
@onready var uv_canvas: UVCanvas = %UVCanvas

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_window().min_size = Vector2i(1280, 760)
	%ToolBar.tool_selected.connect(_select_tool)
	%ToolBar.compact_changed.connect(func(compact: bool): %ToolScroll.custom_minimum_size.x = 96 if compact else 138; _queue_preferences_save())
	%ToolOptions.setting_changed.connect(_setting)
	%SprayOptions.setting_changed.connect(_setting)
	%MenuBar.action_requested.connect(_action)
	%PalettePanel.color_selected.connect(func(c: Color, slot: int): _setting("color" if slot == 1 else "color_b", c))
	%PalettePanel.palette_change_requested.connect(_palette_change)
	%PalettePanel.load_requested.connect(func(): _file_dialog("palette"))
	%Layers.action_requested.connect(_layer_action)
	%Effects.effect_changed.connect(_effect_changed)
	%Effects.section_changed.connect(_queue_preferences_save)
	%UV.action_requested.connect(_uv_action)
	%Pattern.load_requested.connect(func(): _file_dialog("pattern"))
	%Pattern.apply_requested.connect(func(): _apply_pattern(selected_faces))
	%Pattern.settings_changed.connect(_pattern_settings_changed)
	%Pattern.transform_committed.connect(func():
		if document != null and document.selected_layer().pattern_image != null: _apply_pattern(document.selected_layer().pattern_faces))
	%StampPanel.load_requested.connect(func(): _file_dialog("stencil"))
	%StampPanel.region_changed.connect(_stamp_region_changed)
	%StampPanel.rotation_changed.connect(func(angle: float): _stamp_rotation_input(angle,false))
	%StampPanel.rotation_committed.connect(func(angle: float): _stamp_rotation_input(angle,true))
	%StampPanel.navigation_changed.connect(_queue_preferences_save)
	%Inspector.tab_changed.connect(func(_tab: int): _queue_preferences_save())
	model_view.surface_event.connect(_surface_input.bind(true))
	model_view.history_requested.connect(_action)
	model_view.background_color_changed.connect(func(_color: Color): _queue_preferences_save())
	uv_canvas.surface_event.connect(_surface_input.bind(false))
	model_view.gesture_motion.connect(_gesture_motion)
	model_view.stamp_rotation_event.connect(_stamp_rotation_drag)
	uv_canvas.gesture_motion.connect(_gesture_motion)
	model_view.hovered.connect(_hover.bind(true))
	uv_canvas.hovered.connect(_hover.bind(false))
	painter.tiles_changed.connect(tiles.mark)
	painter.stroke_committed.connect(_refresh_metadata)
	painter.stroke_committed.connect(_refresh_cursor)
	painter.stroke_committed.connect(_clear_shape_preview)
	painter.preview_changed.connect(_refresh_cursor)
	%MapSelector.item_selected.connect(func(index: int): _select_channel(PaintChannels.IDS[index]))
	%MainDock.drag_ended.connect(_save_layout)
	%MainSplit.drag_ended.connect(_save_layout)
	%PreferencesSave.timeout.connect(_save_preferences)
	jobs.completed.connect(_job_completed)
	%FitUV.pressed.connect(uv_canvas.fit)
	%UVView.toggled.connect(func(on: bool): %UVPane.visible = on; %UVFrame.visible = on; _queue_preferences_save())
	%WireUV.toggled.connect(func(on: bool): uv_canvas.show_uv = on; uv_canvas.queue_redraw(); _queue_preferences_save())
	for button in ["Wires", "Ortho", "Light"]:
		model_view.get_node("Header/"+button).toggled.connect(func(_on: bool): _queue_preferences_save())
	%Layers.get_node("SelectionMode").item_selected.connect(func(i: int): selection_mode = i; _queue_preferences_save())
	%Layers.get_node("ClearSelection").pressed.connect(_clear_selection)
	%Effects.get_node("Edges").pressed.connect(_edges)
	%Effects.get_node("AOGenerate").pressed.connect(_ambient_occlusion)
	%Effects.get_node("EdgeMask").pressed.connect(_generate_geometry_mask.bind("edges"))
	%Effects.get_node("AOMask").pressed.connect(_generate_geometry_mask.bind("ao"))
	%Effects.get_node("NormalGenerate").pressed.connect(_generate_normal_map)
	%Effects.get_node("BlurRadius").value_changed.connect(func(_value: float): _cancel_blur_preview())
	%Effects.get_node("BlurRadius").value_committed.connect(func(_value: float): _preview_layer_blur())
	%Effects.get_node("BlurPreview").pressed.connect(_preview_layer_blur)
	%Effects.get_node("BlurApply").pressed.connect(func(): _blur_apply_when_ready = true; _preview_layer_blur())
	%Effects.get_node("BlurCancel").pressed.connect(_cancel_blur_preview)
	for field in ["EdgeWidth","AOStrength","AORadius","AODepth"]:
		%Effects.get_node(field).value_changed.connect(func(_value: float): _geometry_requested_kind = ""; _cancel_geometry_preview())
		%Effects.get_node(field).value_committed.connect(func(_value: float): _preview_geometry_effect("edges" if field == "EdgeWidth" else "ao"))
	%Effects.get_node("AOFalloff").item_selected.connect(func(_index: int): _preview_geometry_effect("ao"))
	for field in ["EdgeWidth", "AOStrength", "AORadius", "AODepth", "NormalStrength", "BlurRadius"]:
		%Effects.get_node(field).value_changed.connect(func(_value: float): _queue_preferences_save())
	%Effects.get_node("AOFalloff").item_selected.connect(func(_index: int): _queue_preferences_save())
	for field in ["Angle", "Padding", "MoveStep", "Scale"]:
		%UV.get_node(field).value_changed.connect(func(_value: float): _queue_preferences_save())
	%FileDialog.file_selected.connect(_file_selected)
	%Discard.confirmed.connect(func(): _perform_guarded(_pending_discard))
	%UVConfirm.confirmed.connect(_generate_uv)
	%UVApply.confirmed.connect(_commit_uv_preview)
	%UVApply.canceled.connect(_cancel_uv_preview)
	%ResizeDialog.confirmed.connect(_resize_texture)
	%ColorReplaceDialog.confirmed.connect(_replace_color)
	%NewDialog.get_node("Form/Resolution").selected = 2
	%NewDialog.confirmed.connect(_new_from_dialog)
	%CancelJob.pressed.connect(func(): jobs.progress.cancel(); _status("Cancelling at the next safe boundary…"))
	%Autosave.timeout.connect(_autosave)
	%EffectCommit.timeout.connect(_commit_effects)
	%ToolOptions.set_tool("brush")
	%NewDialog.get_node("Form/Resolution").item_selected.connect(func(i: int):
		var resolution := 32 * int(pow(2, i))
		%NewDialog.get_node("Form/Dimensions/Width").set_value(resolution, false)
		%NewDialog.get_node("Form/Dimensions/Height").set_value(resolution, false))
	if settings_enabled:
		_preferences.path = settings_path
		_preferences.load_settings()
		_restore_preferences()
	_restore_layout.call_deferred()
	%MenuBar.refresh(false,false,FileAccess.file_exists(_recovery_path),_last_project_path,_reopen_last,"Albedo")
	if _reopen_last and not _last_project_path.is_empty() and FileAccess.file_exists(_last_project_path):
		jobs.start("open_last", ProjectIO.load_project.bind(_last_project_path))
		_status("Opening last project…")
	else:
		if not _last_project_path.is_empty() and not FileAccess.file_exists(_last_project_path):
			_last_project_path = ""
			_queue_preferences_save()
		_start_new(128, 128, "Field crate", true)

func _start_new(width: int, height: int, title: String, sample := false) -> void:
	jobs.start("new", _create_document.bind(width, height, title, sample))
	_status("Preparing project…")

static func _create_document(progress: BackgroundJob.JobProgress, width: int, height: int, title: String, sample: bool) -> Dictionary:
	progress.report(0.1, "Preparing sample geometry…")
	var doc := PaintDocument.new()
	doc.initialize(width, height, Color("303d50"))
	doc.title = title
	var model := ModelGeometry.demo() if sample else ModelGeometry.new()
	if not sample:
		model.label = "Cube"
		model._box(Vector3.ZERO, Vector3.ONE * 2.0, 0)
		model.build_cache()
	var result := UVUnwrapper.unwrap(model, width, height, 45.0, 1)
	if result.has("error"):
		return result
	doc.geometry = result.geometry
	progress.report(0.7, "Painting sample crate…")
	var colors := [Color("526574"), Color("eea765"), Color("253542"), Color("52cbb1")]
	var base := doc.layers[0]
	for f in doc.geometry.face_count():
		if not sample:
			break
		var tri := PackedVector2Array()
		for c in 3:
			tri.append(doc.geometry.uvs[f * 3 + c] * Vector2(width, height))
		UVRaster.triangle(base.tiles, tri, Vector2i(width, height), colors[doc.geometry.materials[f] % colors.size()])
	doc.saved_revision = -1
	return {"document": doc}

func _set_document(doc: PaintDocument) -> void:
	_cancel_blur_preview()
	_cancel_geometry_preview()
	_gesture_mode = ""
	_effect_before.clear()
	_pattern_before.clear()
	%EffectCommit.stop()
	document = doc
	history.clear()
	selected_faces.clear()
	_selection_steps.clear()
	_gradient_start.clear()
	_clear_shape_preview()
	painter.setup(doc, history)
	painter.color = doc.primary_color
	color_b = doc.secondary_color
	tiles.setup(doc)
	uv_canvas.setup(doc)
	if doc.geometry != null:
		model_view.set_geometry(doc.geometry)
	_pbr_preview_revision = -1
	_apply_materials()
	%PalettePanel.refresh(doc.palette, doc.palette_name)
	_sync_colors()
	%Pattern.set_source(doc.pattern_image, "Project texture")
	%Pattern.restore_settings(doc.pattern_settings)
	_sync_pattern_inspector()
	%UV.get_node("ExportPadding").set_value(doc.uv_export_padding,false)
	%StampPanel.set_source(doc.stamp_image, doc.stamp_name, doc.stamp_region)
	%StampPanel.set_stamp_rotation(doc.stamp_rotation)
	if not doc.path.is_empty() and doc.path == _saved_stamp_view_path:
		%StampPanel.restore_view_state(_saved_stamp_view)
	_refresh_metadata()
	%Effects.refresh(doc)
	_hover({}, false)
	_status("Ready · choose a color and paint. S selects surfaces; Shift adds to selection.")
	_last_saved_autosave_revision = -1

func _document_state() -> Dictionary:
	return {"width":document.width,"height":document.height,"geometry":document.geometry,
		"layers":document.layers.duplicate(),"active_layer":document.active_layer,"editing_mask":document.editing_mask}

func _install_document_state(state: Dictionary) -> void:
	document.width = int(state.width)
	document.height = int(state.height)
	document.geometry = state.geometry
	document.layers.assign(state.layers)
	document.active_layer = clampi(int(state.active_layer),0,document.layers.size()-1)
	document.editing_mask = bool(state.editing_mask)
	selected_faces.clear()
	_selection_steps.clear()
	painter.setup(document,history)
	tiles.setup(document)
	uv_canvas.setup(document)
	model_view.set_geometry(document.geometry)
	_apply_materials()
	_pbr_preview_revision = -1
	_refresh_metadata()

func _commit_uv_preview() -> void:
	if _uv_preview_before.is_empty(): return
	history.push(document,{"kind":"document","label":"UV layout and paint transfer","before":_uv_preview_before,"after":_document_state()})
	_uv_preview_before.clear()
	_refresh_metadata()
	_status("UV layout and transferred paint applied · Undo restores both")

func _cancel_uv_preview() -> void:
	if _uv_preview_before.is_empty(): return
	_install_document_state(_uv_preview_before)
	_uv_preview_before.clear()
	_status("UV preview cancelled · original layout and paint restored")

func _resize_texture() -> void:
	if document == null or jobs.busy() or painter.active: return
	var width := int(%ResizeDialog.get_node("Form/Width").value)
	var height := int(%ResizeDialog.get_node("Form/Height").value)
	if width == document.width and height == document.height: return
	jobs.start("resize",ProjectTransforms.resize.bind(document.read_copy(),width,height))

func _replace_color() -> void:
	if document == null or jobs.busy() or painter.active: return
	jobs.start("replace_color",ProjectTransforms.replace_color.bind(document.read_copy(),painter.color,color_b,
		float(%ColorReplaceDialog.get_node("Form/Tolerance").value)/100.0))

func _apply_materials() -> void:
	if document == null:
		return
	tiles.apply_to(model_view.display_material)
	tiles.apply_to(uv_canvas.display_material)
	model_view.set_channel(document.current_channel())

func _refresh_metadata() -> void:
	if document == null:
		return
	var dirty := document.revision != document.saved_revision
	%Title.text = "  %s%s   /   %d × %d" % [document.title, " *" if dirty else "", document.width, document.height]
	get_window().title = "%s%s — Retro Texture Painter" % [document.title, " *" if dirty else ""]
	%Layers.refresh(document)
	%MapSelector.select(PaintChannels.IDS.find(document.current_channel()))
	%MapHint.text = "Editing " + PaintChannels.label(document.current_channel()) + (" · grayscale data" if PaintChannels.scalar(document.current_channel()) else " · RGB, OpenGL +Y" if document.current_channel() == "normal" else "")
	%Effects.set_channel(document.current_channel())
	var can_undo := history.cursor > 0 and not jobs.busy() and not painter.active
	var can_redo := history.cursor < history.actions.size() and not jobs.busy() and not painter.active
	model_view.set_history_available(can_undo, can_redo)
	%MenuBar.refresh(can_undo, can_redo, FileAccess.file_exists(_recovery_path),_last_project_path,_reopen_last,PaintChannels.label(document.current_channel()))

func _select_tool(tool: String) -> void:
	_cancel_blur_preview()
	_cancel_geometry_preview()
	if painter.active:
		%ToolBar.select(painter.tool, false)
		_status("Finish the current stroke before changing tools.")
		return
	painter.tool = tool
	model_view.set_stamp_rotation_mode(tool == "stencil")
	model_view.interpolate_strokes = tool not in ["line", "rect", "ellipse", "gradient", "select", "fill", "texture", "picker"]
	_gradient_start.clear()
	_gradient_end.clear()
	_clear_shape_preview()
	%ToolOptions.set_tool(tool)
	%SprayOptions.visible = tool == "spray"
	if tool == "select": model_view.get_node("Header/Wires").button_pressed = true
	if tool == "stencil": %Inspector.current_tab = 4
	_refresh_cursor()
	_queue_preferences_save()
	_status({"gradient": "Gradient: click and drag the direction. Length stays exactly %d px. UV seams use unfolded surface distance." % gradient_length,
		"select": "Click a surface. Shift adds; Ctrl subtracts. Ctrl+. grows; Ctrl+, shrinks. Esc clears.",
		"fill": "Fill selected faces, or the connected color region under the cursor.",
		"texture": "Select faces, load a texture in Pattern, then click to fill. Set its rotation before filling.",
		"clone": "Ctrl+click sets the source on the active layer. Paint to copy it; the source stays frozen during the stroke.",
		"smudge": "Smudge: drag existing paint · Opacity sets strength · up to 64 px · reads current map",
		"blur": "Blur: smooth local texels · Opacity sets strength · up to 64 px · reads current map",
		"spray": "Preview shows the next burst · Opacity caps the stroke · Flow sets buildup · Alt+click picks a color",
		"stencil": "Stamp: load and crop an image, then hover to preview. Alt+right-drag rotates; right-drag orbits the camera."}.get(tool, tool.capitalize() + " · draw in either view"))

func _setting(key: String, value: Variant) -> void:
	if key == "color": _cancel_geometry_preview()
	if key == "gradient_length":
		gradient_length = value
	elif key == "fill_tolerance":
		fill_tolerance = value
	elif key == "fill_contiguous":
		fill_contiguous = value
	elif key == "symmetry_axes":
		symmetry_axes = int(value)
	elif key == "color_b":
		color_b = value
	else:
		painter.set(key, value)
	if key in ["color", "color_b"]:
		_sync_colors()
	if key == "opacity":
		%ToolOptions.get_node("Opacity").set_value(value*100,false)
		%SprayOptions.get_node("Opacity").set_value(value*100,false)
	_refresh_cursor()
	if key not in ["color", "color_b"]: _queue_preferences_save()

func _sync_colors() -> void:
	if document != null:
		document.primary_color = painter.color
		document.secondary_color = color_b
	%PalettePanel.set_colors(painter.color, color_b)

func _surface_input(phase: String, hit: Dictionary, modifiers: int, from_model: bool) -> void:
	if document == null or (jobs.busy() and jobs.kind != "pbr_preview"):
		return
	if phase == "begin" and not _replaying_gesture_click and (modifiers & 6) != 0:
		_commit_effects()
		_gesture_mode = "opacity" if (modifiers & 4) != 0 else "size"
		_gesture_hit = hit.duplicate()
		_gesture_modifiers = modifiers
		_gesture_from_model = from_model
		_gesture_initial = painter.opacity * 100.0 if _gesture_mode == "opacity" else float(painter.brush_size)
		_gesture_x = 0.0
		_gesture_travel = 0.0
		_gesture_dragging = false
		return
	if not _gesture_mode.is_empty():
		if phase == "end":
			var was_dragging := _gesture_dragging
			var mode := _gesture_mode
			_gesture_mode = ""
			if not was_dragging and not _gesture_hit.is_empty():
				if mode == "opacity":
					_pick_color(_gesture_hit)
				else:
					_replaying_gesture_click = true
					_surface_input("begin", _gesture_hit, _gesture_modifiers, _gesture_from_model)
					_surface_input("end", _gesture_hit, _gesture_modifiers, _gesture_from_model)
					_replaying_gesture_click = false
		return
	if phase == "begin":
		_commit_effects()
	if phase == "end":
		if painter.tool == "gradient" and not _gradient_start.is_empty():
			if not hit.is_empty():
				_gradient_end = hit.duplicate()
			_run_gradient()
		else:
			if painter.tool in ["line", "rect", "ellipse"] and painter.active and not hit.is_empty():
				var endpoint_face := int(hit.get("face", -1))
				painter.append(hit.uv, document.geometry.islands[endpoint_face] if endpoint_face >= 0 else -1, endpoint_face)
			painter.end()
			_clear_shape_preview()
		return
	if hit.is_empty():
		if painter.tool not in ["line", "rect", "ellipse"]: painter.break_path()
		return
	if document.geometry != null and from_model and not document.geometry.has_uv:
		_status("This model needs UV coordinates. Open the UV tab and choose Generate UV layout.")
		return
	if painter.tool == "select":
		if phase == "begin":
			_select_surface(hit, modifiers)
		return
	if painter.tool == "picker":
		if phase == "begin" or phase == "move":
			_pick_color(hit)
		return
	if document.selected_layer().locked:
		_status("The active layer is locked.")
		return
	if painter.tool == "fill":
		if phase == "begin":
			if painter.selection_active:
				jobs.start("operation", PaintOperations.fill.bind(document, painter.selection, true, painter.color))
			else:
				var fill_pixel := Vector2i((hit.uv * Vector2(document.width, document.height)).floor())
				var limit_island := document.geometry.islands[int(hit.face)] if from_model and int(hit.get("face", -1)) >= 0 else -1
				jobs.start("operation", PaintFloodFill.run.bind(document, fill_pixel, limit_island, painter.color, fill_tolerance, fill_contiguous))
		return
	if painter.tool == "texture":
		if phase == "begin":
			var faces := selected_faces.duplicate()
			var clicked := int(hit.get("face", -1))
			if faces.is_empty() and clicked >= 0:
				for f in document.geometry.face_count():
					if document.geometry.islands[f] == document.geometry.islands[clicked]:
						faces.append(f)
			_texture_fill(faces)
		return
	if painter.tool == "clone":
		if phase == "begin" and modifiers & 2:
			painter.clone_source = Vector2i(hit.uv * Vector2(document.width, document.height))
			_status("Clone source set at %d, %d · paint on the destination" % [painter.clone_source.x, painter.clone_source.y])
			return
		if painter.clone_source.x < 0:
			_status("Ctrl+click to set the clone source first.")
			return
	if painter.tool == "gradient":
		if phase == "begin":
			_gradient_start = hit.duplicate()
		_gradient_end = hit.duplicate()
		_update_gradient_preview()
		return
	if painter.tool == "stencil" and painter.stencil == null:
		if phase == "begin":
			_file_dialog("stencil")
		return
	var face := int(hit.get("face", -1))
	var island := document.geometry.islands[face] if face >= 0 else -1
	if phase == "begin":
		painter.begin(hit.uv, island, face)
	else:
		painter.append(hit.uv, island, face)
	if from_model and symmetry_axes != 0 and painter.tool in ["brush","eraser","stencil","spray","smudge","blur"]:
		for subset in range(1,8):
			if (subset & symmetry_axes) != subset: continue
			var mirror := document.geometry.mirrored_hit(hit,subset)
			if mirror.is_empty(): continue
			var mirror_face := int(mirror.face)
			painter.append_symmetry(mirror.uv,document.geometry.islands[mirror_face],subset)
	if painter.tool in ["line", "rect", "ellipse"]: _update_shape_preview()

func _gesture_motion(delta: Vector2) -> void:
	if _gesture_mode.is_empty():
		return
	_gesture_x += delta.x
	_gesture_travel += delta.length()
	if _gesture_travel < 4.0:
		return
	_gesture_dragging = true
	if _gesture_mode == "size":
		%ToolOptions.get_node("Size").set_value(_gesture_initial + _gesture_x / 3.0)
		_status("Size: %d px" % painter.brush_size)
	else:
		var field: NumberField = %SprayOptions.get_node("Opacity") if painter.tool == "spray" else %ToolOptions.get_node("Opacity")
		field.set_value(_gesture_initial + _gesture_x / 2.0)
		_status("Opacity: %d%%" % roundi(painter.opacity * 100.0))

func _update_shape_preview() -> void:
	if not painter.active or painter.tool not in ["line", "rect", "ellipse"]: return
	var start := painter._start
	var finish := painter._last if painter._last.x > -90000 else start
	model_view.set_shape_preview(start, finish, painter.tool, painter.footprint_size(), painter._last_island)
	uv_canvas.set_shape_preview(start, finish, painter.tool, painter.footprint_size())

func _update_gradient_preview() -> void:
	if _gradient_start.is_empty() or _gradient_end.is_empty(): return
	var extent := Vector2(document.width, document.height)
	var first := Vector2i((_gradient_start.uv * extent).floor())
	var last := Vector2i((_gradient_end.uv * extent).floor())
	var face := int(_gradient_start.get("face", -1))
	var island := document.geometry.islands[face] if face >= 0 else -1
	model_view.set_shape_preview(first, last, "line", painter.brush_size, island)
	uv_canvas.set_shape_preview(first, last, "line", painter.brush_size)

func _clear_shape_preview() -> void:
	if is_node_ready():
		model_view.set_shape_preview(Vector2i.ZERO, Vector2i.ZERO, "", 1, -1)
		uv_canvas.set_shape_preview(Vector2i.ZERO, Vector2i.ZERO, "", 1)

func _pick_color(hit: Dictionary) -> void:
	var pixel := Vector2i((hit.uv * Vector2(document.width, document.height)).floor()).clamp(Vector2i.ZERO, Vector2i(document.width - 1, document.height - 1))
	var tile := document.compose_tile(Vector2i(pixel.x >> 6, pixel.y >> 6))
	var sample := tile.get_region(Rect2i(pixel.x % 64, pixel.y % 64, 1, 1))
	var c := (ProjectIO.apply_effects(sample,pixel,document) if document.current_channel() == "albedo" else sample).get_pixel(0,0)
	_setting("color", c)
	_status("Picked #%s at %d, %d · %s remains active" % [c.to_html(false).to_upper(), pixel.x, pixel.y, painter.tool.capitalize()])

func _palette_change(action: String, index: int, color: Color) -> void:
	if document == null or jobs.busy() or painter.active: return
	if action == "add" and document.palette.size() >= PaletteIO.MAX_COLORS:
		_message("The palette supports up to %d colors." % PaletteIO.MAX_COLORS)
		return
	if action in ["edit","remove"] and (index < 0 or index >= document.palette.size()): return
	if action == "remove" and document.palette.size() <= 1: return
	var before := {"colors":document.palette.duplicate(),"name":document.palette_name,
		"primary":document.primary_color,"secondary":document.secondary_color}
	var old := document.palette[index] if index >= 0 else Color.TRANSPARENT
	match action:
		"add": document.palette.append(color)
		"edit": document.palette[index] = color
		"remove": document.palette.remove_at(index)
	if action == "edit":
		if document.primary_color.to_rgba32() == old.to_rgba32(): document.primary_color = color
		if document.secondary_color.to_rgba32() == old.to_rgba32(): document.secondary_color = color
	elif action == "add": document.primary_color = color
	document.palette_lookup = null
	var after := {"colors":document.palette.duplicate(),"name":document.palette_name,
		"primary":document.primary_color,"secondary":document.secondary_color}
	history.push(document,{"kind":"palette","label":action.capitalize()+" palette color","before":before,"after":after})
	painter.color = document.primary_color
	color_b = document.secondary_color
	%PalettePanel.refresh(document.palette,document.palette_name)
	_sync_colors()
	_apply_materials()
	_refresh_metadata()

func _select_surface(hit: Dictionary, modifiers: int) -> void:
	if document.geometry == null:
		return
	var model := document.geometry
	var face := int(hit.get("face", -1))
	if face < 0:
		for f in model.face_count():
			var tri := PackedVector2Array([model.uvs[f * 3], model.uvs[f * 3 + 1], model.uvs[f * 3 + 2]])
			if Geometry2D.is_point_in_polygon(hit.uv, tri):
				face = f
				break
	if face < 0:
		return
	_selection_before = selected_faces.duplicate()
	_steps_before = _selection_steps.duplicate()
	var found := PackedInt32Array()
	for f in model.face_count():
		if (selection_mode == 0 and model.islands[f] == model.islands[face]) or (selection_mode == 1 and f == face) or (selection_mode == 2 and model.objects[f] == model.objects[face]) or (selection_mode == 3 and model.materials[f] == model.materials[face]):
			found.append(f)
	var selected: Dictionary = {}
	if modifiers != 0:
		for f in selected_faces:
			selected[f] = true
	for f in found:
		if modifiers & 2:
			selected.erase(f)
		else:
			selected[f] = true
	selected_faces = PackedInt32Array(selected.keys())
	selected_faces.sort()
	_selection_steps.clear()
	_rebuild_selection()

func _resize_selection(grow: bool) -> void:
	if jobs.busy() or painter.active or document == null or document.geometry == null: return
	if selected_faces.is_empty():
		_status("Select a face first, then Ctrl+. to grow the selection.")
		return
	_selection_before = selected_faces.duplicate()
	_steps_before = _selection_steps.duplicate()
	if not grow:
		if _selection_steps.is_empty():
			_status("Selection is back at its original size.")
			return
		selected_faces = _selection_steps.pop_back()
	else:
		var expanded := document.geometry.grow_selection(selected_faces)
		if expanded == selected_faces: return
		_selection_steps.append(selected_faces.duplicate())
		selected_faces = expanded
	_rebuild_selection()

func _rebuild_selection() -> void:
	if selected_faces.is_empty():
		_clear_selection()
		return
	jobs.start("selection", func(progress: BackgroundJob.JobProgress) -> Dictionary:
		progress.report(0.5, "Preparing selection mask…")
		return {"selection": UVRaster.selection(document.geometry, selected_faces, Vector2i(document.width, document.height))})

func _show_selection() -> void:
	model_view.show_selection(selected_faces)
	uv_canvas.selected_faces = selected_faces
	uv_canvas.queue_redraw()
	_status("%d selected triangles · painting stays inside the selection" % selected_faces.size() if not selected_faces.is_empty() else "Selection cleared")

func _clear_selection() -> void:
	if jobs.busy() or painter.active:
		return
	selected_faces.clear()
	_selection_steps.clear()
	painter.selection.clear()
	painter.selection_active = false
	_show_selection()

func _run_gradient() -> void:
	var faces := selected_faces.duplicate()
	var start_face := int(_gradient_start.get("face", -1))
	# A planar side normally contains two triangles; include the connected coplanar side by default.
	if faces.is_empty() and start_face >= 0:
		var queue: Array[int] = [start_face]
		var found: Dictionary = {start_face: true}
		while not queue.is_empty():
			var f: int = queue.pop_back()
			for next in document.geometry.neighbors[f]:
				if not found.has(next) and document.geometry.face_normals[next].dot(document.geometry.face_normals[start_face]) > 0.999:
					found[next] = true
					queue.append(next)
		faces = PackedInt32Array(found.keys())
	jobs.start("operation", PaintOperations.gradient.bind(document, faces, _gradient_start.duplicate(), _gradient_end.duplicate(), gradient_length, painter.color, color_b, painter.dither, painter.brush_size))
	_gradient_start.clear()
	_gradient_end.clear()
	_clear_shape_preview()

func _layer_action(action: String, value: Variant) -> void:
	if document == null or painter.active or jobs.busy():
		return
	_cancel_blur_preview()
	_cancel_geometry_preview()
	_commit_effects()
	var channel_before := document.current_channel()
	if action == "clear_map":
		_clear_current_map()
		return
	if action in ["visibility_at","rename_at","lock_at"]:
		for layer in document.layers:
			if layer.id != value.id: continue
			var property := "visible" if action == "visibility_at" else "locked" if action == "lock_at" else "title"
			var next: Variant = value.visible if action == "visibility_at" else value.locked if action == "lock_at" else str(value.title).strip_edges().left(128)
			if property == "title" and str(next).is_empty(): return
			if layer.get(property) != next:
				history.push(document,{"kind":"property","label":"Layer "+property,"target":layer,"property":property,"before":layer.get(property),"after":next})
				layer.set(property,next)
				if property == "visible" and layer.channel == channel_before: tiles.mark(document.all_keys(),false)
		_refresh_metadata()
		return
	if action == "select_id":
		for i in document.layers.size():
			if document.layers[i].id == value: document.active_layer = i; break
	elif action == "select":
		document.active_layer = document.layers.size() - 1 - int(value)
	elif action == "editing_mask":
		document.editing_mask = value
		_status("Painting MASK · use white or black" if value else "Painting COLOR")
	elif action in ["add", "duplicate", "delete", "up", "down"]:
		if action in ["add", "duplicate"] and document.layers.size() >= 32:
			_message("This project supports up to 32 layers across all maps.")
			return
		var before := document.layers.duplicate()
		var index := document.active_layer
		if action == "add":
			var layer := PaintLayer.new()
			layer.channel = document.current_channel()
			layer.title = "Paint %02d" % document.layers.size()
			document.layers.insert(index + 1, layer)
			document.active_layer += 1
		elif action == "duplicate":
			var layer := document.selected_layer().copy_layer()
			layer.id = str(Time.get_ticks_usec())
			layer.title += " copy"
			document.layers.insert(index + 1, layer)
			document.active_layer += 1
		elif action == "delete" and document.layers.size() > 1:
			document.layers.remove_at(index)
			document.active_layer = mini(index, document.layers.size() - 1)
		elif action in ["up", "down"]:
			var next := clampi(index + (1 if action == "up" else -1), 0, document.layers.size() - 1)
			var layer := document.layers[index]
			document.layers.remove_at(index)
			document.layers.insert(next, layer)
			document.active_layer = next
		history.push(document, {"kind": "layers", "label": action.capitalize() + " layer", "before": before, "after": document.layers.duplicate(),"active_before":index,"active_after":document.active_layer})
		tiles.mark(document.all_keys(), false)
	else:
		var target := document.selected_layer()
		var before: Variant = target.get(action)
		if before != value:
			target.set(action, value)
			history.push(document, {"kind": "property", "label": "Layer " + action, "target": target, "property": action, "before": before, "after": value})
			if action not in ["title", "locked"]:
				tiles.mark(document.all_keys(), false)
	if document.current_channel() != channel_before:
		tiles.mark(document.all_keys(),false)
		_apply_materials()
	_sync_pattern_inspector()
	_refresh_metadata()

func _clear_current_map() -> void:
	if document == null or painter.active or jobs.busy(): return
	var channel := document.current_channel()
	var before := document.layers.duplicate()
	var after: Array[PaintLayer] = []
	var changed := false
	var removed_bytes := 0
	for layer in before:
		if layer.channel != channel:
			after.append(layer)
			continue
		var blank := PaintLayer.from_metadata(layer.metadata())
		blank.base_color = Color.TRANSPARENT
		blank.mask_enabled = false
		blank.pattern_image = null
		blank.pattern_faces.clear()
		blank.pattern_settings.clear()
		after.append(blank)
		if not layer.tiles.is_empty() or not layer.masks.is_empty() or not layer.pattern_tiles.is_empty() or layer.base_color != Color.TRANSPARENT or layer.mask_enabled:
			changed = true
			removed_bytes += (layer.tiles.size()+layer.masks.size()+layer.pattern_tiles.size())*64*64*4
	if not changed:
		_status(PaintChannels.label(channel) + " map is already blank.")
		return
	var mask_before := document.editing_mask
	document.layers.assign(after)
	document.editing_mask = false
	history.push(document,{"kind":"layers","label":"Reset " + PaintChannels.label(channel) + " map","before":before,"after":after,"active_before":document.active_layer,"active_after":document.active_layer,"editing_mask_before":mask_before,"editing_mask_after":false,"bytes":removed_bytes})
	tiles.mark(document.all_keys(),false)
	_apply_materials()
	_refresh_metadata()
	_status(PaintChannels.label(channel) + " map reset · Undo restores it")

func _select_channel(channel: String) -> void:
	if document == null or jobs.busy() or painter.active:
		if document != null: %MapSelector.select(PaintChannels.IDS.find(document.current_channel()))
		return
	_cancel_blur_preview()
	_cancel_geometry_preview()
	_commit_effects()
	for i in range(document.layers.size()-1,-1,-1):
		if document.layers[i].channel == channel:
			document.active_layer = i
			tiles.mark(document.all_keys(),false)
			_apply_materials()
			_sync_pattern_inspector()
			_refresh_metadata()
			return
	if document.layers.size() >= 32:
		_message("This project supports up to 32 layers across all maps.")
		_refresh_metadata()
		return
	var before := document.layers.duplicate()
	var previous := document.active_layer
	var layer := PaintLayer.new()
	layer.channel = channel
	layer.title = PaintChannels.label(channel) + " 01"
	document.layers.append(layer)
	document.active_layer = document.layers.size()-1
	history.push(document,{"kind":"layers","label":"Add "+channel+" map","before":before,"after":document.layers.duplicate(),"active_before":previous,"active_after":document.active_layer})
	tiles.mark(document.all_keys(),false)
	_apply_materials()
	_sync_pattern_inspector()
	_refresh_metadata()

func _effect_changed(key: String, value: Variant) -> void:
	if document == null or jobs.busy() or document.current_channel() != "albedo":
		return
	if _effect_before.is_empty():
		_effect_before = document.effects.duplicate(true)
	if key == "reset":
		document.effects = PaintDocument.new().effects
		%Effects.refresh(document)
	else:
		document.effects[key] = value
	_apply_materials()
	%EffectCommit.start()

func _commit_effects() -> void:
	if not _effect_before.is_empty() and document != null:
		if _effect_before != document.effects:
			history.push(document, {"kind": "effects", "label": "Adjust effects", "before": _effect_before.duplicate(true), "after": document.effects.duplicate(true)})
		_effect_before.clear()
		_refresh_metadata()
	_commit_pattern_settings()

func _pattern_settings_changed() -> void:
	if document == null: return
	if document.selected_layer().pattern_image != null: return
	var settings: Dictionary = %Pattern.settings()
	var next := {"angle": settings.angle, "scale": settings.scale, "offset_x": settings.offset.x, "offset_y": settings.offset.y}
	if next == document.pattern_settings: return
	if _pattern_before.is_empty(): _pattern_before = document.pattern_settings.duplicate(true)
	document.pattern_settings = next
	%EffectCommit.start()

func _commit_pattern_settings() -> void:
	if _pattern_before.is_empty() or document == null: return
	if _pattern_before != document.pattern_settings:
		history.push(document, {"kind": "property", "label": "Pattern transform", "target": document, "property": "pattern_settings", "before": _pattern_before.duplicate(true), "after": document.pattern_settings.duplicate(true)})
	_pattern_before.clear()
	_refresh_metadata()

func _sync_pattern_inspector() -> void:
	if document == null or document.layers.is_empty(): return
	var layer := document.selected_layer()
	if layer.pattern_image != null:
		%Pattern.set_source(layer.pattern_image,layer.title)
		%Pattern.restore_settings(layer.pattern_settings)
		%Pattern.set_editing_pattern(true)
	else:
		%Pattern.set_source(document.pattern_image,"Project texture")
		%Pattern.restore_settings(document.pattern_settings)
		%Pattern.set_editing_pattern(false)

func _uv_action(action: String, value: Variant) -> void:
	if document == null or document.geometry == null or jobs.busy() or painter.active:
		return
	if action == "export_padding":
		if document.uv_export_padding != int(value):
			history.push(document,{"kind":"property","label":"Export seam padding","target":document,"property":"uv_export_padding","before":document.uv_export_padding,"after":int(value)})
			document.uv_export_padding = int(value)
			_refresh_metadata()
		return
	if action == "inspect":
		jobs.start("uv_inspect",ProjectTransforms.inspect_uv.bind(document.geometry,Vector2i(document.width,document.height)))
		return
	if action == "generate":
		_pending_uv = value
		%UVConfirm.popup_centered()
		return
	if selected_faces.is_empty():
		_status("Select an island before editing UVs.")
		return
	var result := ModelGeometry.from_data(document.geometry.serialized())
	var center := Vector2.ZERO
	var count := 0
	for f in selected_faces:
		for c in 3:
			center += result.uvs[f * 3 + c]
			count += 1
	center /= maxi(count, 1)
	var resolution := Vector2(document.width, document.height)
	for f in selected_faces:
		for c in 3:
			var index := f * 3 + c
			var p := result.uvs[index]
			match action:
				"move": p += Vector2(value) / resolution
				"rotate": p = center + ((p - center) * resolution).rotated(deg_to_rad(float(value))) / resolution
				"scale": p = center + (p - center) * float(value)
				"snap": p = (p * resolution).round() / resolution
			if p.x < 0 or p.y < 0 or p.x > 1 or p.y > 1:
				_status("UV edit would leave the texture. Move the island inward first.")
				return
			result.uvs[index] = p
	for f in selected_faces:
		var a := result.uvs[f * 3 + 1] - result.uvs[f * 3]
		var b := result.uvs[f * 3 + 2] - result.uvs[f * 3]
		if absf(a.cross(b)) < 0.0000000001:
			_status("This edit would collapse a UV triangle. Increase its size before snapping.")
			return
	var snapshot := document.read_copy()
	jobs.start("geometry_edit", func(progress: BackgroundJob.JobProgress) -> Dictionary:
		progress.report(0.5, "Updating UV layout…")
		result.build_cache()
		return ProjectTransforms.reproject_uv(progress,snapshot,result))

func _generate_uv() -> void:
	if jobs.busy() or document == null:
		return
	var snapshot := document.read_copy()
	jobs.start("unwrap", func(progress: BackgroundJob.JobProgress) -> Dictionary:
		progress.report(0.1, "Grouping faces and packing UV islands…")
		var unwrapped := UVUnwrapper.unwrap(snapshot.geometry, snapshot.width, snapshot.height, float(_pending_uv.get("angle", 45)), int(_pending_uv.get("padding", 2)), progress)
		if unwrapped.has("error") or unwrapped.get("cancelled",false): return unwrapped
		var remapped := ProjectTransforms.reproject_uv(progress,snapshot,unwrapped.geometry)
		remapped.merge(unwrapped,false)
		return remapped)

func _edges() -> void:
	if document != null and document.geometry != null and not jobs.busy() and not painter.active:
		_cancel_blur_preview()
		if _commit_geometry_preview("edges"): return
		_cancel_geometry_preview()
		if document.layers.size() >= 32:
			_message("This project supports up to 32 layers across all maps.")
			return
		jobs.start("edges", PaintOperations.edge_layer.bind(document, int(%Effects.get_node("EdgeWidth").value), painter.color))

func _ambient_occlusion() -> void:
	if document == null or document.geometry == null or jobs.busy() or painter.active:
		return
	_cancel_blur_preview()
	if not document.geometry.has_uv:
		_status("Generate a UV layout before baking AO.")
		return
	if _commit_geometry_preview("ao"): return
	_cancel_geometry_preview()
	if document.layers.size() >= 32:
		_message("This project supports up to 32 layers across all maps.")
		return
	_commit_effects()
	jobs.start("ao", PaintOperations.cavity_ao.bind(document,
		float(%Effects.get_node("AOStrength").value) / 100.0,
		int(%Effects.get_node("AORadius").value),
		float(%Effects.get_node("AODepth").value) / 100.0,
		%Effects.get_node("AOFalloff").selected))

func _generate_geometry_mask(kind: String) -> void:
	if document == null or document.geometry == null or jobs.busy() or painter.active: return
	if document.selected_layer().locked:
		_status("Unlock the selected layer before generating its mask.")
		return
	_cancel_geometry_preview()
	_cancel_blur_preview()
	var parameters := {"width":int(%Effects.get_node("EdgeWidth").value),
		"strength":float(%Effects.get_node("AOStrength").value)/100.0,
		"radius":int(%Effects.get_node("AORadius").value),
		"depth":float(%Effects.get_node("AODepth").value)/100.0,
		"falloff":%Effects.get_node("AOFalloff").selected,
		"invert":%Effects.get_node("EdgeMaskInvert" if kind == "edges" else "AOMaskInvert").button_pressed}
	jobs.start("geometry_mask",PaintOperations.geometry_mask.bind(document.read_copy(),kind,parameters))

func _geometry_signature(kind: String) -> Array:
	if kind == "edges": return [int(%Effects.get_node("EdgeWidth").value),painter.color.to_rgba32()]
	return [float(%Effects.get_node("AOStrength").value),int(%Effects.get_node("AORadius").value),float(%Effects.get_node("AODepth").value),int(%Effects.get_node("AOFalloff").selected)]

func _cancel_geometry_preview(clear_request := true) -> void:
	if clear_request: _geometry_requested_kind = ""
	if _geometry_preview_layer == null or document == null: return
	var index := document.layers.find(_geometry_preview_layer)
	if index >= 0:
		document.layers.remove_at(index)
		var keys: Array[Vector2i] = []
		keys.assign(_geometry_preview_layer.tiles.keys())
		tiles.mark(keys,false)
	_geometry_preview_layer = null
	_geometry_preview_kind = ""
	_geometry_preview_signature.clear()

func _preview_geometry_effect(kind: String) -> void:
	if document == null or document.geometry == null or not document.geometry.has_uv or painter.active: return
	if document.current_channel() != "albedo":
		_status("Select Albedo to preview geometry effects.")
		return
	if document.layers.size() >= 32 and _geometry_preview_layer == null: return
	_geometry_requested_kind = kind
	_geometry_requested_signature = _geometry_signature(kind)
	if jobs.busy(): return
	if _geometry_preview_layer != null and _geometry_preview_kind == kind and _geometry_preview_signature == _geometry_requested_signature: return
	_cancel_geometry_preview(false)
	_geometry_job_signature = _geometry_requested_signature.duplicate()
	var snapshot := document.read_copy()
	if kind == "edges":
		jobs.start("edges_preview",PaintOperations.edge_layer.bind(snapshot,int(%Effects.get_node("EdgeWidth").value),painter.color))
	else:
		jobs.start("ao_preview",PaintOperations.cavity_ao.bind(snapshot,float(%Effects.get_node("AOStrength").value)/100.0,int(%Effects.get_node("AORadius").value),float(%Effects.get_node("AODepth").value)/100.0,int(%Effects.get_node("AOFalloff").selected)))

func _commit_geometry_preview(kind: String) -> bool:
	if _geometry_preview_layer == null or _geometry_preview_kind != kind or _geometry_preview_signature != _geometry_signature(kind): return false
	var before := document.layers.duplicate()
	before.erase(_geometry_preview_layer)
	var previous := document.active_layer
	document.active_layer = document.layers.find(_geometry_preview_layer)
	history.push(document,{"kind":"layers","label":"Edge highlights" if kind == "edges" else "Cavity AO","before":before,"after":document.layers.duplicate(),"active_before":previous,"active_after":document.active_layer})
	_geometry_preview_layer = null
	_geometry_preview_kind = ""
	_geometry_requested_kind = ""
	_refresh_metadata()
	_status("Geometry effect applied · Undo restores it")
	return true

func _generate_normal_map() -> void:
	if document == null or jobs.busy() or painter.active: return
	_cancel_blur_preview()
	_cancel_geometry_preview()
	if not document.has_channel("height"):
		_status("Paint a Height map first, then generate its Normal map.")
		return
	if document.layers.size() >= 32:
		_message("This project supports up to 32 layers across all maps.")
		return
	_commit_effects()
	jobs.start("normal", PaintOperations.normal_from_height.bind(document.read_copy(),float(%Effects.get_node("NormalStrength").value)/100.0))

func _find_layer(id: String) -> PaintLayer:
	if document == null: return null
	for layer in document.layers:
		if layer.id == id: return layer
	return null

func _cancel_blur_preview() -> void:
	_blur_job_layer_id = ""
	_blur_wanted_radius = 0
	_blur_apply_when_ready = false
	if _blur_preview_layer_id.is_empty(): return
	var layer := _find_layer(_blur_preview_layer_id)
	if layer != null:
		layer.tiles = _blur_original_tiles
		layer._prepared.clear()
		tiles.mark(_blur_changed,false)
	_blur_preview_layer_id = ""
	_blur_original_tiles = {}
	_blur_changed.clear()

func _preview_layer_blur() -> void:
	if document == null or painter.active: return
	var layer := document.selected_layer()
	if layer.locked:
		_status("Unlock this layer before applying Blur.")
		_blur_apply_when_ready = false
		return
	_blur_wanted_radius = int(%Effects.get_node("BlurRadius").value)
	if _blur_preview_layer_id == layer.id and not _blur_apply_when_ready and not jobs.busy():
		return
	if _blur_preview_layer_id == layer.id and _blur_apply_when_ready:
		_apply_layer_blur()
		return
	if jobs.busy(): return
	var apply_when_ready := _blur_apply_when_ready
	_cancel_blur_preview()
	_blur_apply_when_ready = apply_when_ready
	_blur_wanted_radius = int(%Effects.get_node("BlurRadius").value)
	_blur_job_layer_id = layer.id
	jobs.start("layer_blur_preview",PaintOperations.blur_layer.bind(document.read_copy(),layer.id,_blur_wanted_radius))

func _apply_layer_blur() -> void:
	var layer := _find_layer(_blur_preview_layer_id)
	if layer == null or _blur_changed.is_empty():
		_cancel_blur_preview()
		_status("Blur did not change this layer.")
		return
	var before := {}
	var after := {}
	for key in _blur_changed:
		before[key] = _blur_original_tiles[key] if _blur_original_tiles.has(key) else null
		after[key] = layer.tiles[key] if layer.tiles.has(key) else null
	history.push(document,{"kind":"tiles","label":"Blur layer %d px" % _blur_wanted_radius,"layer":layer,"mask":false,"before":before,"after":after,"bytes":_blur_changed.size()*64*64*4*2})
	_blur_preview_layer_id = ""
	_blur_original_tiles = {}
	_blur_changed.clear()
	_blur_apply_when_ready = false
	_refresh_metadata()
	_status("Blur applied to selected layer · Undo restores it")

func _action(action: String) -> void:
	if action == "About":
		%About.popup_centered()
		return
	if action == "ToggleFullscreen":
		_toggle_fullscreen()
		return
	if jobs.busy() or painter.active:
		_status("Wait for the current operation to finish.")
		return
	_cancel_blur_preview()
	_cancel_geometry_preview()
	_commit_effects()
	_sync_assets()
	match action:
		"New", "Open", "OpenRecent", "Quit", "Recover":
			if document != null and document.revision != document.saved_revision:
				_pending_discard = action
				%Discard.popup_centered()
			else:
				_perform_guarded(action)
		"Save":
			if document.path.is_empty():
				_file_dialog("save")
			else:
				jobs.start("save", ProjectIO.save_project.bind(document, document.path))
		"SaveAs": _file_dialog("save")
		"Import": _file_dialog("import")
		"Export": _file_dialog("export")
		"ExportMaps": _file_dialog("export_maps")
		"ExportModel": _file_dialog("export_model")
		"ToggleRestoreLast":
			_reopen_last = not _reopen_last
			_queue_preferences_save()
			_refresh_metadata()
		"Pattern": _file_dialog("pattern")
		"Stamp": _file_dialog("stencil")
		"ClearSelection": _clear_selection()
		"ResetMap": _clear_current_map()
		"ResizeTexture":
			%ResizeDialog.get_node("Form/Width").set_value(document.width,false)
			%ResizeDialog.get_node("Form/Height").set_value(document.height,false)
			%ResizeDialog.popup_centered()
		"ReplaceColor":
			%ColorReplaceDialog.get_node("Form/Colors").text = "#%s  →  #%s" % [painter.color.to_html(false).to_upper(),color_b.to_html(false).to_upper()]
			%ColorReplaceDialog.popup_centered()
		"GrowSelection": _resize_selection(true)
		"ShrinkSelection": _resize_selection(false)
		"Frame": model_view.frame_model()
		"FitUV": uv_canvas.fit()
		"WireUV": %WireUV.button_pressed = not %WireUV.button_pressed
		"WireModel": model_view.toggle_wires()
		"ToggleUV": %UVView.button_pressed = not %UVView.button_pressed
		"Undo", "Redo":
			var dimensions_before := Vector2i(document.width,document.height)
			var keys := history.undo(document) if action == "Undo" else history.redo(document)
			if dimensions_before != Vector2i(document.width,document.height):
				painter.setup(document,history)
				tiles.setup(document)
				uv_canvas.setup(document)
			else: tiles.mark(keys, false)
			if document.geometry != model_view.geometry:
				model_view.set_geometry(document.geometry)
				uv_canvas._layout()
				_clear_selection()
			_apply_materials()
			%Effects.refresh(document)
			%PalettePanel.refresh(document.palette, document.palette_name)
			_sync_colors()
			painter.stencil = document.stamp_image
			painter.stencil_region = document.stamp_region
			painter.stencil_rotation = document.stamp_rotation
			%Pattern.set_source(document.pattern_image, "Project texture")
			%Pattern.restore_settings(document.pattern_settings)
			_sync_pattern_inspector()
			%UV.get_node("ExportPadding").set_value(document.uv_export_padding,false)
			%StampPanel.set_source(document.stamp_image, document.stamp_name, document.stamp_region)
			%StampPanel.set_stamp_rotation(document.stamp_rotation)
			_stamp_rotation_editing = false
			_refresh_metadata()

func _perform_guarded(action: String) -> void:
	match action:
		"New": %NewDialog.popup_centered()
		"Open": _file_dialog("open")
		"OpenRecent":
			if _last_project_path.is_empty() or not FileAccess.file_exists(_last_project_path):
				_message("The last project is no longer available. Use File → Open project.")
			else:
				jobs.start("open", ProjectIO.load_project.bind(_last_project_path))
		"Quit":
			_save_preferences()
			get_tree().quit()
		"Recover": jobs.start("recover", ProjectIO.load_project.bind(ProjectSettings.globalize_path(_recovery_path)))

func _new_from_dialog() -> void:
	var width := int(%NewDialog.get_node("Form/Dimensions/Width").value)
	var height := int(%NewDialog.get_node("Form/Dimensions/Height").value)
	_start_new(width, height, %NewDialog.get_node("Form/ProjectName").text)

func _file_dialog(action: String) -> void:
	if jobs.busy() or painter.active:
		return
	_file_action = action
	var dialog: FileDialog = %FileDialog
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action in ["save", "export", "export_model", "export_maps"] else FileDialog.FILE_MODE_OPEN_FILE
	match action:
		"save", "open": dialog.filters = PackedStringArray(["*.rtpaint ; Retro Painter project"])
		"import": dialog.filters = PackedStringArray(["*.glb, *.gltf, *.obj ; 3D models"])
		"stencil", "pattern": dialog.filters = PackedStringArray(["*.png, *.jpg, *.webp ; Texture image"])
		"palette": dialog.filters = PackedStringArray(["*.png, *.hex, *.gpl, *.pal, *.txt, *.ase, *.json, *.csv ; Color palettes"])
		"export", "export_maps": dialog.filters = PackedStringArray(["*.png ; PNG texture"])
		"export_model": dialog.filters = PackedStringArray(["*.glb ; GLB model with embedded texture", "*.gltf ; glTF model with texture files", "*.obj ; OBJ with current UV coordinates"])
	dialog.title = action.replace("_", " ").capitalize()
	dialog.current_file = ""
	if not _last_project_path.is_empty() and FileAccess.file_exists(_last_project_path):
		dialog.current_dir = _last_project_path.get_base_dir()
	if document != null and action in ["save", "export", "export_model", "export_maps"]:
		dialog.current_file = document.title.validate_filename() + {"save": ".rtpaint", "export": "_"+document.current_channel()+".png", "export_model": ".glb", "export_maps":".png"}[action]
	dialog.popup_centered_ratio(0.7)

func _file_selected(path: String) -> void:
	match _file_action:
		"palette": jobs.start("palette", PaletteIO.load_palette.bind(path))
		"save": jobs.start("save", ProjectIO.save_project.bind(document, path if path.ends_with(".rtpaint") else path + ".rtpaint"))
		"open": jobs.start("open", ProjectIO.load_project.bind(path))
		"import": jobs.start("import", ModelIO.load_model.bind(path,document.width,document.height))
		"export": jobs.start("export", ProjectIO.export_png.bind(document, path if path.ends_with(".png") else path + ".png"))
		"export_maps": jobs.start("export", ModelExport.export_maps.bind(document,path))
		"export_model":
			jobs.start("export_model", ModelExport.save.bind(document, path))
		"stencil":
			var image := Image.load_from_file(path)
			if image == null or image.get_width() > 4096 or image.get_height() > 4096:
				_message("Choose a valid stamp up to 4096 × 4096.")
			else:
				image.convert(Image.FORMAT_RGBA8)
				var selected := Rect2i(Vector2i.ZERO, image.get_size())
				history.push(document, {"kind": "stamp", "before": {"image": document.stamp_image, "region": document.stamp_region, "name": document.stamp_name}, "after": {"image": image, "region": selected, "name": path.get_file()}})
				document.stamp_image = image
				document.stamp_region = selected
				document.stamp_name = path.get_file()
				painter.stencil = image
				painter.stencil_region = selected
				%StampPanel.set_source(image, document.stamp_name, selected)
				%ToolBar.select("stencil")
				_refresh_metadata()
				_status("Stamp loaded · drag on its preview to choose a crop")
		"pattern":
			var image := Image.load_from_file(path)
			if image == null or image.get_width() > 4096 or image.get_height() > 4096:
				_message("Choose a valid texture up to 4096 × 4096.")
			else:
				image.convert(Image.FORMAT_RGBA8)
				%Pattern.set_source(image, path.get_file())
				if document.selected_layer().pattern_image == null:
					history.push(document, {"kind": "property", "target": document, "property": "pattern_image", "before": document.pattern_image, "after": image})
					document.pattern_image = image
				else: _apply_pattern(document.selected_layer().pattern_faces)
				%Inspector.current_tab = 3
				%ToolBar.select("texture")

func _texture_fill(faces: PackedInt32Array) -> void:
	if jobs.busy() or painter.active or document == null or document.selected_layer().locked:
		return
	if %Pattern.source == null:
		_file_dialog("pattern")
		return
	if faces.is_empty():
		_status("Select faces, or click a model surface with the Texture tool.")
		return
	if document.layers.size() >= 32:
		_message("This project supports up to 32 layers across all maps.")
		return
	jobs.start("pattern_render", PaintOperations.pattern_layer.bind(document.read_copy(), faces, %Pattern.source, %Pattern.settings()))

func _apply_pattern(faces: PackedInt32Array) -> void:
	if document == null or jobs.busy() or painter.active or %Pattern.source == null: return
	var layer := document.selected_layer()
	if layer.pattern_image != null:
		jobs.start("pattern_render",PaintOperations.rerender_pattern.bind(document.read_copy(),layer.id,%Pattern.source,%Pattern.settings()))
	else: _texture_fill(faces)

func _stamp_region_changed(region: Rect2i) -> void:
	if document == null or document.stamp_image == null or region == document.stamp_region:
		return
	var previous := {"image": document.stamp_image, "region": document.stamp_region, "name": document.stamp_name}
	var next := {"image": document.stamp_image, "region": region, "name": document.stamp_name}
	history.push(document, {"kind": "stamp", "before": previous, "after": next, "bytes": 0})
	document.stamp_region = region
	painter.stencil_region = region
	_stamp_source_image = null
	_refresh_cursor()
	_refresh_metadata()
	_status("Stamp crop: %d × %d px from %d, %d" % [region.size.x, region.size.y, region.position.x, region.position.y])

func _stamp_rotation_input(angle: float, commit: bool) -> void:
	if document == null or painter.active: return
	if not _stamp_rotation_editing:
		_stamp_rotation_before = document.stamp_rotation
		_stamp_rotation_editing = true
	var normalized := fposmod(angle+180.0,360.0)-180.0
	document.stamp_rotation = normalized
	painter.stencil_rotation = normalized
	%StampPanel.set_stamp_rotation(normalized)
	_refresh_cursor()
	if commit:
		if not is_equal_approx(_stamp_rotation_before,normalized):
			history.push(document,{"kind":"property","target":document,"property":"stamp_rotation","before":_stamp_rotation_before,"after":normalized,"bytes":0})
			_refresh_metadata()
		_stamp_rotation_editing = false
		if painter.stencil != null: %StampPanel.set_result_preview(painter.stamp_preview())
		_status("Stamp rotation: %d°" % roundi(normalized))

func _stamp_rotation_drag(phase: String, horizontal_delta: float) -> void:
	if phase == "begin":
		_stamp_rotation_before = document.stamp_rotation if document != null else 0.0
		_stamp_rotation_editing = true
	elif phase == "move" and _stamp_rotation_editing:
		_stamp_rotation_input(document.stamp_rotation+horizontal_delta*0.5,false)
	elif phase == "end" and _stamp_rotation_editing:
		_stamp_rotation_input(document.stamp_rotation,true)

func _job_completed(kind: String, value: Variant) -> void:
	var result: Dictionary = value if value is Dictionary else {"error": "Operation returned no result."}
	if kind == "open_last" and (result.has("error") or result.get("cancelled", false)):
		_last_project_path = ""
		_queue_preferences_save()
		_start_new(128,128,"Field crate",true)
		_message("The last project could not be reopened. " + str(result.get("error","")))
		return
	if kind == "selection" and (result.has("error") or result.get("cancelled", false)):
		selected_faces = _selection_before
		_selection_steps = _steps_before
	if result.has("error"):
		_message(result.error)
		return
	if result.get("cancelled", false):
		_status("Operation cancelled · document unchanged")
		return
	match kind:
		"geometry_mask":
			var selected := _find_layer(str(result.layer_id))
			if selected == null: return
			var before := _document_state()
			var updated := selected.copy_layer()
			updated.masks = result.masks
			updated.mask_enabled = true
			for i in document.layers.size():
				if document.layers[i].id == selected.id:
					document.layers[i] = updated
					break
			history.push(document,{"kind":"document","label":"Generate geometry mask","before":before,"after":_document_state()})
			tiles.mark(document.all_keys(),false)
			_refresh_metadata()
			_status("%s mask applied to selected layer · Undo restores it" % ["Edge" if result.kind == "edges" else "Cavity"])
		"pbr_preview":
			model_view.set_pbr_maps(result.maps)
		"palette":
			_commit_effects()
			history.push(document, {"kind":"palette", "label":"Load palette", "before":{"colors":document.palette.duplicate(),"name":document.palette_name}, "after":{"colors":result.palette.duplicate(),"name":result.name}})
			document.palette = result.palette
			document.palette_name = result.name
			%PalettePanel.refresh(document.palette, document.palette_name)
			_sync_colors()
			_apply_materials()
			_refresh_metadata()
			_status("Loaded %s · %d colors · left click: 1, right click: 2" % [result.name, result.palette.size()])
		"new", "open", "open_last":
			_set_document(result.document)
			if kind in ["open", "open_last"]: _remember_project(result.document.path)
		"recover":
			result.document.path = ""
			result.document.saved_revision = -1
			_set_document(result.document)
			_status("Recovery opened · use Save as to keep this project")
		"save":
			document.path = result.path
			document.saved_revision = int(result.revision)
			_remember_project(result.path)
			_refresh_metadata()
			_status("Saved · " + result.path)
		"autosave":
			_last_saved_autosave_revision = int(result.revision)
			_status("Recovery copy saved")
			_refresh_metadata()
		"export": _status("Exported · " + result.path)
		"export_model":
			_status("Exported · " + result.path)
			if OS.get_name() == "Windows" and DisplayServer.get_name() != "headless":
				var folder_error := OS.shell_show_in_file_manager(ProjectSettings.globalize_path(result.path).get_base_dir())
				if folder_error != OK:
					_message("Model exported, but Windows Explorer could not open its folder.")
		"import":
			var before := _document_state()
			var added: Array = result.get("imported_layers",[])
			if added.size()+2>32:
				_message("The model has too many material maps for the 32-layer limit.")
				return
			# A new mesh has a different UV layout. Old paint belongs to the previous mesh.
			document.layers.clear()
			var base := PaintLayer.new()
			base.title = "Base color"
			document.layers.append(base)
			for imported in added: document.layers.append(imported)
			var paint_layer := PaintLayer.new()
			paint_layer.title = "Paint 01"
			document.layers.append(paint_layer)
			document.active_layer = document.layers.size()-1
			document.editing_mask = false
			document.geometry = result.geometry
			history.push(document, {"kind": "document", "label": "Import model and materials", "before": before, "after": _document_state()})
			_install_document_state(_document_state())
			if not document.geometry.has_uv:
				_status("Model imported without usable UVs · generate a layout in the UV tab")
			elif added.is_empty():
				_status("Model UVs loaded; no supported material textures found in the file")
			else:
				var import_status := "Model UVs loaded · %d material map(s) imported · previous model paint cleared" % added.size()
				if int(result.get("material_overlap", 0)) > 0:
					import_status += " · %d shared texels kept their first texture" % int(result.material_overlap)
				_status(import_status)
			_refresh_metadata()
		"unwrap", "geometry_edit":
			_uv_preview_before = _document_state()
			var state := {"width":document.width,"height":document.height,"geometry":result.geometry,
				"layers":result.layers,"active_layer":document.active_layer,"editing_mask":document.editing_mask}
			_install_document_state(state)
			if kind == "unwrap":
				var info := "%d islands · %.1f%% packed rectangles" % [result.islands,result.occupancy*100]
				if int(result.get("subpixel_faces",0)) > 0: info += "\n%d tiny faces share texels; increase resolution for detail." % int(result.subpixel_faces)
				if int(result.get("overlap",0)) > 0: info += "\n%d texels overlap between UV islands." % int(result.overlap)
				if int(result.get("uncovered",0)) > 0: info += "\n%d faces cover no texel." % int(result.uncovered)
				%UV.get_node("Info").text = info
			%UVApply.popup_centered()
			_status("UV preview · inspect the model, then Apply or Cancel")
		"resize":
			if result.get("unchanged",false): return
			var before := _document_state()
			var state := {"width":result.width,"height":result.height,"geometry":document.geometry,
				"layers":result.layers,"active_layer":document.active_layer,"editing_mask":document.editing_mask}
			_install_document_state(state)
			history.push(document,{"kind":"document","label":"Resize texture","before":before,"after":state})
			_refresh_metadata()
			_status("All maps resized to %d × %d with nearest-neighbor pixels · Undo restores them" % [document.width,document.height])
		"uv_inspect":
			%UV.get_node("Info").text = "%d tiny faces · %d uncovered faces · %d shared texels across islands" % [int(result.subpixel),int(result.uncovered),int(result.overlap)]
			_status("UV coverage inspected · see UV Info")
		"replace_color":
			if int(result.changed) == 0:
				_status("No matching color found in the current map.")
				return
			var before := _document_state()
			document.layers.assign(result.layers)
			history.push(document,{"kind":"document","label":"Replace color","before":before,"after":_document_state()})
			tiles.mark(document.all_keys(),false)
			_refresh_metadata()
			_status("Replaced %d pixels in the current map · Undo restores them" % int(result.changed))
		"pattern_render":
			if result.has("layer_id"):
				var before := _document_state()
				for i in document.layers.size():
					if document.layers[i].id == result.layer_id:
						document.layers[i] = result.layer
						break
				history.push(document,{"kind":"document","label":"Update pattern fill","before":before,"after":_document_state()})
				tiles.mark(document.all_keys(),false)
				_status("Pattern preview applied · manual paint on the layer was preserved")
			else:
				var before := document.layers.duplicate()
				var previous := document.active_layer
				document.layers.insert(previous+1,result.layer)
				document.active_layer = previous+1
				history.push(document,{"kind":"layers","label":"Create pattern fill layer","before":before,"after":document.layers.duplicate(),"active_before":previous,"active_after":document.active_layer})
				tiles.mark(document.all_keys(),false)
				_status("Editable pattern layer created · change its transform in Pattern")
			_sync_pattern_inspector()
			_refresh_metadata()
		"selection":
			painter.selection = result.selection
			painter.selection_active = not selected_faces.is_empty()
			_show_selection()
		"operation":
			var command: Dictionary = result.command
			if command.after.is_empty():
				_status("No pixels changed.")
				return
			var bank: Dictionary = command.layer.masks if command.mask else command.layer.tiles
			for key in command.after:
				bank[key] = command.after[key].duplicate()
				command.layer.invalidate(key)
			history.push(document, command)
			var keys: Array[Vector2i] = []
			keys.assign(command.after.keys())
			tiles.mark(keys, false)
			_refresh_metadata()
			_status(command.label + " complete")
		"edges":
			var before := document.layers.duplicate()
			var previous := document.active_layer
			document.layers.append(result.layer)
			document.active_layer = document.layers.size() - 1
			history.push(document, {"kind": "layers", "label": "Edge highlights", "before": before, "after": document.layers.duplicate(), "active_before": previous, "active_after": document.active_layer})
			tiles.mark(document.all_keys(), false)
			_refresh_metadata()
			_status("Edge highlights added as an editable layer")
		"ao":
			if result.layer.tiles.is_empty():
				_status("No inward corners were found on this model.")
				return
			var before := document.layers.duplicate()
			var previous := document.active_layer
			document.layers.append(result.layer)
			document.active_layer = document.layers.size() - 1
			history.push(document, {"kind": "layers", "label": "Cavity AO", "before": before, "after": document.layers.duplicate(), "active_before": previous, "active_after": document.active_layer})
			tiles.mark(document.all_keys(), false)
			_apply_materials()
			_refresh_metadata()
			_status("Cavity AO baked on an editable Albedo layer · %d inner corners" % int(result.corners))
		"normal":
			if result.layer.tiles.is_empty():
				_status("Height map is flat; no Normal pixels were generated.")
				return
			var before := document.layers.duplicate()
			var previous := document.active_layer
			document.layers.append(result.layer)
			document.active_layer = document.layers.size() - 1
			history.push(document,{"kind":"layers","label":"Normal from Height","before":before,"after":document.layers.duplicate(),"active_before":previous,"active_after":document.active_layer})
			tiles.mark(document.all_keys(),false)
			_apply_materials()
			_refresh_metadata()
			_status("Normal map generated from Height · %d affected texels" % int(result.pixels))
		"layer_blur_preview":
			if result.get("cancelled",false) or result.has("error"):
				_blur_apply_when_ready = false
				return
			if _blur_job_layer_id != document.selected_layer().id:
				_blur_apply_when_ready = false
				if _blur_wanted_radius > 0: _preview_layer_blur()
				return
			if int(result.radius) != int(%Effects.get_node("BlurRadius").value):
				_preview_layer_blur()
				return
			if result.changed.is_empty():
				_blur_apply_when_ready = false
				_status("Blur did not change this layer.")
				return
			var target := _find_layer(result.layer_id)
			_blur_original_tiles = target.tiles.duplicate()
			_blur_changed = result.changed
			_blur_preview_layer_id = target.id
			target.tiles = result.tiles
			target._prepared.clear()
			tiles.mark(_blur_changed,false)
			_status("Blur preview · adjust Radius, Apply, or Cancel")
			if _blur_apply_when_ready: _apply_layer_blur()
		"ao_preview", "edges_preview":
			var effect_kind := "ao" if kind == "ao_preview" else "edges"
			if _geometry_requested_kind != effect_kind or _geometry_requested_signature != _geometry_job_signature:
				if not _geometry_requested_kind.is_empty(): _preview_geometry_effect(_geometry_requested_kind)
				return
			if result.layer.tiles.is_empty():
				_status("No geometry pixels were found for this effect.")
				return
			_geometry_preview_layer = result.layer
			_geometry_preview_kind = effect_kind
			_geometry_preview_signature = _geometry_job_signature.duplicate()
			document.layers.append(result.layer)
			var affected_keys: Array[Vector2i] = []
			affected_keys.assign(result.layer.tiles.keys())
			tiles.mark(affected_keys,false)
			_status("%s preview · change settings or click Bake/Generate to apply" % ("AO" if effect_kind == "ao" else "Edge"))

func _autosave() -> void:
	if document != null and not jobs.busy() and not painter.active and document.revision != document.saved_revision and document.revision != _last_saved_autosave_revision:
		_cancel_blur_preview()
		_cancel_geometry_preview()
		_sync_assets()
		jobs.start("autosave", ProjectIO.save_project.bind(document, ProjectSettings.globalize_path(_recovery_path)))

func _sync_assets() -> void:
	if document == null:
		return
	var settings: Dictionary = %Pattern.settings()
	document.pattern_settings = {"angle": settings.angle, "scale": settings.scale, "offset_x": settings.offset.x, "offset_y": settings.offset.y}

func _hover(hit: Dictionary, from_model := false) -> void:
	_cursor_hit = hit
	_cursor_from_model = from_model
	_refresh_cursor()

func _refresh_cursor() -> void:
	if document == null:
		return
	var resolution := Vector2(document.width, document.height)
	var brush_tool := painter.tool in ["brush", "eraser", "clone", "stencil", "line", "rect", "ellipse", "spray", "smudge", "blur"]
	var diameter: int = painter.footprint_size() if brush_tool else 1
	var rounded := (painter.shape == 1 or painter.tool == "spray") and painter.tool != "stencil" and brush_tool
	model_view.set_cursor(_cursor_hit, resolution, diameter, rounded, painter.mirror and brush_tool)
	var symmetry_hits: Array[Dictionary] = []
	if _cursor_from_model and not _cursor_hit.is_empty() and symmetry_axes != 0 and painter.tool in ["brush","eraser","stencil","spray","smudge","blur"]:
		for subset in range(1,8):
			if (subset & symmetry_axes) == subset:
				var reflected := document.geometry.mirrored_hit(_cursor_hit,subset)
				if not reflected.is_empty(): symmetry_hits.append(reflected)
	model_view.set_symmetry_preview(symmetry_hits)
	uv_canvas.set_cursor(_cursor_hit, diameter, rounded, painter.mirror and brush_tool)
	var face_under := int(_cursor_hit.get("face",-1))
	model_view.show_hover(face_under if painter.tool == "select" else -1,selection_mode)
	var current_stamp: Image
	if painter.tool == "stencil" and painter.stencil != null:
		current_stamp = painter.stamp_source_preview()
		if not _stamp_rotation_editing: %StampPanel.set_result_preview(painter.stamp_preview())
	if painter.tool == "spray" and not _cursor_hit.is_empty():
		model_view.set_stamp_preview(null,1,0.0)
		uv_canvas.set_stamp_preview(null,0.0)
		var island := document.geometry.islands[face_under] if _cursor_from_model and face_under >= 0 else -1
		var preview := painter.spray_preview(_cursor_hit.uv,island)
		if _spray_preview_texture == null or Vector2i(_spray_preview_texture.get_size()) != preview.get_size():
			_spray_preview_texture = ImageTexture.create_from_image(preview)
		else:
			_spray_preview_texture.update(preview)
		model_view.set_spray_preview(_spray_preview_texture)
		if painter.mirror:
			var pixel := Vector2i((_cursor_hit.uv*resolution).floor()).clamp(Vector2i.ZERO,Vector2i(resolution)-Vector2i.ONE)
			var mirror_uv := (Vector2(document.width-pixel.x-1,pixel.y)+Vector2.ONE*0.5)/resolution
			var mirrored := painter.spray_preview(mirror_uv,-1)
			if _spray_mirror_texture == null or Vector2i(_spray_mirror_texture.get_size()) != mirrored.get_size():
				_spray_mirror_texture = ImageTexture.create_from_image(mirrored)
			else: _spray_mirror_texture.update(mirrored)
			model_view.set_spray_mirror_preview(_spray_mirror_texture)
			uv_canvas.set_spray_preview(_spray_preview_texture,_spray_mirror_texture)
		else:
			model_view.set_spray_mirror_preview(null)
			uv_canvas.set_spray_preview(_spray_preview_texture)
	elif painter.tool == "stencil" and painter.stencil != null and not _cursor_hit.is_empty():
		if current_stamp != _stamp_source_image:
			_stamp_source_image = current_stamp
			_stamp_source_texture = ImageTexture.create_from_image(current_stamp)
		model_view.set_spray_preview(null)
		model_view.set_spray_mirror_preview(null)
		model_view.set_stamp_preview(_stamp_source_texture,painter.brush_size,painter.stencil_rotation)
		uv_canvas.set_spray_preview(null)
		uv_canvas.set_stamp_preview(_stamp_source_texture,painter.stencil_rotation)
	else:
		model_view.set_spray_preview(null)
		model_view.set_spray_mirror_preview(null)
		model_view.set_stamp_preview(null,1,0.0)
		uv_canvas.set_spray_preview(null)
		uv_canvas.set_stamp_preview(null,0.0)

func _status(text: String) -> void:
	%Status.text = text

func _message(text: String) -> void:
	%Message.dialog_text = text
	%Message.popup_centered()
	_status(text)

func _process(delta: float) -> void:
	if document != null and document.geometry != null and model_view.pbr_requested() and document.revision != _pbr_preview_revision and not jobs.busy() and not painter.active and tiles.is_settled():
		_pbr_preview_revision = document.revision
		jobs.start("pbr_preview",PBR_PREVIEW.build.bind(document.read_copy()))
	%JobBar.visible = jobs.busy()
	if jobs.busy():
		var state := jobs.progress.read()
		%JobText.text = state.message
		%JobProgress.value = state.value * 100
	_perf_clock += delta
	if _perf_clock > 0.5:
		_perf_clock = 0.0
		%Performance.text = "%d FPS  ·  paint %.1f ms  ·  compose %.1f ms  ·  undo %.1f MB" % [Engine.get_frames_per_second(), painter.last_work_ms, tiles.last_work_ms, history.memory_bytes / 1048576.0]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_N: _action("New")
			KEY_O: _action("Open")
			KEY_S: _action("SaveAs" if event.shift_pressed else "Save")
			KEY_Z: _action("Redo" if event.shift_pressed else "Undo")
			KEY_Y: _action("Redo")
			KEY_E: _action("Export")
			KEY_PERIOD: _resize_selection(true)
			KEY_COMMA: _resize_selection(false)
	else:
		var keys := {KEY_B: "brush", KEY_A: "spray", KEY_U:"smudge", KEY_V:"blur", KEY_E: "eraser", KEY_I: "picker", KEY_F: "fill", KEY_S: "select", KEY_L: "line", KEY_R: "rect", KEY_O: "ellipse", KEY_G: "gradient", KEY_T: "stencil", KEY_P: "texture", KEY_C: "clone"}
		if keys.has(event.keycode):
			%ToolBar.select(keys[event.keycode])
		elif event.keycode == KEY_ESCAPE:
			_clear_selection()
		elif event.keycode == KEY_F2: %Layers.rename_active()
		elif event.keycode == KEY_BRACKETLEFT:
			%ToolOptions.get_node("Size").set_value(painter.brush_size - 1)
		elif event.keycode == KEY_BRACKETRIGHT:
			%ToolOptions.get_node("Size").set_value(painter.brush_size + 1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_action("Quit")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed and not event.meta_pressed and event.keycode == KEY_F:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB and not get_viewport().gui_get_focus_owner() is LineEdit:
		model_view.toggle_wires()
		get_viewport().set_input_as_handled()

func _toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = _mode_before_fullscreen
	else:
		_mode_before_fullscreen = window.mode
		window.mode = Window.MODE_FULLSCREEN

func _restore_layout() -> void:
	if not settings_enabled: return
	_restoring_preferences = true
	%MainDock.split_offset = clampi(int(_preferences.get_setting("panels","palette_offset",-170)),-8192,-90)
	%MainSplit.split_offset = clampi(int(_preferences.get_setting("panels","inspector_offset",-320)),-8192,-300)
	_restoring_preferences = false

func _save_layout() -> void:
	_queue_preferences_save()

func _restore_preferences() -> void:
	_restoring_preferences = true
	_last_project_path = str(_preferences.get_setting("files","last_project",""))
	_reopen_last = bool(_preferences.get_setting("files","reopen_on_start",true))
	_saved_stamp_view_path = str(_preferences.get_setting("view","stamp_preview_path",""))
	var stored_stamp_view: Variant = _preferences.get_setting("view","stamp_preview",{})
	_saved_stamp_view = stored_stamp_view if stored_stamp_view is Dictionary else {}
	var compact := bool(_preferences.get_setting("view","compact_toolbar",true))
	%ToolBar.get_node("Compact").set_pressed_no_signal(compact)
	%ToolBar.set_compact(compact)
	var show_uv := bool(_preferences.get_setting("view","uv_panel",true))
	%UVView.set_pressed_no_signal(show_uv)
	%UVPane.visible = show_uv
	%UVFrame.visible = show_uv
	var show_uv_lines := bool(_preferences.get_setting("view","uv_wires",true))
	%WireUV.set_pressed_no_signal(show_uv_lines)
	uv_canvas.show_uv = show_uv_lines
	uv_canvas.queue_redraw()
	model_view.restore_view(bool(_preferences.get_setting("view","model_wires",false)),bool(_preferences.get_setting("view","orthographic",false)),bool(_preferences.get_setting("view","light",false)))
	var saved_background: Variant = _preferences.get_setting("view","model_background",Color(0.15,0.15,0.15))
	if saved_background is Color: model_view.set_background_color(saved_background)
	selection_mode = clampi(int(_preferences.get_setting("view","selection_mode",0)),0,3)
	%Layers.get_node("SelectionMode").select(selection_mode)
	%ToolOptions.get_node("Size").set_value(float(_preferences.get_setting("brush","size",4)),false)
	painter.brush_size = int(%ToolOptions.get_node("Size").value)
	%ToolOptions.get_node("Opacity").set_value(float(_preferences.get_setting("brush","opacity",100)),false)
	%SprayOptions.get_node("Opacity").set_value(%ToolOptions.get_node("Opacity").value,false)
	painter.opacity = %ToolOptions.get_node("Opacity").value/100.0
	%ToolOptions.get_node("Falloff").set_value(float(_preferences.get_setting("brush","falloff",0)),false)
	painter.falloff = %ToolOptions.get_node("Falloff").value/100.0
	painter.shape = clampi(int(_preferences.get_setting("brush","shape",0)),0,1)
	%ToolOptions.set_shape(painter.shape)
	painter.dither = bool(_preferences.get_setting("brush","dither",false))
	%ToolOptions.get_node("Dither").set_pressed_no_signal(painter.dither)
	painter.mirror = bool(_preferences.get_setting("brush","mirror",false))
	%ToolOptions.get_node("Mirror").set_pressed_no_signal(painter.mirror)
	symmetry_axes = clampi(int(_preferences.get_setting("brush","symmetry_axes",0)),0,7)
	%ToolOptions.set_symmetry_axes(symmetry_axes)
	fill_tolerance = clampf(float(_preferences.get_setting("fill","tolerance",0.0)),0.0,1.0)
	fill_contiguous = bool(_preferences.get_setting("fill","contiguous",true))
	%ToolOptions.get_node("Tolerance").set_value(fill_tolerance*100.0,false)
	%ToolOptions.get_node("Contiguous").set_pressed_no_signal(fill_contiguous)
	%ToolOptions.get_node("Length").set_value(float(_preferences.get_setting("brush","gradient_length",7)),false)
	gradient_length = int(%ToolOptions.get_node("Length").value)
	%SprayOptions.get_node("Flow").set_value(float(_preferences.get_setting("spray","flow",10)),false)
	painter.spray_flow = %SprayOptions.get_node("Flow").value/100.0
	%SprayOptions.get_node("Particles").set_value(float(_preferences.get_setting("spray","density",12)),false)
	painter.spray_particles = int(%SprayOptions.get_node("Particles").value)
	%SprayOptions.get_node("Spacing").set_value(float(_preferences.get_setting("spray","spacing",4)),false)
	painter.spray_spacing = %SprayOptions.get_node("Spacing").value
	%SprayOptions.get_node("Rate").set_value(float(_preferences.get_setting("spray","rate",20)),false)
	painter.spray_rate = %SprayOptions.get_node("Rate").value
	%SprayOptions.get_node("Distance").set_value(float(_preferences.get_setting("spray","distance",100)),false)
	painter.spray_distance = %SprayOptions.get_node("Distance").value/100.0
	var last_tool := str(_preferences.get_setting("brush","tool","brush"))
	%ToolBar.select(last_tool if last_tool in %ToolBar.TOOLS else "brush")
	for field in ["EdgeWidth", "AOStrength", "AORadius", "AODepth", "NormalStrength", "BlurRadius"]:
		var control: NumberField = %Effects.get_node(field)
		control.set_value(float(_preferences.get_setting("inspector",field,control.value)),false)
	%Effects.get_node("AOFalloff").select(clampi(int(_preferences.get_setting("inspector","AOFalloff",1)),0,2))
	var expanded: Variant = _preferences.get_setting("inspector","expanded_effects",{})
	%Effects.restore_sections(expanded if expanded is Dictionary else {})
	for field in ["Angle", "Padding", "MoveStep", "Scale"]:
		var control: NumberField = %UV.get_node(field)
		control.set_value(float(_preferences.get_setting("uv",field,control.value)),false)
	%Inspector.current_tab = clampi(int(_preferences.get_setting("view","inspector_tab",%Inspector.current_tab)),0,%Inspector.get_tab_count()-1)
	_restoring_preferences = false

func _remember_project(path: String) -> void:
	if path.is_empty(): return
	_last_project_path = path
	_save_preferences()
	_refresh_metadata()

func _queue_preferences_save() -> void:
	if settings_enabled and not _restoring_preferences and is_node_ready():
		%PreferencesSave.start()

func _save_preferences() -> void:
	if not settings_enabled or not is_node_ready(): return
	_preferences.set_setting("files","last_project",_last_project_path)
	_preferences.set_setting("files","reopen_on_start",_reopen_last)
	_preferences.set_setting("view","compact_toolbar",%ToolBar.get_node("Compact").button_pressed)
	_preferences.set_setting("view","uv_panel",%UVView.button_pressed)
	_preferences.set_setting("view","uv_wires",%WireUV.button_pressed)
	_preferences.set_setting("view","model_wires",model_view.get_node("Header/Wires").button_pressed)
	_preferences.set_setting("view","orthographic",model_view.get_node("Header/Ortho").button_pressed)
	_preferences.set_setting("view","light",model_view.get_node("Header/Light").button_pressed)
	_preferences.set_setting("view","model_background",model_view.background_color())
	_preferences.set_setting("view","selection_mode",selection_mode)
	_preferences.set_setting("view","inspector_tab",%Inspector.current_tab)
	if document != null and not document.path.is_empty() and document.path == _last_project_path:
		_saved_stamp_view_path = document.path
		_saved_stamp_view = %StampPanel.view_state()
	_preferences.set_setting("view","stamp_preview_path",_saved_stamp_view_path)
	_preferences.set_setting("view","stamp_preview",_saved_stamp_view)
	_preferences.set_setting("panels","palette_offset",%MainDock.split_offset)
	_preferences.set_setting("panels","inspector_offset",%MainSplit.split_offset)
	_preferences.set_setting("brush","tool",painter.tool)
	_preferences.set_setting("brush","size",painter.brush_size)
	_preferences.set_setting("brush","opacity",%ToolOptions.get_node("Opacity").value)
	_preferences.set_setting("brush","falloff",%ToolOptions.get_node("Falloff").value)
	_preferences.set_setting("brush","shape",painter.shape)
	_preferences.set_setting("brush","dither",painter.dither)
	_preferences.set_setting("brush","mirror",painter.mirror)
	_preferences.set_setting("brush","symmetry_axes",symmetry_axes)
	_preferences.set_setting("fill","tolerance",fill_tolerance)
	_preferences.set_setting("fill","contiguous",fill_contiguous)
	_preferences.set_setting("brush","gradient_length",gradient_length)
	_preferences.set_setting("spray","flow",%SprayOptions.get_node("Flow").value)
	_preferences.set_setting("spray","density",painter.spray_particles)
	_preferences.set_setting("spray","spacing",painter.spray_spacing)
	_preferences.set_setting("spray","rate",painter.spray_rate)
	_preferences.set_setting("spray","distance",%SprayOptions.get_node("Distance").value)
	for field in ["EdgeWidth", "AOStrength", "AORadius", "AODepth", "NormalStrength", "BlurRadius"]:
		_preferences.set_setting("inspector",field,%Effects.get_node(field).value)
	_preferences.set_setting("inspector","AOFalloff",%Effects.get_node("AOFalloff").selected)
	_preferences.set_setting("inspector","expanded_effects",%Effects.open_sections())
	for field in ["Angle", "Padding", "MoveStep", "Scale"]:
		_preferences.set_setting("uv",field,%UV.get_node(field).value)
	var error := _preferences.save_settings()
	if error != OK: _status("Could not save painter settings: " + error_string(error))
