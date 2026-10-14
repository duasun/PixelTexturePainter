class_name StampCropPreview
extends Control

signal region_previewed(region: Rect2i)
signal region_committed(region: Rect2i)
signal navigation_changed

var source: Image
var texture: ImageTexture
var region := Rect2i()
var _dragging := false
var _panning := false
var _start_pixel := Vector2i.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO

const MIN_ZOOM := 0.25
const MAX_ZOOM := 128.0
const ZOOM_STEP := 1.25

func set_source(image: Image, selected: Rect2i) -> void:
	if source != image:
		source = image
		texture = ImageTexture.create_from_image(image) if image != null else null
		_zoom = 1.0
		_pan = Vector2.ZERO
		_dragging = false
		_panning = false
	region = selected
	queue_redraw()

func _image_rect() -> Rect2:
	if source == null: return Rect2()
	var available := (size - Vector2(16, 16)).max(Vector2.ONE)
	var image_scale := minf(available.x / source.get_width(), available.y / source.get_height()) * _zoom
	var extent := Vector2(source.get_size()) * image_scale
	return Rect2((size - extent) * 0.5 + _pan, extent)

func _constrain_pan() -> void:
	if source == null: return
	var bounds := _image_rect()
	var minimum_visible := 24.0
	for axis in 2:
		if bounds.position[axis] > size[axis] - minimum_visible:
			_pan[axis] -= bounds.position[axis] - (size[axis] - minimum_visible)
		elif bounds.end[axis] < minimum_visible:
			_pan[axis] += minimum_visible - bounds.end[axis]

func view_state() -> Dictionary:
	if source == null: return {}
	var bounds := _image_rect()
	var center := (size * 0.5 - bounds.position) / bounds.size
	return {"zoom": _zoom, "center_x": center.x, "center_y": center.y}

func restore_view_state(state: Dictionary) -> void:
	if source == null or state.is_empty(): return
	_zoom = clampf(float(state.get("zoom", 1.0)), MIN_ZOOM, MAX_ZOOM)
	var available := (size - Vector2(16, 16)).max(Vector2.ONE)
	var image_scale := minf(available.x / source.get_width(), available.y / source.get_height()) * _zoom
	var extent := Vector2(source.get_size()) * image_scale
	var center := Vector2(clampf(float(state.get("center_x", 0.5)), -1.0, 2.0), clampf(float(state.get("center_y", 0.5)), -1.0, 2.0))
	_pan = size * 0.5 - center * extent - (size - extent) * 0.5
	_constrain_pan()
	queue_redraw()

func _zoom_at(point: Vector2, factor: float) -> void:
	var old_bounds := _image_rect()
	var anchor := point if old_bounds.has_point(point) else old_bounds.get_center()
	var uv := (anchor - old_bounds.position) / old_bounds.size
	var next_zoom := clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(next_zoom, _zoom): return
	_zoom = next_zoom
	# Recompute from the fitted dimensions to avoid accumulating rounding error.
	var available := (size - Vector2(16, 16)).max(Vector2.ONE)
	var image_scale := minf(available.x / source.get_width(), available.y / source.get_height()) * _zoom
	var new_extent := Vector2(source.get_size()) * image_scale
	_pan = anchor - uv * new_extent - (size - new_extent) * 0.5
	_constrain_pan()
	queue_redraw()
	navigation_changed.emit()

func _pixel_at(point: Vector2) -> Vector2i:
	var bounds := _image_rect()
	var uv := (point - bounds.position) / bounds.size
	return Vector2i(clampi(floori(uv.x * source.get_width()), 0, source.get_width() - 1), clampi(floori(uv.y * source.get_height()), 0, source.get_height() - 1))

func _selection_to(point: Vector2) -> Rect2i:
	var last := _pixel_at(point)
	var first := Vector2i(mini(_start_pixel.x, last.x), mini(_start_pixel.y, last.y))
	var end := Vector2i(maxi(_start_pixel.x, last.x), maxi(_start_pixel.y, last.y)) + Vector2i.ONE
	return Rect2i(first, end - first)

func _gui_input(event: InputEvent) -> void:
	if source == null:
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(event.position, ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if not _dragging:
				_panning = event.pressed
				accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and not _panning:
			if event.pressed and _image_rect().has_point(event.position):
				_dragging = true
				_start_pixel = _pixel_at(event.position)
				region = Rect2i(_start_pixel, Vector2i.ONE)
				region_previewed.emit(region)
				queue_redraw()
				accept_event()
			elif not event.pressed and _dragging:
				_dragging = false
				region = _selection_to(event.position)
				region_committed.emit(region)
				queue_redraw()
				accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			_constrain_pan()
			queue_redraw()
			navigation_changed.emit()
			accept_event()
		elif _dragging:
			region = _selection_to(event.position)
			region_previewed.emit(region)
			queue_redraw()
			accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.13, 0.13), true)
	if texture == null:
		return
	var bounds := _image_rect()
	var visible_area := bounds.intersection(Rect2(Vector2.ZERO, size))
	var checker := 12.0
	var left := floori((visible_area.position.x - bounds.position.x) / checker)
	var right := ceili((visible_area.end.x - bounds.position.x) / checker)
	var top := floori((visible_area.position.y - bounds.position.y) / checker)
	var bottom := ceili((visible_area.end.y - bounds.position.y) / checker)
	for y in range(top, bottom):
		for x in range(left, right):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(bounds.position + Vector2(x, y) * checker, Vector2.ONE * checker).intersection(visible_area), Color(0.30, 0.30, 0.30), true)
	draw_texture_rect(texture, bounds, false)
	var image_scale := bounds.size / Vector2(source.get_size())
	var selected := Rect2(bounds.position + Vector2(region.position) * image_scale, Vector2(region.size) * image_scale)
	draw_rect(selected, Color(0.96, 0.59, 0.25, 0.17), true)
	draw_rect(selected, Color(1.0, 0.67, 0.31), false, 2.0)
	draw_rect(bounds, Color(0.56, 0.56, 0.56), false, 1.0)
