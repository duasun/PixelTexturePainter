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

static func texture_fill(progress: BackgroundJob.JobProgress, doc: PaintDocument, faces: PackedInt32Array, pattern: Image, settings: Dictionary, restriction: Dictionary = {}) -> Dictionary:
	var selection := restriction if not restriction.is_empty() else UVRaster.selection(doc.geometry, faces, Vector2i(doc.width, doc.height))
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
	length: int, color_a: Color, color_b: Color, ordered: bool, brush_width := 0, restriction: Dictionary = {}) -> Dictionary:
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
			if not restriction.is_empty() and not restriction.has(key): continue
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
					if not restriction.is_empty() and restriction[key].get_pixel(x,y).a == 0.0: continue
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
				if not restriction.is_empty() and not restriction.has(key): continue
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
						if not restriction.is_empty() and restriction[key].get_pixel(x,y).a == 0.0: continue
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
	layer.effect_kind = "edges"
	layer.mask_enabled = true
	var model := doc.geometry
	var faces := PackedInt32Array()
	for f in model.face_count():
		faces.append(f)
	layer.masks = UVRaster.selection(model, faces, Vector2i(doc.width, doc.height))
	var entries := model.edges.values()
	var island_masks: Dictionary = {}
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
			var inside := model.uvs[face * 3 + (c + 2) % 3] * Vector2(doc.width, doc.height)
			var along := (b - a).normalized()
			var inward := Vector2(-along.y, along.x)
			if inward.dot(inside - a) < 0.0: inward = -inward
			var steps := maxi(1, ceili(a.distance_to(b)))
			for s in steps + 1:
				var point := a.lerp(b, s / float(steps))
				for depth in maxi(1,width):
					var p := Vector2i((point + inward * (depth + 0.5)).floor())
					if p.x >= 0 and p.y >= 0 and p.x < doc.width and p.y < doc.height:
						UVRaster.span(layer.tiles, p.y, p.x, p.x, color)
			if scatter_reach > 0 and noise_amount > 0.0:
				_edge_scatter(layer.tiles,model,model.islands[face],island_masks,a,b,Vector2i(doc.width,doc.height),width,scatter_reach,noise_amount,side_falloff,color)
	return {"layer": layer}

static func _edge_scatter(tiles: Dictionary, model: ModelGeometry, island: int, mask_cache: Dictionary, a: Vector2, b: Vector2, size: Vector2i, width: int, reach: int, amount: float, falloff: float, color: Color) -> void:
	var edge := b-a
	var length_squared := edge.length_squared()
	if length_squared < 0.0001: return
	var outer := float(width+reach)
	var inner_squared := float(width*width)
	var outer_squared := outer*outer
	var last_mask_key := Vector3i(-1,-1,-1)
	var mask_data := PackedByteArray()
	var last_tile_key := Vector2i(-1,-1)
	var paint_tile: Image = null
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
			var px := x+0.5-a.x
			var py := y+0.5-a.y
			var along := clampf((px*edge.x+py*edge.y)/length_squared,0.0,1.0)
			var dx := px-edge.x*along
			var dy := py-edge.y*along
			var distance_squared := dx*dx+dy*dy
			if distance_squared <= inner_squared or distance_squared >= outer_squared: continue
			var noise := ((x*73856093) ^ (y*19349663)) & 0x7fffffff
			noise = ((noise ^ (noise >> 16))*2246822519) & 0x7fffffff
			noise = ((noise ^ (noise >> 13))*3266489917) & 0x7fffffff
			noise = noise ^ (noise >> 16)
			if float(noise & 65535)/65535.0 > amount: continue
			var key := Vector2i(x >> 6,y >> 6)
			var mask_key := Vector3i(island,key.x,key.y)
			if mask_key != last_mask_key:
				last_mask_key = mask_key
				if not mask_cache.has(mask_key):
					if mask_cache.size() >= 1024: mask_cache.clear()
					var island_mask := model.island_tile_mask(island,key,size)
					mask_cache[mask_key] = PackedByteArray() if island_mask == null else island_mask.get_data()
				mask_data = mask_cache[mask_key]
			if mask_data.is_empty() or mask_data[((y & 63)*64+(x & 63))*4+3] == 0: continue
			var distance_ratio := clampf((sqrt(distance_squared)-float(width))/float(reach),0.0,1.0)
			var remaining := 1.0-distance_ratio
			var faded := lerpf(1.0,remaining*remaining,falloff)
			var grain := 0.6+0.4*float((noise >> 16) & 32767)/32767.0
			var alpha := color.a*faded*grain
			if key != last_tile_key:
				last_tile_key = key
				if not tiles.has(key):
					var blank := Image.create(64,64,false,Image.FORMAT_RGBA8)
					blank.fill(Color.TRANSPARENT)
					tiles[key] = blank
				paint_tile = tiles[key]
			var local := Vector2i(x & 63,y & 63)
			if paint_tile.get_pixelv(local).a < alpha:
				paint_tile.set_pixelv(local,Color(color.r,color.g,color.b,alpha))

## Sample actual nearby geometry with hemisphere rays, then interpolate the
## result in UV space. Sampling is bounded per triangle even for 4K atlases.
static func cavity_ao(progress: BackgroundJob.JobProgress, doc: PaintDocument, strength: float, radius: int, depth_focus: float, falloff: int) -> Dictionary:
	var layer := PaintLayer.new()
	layer.title = "Cavity AO"
	layer.effect_kind = "ao"
	layer.channel = "albedo"
	if strength <= 0.0 or doc.geometry == null or not doc.geometry.has_uv:
		return {"layer": layer, "samples": 0}
	var model := doc.geometry
	var output_size := Vector2i(doc.width, doc.height)
	var factor := minf(1.0, 1024.0 / float(maxi(doc.width, doc.height)))
	var size := Vector2i(maxi(1,roundi(doc.width * factor)),maxi(1,roundi(doc.height * factor)))
	var work_radius := maxi(1,roundi(radius * factor))
	var samples := 0
	for face in model.face_count():
		if progress.report(float(face) / maxi(1, model.face_count()), "Baking ambient occlusion…"):
			return {"cancelled": true}
		var at := face * 3
		var a: Vector2 = model.uvs[at] * Vector2(size)
		var b: Vector2 = model.uvs[at + 1] * Vector2(size)
		var c: Vector2 = model.uvs[at + 2] * Vector2(size)
		var ab := b - a
		var ac := c - a
		var determinant := ab.cross(ac)
		if absf(determinant) < 0.0001:
			continue
		var p0: Vector3 = model.positions[at]
		var p1: Vector3 = model.positions[at + 1]
		var p2: Vector3 = model.positions[at + 2]
		var world_area := (p1 - p0).cross(p2 - p0).length()
		if world_area < 0.00000001:
			continue
		var world_per_pixel := sqrt(world_area / absf(determinant))
		var reach := maxf(world_per_pixel * float(work_radius), model.bounds.size.length() * 0.00001)
		var normal: Vector3 = model.face_normals[face]
		var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var bitangent := normal.cross(tangent)
		var shortest_edge := minf((p1 - p0).length(), minf((p2 - p0).length(), (p2 - p1).length()))
		var sample_inset := clampf(world_per_pixel * 2.0 / maxf(shortest_edge, 0.000001), 0.0, 0.1)
		var center := (p0 + p1 + p2) / 3.0
		var divisions := clampi(ceili(maxf(ab.length(), maxf(ac.length(), (c - b).length())) / maxf(4.0, float(work_radius) * 0.75)), 3, 20)
		var stride := divisions + 1
		var values := PackedFloat32Array()
		values.resize(stride * stride)
		var has_shadow := false
		for i in stride:
			for j in stride - i:
				var u := float(i) / float(divisions)
				var v := float(j) / float(divisions)
				var point := (p0 + (p1 - p0) * u + (p2 - p0) * v).lerp(center, sample_inset)
				var value := _ao_sample(model, face, point, normal, tangent, bitangent, reach, depth_focus, falloff, i * stride + j)
				values[i * stride + j] = value * clampf(strength, 0.0, 1.0)
				if value > 0.0:
					has_shadow = true
				samples += 1
		if not has_shadow:
			continue
		var x0 := clampi(floori(minf(a.x, minf(b.x, c.x))), 0, size.x - 1)
		var x1 := clampi(ceili(maxf(a.x, maxf(b.x, c.x))), 0, size.x - 1)
		var y0 := clampi(floori(minf(a.y, minf(b.y, c.y))), 0, size.y - 1)
		var y1 := clampi(ceili(maxf(a.y, maxf(b.y, c.y))), 0, size.y - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var offset := Vector2(x + 0.5, y + 0.5) - a
				var u := offset.cross(ac) / determinant
				var v := ab.cross(offset) / determinant
				if u < 0.0 or v < 0.0 or u + v > 1.0:
					continue
				var alpha := _ao_interpolate(values, divisions, u, v)
				if alpha < 1.0 / 255.0:
					continue
				var key := Vector2i(x >> 6, y >> 6)
				if not layer.tiles.has(key):
					var tile := Image.create(64, 64, false, Image.FORMAT_RGBA8)
					tile.fill(Color(0,0,0,0))
					layer.tiles[key] = tile
				var image: Image = layer.tiles[key]
				var local := Vector2i(x & 63, y & 63)
				if image.get_pixelv(local).a < alpha:
					image.set_pixelv(local, Color(0, 0, 0, alpha))
	if size != output_size and not layer.tiles.is_empty():
		if progress.report(0.98, "Scaling ambient occlusion to texture size…"):
			return {"cancelled": true}
		_ao_upscale(layer, size, output_size)
	return {"layer": layer, "samples": samples}

static func _ao_upscale(layer: PaintLayer, work_size: Vector2i, output_size: Vector2i) -> void:
	var atlas := Image.create(work_size.x, work_size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0,0,0,0))
	for key in layer.tiles:
		var origin: Vector2i = key * 64
		var part := Vector2i(mini(64,work_size.x-origin.x),mini(64,work_size.y-origin.y))
		atlas.blit_rect(layer.tiles[key],Rect2i(Vector2i.ZERO,part),origin)
	atlas.resize(output_size.x,output_size.y,Image.INTERPOLATE_BILINEAR)
	layer.tiles.clear()
	for y in range(0,output_size.y,64):
		for x in range(0,output_size.x,64):
			var key := Vector2i(x >> 6,y >> 6)
			var part := Vector2i(mini(64,output_size.x-x),mini(64,output_size.y-y))
			var tile := Image.create(64,64,false,Image.FORMAT_RGBA8)
			tile.fill(Color(0,0,0,0))
			tile.blit_rect(atlas,Rect2i(Vector2i(x,y),part),Vector2i.ZERO)
			if tile.get_used_rect().has_area(): layer.tiles[key] = tile

static func _ao_sample(model: ModelGeometry, face: int, point: Vector3, normal: Vector3, tangent: Vector3, bitangent: Vector3, reach: float, focus: float, falloff: int, sample_seed: int) -> float:
	const RAYS := 16
	var origin := point + normal * maxf(reach * 0.005, model.bounds.size.length() * 0.000001)
	var rotation := fposmod(float((sample_seed * 73 + face * 193) % 997) / 997.0, 1.0)
	var blocked := 0.0
	for k in RAYS:
		var r := sqrt((float(k) + 0.5) / float(RAYS))
		var angle := TAU * fposmod(float(k) * 0.61803398875 + rotation, 1.0)
		var direction := tangent * (cos(angle) * r) + bitangent * (sin(angle) * r) + normal * sqrt(1.0 - r * r)
		var distance := model.occlusion_distance(origin, direction, reach, face)
		if distance == INF:
			continue
		var weight := clampf(1.0 - distance / reach, 0.0, 1.0)
		match falloff:
			1: weight = weight * weight * (3.0 - 2.0 * weight)
			2: weight *= weight
		weight = pow(weight, lerpf(0.7, 2.0, clampf(focus, 0.0, 1.0)))
		blocked += weight
	return blocked / float(RAYS)

static func _ao_interpolate(values: PackedFloat32Array, divisions: int, u: float, v: float) -> float:
	var fx := clampf(u * divisions, 0.0, float(divisions) - 0.00001)
	var fy := clampf(v * divisions, 0.0, float(divisions) - 0.00001)
	var i := floori(fx)
	var j := floori(fy)
	var dx := fx - i
	var dy := fy - j
	var stride := divisions + 1
	if dx + dy <= 1.0 or i + j >= divisions - 1:
		return values[i * stride + j] * (1.0 - dx - dy) + values[(i + 1) * stride + j] * dx + values[i * stride + j + 1] * dy
	return values[(i + 1) * stride + j + 1] * (dx + dy - 1.0) + values[(i + 1) * stride + j] * (1.0 - dy) + values[i * stride + j + 1] * (1.0 - dx)

## Central height differences produce OpenGL (+Y) tangent-space normals.
## Only painted Height tiles and their one-tile border are scanned, including at 4K.
static func normal_from_height(progress: BackgroundJob.JobProgress, doc: PaintDocument, strength: float) -> Dictionary:
	var layer := PaintLayer.new()
	layer.title = "From Height"
	layer.effect_kind = "normal"
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

## A sparse, bounded line kernel. Nine or fewer samples keep the 4K worker
## predictable while premultiplied color avoids dark fringes on transparent paint.
static func directional_blur_layer(progress: BackgroundJob.JobProgress, doc: PaintDocument, layer_id: String, length: int, angle: float, strength: float, selection: Dictionary = {}) -> Dictionary:
	var source: PaintLayer
	for layer in doc.layers:
		if layer.id == layer_id: source = layer; break
	if source == null: return {"error":"The selected layer no longer exists."}
	length = clampi(length,2,64)
	strength = clampf(strength,0.0,1.0)
	var radius := maxi(1,roundi(length*0.5))
	var direction := Vector2.from_angle(deg_to_rad(angle))
	var offsets: Array[Vector2i] = []
	for i in 9:
		var position := Vector2i((direction*lerpf(-radius,radius,float(i)/8.0)).round())
		if not offsets.has(position): offsets.append(position)
	var extent := doc.tile_extent()
	var candidates: Dictionary = {}
	for key in source.tiles:
		for oy in range(-1,2):
			for ox in range(-1,2):
				var neighbor: Vector2i = key+Vector2i(ox,oy)
				if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < extent.x and neighbor.y < extent.y:
					if selection.is_empty() or selection.has(neighbor): candidates[neighbor] = true
	var keys := candidates.keys()
	var result_tiles := source.tiles.duplicate()
	var changed: Array[Vector2i] = []
	for index in keys.size():
		if progress.report(float(index)/maxi(1,keys.size()),"Previewing directional blur…"):
			return {"cancelled":true}
		var key: Vector2i = keys[index]
		var original := source.tile_at(key,false,false)
		var mask: Image = selection.get(key)
		var output := _directional_tile(source,key,radius,offsets,strength,mask)
		if output.get_data() != original.get_data():
			result_tiles[key] = output
			changed.append(key)
	return {"tiles":result_tiles,"changed":changed,"layer_id":layer_id,"length":length,"angle":angle,"strength":strength}

static func _directional_tile(layer: PaintLayer, key: Vector2i, radius: int, offsets: Array[Vector2i], strength: float, mask: Image) -> Image:
	var side := 64+radius*2
	var padded := Image.create(side,side,false,Image.FORMAT_RGBA8)
	padded.fill(layer.base_color)
	var bounds := Rect2i(key*64-Vector2i.ONE*radius,Vector2i.ONE*side)
	for ty in range(floori(float(bounds.position.y)/64.0),floori(float(bounds.end.y-1)/64.0)+1):
		for tx in range(floori(float(bounds.position.x)/64.0),floori(float(bounds.end.x-1)/64.0)+1):
			var tile_rect := Rect2i(tx*64,ty*64,64,64)
			var part := bounds.intersection(tile_rect)
			if part.has_area(): padded.blit_rect(layer.tile_at(Vector2i(tx,ty),false,false),Rect2i(part.position-tile_rect.position,part.size),part.position-bounds.position)
	var data := padded.get_data()
	var output := layer.tile_at(key,false,false).get_data()
	var mask_bytes := mask.get_data() if mask != null else PackedByteArray()
	for y in 64:
		for x in 64:
			var dst := (y*64+x)*4
			var mix_amount := strength*(float(mask_bytes[dst+3])/255.0 if not mask_bytes.is_empty() else 1.0)
			if mix_amount <= 0.0: continue
			var sum_r := 0; var sum_g := 0; var sum_b := 0; var sum_a := 0
			for offset in offsets:
				var src := ((y+radius+offset.y)*side+x+radius+offset.x)*4
				var alpha := int(data[src+3])
				sum_a += alpha
				sum_r += int(data[src])*alpha
				sum_g += int(data[src+1])*alpha
				sum_b += int(data[src+2])*alpha
			var blur_a := float(sum_a)/offsets.size()
			var center_a := float(output[dst+3])
			var out_a := lerpf(center_a,blur_a,mix_amount)
			if out_a < 0.5:
				for channel in 4: output[dst+channel] = 0
				continue
			for channel in 3:
				var sum_channel := sum_r if channel == 0 else sum_g if channel == 1 else sum_b
				var center_premultiplied := float(output[dst+channel])*center_a/255.0
				var blurred_premultiplied := float(sum_channel)/(offsets.size()*255.0)
				output[dst+channel] = clampi(roundi(lerpf(center_premultiplied,blurred_premultiplied,mix_amount)*255.0/out_a),0,255)
			output[dst+3] = clampi(roundi(out_a),0,255)
	return Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,output)

static func _triangle_contains(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var first := (b - a).cross(point - a)
	var second := (c - b).cross(point - b)
	var third := (a - c).cross(point - c)
	return (first >= -0.001 and second >= -0.001 and third >= -0.001) or (first <= 0.001 and second <= 0.001 and third <= 0.001)
