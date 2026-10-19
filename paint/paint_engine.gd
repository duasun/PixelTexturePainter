class_name PaintEngine
extends Node
signal tiles_changed(keys: Array[Vector2i])
signal stroke_committed
signal preview_changed
var document: PaintDocument
var history: PaintHistory
var tool := "brush"
var color := Color("eea765")
var brush_size := 4
var opacity := 1.0
var falloff := 0.0
var shape := 0
var dither := false
var selection: Dictionary = {}
var selection_active := false
var selection_bounds: Dictionary = {}
var edge_wrap := false
var edge_wrap_faces: Dictionary = {}
var edge_wrap_camera_position := Vector3.ZERO
var edge_wrap_visible_only := false
var stencil: Image
var brush_tip: Image
var brush_angle := 0.0
var _stroke_brush_tip: Image
var _stroke_brush_angle := 0.0
var stencil_region := Rect2i()
var stencil_rotation := 0.0
var _cached_stencil: Image
var _cached_stencil_region := Rect2i()
var _cached_stencil_size := -1
var _cached_stencil_rotation := -1.0
var _cached_stencil_opacity := -1.0
var _cached_stencil_mask := false
var _cached_stencil_stamp: Image
var _cached_source: Image
var _cached_source_stencil: Image
var _cached_source_region := Rect2i()
var _cached_source_size := -1
var _cached_source_opacity := -1.0
var _cached_source_mask := false
var stencil_scale := 1.0
var mirror := false
var clone_source := Vector2i(-1, -1)
var spray_particles := 12
var spray_spacing := 4.0
var spray_rate := 20.0
var spray_distance := 1.0
var spray_flow := 0.1
var spray_dot_size := 1
var spray_dot_round := true
var _stroke_spray_flow := 0.1
var _spray_seed: int = randi()
var _spray_dots := PackedVector2Array()
var _spray_coverage: Dictionary = {}
var _preview_state: Array = []
var _preview_pattern: Image
var _drag_buffers: Dictionary = {}
var _spray_elapsed := 0.0
var _spray_anchor := Vector2(-99999, -99999)
var _stroke_spray_particles := 12
var _stroke_spray_spacing := 4.0
var _stroke_spray_rate := 20.0
var _stroke_spray_dot_size := 1
var _stroke_spray_dot_round := true
var _clone_offset := Vector2i.ZERO
var _clone_layer: PaintLayer
var _clone_cache: Dictionary = {}
var _shape_stamp: Image
var active := false
var finishing := false
var last_work_ms := 0.0
var _layer: PaintLayer
var _mask := false
var _before: Dictionary = {}
var _points: Array[Vector4i] = []
var _symmetry_paths: Dictionary = {}
var _island_masks: Dictionary = {}
var _mask_geometry: ModelGeometry
var _read := 0
var _stamp: Image
var _last := Vector2i(-99999, -99999)
var _last_island := -1
var _last_face := -1
var _start := Vector2i.ZERO

func setup(doc: PaintDocument, undo: PaintHistory) -> void:
	document = doc
	history = undo
	selection.clear()
	selection_active = false
	selection_bounds.clear()
	edge_wrap_faces.clear()
	active = false
	finishing = false
	_points.clear()
	_symmetry_paths.clear()
	_island_masks.clear()
	_spray_coverage.clear()
	_drag_buffers.clear()
	_mask_geometry = doc.geometry
	clone_source = Vector2i(-1, -1)
	stencil = doc.stamp_image
	stencil_region = doc.stamp_region
	stencil_rotation = doc.stamp_rotation
	_cached_stencil = null
	_cached_stencil_stamp = null
	_cached_source = null

func set_selection(mask: Dictionary) -> void:
	selection = mask
	selection_active = not mask.is_empty()
	selection_bounds.clear()
	for key in mask: selection_bounds[key] = mask[key].get_used_rect()

var _stroke_tool: String
var _stroke_color: Color
var _stroke_brush_size: int
var _stroke_opacity: float
var _stroke_falloff: float
var _stroke_shape: int
var _stroke_dither: bool
var _stroke_mirror: bool
var _stroke_stencil_rotation: float
var _stroke_edge_wrap: bool

func begin(uv: Vector2, island := -1, face := -1) -> void:
	if active or document.selected_layer().locked:
		return
	_stroke_tool = tool
	_stroke_color = color
	_stroke_brush_size = mini(64,brush_size) if tool in ["smudge","blur"] else brush_size
	_stroke_opacity = opacity
	_stroke_falloff = falloff
	_stroke_shape = shape
	_stroke_dither = dither and tool != "spray"
	_stroke_mirror = mirror and tool != "spray"
	_stroke_stencil_rotation = stencil_rotation
	_stroke_edge_wrap = edge_wrap
	_stroke_brush_tip = brush_tip if tool == "brush" else null
	_stroke_brush_angle = brush_angle
	if tool == "stencil": _stroke_brush_size = _stencil_extent(brush_size, _stroke_stencil_rotation)
	if tool == "spray":
		_stroke_brush_size = footprint_size()
		_stroke_spray_flow = spray_flow / maxf(1.0,spray_distance*spray_distance)
		_spray_coverage.clear()
		_stroke_spray_particles = spray_particles
		_stroke_spray_spacing = maxf(1.0, spray_spacing)
		_stroke_spray_rate = maxf(1.0, spray_rate)
		_stroke_spray_dot_size = spray_dot_size
		_stroke_spray_dot_round = spray_dot_round
		_spray_elapsed = 0.0
		_spray_anchor = Vector2(-99999, -99999)
	if _mask_geometry != document.geometry:
		_island_masks.clear()
		_mask_geometry = document.geometry
	_layer = document.selected_layer()
	_mask = document.editing_mask
	if _mask:
		_layer.mask_enabled = true
	_before.clear()
	_points.clear()
	_symmetry_paths.clear()
	_read = 0
	_last = Vector2i(-99999, -99999)
	_last_island = island
	_last_face = face
	active = true
	finishing = false
	_make_stamp()
	_shape_stamp = _stamp
	_drag_buffers.clear()
	_start = _pixel(uv)
	_last = _start
	if _stroke_tool == "clone":
		_clone_offset = clone_source - _start
		_clone_cache.clear()
		_clone_layer = PaintLayer.from_metadata(_layer.metadata())
		_clone_layer.tiles = _layer.tiles.duplicate()
		_clone_layer.masks = _layer.masks.duplicate()
		_clone_layer.pattern_tiles = _layer.pattern_tiles.duplicate()
		_shape_stamp = _stamp
	if _stroke_tool not in ["line", "rect", "ellipse"]:
		append(uv, island, face)

func append(uv: Vector2, island := -1, face := -1) -> void:
	if not active or finishing:
		return
	var p := _pixel(uv)
	if _stroke_tool == "spray":
		# A new surface sample owns the live spray paths. Old mirrored/wrapped
		# positions must never keep receiving timed bursts after an island jump.
		_symmetry_paths.clear()
		var disconnected := _spray_anchor.x < -90000 or island != _last_island
		if not disconnected:
			disconnected = _spray_anchor.distance_to(Vector2(p)) >= maxf(document.width, document.height) * 0.25
		if disconnected:
			if island != _last_island: _discard_pending_spray()
			_enqueue(p, island)
			_spray_anchor = Vector2(p)
			_spray_elapsed = 0.0
		else:
			var delta := Vector2(p) - _spray_anchor
			var steps := floori(delta.length() / _stroke_spray_spacing)
			var direction := delta.normalized()
			for i in steps:
				_spray_anchor += direction * _stroke_spray_spacing
				_enqueue(Vector2i(_spray_anchor.round()), island)
			if steps > 0:
				_spray_elapsed = 0.0
		_last = p
		_last_island = island
		_last_face = face
		return
	if _stroke_tool in ["line", "rect", "ellipse"]:
		_last = p
		return
	if _last.x > -90000 and island == _last_island:
		var distance := Vector2(_last).distance_to(Vector2(p))
		# Avoid joining through an unrelated surface hit even if a UV island is connected.
		if distance < maxf(document.width, document.height) * 0.25:
			var steps := maxi(1, ceili(distance / maxf(1.0, _stroke_brush_size * 0.25)))
			for i in range(1, steps + 1):
				_enqueue(Vector2i(Vector2(_last).lerp(Vector2(p), i / float(steps)).round()), island)
		else:
			_enqueue(p, island)
	else:
		_enqueue(p, island)
	_last = p
	_last_island = island
	_last_face = face

func end() -> void:
	if not active or finishing:
		return
	if _stroke_tool == "line":
		_queue_line(_start, _last)
	elif _stroke_tool == "rect":
		_queue_line(_start, Vector2i(_last.x, _start.y))
		_queue_line(Vector2i(_last.x, _start.y), _last)
		_queue_line(_last, Vector2i(_start.x, _last.y))
		_queue_line(Vector2i(_start.x, _last.y), _start)
	elif _stroke_tool == "ellipse":
		var center := Vector2(_start + _last) * 0.5
		var radius := Vector2((_last - _start).abs()) * 0.5
		var steps := maxi(16, ceili(TAU * maxf(radius.x, radius.y)))
		for i in steps:
			var a := TAU * i / steps
			_enqueue(Vector2i((center + Vector2(cos(a), sin(a)) * radius).round()), _last_island)
	finishing = true

func break_path() -> void:
	if active and _stroke_tool == "spray" and not finishing: _discard_pending_spray()
	_drag_buffers.clear()
	_symmetry_paths.clear()
	_last = Vector2i(-99999, -99999)
	_last_island = -1
	_spray_anchor = Vector2(-99999, -99999)
	_spray_elapsed = 0.0

func _discard_pending_spray() -> void:
	# Keep already applied paint, but do not drain stale queued bursts later.
	_points.resize(_read)

func append_symmetry(uv: Vector2, island: int, path_id: int) -> void:
	if not active or finishing or _stroke_tool not in ["brush","eraser","stencil","spray","smudge","blur","clone","line","rect","ellipse"]: return
	var pixel := Vector2i((uv * Vector2(document.width, document.height)).floor()) if path_id >= 1000 else _pixel(uv)
	var previous: Dictionary = _symmetry_paths.get(path_id,{})
	if previous.is_empty() or int(previous.island) != island:
		_enqueue(pixel,island,path_id)
	else:
		var old: Vector2i = previous.pixel
		var distance := Vector2(old).distance_to(Vector2(pixel))
		if distance < maxf(document.width,document.height)*0.25:
			var spacing := _stroke_spray_spacing if _stroke_tool == "spray" else maxf(1.0,_stroke_brush_size*0.25)
			var steps := maxi(1,ceili(distance/spacing))
			for i in range(1,steps+1): _enqueue(Vector2i(Vector2(old).lerp(Vector2(pixel),i/float(steps)).round()),island,path_id)
		else: _enqueue(pixel,island,path_id)
	_symmetry_paths[path_id] = {"pixel":pixel,"island":island}

func footprint_size() -> int:
	if active:
		return _stroke_brush_size
	if tool in ["smudge","blur"]: return mini(64,brush_size)
	if tool == "stencil": return _stencil_extent(brush_size,stencil_rotation)
	return clampi(roundi(brush_size * spray_distance), 1, 256) if tool == "spray" else brush_size

func stamp_preview() -> Image:
	if stencil == null: return null
	return _stencil_raster(brush_size, stencil_rotation, opacity, document.editing_mask)

func stamp_source_preview() -> Image:
	if stencil == null: return null
	return _stencil_source(brush_size,opacity,document.editing_mask)

func _stencil_extent(size: int, angle: float) -> int:
	var radians := deg_to_rad(angle)
	return maxi(size, ceili(size * (absf(cos(radians)) + absf(sin(radians))) - 0.00001))

func _stencil_raster(size: int, angle: float, alpha: float, grayscale: bool) -> Image:
	var full := Rect2i(Vector2i.ZERO,stencil.get_size())
	var region := stencil_region.intersection(full)
	if not region.has_area(): region = full
	if _cached_stencil == stencil and _cached_stencil_region == region and _cached_stencil_size == size and is_equal_approx(_cached_stencil_rotation,angle) and is_equal_approx(_cached_stencil_opacity,alpha) and _cached_stencil_mask == grayscale and _cached_stencil_stamp != null:
		return _cached_stencil_stamp
	var source := _stencil_source(size,alpha,grayscale)
	var source_pixels := source.get_data()
	var extent := _stencil_extent(size,angle)
	var pixels := PackedByteArray()
	pixels.resize(extent*extent*4)
	var radians := deg_to_rad(angle)
	var c := cos(radians)
	var s := sin(radians)
	var output_center := (extent-1)*0.5
	var source_center := (size-1)*0.5
	for y in extent:
		var dy := y-output_center
		for x in extent:
			var dx := x-output_center
			var sx := roundi(c*dx+s*dy+source_center)
			var sy := roundi(-s*dx+c*dy+source_center)
			if sx < 0 or sx >= size or sy < 0 or sy >= size: continue
			var src := (sy*size+sx)*4
			var dst := (y*extent+x)*4
			pixels[dst] = source_pixels[src]; pixels[dst+1] = source_pixels[src+1]
			pixels[dst+2] = source_pixels[src+2]; pixels[dst+3] = source_pixels[src+3]
	_cached_stencil = stencil
	_cached_stencil_region = region
	_cached_stencil_size = size
	_cached_stencil_rotation = angle
	_cached_stencil_opacity = alpha
	_cached_stencil_mask = grayscale
	_cached_stencil_stamp = Image.create_from_data(extent,extent,false,Image.FORMAT_RGBA8,pixels)
	return _cached_stencil_stamp

func _stencil_source(size: int, alpha: float, grayscale: bool) -> Image:
	var full := Rect2i(Vector2i.ZERO,stencil.get_size())
	var region := stencil_region.intersection(full)
	if not region.has_area(): region = full
	if _cached_source_stencil == stencil and _cached_source_region == region and _cached_source_size == size and is_equal_approx(_cached_source_opacity,alpha) and _cached_source_mask == grayscale and _cached_source != null:
		return _cached_source
	var source := stencil.get_region(region)
	source.resize(size,size,Image.INTERPOLATE_NEAREST)
	if alpha < 1.0 or grayscale:
		var pixels := source.get_data()
		for index in range(0,pixels.size(),4):
			if grayscale:
				var gray := roundi(0.2126*pixels[index]+0.7152*pixels[index+1]+0.0722*pixels[index+2])
				pixels[index] = gray; pixels[index+1] = gray; pixels[index+2] = gray
			pixels[index+3] = roundi(pixels[index+3]*alpha)
		source = Image.create_from_data(size,size,false,Image.FORMAT_RGBA8,pixels)
	_cached_source_stencil = stencil
	_cached_source_region = region
	_cached_source_size = size
	_cached_source_opacity = alpha
	_cached_source_mask = grayscale
	_cached_source = source
	return source

func _queue_line(a: Vector2i, b: Vector2i) -> void:
	if b.x < -90000:
		b = a
	var steps := maxi(1, maxi(absi(a.x - b.x), absi(a.y - b.y)))
	for i in steps + 1:
		_enqueue(Vector2i(Vector2(a).lerp(Vector2(b), i / float(steps)).round()), _last_island)

func _enqueue(point: Vector2i, island: int, path_id := 0) -> void:
	_points.append(Vector4i(point.x, point.y, island, path_id))
	if not _stroke_edge_wrap or path_id != 0 or island < 0 or document.geometry == null:
		return
	var resolution := Vector2i(document.width, document.height)
	var found := document.geometry.surface_at_uv((Vector2(point) + Vector2.ONE * 0.5) / Vector2(resolution), island, _last_face)
	if found.is_empty(): return
	var allowed := edge_wrap_faces if selection_active else {}
	for target in document.geometry.edge_wrap_targets(int(found.face), found.position, _stroke_brush_size, resolution, allowed, edge_wrap_camera_position, edge_wrap_visible_only):
		append_symmetry(target.uv, int(target.island), 1000 + int(target.face))

func _pixel(uv: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(uv.x * document.width), 0, document.width - 1), clampi(floori(uv.y * document.height), 0, document.height - 1))

func _process(_delta: float) -> void:
	if not active:
		return
	if _stroke_tool == "spray" and not finishing and _last.x > -90000:
		_spray_elapsed += minf(_delta, 0.1)
		var interval := 1.0 / _stroke_spray_rate
		while _spray_elapsed >= interval:
			_enqueue(_last, _last_island)
			for path_id in _symmetry_paths:
				var state: Dictionary = _symmetry_paths[path_id]
				_enqueue(state.pixel,state.island,int(path_id))
			_spray_elapsed -= interval
	var started := Time.get_ticks_usec()
	var changed: Dictionary = {}
	while _read < _points.size() and Time.get_ticks_usec() - started < 3500:
		var queued := _points[_read]
		var p := Vector2i(queued.x, queued.y)
		_read += 1
		if _stroke_tool == "spray": _make_spray_stamp()
		_dab(p, changed, queued.z, false, queued.w)
		if _stroke_mirror:
			_dab(Vector2i(document.width - p.x - 1, p.y), changed, -1, true, -1)
	if not changed.is_empty():
		var keys: Array[Vector2i] = []
		keys.assign(changed.keys())
		tiles_changed.emit(keys)
		if _stroke_tool == "spray": preview_changed.emit()
	last_work_ms = (Time.get_ticks_usec() - started) / 1000.0
	if finishing and _read >= _points.size():
		_commit()
	elif _read > 256:
		_points = _points.slice(_read)
		_read = 0

func _make_stamp() -> void:
	var paint := _stroke_color
	paint.a *= _stroke_opacity
	if _mask:
		paint = Color(_stroke_color.get_luminance(), _stroke_color.get_luminance(), _stroke_color.get_luminance(), _stroke_opacity)
	if _stroke_tool == "spray":
		_stamp = Image.create(_stroke_brush_size, _stroke_brush_size, false, Image.FORMAT_RGBA8)
		_stamp.fill(Color.TRANSPARENT)
		return
	if _stroke_tool == "stencil" and stencil != null:
		_stamp = _stencil_raster(brush_size,_stroke_stencil_rotation,_stroke_opacity,_mask)
		return
	if _stroke_tool == "brush" and _stroke_brush_tip != null:
		var tip := BrushLibrary.rotated_tip(_stroke_brush_tip,_stroke_brush_size,_stroke_brush_angle)
		_stamp = Image.create(_stroke_brush_size,_stroke_brush_size,false,Image.FORMAT_RGBA8)
		_stamp.fill(Color.TRANSPARENT)
		for y in _stroke_brush_size:
			for x in _stroke_brush_size:
				var sample: Color = tip.get_pixel(x,y)
				if sample.a > 0.0:
					var tinted := paint
					tinted.a *= sample.a * sample.get_luminance()
					_stamp.set_pixel(x,y,tinted)
	else:
		_stamp = Image.create(_stroke_brush_size, _stroke_brush_size, false, Image.FORMAT_RGBA8)
		_stamp.fill(Color.TRANSPARENT)
		for y in _stroke_brush_size:
			if _stroke_shape == 0:
				_stamp.fill_rect(Rect2i(0, y, _stroke_brush_size, 1), paint)
			else:
				var radius := _stroke_brush_size / 2.0
				var dy := y + 0.5 - radius
				var half := sqrt(maxf(0.0, radius * radius - dy * dy))
				var start := ceili(radius - half - 0.5)
				var row_end := floori(radius + half - 0.5)
				_stamp.fill_rect(Rect2i(start, y, row_end - start + 1, 1), paint)
	if _stroke_falloff > 0.0 and _stroke_brush_size > 1:
		var pixels := _stamp.get_data()
		var radius := _stroke_brush_size * 0.5
		var nearest := 0.5 if _stroke_brush_size % 2 == 0 else 0.0
		var edge := maxf(nearest + 0.001, radius - 0.5)
		var inner := nearest + (edge - nearest) * (1.0 - clampf(_stroke_falloff, 0.0, 1.0))
		for y in _stroke_brush_size:
			for x in _stroke_brush_size:
				var index := (y * _stroke_brush_size + x) * 4 + 3
				if pixels[index] == 0: continue
				var dx := absf(x + 0.5 - radius)
				var dy := absf(y + 0.5 - radius)
				var distance := maxf(dx, dy) if _stroke_shape == 0 else Vector2(dx, dy).length()
				var t := clampf((edge - distance) / maxf(0.001, edge - inner), 0.0, 1.0)
				pixels[index] = roundi(pixels[index] * t * t * (3.0 - 2.0 * t))
		_stamp = Image.create_from_data(_stroke_brush_size, _stroke_brush_size, false, Image.FORMAT_RGBA8, pixels)
	if _stroke_dither:
		for y in _stroke_brush_size:
			for x in _stroke_brush_size:
				if (x + y) % 2:
					_stamp.set_pixel(x, y, Color.TRANSPARENT)

func _dab(p: Vector2i, changed: Dictionary, island := -1, mirrored := false, path_id := 0) -> void:
	if _stroke_opacity <= 0: return
	var origin := p - Vector2i(_stroke_brush_size >> 1, _stroke_brush_size >> 1)
	if _stroke_tool == "clone":
		_make_clone_stamp(origin + _clone_offset)
	elif _stroke_tool == "spray":
		if _stroke_spray_flow <= 0: return
	elif _stroke_tool in ["smudge","blur"]:
		if not _make_filter_stamp(origin,island,path_id): return
	var rect := Rect2i(origin, Vector2i.ONE * _stroke_brush_size).intersection(Rect2i(0, 0, document.width, document.height))
	if not rect.has_area():
		return
	for ty in range(rect.position.y >> 6, ((rect.end.y - 1) >> 6) + 1):
		for tx in range(rect.position.x >> 6, ((rect.end.x - 1) >> 6) + 1):
			var key := Vector2i(tx, ty)
			var restriction := _restriction(key,island)
			if (selection_active or island >= 0) and restriction == null: continue
			var clipped := rect.intersection(Rect2i(key * 64, Vector2i.ONE * 64))
			var dest := clipped.position - key * 64
			if selection_active:
				var bounds: Rect2i = selection_bounds.get(key,Rect2i(Vector2i.ZERO,Vector2i(64,64)))
				if not bounds.intersects(Rect2i(dest,clipped.size)): continue
			var bank: Dictionary = _layer.masks if _mask else _layer.tiles
			if not _before.has(key):
				_before[key] = bank[key].duplicate() if bank.has(key) else null
				# Copy-on-write keeps the clone source stable throughout an overlapping stroke.
				if bank.has(key):
					bank[key] = bank[key].duplicate()
			var target := _layer.tile_at(key, _mask)
			var src := Rect2i(clipped.position - origin, clipped.size)
			if _stroke_tool == "spray":
				_apply_spray(key,origin,target,restriction)
			elif _stroke_tool == "eraser":
				var allowed := _stamp.get_region(src)
				if _stroke_falloff > 0.0:
					for sy in clipped.size.y:
						for sx in clipped.size.x:
							var amount := allowed.get_pixel(sx,sy).a
							if restriction != null: amount *= restriction.get_pixel(dest.x+sx,dest.y+sy).a
							if amount <= 0.0: continue
							var at := dest+Vector2i(sx,sy)
							var old := target.get_pixelv(at)
							if _mask:
								old.r *= 1.0-amount; old.g *= 1.0-amount; old.b *= 1.0-amount
							else:
								old.a *= 1.0-amount
							target.set_pixelv(at,old)
					changed[key] = true
					_layer.invalidate(key)
					continue
				if restriction != null:
					var mask_region: Image = restriction.get_region(Rect2i(dest, clipped.size))
					var filtered := Image.create(clipped.size.x, clipped.size.y, false, Image.FORMAT_RGBA8)
					filtered.fill(Color.TRANSPARENT)
					filtered.blit_rect_mask(allowed, mask_region, Rect2i(Vector2i.ZERO, clipped.size), Vector2i.ZERO)
					allowed = filtered
				var clear := Image.create(clipped.size.x, clipped.size.y, false, Image.FORMAT_RGBA8)
				clear.fill(Color.BLACK if _mask else Color.TRANSPARENT)
				target.blit_rect_mask(clear, allowed, Rect2i(Vector2i.ZERO, clipped.size), dest)
			elif restriction != null:
				var stamp_region := _stamp.get_region(src)
				var mask_region: Image = restriction.get_region(Rect2i(dest, clipped.size))
				target.blend_rect_mask(stamp_region, mask_region, Rect2i(Vector2i.ZERO, clipped.size), dest)
			else:
				target.blend_rect(_stamp, src, dest)
			changed[key] = true
			_layer.invalidate(key)

func _restriction(key: Vector2i, island: int) -> Image:
	if selection_active and not selection.has(key): return null
	var result: Image = selection.get(key) if selection_active else null
	if island >= 0 and document.geometry != null:
		if _mask_geometry != document.geometry:
			_island_masks.clear(); _mask_geometry = document.geometry
		var cache_key := Vector3i(island,key.x,key.y)
		if not _island_masks.has(cache_key):
			if _island_masks.size() >= 256: _island_masks.clear()
			_island_masks[cache_key] = document.geometry.island_tile_mask(island,key,Vector2i(document.width,document.height))
		var surface: Image = _island_masks[cache_key]
		if surface == null: return null
		if result == null: return surface
		var combined := Image.create(64,64,false,Image.FORMAT_RGBA8)
		combined.fill(Color.TRANSPARENT)
		combined.blit_rect_mask(result,surface,Rect2i(0,0,64,64),Vector2i.ZERO)
		return combined
	return result

func _make_filter_stamp(origin: Vector2i, island: int, path_id: int) -> bool:
	var extent := Vector2i.ONE * _stroke_brush_size
	var sample := BrushFilters.sample(document,_layer,_mask,Rect2i(origin,extent))
	if _stroke_tool == "blur":
		var padded := BrushFilters.sample(document,_layer,_mask,Rect2i(origin-Vector2i(2,2),extent+Vector2i(4,4)))
		_stamp = BrushFilters.strength(BrushFilters.blur(padded).get_region(Rect2i(Vector2i(2,2),extent)),_stroke_opacity,_shape_stamp)
		return true
	var old: Dictionary = _drag_buffers.get(path_id,{})
	if old.is_empty() or old.island != island:
		_drag_buffers[path_id] = {"image":sample,"origin":origin,"island":island}
		return false
	if old.origin == origin: return false
	_stamp = BrushFilters.strength(old.image,_stroke_opacity,_shape_stamp)
	var carry: Image = old.image.duplicate()
	carry.blend_rect(BrushFilters.strength(sample,0.25),Rect2i(Vector2i.ZERO,extent),Vector2i.ZERO)
	_drag_buffers[path_id] = {"image":carry,"origin":origin,"island":island}
	return true

func _commit() -> void:
	var after: Dictionary = {}
	var bank: Dictionary = _layer.masks if _mask else _layer.tiles
	for key in _before.keys():
		var image: Image = bank[key]
		var unchanged := false
		if _before[key] != null:
			unchanged = _before[key].get_data() == image.get_data()
		else:
			var empty := Image.create(64,64,false,Image.FORMAT_RGBA8)
			empty.fill(Color.WHITE if _mask else _layer.base_color)
			unchanged = empty.get_data() == image.get_data()
			if unchanged: bank.erase(key)
		if unchanged:
			_before.erase(key)
		else:
			after[key] = image.duplicate()
	if not _before.is_empty():
		history.push(document, {"kind": "tiles", "label": "Paint mask" if _mask else _stroke_tool.capitalize(),
			"layer": _layer, "mask": _mask, "before": _before.duplicate(), "after": after,
			"bytes": _before.size() * 64 * 64 * 4 * 2})
	active = false
	finishing = false
	_points.clear()
	_before.clear()
	_spray_coverage.clear()
	_drag_buffers.clear()
	stroke_committed.emit()
	_clone_layer = null
	_clone_cache.clear()

func _make_spray_stamp() -> void:
	var tint := _stroke_color
	if _mask:
		tint = Color(tint.get_luminance(), tint.get_luminance(), tint.get_luminance(), tint.a)
	tint.a *= _stroke_spray_flow
	var pattern := spray_pattern(_spray_seed,_stroke_brush_size,_stroke_spray_particles,tint,_stroke_dither,_stroke_spray_dot_size,_stroke_spray_dot_round)
	_stamp = pattern.image
	_spray_dots = pattern.points
	_spray_seed = pattern.next_seed

static func spray_pattern(seed_value: int, diameter: int, count: int, tint: Color, ordered: bool, dot_size := 1, round_dot := true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := Image.create(diameter,diameter,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var points: Dictionary = {}
	var radius := diameter / 2.0
	for particle in count:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * radius
		var position := Vector2.ONE * radius + Vector2(cos(angle), sin(angle)) * distance
		var pixel := Vector2i(position.floor()).clamp(Vector2i.ZERO, Vector2i.ONE * (diameter - 1))
		# Reject cells outside the same discrete circle shown by the cursor.
		if (Vector2(pixel) + Vector2.ONE * 0.5 - Vector2.ONE * radius).length_squared() > radius * radius:
			continue
		if ordered and (pixel.x + pixel.y) % 2:
			continue
		var side := clampi(dot_size,1,diameter)
		var corner := pixel - Vector2i(side / 2,side / 2)
		for dy in side:
			for dx in side:
				var dot := corner + Vector2i(dx,dy)
				if dot.x < 0 or dot.y < 0 or dot.x >= diameter or dot.y >= diameter: continue
				if round_dot and (Vector2(dx,dy)+Vector2.ONE*0.5-Vector2.ONE*side*0.5).length_squared() > float(side*side)*0.25: continue
				image.set_pixelv(dot,image.get_pixelv(dot).blend(tint))
				points[dot] = true
	return {"image":image,"points":PackedVector2Array(points.keys()),"next_seed":rng.randi()}

func _apply_spray(key: Vector2i, origin: Vector2i, target: Image, restriction: Image) -> void:
	if not _spray_coverage.has(key):
		var fresh_coverage := Image.create(64,64,false,Image.FORMAT_RF)
		fresh_coverage.fill(Color.BLACK)
		_spray_coverage[key] = fresh_coverage
	var coverage: Image = _spray_coverage[key]
	var original: Image = _before[key]
	var tint := _stroke_color
	if _mask: tint = Color(tint.get_luminance(),tint.get_luminance(),tint.get_luminance())
	for dot in _spray_dots:
		var pixel := origin + Vector2i(dot)
		var local := pixel - key*64
		if local.x < 0 or local.y < 0 or local.x >= 64 or local.y >= 64 or pixel.x < 0 or pixel.y < 0 or pixel.x >= document.width or pixel.y >= document.height: continue
		if restriction != null and restriction.get_pixelv(local).a == 0: continue
		var amount := coverage.get_pixelv(local).r
		amount += (1.0-amount)*_stamp.get_pixelv(Vector2i(dot)).a
		coverage.set_pixelv(local,Color(amount,0,0))
		tint.a = amount*_stroke_opacity
		var base := original.get_pixelv(local) if original != null else Color.WHITE if _mask else _layer.base_color
		target.set_pixelv(local,base.blend(tint))

func spray_preview(uv: Vector2, island: int) -> Image:
	if tool != "spray" or document == null: return null
	var diameter := footprint_size()
	var density := _stroke_spray_particles if active else spray_particles
	var ordered := _stroke_dither if active else false
	var strength := _stroke_opacity if active else opacity
	var flow := _stroke_spray_flow if active else spray_flow / maxf(1.0,spray_distance*spray_distance)
	var tint_alpha := _stroke_color.a if active else color.a
	var dot_size := _stroke_spray_dot_size if active else spray_dot_size
	var round_dot := _stroke_spray_dot_round if active else spray_dot_round
	var state := [_spray_seed,diameter,density,ordered,strength,flow,tint_alpha,dot_size,round_dot]
	if state != _preview_state:
		_preview_state = state
		_preview_pattern = spray_pattern(_spray_seed,diameter,density,Color(0.9,1,1,0.8 if strength*flow*tint_alpha >= 0.5/255 else 0.0),ordered,dot_size,round_dot).image
	var preview := Image.create(diameter,diameter,false,Image.FORMAT_RGBA8)
	preview.fill(Color.TRANSPARENT)
	var origin := _pixel(uv)-Vector2i(diameter >> 1,diameter >> 1)
	var rect := Rect2i(origin,Vector2i.ONE*diameter).intersection(Rect2i(0,0,document.width,document.height))
	for ty in range(rect.position.y >> 6,((rect.end.y-1) >> 6)+1):
		for tx in range(rect.position.x >> 6,((rect.end.x-1) >> 6)+1):
			var key := Vector2i(tx,ty)
			var mask := _restriction(key,island)
			if (selection_active or island >= 0) and mask == null: continue
			var part := rect.intersection(Rect2i(key*64,Vector2i(64,64)))
			var src := Rect2i(part.position-origin,part.size)
			if mask == null:
				preview.blit_rect(_preview_pattern,src,src.position)
			else:
				preview.blit_rect_mask(_preview_pattern.get_region(src),mask.get_region(Rect2i(part.position-key*64,part.size)),Rect2i(Vector2i.ZERO,part.size),src.position)
	return preview

func _make_clone_stamp(origin: Vector2i) -> void:
	var sampled := Image.create(_stroke_brush_size, _stroke_brush_size, false, Image.FORMAT_RGBA8)
	sampled.fill(Color.TRANSPARENT)
	var rect := Rect2i(origin, Vector2i.ONE * _stroke_brush_size).intersection(Rect2i(0, 0, document.width, document.height))
	if rect.has_area():
		for ty in range(rect.position.y >> 6, ((rect.end.y - 1) >> 6) + 1):
			for tx in range(rect.position.x >> 6, ((rect.end.x - 1) >> 6) + 1):
				var key := Vector2i(tx, ty)
				if not _clone_cache.has(key):
					if _mask:
						_clone_cache[key] = _clone_layer.tile_at(key,true,false)
					elif _clone_layer.pattern_tiles.has(key):
						var combined: Image = _clone_layer.pattern_tiles[key].duplicate()
						if _clone_layer.tiles.has(key): combined.blend_rect(_clone_layer.tiles[key],Rect2i(0,0,64,64),Vector2i.ZERO)
						_clone_cache[key] = combined
					else:
						_clone_cache[key] = _clone_layer.tile_at(key,false,false)
				var part := rect.intersection(Rect2i(key * 64, Vector2i.ONE * 64))
				sampled.blit_rect(_clone_cache[key], Rect2i(part.position - key * 64, part.size), part.position - origin)
	_stamp = Image.create(_stroke_brush_size, _stroke_brush_size, false, Image.FORMAT_RGBA8)
	_stamp.fill(Color.TRANSPARENT)
	_stamp.blit_rect_mask(sampled, _shape_stamp, Rect2i(0, 0, _stroke_brush_size, _stroke_brush_size), Vector2i.ZERO)
	if _stroke_opacity < 1.0 or _stroke_falloff > 0.0:
		var data := _stamp.get_data()
		var shape_data := _shape_stamp.get_data()
		for i in range(3, data.size(), 4):
			data[i] = roundi(data[i] * shape_data[i] / 255.0)
		_stamp = Image.create_from_data(_stroke_brush_size, _stroke_brush_size, false, Image.FORMAT_RGBA8, data)
