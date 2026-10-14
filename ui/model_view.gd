class_name ModelView
extends VBoxContainer
signal surface_event(phase: String, hit: Dictionary, modifiers: int)
signal gesture_motion(delta: Vector2)
signal hovered(hit: Dictionary)
signal history_requested(action: String)
var geometry: ModelGeometry
var display_material: ShaderMaterial
var yaw := 0.55
var pitch := 0.3
var distance := 5.5
var target := Vector3.ZERO
var _orbit := false
var _pan := false
var _painting := false
var _gesture_candidate := false
var interpolate_strokes := true
var _previous := Vector2.ZERO
var _marker_position: Variant = null
var _hover_key := Vector2i(-2,-2)
@onready var display: SubViewportContainer = $Display
@onready var viewport: SubViewport = $Display/Viewport
@onready var camera: Camera3D = $Display/Viewport/World/Camera
@onready var model: MeshInstance3D = $Display/Viewport/World/Model
@onready var overlay: MeshInstance3D = $Display/Viewport/World/Selection

func _ready() -> void:
	display_material = ShaderMaterial.new()
	display_material.shader = preload("res://shaders/model.gdshader")
	model.material_override = display_material
	display.gui_input.connect(_input_display)
	display.resized.connect(func(): _place_marker.call_deferred())
	$Header/Undo.pressed.connect(func(): history_requested.emit("Undo"))
	$Header/Redo.pressed.connect(func(): history_requested.emit("Redo"))
	$Header/Frame.pressed.connect(frame_model)
	$Header/Wires.toggled.connect(func(on: bool): $Display/Viewport/World/Wires.visible = on)
	$Header/Light.toggled.connect(func(on: bool): display_material.set_shader_parameter("shaded", on))
	$Header/Light.toggled.connect(func(on: bool):
		display_material.set_shader_parameter("pbr_enabled",on and _pbr_ready))
	$Header/Ortho.toggled.connect(func(on: bool):
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL if on else Camera3D.PROJECTION_PERSPECTIVE
		_update_camera())
	display.mouse_exited.connect(func(): hovered.emit({}))
	_update_camera()

func set_history_available(can_undo: bool, can_redo: bool) -> void:
	$Header/Undo.disabled = not can_undo
	$Header/Redo.disabled = not can_redo

func set_geometry(data: ModelGeometry) -> void:
	geometry = data
	model.mesh = data.to_mesh()
	overlay.mesh = null
	var faces := PackedInt32Array()
	for face in data.face_count(): faces.append(face)
	$Display/Viewport/World/Wires.mesh = _overlay_mesh(faces)
	$Display/Viewport/World/Hover.mesh = null
	_hover_key = Vector2i(-2,-2)
	frame_model()
	$Header/Title.text = "%s · %d tris" % [data.label, data.face_count()]
	_pbr_ready = false
	display_material.set_shader_parameter("pbr_enabled",false)

var _pbr_ready := false
func pbr_requested() -> bool:
	return $Header/Light.button_pressed

func set_pbr_maps(maps: Dictionary) -> void:
	for channel in maps:
		display_material.set_shader_parameter("pbr_"+channel,ImageTexture.create_from_image(maps[channel]))
	_pbr_ready = true
	display_material.set_shader_parameter("pbr_enabled",pbr_requested())

func frame_model() -> void:
	if geometry != null:
		target = geometry.bounds.get_center()
		distance = maxf(geometry.bounds.size.length() * 1.15, 0.1)
	_update_camera()

func restore_view(wires: bool, orthographic: bool, light: bool) -> void:
	$Header/Wires.set_pressed_no_signal(wires)
	$Display/Viewport/World/Wires.visible = wires
	$Header/Ortho.set_pressed_no_signal(orthographic)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if orthographic else Camera3D.PROJECTION_PERSPECTIVE
	$Header/Light.set_pressed_no_signal(light)
	display_material.set_shader_parameter("shaded", light)
	display_material.set_shader_parameter("pbr_enabled",light and _pbr_ready)
	_update_camera()

func _update_camera() -> void:
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = target + direction * distance
	camera.look_at(target)
	camera.size = distance * 0.8
	camera.near = maxf(0.001, distance * 0.001)
	camera.far = maxf(100.0, distance * 100.0)
	if display.get_global_rect().has_point(get_global_mouse_position()):
		hovered.emit(_hit(display.get_local_mouse_position()))

func set_cursor(hit: Dictionary, resolution: Vector2, diameter: int, rounded: bool, mirrored: bool) -> void:
	display_material.set_shader_parameter("cursor_visible", not hit.is_empty() and geometry != null and geometry.has_uv)
	_marker_position = hit.get("position")
	_place_marker()
	if hit.is_empty():
		return
	display_material.set_shader_parameter("cursor_pixel", (hit.uv * resolution).floor().clamp(Vector2.ZERO, resolution - Vector2.ONE))
	display_material.set_shader_parameter("cursor_size", float(diameter))
	display_material.set_shader_parameter("cursor_round", rounded)
	display_material.set_shader_parameter("cursor_mirror", mirrored)
	var face := int(hit.get("face", -1))
	display_material.set_shader_parameter("cursor_island", float(geometry.islands[face]) if face >= 0 else -1.0)

func set_symmetry_preview(hits: Array[Dictionary]) -> void:
	var points := PackedVector2Array()
	for hit in hits:
		if hit.is_empty(): continue
		var point: Vector3 = hit.position
		if camera.is_position_behind(point): continue
		points.append(camera.unproject_position(point))
	$Display/SymmetryPreview.show_points(points)

func set_shape_preview(start: Vector2i, finish: Vector2i, kind: String, diameter: int, island: int) -> void:
	display_material.set_shader_parameter("shape_preview_mode", ["", "line", "rect", "ellipse"].find(kind))
	if kind.is_empty(): return
	display_material.set_shader_parameter("shape_preview_start", Vector2(start))
	display_material.set_shader_parameter("shape_preview_end", Vector2(finish))
	display_material.set_shader_parameter("shape_preview_size", float(diameter))
	display_material.set_shader_parameter("shape_preview_island", float(island))

func _place_marker() -> void:
	$Display/CursorMarker.show_at(camera.unproject_position(_marker_position) if _marker_position != null else Vector2(-10000, -10000))

func _hit(point: Vector2) -> Dictionary:
	if geometry == null:
		return {}
	return geometry.ray_hit(camera.project_ray_origin(point), camera.project_ray_normal(point))

func _input_display(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		hovered.emit(_hit(event.position))
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = maxf(0.01, distance * 0.9)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = minf(100000.0, distance / 0.9)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_painting = event.pressed
			if event.pressed:
				_gesture_candidate = event.ctrl_pressed or event.alt_pressed
			_previous = event.position
			surface_event.emit("begin" if event.pressed else "end", _hit(event.position), (1 if event.shift_pressed else 0) + (2 if event.ctrl_pressed else 0) + (4 if event.alt_pressed else 0))
			if not event.pressed:
				_gesture_candidate = false
		display.accept_event()
	elif event is InputEventMouseMotion:
		if _orbit:
			yaw -= event.relative.x * 0.008
			pitch = clampf(pitch + event.relative.y * 0.008, -1.5, 1.5)
			_update_camera()
		elif _pan:
			target += (-camera.basis.x * event.relative.x + camera.basis.y * event.relative.y) * distance * 0.0015
			_update_camera()
		else:
			var hit := _hit(event.position)
			hovered.emit(hit)
			if _painting:
				if _gesture_candidate:
					gesture_motion.emit(event.relative)
				elif not interpolate_strokes:
					surface_event.emit("move", hit, 4 if event.alt_pressed else 0)
				else:
					# Sample the screen path, not a straight UV segment across disconnected islands.
					var steps := clampi(ceili(_previous.distance_to(event.position) / 3.0), 1, 64)
					for i in range(1, steps + 1):
						surface_event.emit("move", _hit(_previous.lerp(event.position, i / float(steps))), 4 if event.alt_pressed else 0)
			_previous = event.position

func show_selection(faces: PackedInt32Array) -> void:
	overlay.mesh = _overlay_mesh(faces)

func toggle_wires() -> void:
	$Header/Wires.button_pressed = not $Header/Wires.button_pressed

func set_channel(channel: String) -> void:
	display_material.set_shader_parameter("shaded",channel == "albedo" and $Header/Light.button_pressed)

func show_hover(face: int, mode: int) -> void:
	var group := face
	if geometry != null and face >= 0 and face < geometry.face_count():
		if mode == 0: group = geometry.islands[face]
		elif mode == 2: group = geometry.objects[face]
		elif mode == 3: group = geometry.materials[face]
	var key := Vector2i(group,mode)
	if key == _hover_key: return
	_hover_key = key
	var faces := PackedInt32Array()
	if geometry != null and face >= 0 and face < geometry.face_count():
		for f in geometry.face_count():
			if (mode == 0 and geometry.islands[f] == geometry.islands[face]) or (mode == 1 and f == face) or (mode == 2 and geometry.objects[f] == geometry.objects[face]) or (mode == 3 and geometry.materials[f] == geometry.materials[face]): faces.append(f)
	$Display/Viewport/World/Hover.mesh = _overlay_mesh(faces)

func _overlay_mesh(faces: PackedInt32Array) -> ImmediateMesh:
	if geometry == null or faces.is_empty():
		return null
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var offset := maxf(geometry.bounds.size.length() * 0.00003, 0.000001)
	for f in faces:
		for c in 3:
			mesh.surface_set_color([Color.RED, Color.GREEN, Color.BLUE][c])
			mesh.surface_add_vertex(geometry.positions[f * 3 + c] + geometry.face_normals[f] * offset)
	mesh.surface_end()
	return mesh

func set_spray_preview(texture: Texture2D) -> void:
	display_material.set_shader_parameter("spray_preview_enabled", texture != null)
	if texture != null: display_material.set_shader_parameter("spray_preview",texture)

func set_spray_mirror_preview(texture: Texture2D) -> void:
	display_material.set_shader_parameter("spray_mirror_enabled",texture != null)
	if texture != null: display_material.set_shader_parameter("spray_mirror",texture)
