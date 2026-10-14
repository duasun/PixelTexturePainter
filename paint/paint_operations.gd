class_name PaintOperations
extends RefCounted
## Whole-document operations run on BackgroundJob. They return a command, never mutate live state.

static func fill(progress: BackgroundJob.JobProgress, doc: PaintDocument, selection: Dictionary, restricted: bool, color: Color) -> Dictionary:
	var layer := doc.selected_layer()
	var before: Dictionary = {}
	var after: Dictionary = {}
	var bank: Dictionary = layer.masks if doc.editing_mask else layer.tiles
	var keys: Array[Vector2i] = []
	keys.assign(selection.keys() if restricted else doc.all_keys())
	for i in keys.size():
		if progress.report(i / float(maxi(1, keys.size())), "Filling selected area…"):
			return {"cancelled": true}
		var key := keys[i]
		before[key] = bank.get(key)
		var tile := layer.tile_at(key, doc.editing_mask, false).duplicate()
		var solid := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		solid.fill(color)
		if restricted:
			tile.blend_rect_mask(solid, selection[key], Rect2i(0, 0, 64, 64), Vector2i.ZERO)
		else:
			tile.fill(color)
		after[key] = tile
	return _command(layer, doc.editing_mask, before, after, "Fill")

static func _command(layer: PaintLayer, mask: bool, before: Dictionary, after: Dictionary, title: String) -> Dictionary:
	return {"command": {"kind": "tiles", "label": title, "layer": layer, "mask": mask,
		"before": before, "after": after, "bytes": after.size() * 64 * 64 * 4 * 2}}

static func texture_fill(progress: BackgroundJob.JobProgress, doc: PaintDocument, faces: PackedInt32Array, pattern: Image, settings: Dictionary) -> Dictionary:
	var selection := UVRaster.selection(doc.geometry, faces, Vector2i(doc.width, doc.height))
	var before: Dictionary = {}
	var after: Dictionary = {}
	var keys := selection.keys()
	var angle := deg_to_rad(float(settings.angle))
	var scale := maxf(0.01, float(settings.scale))
	var offset: Vector2 = settings.offset
	var cosine := snappedf(cos(angle), 0.000000001)
	var sine := snappedf(sin(angle), 0.000000001)
	var axis_x := Vector2(cosine, sine) / scale
	var axis_y := Vector2(-sine, cosine) / scale
	var source_data := pattern.get_data()
	var width := pattern.get_width()
	var height := pattern.get_height()
	for i in keys.size():
		if progress.report(float(i) / maxi(1, keys.size()), "Filling faces with texture…"):
			return {"cancelled": true}
		var key: Vector2i = keys[i]
		_capture(doc, key, before, after)
		var data := PackedByteArray()
		data.resize(64 * 64 * 4)
		for y in 64:
			var row := Vector2(key * 64 + Vector2i(0, y)) - offset
			var sample_x := row.dot(axis_x)
			var sample_y := row.dot(axis_y)
			for x in 64:
				var sx := posmod(floori(sample_x + x * axis_x.x), width)
				var sy := posmod(floori(sample_y + x * axis_y.x), height)
				var src := (sy * width + sx) * 4
				var dst := (y * 64 + x) * 4
				data[dst] = source_data[src]
				data[dst + 1] = source_data[src + 1]
				data[dst + 2] = source_data[src + 2]
				data[dst + 3] = source_data[src + 3]
		var image := Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, data)
		after[key].blend_rect_mask(image, selection[key], Rect2i(0, 0, 64, 64), Vector2i.ZERO)
	return _command(doc.selected_layer(), doc.editing_mask, before, after, "Texture fill")

static func pattern_layer(progress: BackgroundJob.JobProgress, doc: PaintDocument, faces: PackedInt32Array, pattern: Image, settings: Dictionary) -> Dictionary:
	if pattern == null or faces.is_empty(): return {"error":"Select faces and load a pattern image first."}
	var layer := PaintLayer.new()
	layer.title = "Pattern fill"
	layer.channel = doc.current_channel()
	layer.pattern_image = pattern
	layer.pattern_faces = faces.duplicate()
	layer.pattern_settings = {"angle":float(settings.angle),"scale":float(settings.scale),
		"offset_x":settings.offset.x,"offset_y":settings.offset.y}
	var temporary := doc.read_copy()
	temporary.layers.append(layer)
	temporary.active_layer = temporary.layers.size()-1
	temporary.editing_mask = false
	var filled := texture_fill(progress,temporary,faces,pattern,settings)
	if filled.has("cancelled") or filled.has("error"): return filled
	layer.pattern_tiles = filled.command.after
	return {"layer":layer}

static func rerender_pattern(progress: BackgroundJob.JobProgress, doc: PaintDocument, layer_id: String, pattern: Image, settings: Dictionary) -> Dictionary:
	var found: PaintLayer
	for layer in doc.layers:
		if layer.id == layer_id: found = layer; break
	if found == null or found.pattern_faces.is_empty(): return {"error":"Select a pattern fill layer first."}
	var result := pattern_layer(progress,doc,found.pattern_faces,pattern,settings)
	if result.has("error") or result.has("cancelled"): return result
	var updated := found.copy_layer()
	updated.pattern_image = pattern
	updated.pattern_tiles = result.layer.pattern_tiles
	updated.pattern_settings = result.layer.pattern_settings
	updated._prepared.clear()
	return {"layer":updated,"layer_id":layer_id}

static func gradient(progress: BackgroundJob.JobProgress, doc: PaintDocument, faces: PackedInt32Array, start: Dictionary, finish: Dictionary,
	length: int, color_a: Color, color_b: Color, ordered: bool, brush_width := 0) -> Dictionary:
	var layer := doc.selected_layer()
	var before: Dictionary = {}
	var after: Dictionary = {}
	var model := doc.geometry
	var origin: Vector2 = (start.uv * Vector2(doc.width, doc.height)).floor() + Vector2.ONE * 0.5
	var end: Vector2 = finish.get("uv", start.uv) * Vector2(doc.width, doc.height)
	var charts: Dictionary = {}
	var root_face := int(start.get("face", -1))
	var affected := faces.duplicate()
	if root_face >= 0:
		if affected.is_empty():
			affected.append(root_face)
		charts = _unfold(model, affected, root_face, Vector2(doc.width, doc.height))
		var end_face := int(finish.get("face", root_face))
		if charts.has(end_face):
			end = _interpolate_uv(model, end_face, finish.get("uv", start.uv), charts[end_face])
	var direction := (end - origin).normalized()
	if (end - origin).length() < 1.0:
		direction = Vector2.DOWN
	var lateral := Vector2(-direction.y, direction.x)
	var half_width := float(brush_width) * 0.5
	if affected.is_empty():
		# 2D unrestricted gradient: scan in small tiles, keeping the UI responsive.
		var keys := doc.all_keys()
		for i in keys.size():
			if progress.report(float(i) / keys.size(), "Rendering %d px gradient…" % length):
				return {"cancelled": true}
			var key: Vector2i = keys[i]
			if brush_width > 0:
				var minimum := INF
				var maximum := -INF
				for corner in [Vector2.ZERO, Vector2(64,0), Vector2(0,64), Vector2(64,64)]:
					var lateral_distance: float = (Vector2(key * 64) + corner - origin).dot(lateral)
					minimum = minf(minimum, lateral_distance)
					maximum = maxf(maximum, lateral_distance)
				if minimum > half_width or maximum < -half_width: continue
			_capture(doc, key, before, after)
			for y in mini(64, doc.height - key.y * 64):
				for x in mini(64, doc.width - key.x * 64):
					var pixel := key * 64 + Vector2i(x, y)
					var displacement := (Vector2(pixel) + Vector2.ONE * 0.5) - origin
					if brush_width > 0 and absf(displacement.dot(lateral)) > half_width: continue
					var t := displacement.dot(direction) / maxi(1, length - 1)
					after[key].set_pixel(x, y, _ramp(color_a, color_b, t, ordered, pixel))
	else:
		for fi in affected.size():
			if progress.report(float(fi) / affected.size(), "Rendering surface gradient…"):
				return {"cancelled": true}
			var face := affected[fi]
			if root_face >= 0 and not charts.has(face):
				continue
			var tri := PackedVector2Array()
			for c in 3:
				tri.append(model.uvs[face * 3 + c] * Vector2(doc.width, doc.height))
			var projected: PackedVector2Array = charts.get(face, tri)
			var weights := PackedFloat32Array()
			var lateral_weights := Vector3.ZERO
			for p in projected:
				weights.append((p - origin).dot(direction) / maxi(1, length - 1))
			for vertex in 3:
				lateral_weights[vertex] = (projected[vertex] - origin).dot(lateral)
			if brush_width > 0 and (minf(lateral_weights.x, minf(lateral_weights.y, lateral_weights.z)) > half_width or maxf(lateral_weights.x, maxf(lateral_weights.y, lateral_weights.z)) < -half_width):
				continue
			var masks: Dictionary = {}
			UVRaster.triangle(masks, tri, Vector2i(doc.width, doc.height), Color.WHITE)
			for key in masks:
				if brush_width > 0:
					var minimum := INF
					var maximum := -INF
					for corner in [Vector2.ZERO, Vector2(64,0), Vector2(0,64), Vector2(64,64)]:
						var weights_at_corner := _barycentric(Vector2(key * 64) + corner, tri)
						var offset: float = weights_at_corner.dot(lateral_weights)
						minimum = minf(minimum, offset)
						maximum = maxf(maximum, offset)
					if minimum > half_width or maximum < -half_width: continue
				_capture(doc, key, before, after)
				var mask_data: PackedByteArray = masks[key].get_data()
				for y in 64:
					for x in 64:
						if mask_data[(y * 64 + x) * 4 + 3] == 0:
							continue
						var pixel: Vector2i = key * 64 + Vector2i(x, y)
						var bary := _barycentric(Vector2(pixel) + Vector2.ONE * 0.5, tri)
						if brush_width > 0 and absf(bary.dot(lateral_weights)) > half_width: continue
						var t := bary.dot(Vector3(weights[0], weights[1], weights[2]))
						after[key].set_pixel(x, y, _ramp(color_a, color_b, t, ordered, pixel))
	return _command(layer, doc.editing_mask, before, after, "Gradient %d px" % length)

static func _capture(doc: PaintDocument, key: Vector2i, before: Dictionary, after: Dictionary) -> void:
	if after.has(key):
		return
	var layer := doc.selected_layer()
	var bank: Dictionary = layer.masks if doc.editing_mask else layer.tiles
	before[key] = bank.get(key)
	after[key] = layer.tile_at(key, doc.editing_mask, false).duplicate()

static func _ramp(a: Color, b: Color, t: float, ordered: bool, pixel: Vector2i) -> Color:
	t = clampf(t, 0.0, 1.0)
	if ordered:
		var bayer := [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5]
		return b if t >= (bayer[(pixel.y % 4) * 4 + pixel.x % 4] + 0.5) / 16.0 else a
	return a.lerp(b, t)

static func _barycentric(p: Vector2, tri: PackedVector2Array) -> Vector3:
	var a := tri[1] - tri[0]
	var b := tri[2] - tri[0]
	var det := a.cross(b)
	if absf(det) < 0.00000001:
		return Vector3(1, 0, 0)
	var delta := p - tri[0]
	var u := delta.cross(b) / det
	var v := a.cross(delta) / det
	return Vector3(1.0 - u - v, u, v)

static func _interpolate_uv(model: ModelGeometry, face: int, uv: Vector2, mapped: PackedVector2Array) -> Vector2:
	var tri := PackedVector2Array([model.uvs[face * 3], model.uvs[face * 3 + 1], model.uvs[face * 3 + 2]])
	var bary := _barycentric(uv, tri)
	return mapped[0] * bary.x + mapped[1] * bary.y + mapped[2] * bary.z

static func _unfold(model: ModelGeometry, faces: PackedInt32Array, root: int, size: Vector2) -> Dictionary:
	# Unfold adjacent triangles around their common edge. UV island gaps never enter this metric.
	var allowed: Dictionary = {}
	for f in faces:
		allowed[f] = true
	allowed[root] = true
	var p0 := model.positions[root * 3]
	var p1 := model.positions[root * 3 + 1]
	var p2 := model.positions[root * 3 + 2]
	var edge := p1 - p0
	var u := edge.normalized()
	var x := (p2 - p0).dot(u)
	var y := sqrt(maxf(0.000000001, (p2 - p0).length_squared() - x * x))
	var developed := {root: PackedVector2Array([Vector2.ZERO, Vector2(edge.length(), 0), Vector2(x, y)])}
	var queue: Array[int] = [root]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next in model.neighbors[current]:
			if not allowed.has(next) or developed.has(next):
				continue
			var matching: Array[Vector2i] = []
			for a in 3:
				for b in 3:
					if model.positions[current * 3 + a].is_equal_approx(model.positions[next * 3 + b]):
						matching.append(Vector2i(a, b))
			if matching.size() != 2:
				continue
			var ma := matching[0]
			var mb := matching[1]
			var old_third := 3 - ma.x - mb.x
			var new_third := 3 - ma.y - mb.y
			var a: Vector2 = developed[current][ma.x]
			var b: Vector2 = developed[current][mb.x]
			var third := model.positions[next * 3 + new_third]
			var da := third.distance_squared_to(model.positions[next * 3 + ma.y])
			var db := third.distance_squared_to(model.positions[next * 3 + mb.y])
			var distance := a.distance_to(b)
			if distance < 0.000001:
				continue
			var along := (da - db + distance * distance) / (2.0 * distance)
			var height := sqrt(maxf(0.0, da - along * along))
			var tangent := (b - a) / distance
			var side := signf((b - a).cross(developed[current][old_third] - a))
			var c := a + tangent * along - Vector2(-tangent.y, tangent.x) * height * side
			var points := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			points[ma.y] = a
			points[mb.y] = b
			points[new_third] = c
			developed[next] = points
			queue.append(next)
	var uv0 := model.uvs[root * 3] * size
	var basis_x := (model.uvs[root * 3 + 1] * size - uv0) / edge.length()
	var basis_y := (model.uvs[root * 3 + 2] * size - uv0 - basis_x * x) / y
	for f in developed:
		var points: PackedVector2Array = developed[f]
		for c in 3:
			points[c] = uv0 + basis_x * points[c].x + basis_y * points[c].y
		developed[f] = points
	return developed

static func edge_layer(progress: BackgroundJob.JobProgress, doc: PaintDocument, width: int, color: Color, scatter_reach := 0, noise_amount := 0.0, side_falloff := 0.7) -> Dictionary:
	var layer := PaintLayer.new()
	layer.title = "Edge highlights"
	layer.mask_enabled = true
	var model := doc.geometry
	var faces := PackedInt32Array()
	for f in model.face_count():
		faces.append(f)
	layer.masks = UVRaster.selection(model, faces, Vector2i(doc.width, doc.height))
	var entries := model.edges.values()
	for i in entries.size():
		if progress.report(float(i) / entries.size(), "Detecting geometry edges…"):
			return {"cancelled": true}
		var edge: Array = entries[i]
		if edge.size() == 2 and model.face_normals[edge[0].x].dot(model.face_normals[edge[1].x]) > cos(deg_to_rad(35.0)):
			continue
		for item in edge:
			var face: int = item.x
			var c: int = item.y
			var a := model.uvs[face * 3 + c] * Vector2(doc.width, doc.height)
			var b := model.uvs[face * 3 + (c + 1) % 3] * Vector2(doc.width, doc.height)
			var steps := maxi(1, ceili(a.distance_to(b)))
			for s in steps + 1:
				var p := Vector2i(a.lerp(b, s / float(steps)))
				for y in range(maxi(0, p.y - width), mini(doc.height, p.y + width + 1)):
					UVRaster.span(layer.tiles, y, maxi(0, p.x - width), mini(doc.width - 1, p.x + width), color)
			if scatter_reach > 0 and noise_amount > 0.0:
				var third := model.uvs[face * 3 + (c + 2) % 3] * Vector2(doc.width, doc.height)
				_edge_scatter(layer.tiles,a,b,third,Vector2i(doc.width,doc.height),width,scatter_reach,noise_amount,side_falloff,color,face,c)
	return {"layer": layer}

static func _edge_scatter(tiles: Dictionary, a: Vector2, b: Vector2, third: Vector2, size: Vector2i, width: int, reach: int, amount: float, falloff: float, color: Color, face: int, corner: int) -> void:
	var edge := b-a
	var length_squared := edge.length_squared()
	if length_squared < 0.0001: return
	var outer := float(width+reach)
	var inner_squared := float(width*width)
	var outer_squared := outer*outer
	var y0 := clampi(floori(minf(a.y,b.y)-outer),0,size.y-1)
	var y1 := clampi(ceili(maxf(a.y,b.y)+outer),0,size.y-1)
	for y in range(y0,y1+1):
		var left := minf(a.x,b.x)
		var right := maxf(a.x,b.x)
		if absf(edge.y) > 0.0001:
			var first := clampf((y+0.5-outer-a.y)/edge.y,0.0,1.0)
			var last := clampf((y+0.5+outer-a.y)/edge.y,0.0,1.0)
			left = minf(a.x+edge.x*first,a.x+edge.x*last)
			right = maxf(a.x+edge.x*first,a.x+edge.x*last)
		var x0 := clampi(floori(left-outer),0,size.x-1)
		var x1 := clampi(ceili(right+outer),0,size.x-1)
		for x in range(x0,x1+1):
			var point := Vector2(x+0.5,y+0.5)
			var along := clampf((point-a).dot(edge)/length_squared,0.0,1.0)
			var distance_squared := point.distance_squared_to(a+edge*along)
			if distance_squared <= inner_squared or distance_squared >= outer_squared: continue
			var noise := ((x*73856093) ^ (y*19349663) ^ (face*83492791) ^ (corner*1640531513)) & 0x7fffffff
			noise = ((noise ^ (noise >> 16))*2246822519) & 0x7fffffff
			noise = ((noise ^ (noise >> 13))*3266489917) & 0x7fffffff
			noise = noise ^ (noise >> 16)
			if float(noise & 65535)/65535.0 > amount: continue
			if not _triangle_contains(point,a,b,third): continue
			var distance_ratio := clampf((sqrt(distance_squared)-float(width))/float(reach),0.0,1.0)
			var remaining := 1.0-distance_ratio
			var faded := lerpf(1.0,remaining*remaining,falloff)
			var grain := 0.6+0.4*float((noise >> 16) & 32767)/32767.0
			var alpha := color.a*faded*grain
			var key := Vector2i(x >> 6,y >> 6)
			if not tiles.has(key):
				var blank := Image.create(64,64,false,Image.FORMAT_RGBA8)
				blank.fill(Color.TRANSPARENT)
				tiles[key] = blank
			var tile: Image = tiles[key]
			var local := Vector2i(x & 63,y & 63)
			if tile.get_pixelv(local).a < alpha:
				tile.set_pixelv(local,Color(color.r,color.g,color.b,alpha))

## Fast geometry-based cavity AO. Rasterize only a narrow strip beside concave
## shared edges, so a 4K atlas never needs a full-image Python/GDScript sweep.
static func cavity_ao(progress: BackgroundJob.JobProgress, doc: PaintDocument, strength: float, radius: int, depth_focus: float, falloff: int) -> Dictionary:
	var layer := PaintLayer.new()
	layer.title = "Cavity AO"
	layer.channel = "albedo"
	if strength <= 0.0 or doc.geometry == null or not doc.geometry.has_uv:
		return {"layer": layer, "corners": 0}
	var model := doc.geometry
	var entries := model.edges.values()
	var corners := 0
	var size := Vector2(doc.width, doc.height)
	for index in entries.size():
		if progress.report(float(index) / maxi(1, entries.size()), "Baking cavity AO…"):
			return {"cancelled": true}
		var edge: Array = entries[index]
		if edge.size() != 2:
			continue
		var a: Vector2i = edge[0]
		var b: Vector2i = edge[1]
		var normal_a: Vector3 = model.face_normals[a.x]
		var normal_b: Vector3 = model.face_normals[b.x]
		var dot: float = clampf(normal_a.dot(normal_b), -1.0, 1.0)
		if dot > cos(deg_to_rad(8.0)):
			continue
		var start_a: Vector3 = model.positions[a.x * 3 + a.y]
		var third_b: Vector3 = model.positions[b.x * 3 + (b.y + 2) % 3]
		var world_scale: float = maxf(model.bounds.size.length(), 0.0001)
		if (third_b - start_a).dot(normal_a) <= world_scale * 0.000001:
			continue
		var angle: float = acos(dot)
		var depth: float = pow(clampf(angle / (PI * 0.5), 0.0, 1.0), lerpf(0.0, 2.0, clampf(depth_focus, 0.0, 1.0)))
		var opacity: float = clampf(strength * depth, 0.0, 1.0)
		if opacity <= 0.0:
			continue
		corners += 1
		for item in edge:
			var face: int = item.x
			var corner: int = item.y
			var first: Vector2 = model.uvs[face * 3 + corner] * size
			var second: Vector2 = model.uvs[face * 3 + (corner + 1) % 3] * size
			var third: Vector2 = model.uvs[face * 3 + (corner + 2) % 3] * size
			_ao_edge_strip(layer.tiles, first, second, third, Vector2i(doc.width, doc.height), radius, opacity, falloff)
	return {"layer": layer, "corners": corners}

## Central height differences produce OpenGL (+Y) tangent-space normals.
## Only painted Height tiles and their one-tile border are scanned, including at 4K.
static func normal_from_height(progress: BackgroundJob.JobProgress, doc: PaintDocument, strength: float) -> Dictionary:
	var layer := PaintLayer.new()
	layer.title = "From Height"
	layer.channel = "normal"
	var candidates: Dictionary = {}
	var extent := doc.tile_extent()
	for source in doc.layers:
		if source.channel != "height" or not source.visible or source.opacity <= 0.0: continue
		for bank in [source.tiles, source.masks if source.mask_enabled else {}]:
			for key in bank:
				for oy in range(-1,2):
					for ox in range(-1,2):
						var candidate: Vector2i = key + Vector2i(ox,oy)
						if candidate.x >= 0 and candidate.y >= 0 and candidate.x < extent.x and candidate.y < extent.y:
							candidates[candidate] = true
	var keys := candidates.keys()
	var cache: Dictionary = {}
	var affected := 0
	for k in keys.size():
		if progress.report(float(k) / maxi(1,keys.size()), "Generating Normal map from Height…"):
			return {"cancelled":true}
		var key: Vector2i = keys[k]
		var bytes := PackedByteArray()
		bytes.resize(64*64*4)
		var nonflat := false
		for y in mini(64,doc.height-key.y*64):
			var py := key.y*64+y
			for x in mini(64,doc.width-key.x*64):
				var px := key.x*64+x
				var left := _height_byte(cache,doc,px-1,py)
				var right := _height_byte(cache,doc,px+1,py)
				var up := _height_byte(cache,doc,px,py-1)
				var down := _height_byte(cache,doc,px,py+1)
				if left == right and up == down: continue
				var nx := (left-right) * strength / 255.0
				var ny := (down-up) * strength / 255.0
				var inverse := 1.0 / sqrt(nx*nx+ny*ny+1.0)
				var index := (y*64+x)*4
				bytes[index] = roundi((nx*inverse*0.5+0.5)*255.0)
				bytes[index+1] = roundi((ny*inverse*0.5+0.5)*255.0)
				bytes[index+2] = roundi((inverse*0.5+0.5)*255.0)
				bytes[index+3] = 255
				nonflat = true
				affected += 1
		if nonflat:
			layer.tiles[key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,bytes)
	return {"layer":layer,"pixels":affected}

static func _height_byte(cache: Dictionary, doc: PaintDocument, x: int, y: int) -> int:
	x = clampi(x,0,doc.width-1)
	y = clampi(y,0,doc.height-1)
	var key := Vector2i(x >> 6,y >> 6)
	if not cache.has(key):
		cache[key] = doc.compose_tile(key,"height").get_data()
	var bytes: PackedByteArray = cache[key]
	return bytes[((y%64)*64+x%64)*4]

## Non-destructive worker result for previewing a whole selected layer.
## A summed-area box filter keeps cost independent of blur radius per output texel.
static func blur_layer(progress: BackgroundJob.JobProgress, doc: PaintDocument, layer_id: String, radius: int) -> Dictionary:
	var source: PaintLayer
	for layer in doc.layers:
		if layer.id == layer_id: source = layer; break
	if source == null: return {"error":"The selected layer no longer exists."}
	radius = clampi(radius,1,32)
	var extent := doc.tile_extent()
	var candidates: Dictionary = {}
	for key in source.tiles:
		for oy in range(-1,2):
			for ox in range(-1,2):
				var neighbor: Vector2i = key+Vector2i(ox,oy)
				if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < extent.x and neighbor.y < extent.y:
					candidates[neighbor] = true
	var keys := candidates.keys()
	var result_tiles := source.tiles.duplicate()
	var changed: Array[Vector2i] = []
	for index in keys.size():
		if progress.report(float(index)/maxi(1,keys.size()),"Previewing layer blur…"):
			return {"cancelled":true}
		var key: Vector2i = keys[index]
		var original := source.tile_at(key,false,false)
		var softened := _blur_tile(source,key,radius)
		if softened.get_data() != original.get_data():
			result_tiles[key] = softened
			changed.append(key)
	return {"tiles":result_tiles,"changed":changed,"layer_id":layer_id,"radius":radius}

static func _blur_tile(layer: PaintLayer, key: Vector2i, radius: int) -> Image:
	var side := 64+radius*2
	var padded := Image.create(side,side,false,Image.FORMAT_RGBA8)
	padded.fill(layer.base_color)
	var bounds := Rect2i(key*64-Vector2i.ONE*radius,Vector2i.ONE*side)
	for ty in range(floori(float(bounds.position.y)/64.0),floori(float(bounds.end.y-1)/64.0)+1):
		for tx in range(floori(float(bounds.position.x)/64.0),floori(float(bounds.end.x-1)/64.0)+1):
			var tile_rect := Rect2i(tx*64,ty*64,64,64)
			var part := bounds.intersection(tile_rect)
			if not part.has_area(): continue
			padded.blit_rect(layer.tile_at(Vector2i(tx,ty),false,false),Rect2i(part.position-tile_rect.position,part.size),part.position-bounds.position)
	var data := padded.get_data()
	var stride := side+1
	var count := stride*stride
	var red := PackedInt32Array(); red.resize(count)
	var green := PackedInt32Array(); green.resize(count)
	var blue := PackedInt32Array(); blue.resize(count)
	var alpha := PackedInt32Array(); alpha.resize(count)
	for y in side:
		var rr := 0; var gg := 0; var bb := 0; var aa := 0
		for x in side:
			var pixel := (y*side+x)*4
			var a := int(data[pixel+3])
			rr += floori(int(data[pixel])*a/255.0)
			gg += floori(int(data[pixel+1])*a/255.0)
			bb += floori(int(data[pixel+2])*a/255.0)
			aa += a
			var at := (y+1)*stride+x+1
			var above := y*stride+x+1
			red[at] = red[above]+rr
			green[at] = green[above]+gg
			blue[at] = blue[above]+bb
			alpha[at] = alpha[above]+aa
	var output := PackedByteArray(); output.resize(64*64*4)
	var window := radius*2+1
	var area := window*window
	for y in 64:
		for x in 64:
			var a := y*stride+x
			var b := y*stride+x+window
			var c := (y+window)*stride+x
			var d := (y+window)*stride+x+window
			var sum_a := alpha[d]-alpha[b]-alpha[c]+alpha[a]
			if sum_a <= 0: continue
			var dst := (y*64+x)*4
			output[dst] = clampi(roundi(float(red[d]-red[b]-red[c]+red[a])*255.0/sum_a),0,255)
			output[dst+1] = clampi(roundi(float(green[d]-green[b]-green[c]+green[a])*255.0/sum_a),0,255)
			output[dst+2] = clampi(roundi(float(blue[d]-blue[b]-blue[c]+blue[a])*255.0/sum_a),0,255)
			output[dst+3] = clampi(roundi(float(sum_a)/area),0,255)
	return Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,output)

static func _ao_edge_strip(tiles: Dictionary, a: Vector2, b: Vector2, c: Vector2, size: Vector2i, radius: int, opacity: float, falloff: int) -> void:
	var edge: Vector2 = b - a
	var length: float = edge.length()
	if length < 0.001:
		return
	var inward := Vector2(-edge.y, edge.x) / length
	if inward.dot(c - a) < 0.0:
		inward = -inward
	var steps := maxi(1, ceili(length * 1.5))
	for step in steps + 1:
		var base: Vector2 = a.lerp(b, float(step) / steps)
		for distance in radius:
			var point: Vector2 = base + inward * distance
			var pixel := Vector2i(floori(point.x), floori(point.y))
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= size.x or pixel.y >= size.y:
				continue
			if not _triangle_contains(Vector2(pixel) + Vector2.ONE * 0.5, a, b, c):
				continue
			var t := 1.0 - float(distance) / maxi(1, radius)
			match falloff:
				1: t = t * t * (3.0 - 2.0 * t)
				2: t = t * t
			var alpha := opacity * t
			var key := Vector2i(pixel.x >> 6, pixel.y >> 6)
			if not tiles.has(key):
				var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
				image.fill(Color.TRANSPARENT)
				tiles[key] = image
			var tile: Image = tiles[key]
			var local := Vector2i(pixel.x % 64, pixel.y % 64)
			if tile.get_pixelv(local).a < alpha:
				tile.set_pixelv(local, Color(0, 0, 0, alpha))

static func _triangle_contains(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var first := (b - a).cross(point - a)
	var second := (c - b).cross(point - b)
	var third := (a - c).cross(point - c)
	return (first >= -0.001 and second >= -0.001 and third >= -0.001) or (first <= 0.001 and second <= 0.001 and third <= 0.001)
