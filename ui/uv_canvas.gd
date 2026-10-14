class_name UVCanvas
extends Control
signal surface_event(phase: String, hit: Dictionary, modifiers: int)
signal gesture_motion(delta: Vector2)
signal hovered(hit: Dictionary)
var document: PaintDocument
var display_material: ShaderMaterial
var zoom := 2.0
var pan := Vector2.ZERO
var brush_size := 4
var round_brush := false
var mirror_cursor := false
var _cursor_hit: Dictionary = {}
var _outline := PackedVector2Array()
var _outline_size := -1
var _outline_round := false
var show_uv := true
var show_grid := true
var selected_faces := PackedInt32Array()
var spray_preview_texture: Texture2D
var spray_mirror_texture: Texture2D
var stamp_preview_texture: Texture2D
var stamp_preview_angle := 0.0
var shape_preview_kind := ""
var shape_preview_start := Vector2i.ZERO
var shape_preview_end := Vector2i.ZERO
var shape_preview_size := 1
var _lines := PackedVector2Array()
var _pan_active := false
var _painting := false
var _gesture_candidate := false
var _mouse := Vector2(-10000, -10000)
@onready var texture_rect: TextureRect = $Texture

func _ready() -> void:
	display_material = ShaderMaterial.new()
	display_material.shader = preload("res://shaders/canvas.gdshader")
	texture_rect.material = display_material
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture_rect.texture = ImageTexture.create_from_image(img)
	resized.connect(_layout)
	mouse_exited.connect(func(): _mouse = Vector2(-10000, -10000); hovered.emit({}))

func set_cursor(hit: Dictionary, diameter: int, rounded: bool, mirrored: bool) -> void:
	_cursor_hit = hit
	brush_size = diameter
	round_brush = rounded
	mirror_cursor = mirrored
	queue_redraw()

func set_spray_preview(texture: Texture2D, mirrored: Texture2D = null) -> void:
	spray_preview_texture = texture
	spray_mirror_texture = mirrored
	queue_redraw()

func set_stamp_preview(texture: Texture2D, angle: float) -> void:
	stamp_preview_texture = texture
	stamp_preview_angle = angle
	queue_redraw()

func set_shape_preview(start: Vector2i, finish: Vector2i, kind: String, diameter: int) -> void:
	shape_preview_start = start
	shape_preview_end = finish
	shape_preview_kind = kind
	shape_preview_size = diameter
	display_material.set_shader_parameter("shape_preview_mode",["", "line", "rect", "ellipse"].find(kind))
	if not kind.is_empty():
		display_material.set_shader_parameter("shape_preview_start",Vector2(start))
		display_material.set_shader_parameter("shape_preview_end",Vector2(finish))
		display_material.set_shader_parameter("shape_preview_size",float(diameter))
	queue_redraw()

func setup(doc: PaintDocument) -> void:
	document = doc
	selected_faces.clear()
	fit()

func fit() -> void:
	if document == null:
		return
	zoom = minf((size.x - 40) / document.width, (size.y - 40) / document.height)
	pan = Vector2.ZERO
	_layout()

func _origin() -> Vector2:
	if document == null:
		return Vector2.ZERO
	return (size - Vector2(document.width, document.height) * zoom) * 0.5 + pan

func _layout() -> void:
	if not is_node_ready() or document == null:
		return
	texture_rect.position = _origin()
	texture_rect.size = Vector2(document.width, document.height) * zoom
	_lines.clear()
	if document.geometry != null:
		var uv := document.geometry.uvs
		var factor := Vector2(document.width, document.height) * zoom
		for i in range(0, uv.size(), 3):
			for e in 3:
				_lines.append(_origin() + uv[i + e] * factor)
				_lines.append(_origin() + uv[i + (e + 1) % 3] * factor)
	queue_redraw()

func _hit(point: Vector2) -> Dictionary:
	if document == null:
		return {}
	var uv := (point - _origin()) / (Vector2(document.width, document.height) * zoom)
	if uv.x < 0 or uv.y < 0 or uv.x >= 1 or uv.y >= 1:
		return {}
	return {"uv": uv, "face": -1, "island": -1}

func _gui_input(event: InputEvent) -> void:
	if document == null:
		return
	if event is InputEventMouseButton:
		_mouse = event.position
		hovered.emit(_hit(_mouse))
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_pan_active = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var at: Vector2 = (event.position - _origin()) / zoom
			zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.02, 64.0)
			pan = event.position - at * zoom - (size - Vector2(document.width, document.height) * zoom) * 0.5
			_layout()
			hovered.emit(_hit(_mouse))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_painting = event.pressed
			if event.pressed:
				_gesture_candidate = event.ctrl_pressed or event.alt_pressed
			surface_event.emit("begin" if event.pressed else "end", _hit(event.position), (1 if event.shift_pressed else 0) + (2 if event.ctrl_pressed else 0) + (4 if event.alt_pressed else 0))
			if not event.pressed:
				_gesture_candidate = false
		accept_event()
	elif event is InputEventMouseMotion:
		_mouse = event.position
		if _pan_active:
			pan += event.relative
			_layout()
			hovered.emit(_hit(_mouse))
		else:
			var hit := _hit(event.position)
			hovered.emit(hit)
			if _painting:
				if _gesture_candidate:
					gesture_motion.emit(event.relative)
				else:
					surface_event.emit("move", hit, 4 if event.alt_pressed else 0)
		queue_redraw()

func _draw() -> void:
	if document == null:
		return
	var origin := _origin()
	var extent := Vector2(document.width, document.height) * zoom
	draw_rect(Rect2(origin - Vector2.ONE, extent + Vector2.ONE * 2), Color("566174"), false)
	if show_grid and zoom >= 10.0:
		var grid := PackedVector2Array()
		for x in range(maxi(0, floori(-origin.x / zoom)), mini(document.width, ceili((size.x - origin.x) / zoom)) + 1):
			grid.append(Vector2(origin.x + x * zoom, origin.y))
			grid.append(Vector2(origin.x + x * zoom, origin.y + extent.y))
		for y in range(maxi(0, floori(-origin.y / zoom)), mini(document.height, ceili((size.y - origin.y) / zoom)) + 1):
			grid.append(Vector2(origin.x, origin.y + y * zoom))
			grid.append(Vector2(origin.x + extent.x, origin.y + y * zoom))
		draw_multiline(grid, Color(0.05, 0.1, 0.15, 0.25), 1.0)
	if show_uv and not _lines.is_empty():
		draw_multiline(_lines, Color(0.5, 0.8, 0.8, 0.35), 1.0)
	if document.geometry != null:
		for face in selected_faces:
			var points := PackedVector2Array()
			for c in 3:
				points.append(origin + document.geometry.uvs[face * 3 + c] * extent)
			draw_colored_polygon(points, Color(1.0, 0.61, 0.08, 0.24))
			points.append(points[0])
			draw_polyline(points, Color(0.025, 0.025, 0.025, 0.95), 5.0)
			draw_polyline(points, Color(1.0, 0.91, 0.24), 2.0)
	var hit := _cursor_hit
	if not hit.is_empty():
		var p: Vector2 = (hit.uv * Vector2(document.width, document.height)).floor().clamp(Vector2.ZERO, Vector2(document.width - 1, document.height - 1))
		_draw_cursor_at(origin, p)
		if mirror_cursor:
			_draw_cursor_at(origin, Vector2(document.width - p.x - 1, p.y),true)
		var center := origin + (p + Vector2.ONE * 0.5) * zoom
		var cross := PackedVector2Array([center - Vector2(9, 0), center - Vector2(3, 0), center + Vector2(3, 0), center + Vector2(9, 0), center - Vector2(0, 9), center - Vector2(0, 3), center + Vector2(0, 3), center + Vector2(0, 9)])
		draw_multiline(cross, Color.BLACK, 3.0)
		draw_multiline(cross, Color("ffbe61"), 1.0)
		if zoom >= 4.0:
			draw_rect(Rect2(origin + p * zoom, Vector2.ONE * zoom), Color("ffbe61"), false, 1.0)

func _draw_cursor_at(origin: Vector2, pixel: Vector2, mirrored := false) -> void:
	var preview := spray_mirror_texture if mirrored else spray_preview_texture
	if preview != null:
		var preview_position := origin + (pixel-Vector2.ONE*floorf(brush_size/2.0))*zoom
		draw_texture_rect(preview,Rect2(preview_position,Vector2.ONE*brush_size*zoom),false)
	elif stamp_preview_texture != null:
		var center := origin + (pixel+Vector2.ONE*float(brush_size%2)*0.5)*zoom
		var extent := Vector2(stamp_preview_texture.get_size())*zoom
		draw_set_transform(center,deg_to_rad(stamp_preview_angle))
		draw_texture_rect(stamp_preview_texture,Rect2(-extent*0.5,extent),false)
		draw_set_transform(Vector2.ZERO)
	if _outline_size != brush_size or _outline_round != round_brush:
		_outline = BrushFootprint.outline(brush_size, round_brush)
		_outline_size = brush_size
		_outline_round = round_brush
	var points := PackedVector2Array()
	var offset := origin + (pixel - Vector2.ONE * floorf(brush_size / 2.0)) * zoom
	for point in _outline:
		points.append(offset + point * zoom)
	draw_multiline(points, Color(0.0, 0.0, 0.0, 0.95), 3.0)
	draw_multiline(points, Color("dcfffa"), 1.0)
