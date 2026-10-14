class_name ModelGeometry
extends RefCounted
## Triangle corners are explicit: UV seams never change topology accidentally.
var positions := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var materials := PackedInt32Array()
var objects := PackedInt32Array()
var islands := PackedInt32Array()
var has_uv := true
var label := "Model"
var bounds := AABB()
var face_normals := PackedVector3Array()
var neighbors: Array = []
var edges: Dictionary = {}
var bvh: Dictionary = {}
var uv_buckets: Dictionary = {}

func face_count() -> int:
	return floori(positions.size() / 3.0)

func grow_selection(faces: PackedInt32Array) -> PackedInt32Array:
	var expanded: Dictionary = {}
	for face in faces:
		if face < 0 or face >= face_count(): continue
		expanded[face] = true
		for adjacent in neighbors[face]: expanded[adjacent] = true
	var result := PackedInt32Array(expanded.keys())
	result.sort()
	return result

func build_cache() -> void:
	if positions.is_empty():
		return
	bounds = AABB(positions[0], Vector3.ZERO)
	for p in positions:
		bounds = bounds.expand(p)
	face_normals.resize(face_count())
	neighbors.clear()
	edges.clear()
	var quantum := maxf(bounds.size.length() * 0.000001, 0.0000001)
	for f in face_count():
		var i := f * 3
		face_normals[f] = (positions[i + 2] - positions[i]).cross(positions[i + 1] - positions[i]).normalized()
		neighbors.append([])
		for e in 3:
			var a := _vertex_key(positions[i + e], quantum)
			var b := _vertex_key(positions[i + (e + 1) % 3], quantum)
			var k := str(objects[f]) + ":" + (a + "/" + b if a < b else b + "/" + a)
			if not edges.has(k):
				edges[k] = []
			edges[k].append(Vector2i(f, e))
	for entries in edges.values():
		if entries.size() == 2:
			neighbors[entries[0].x].append(entries[1].x)
			neighbors[entries[1].x].append(entries[0].x)
	if islands.size() != face_count():
		islands.resize(face_count())
		islands.fill(-1)
		var next_id := 0
		for f in face_count():
			if islands[f] >= 0:
				continue
			var queue: Array[int] = [f]
			islands[f] = next_id
			while not queue.is_empty():
				var current: int = queue.pop_back()
				for other in neighbors[current]:
					if islands[other] < 0 and _uv_connected(current, other):
						islands[other] = next_id
						queue.append(other)
			next_id += 1
	var faces: Array[int] = []
	uv_buckets.clear()
	for f in face_count():
		faces.append(f)
		var minimum := uvs[f * 3].min(uvs[f * 3 + 1]).min(uvs[f * 3 + 2])
		var maximum := uvs[f * 3].max(uvs[f * 3 + 1]).max(uvs[f * 3 + 2])
		for by in range(clampi(floori(minimum.y * 16), 0, 15), clampi(floori(maximum.y * 16), 0, 15) + 1):
			for bx in range(clampi(floori(minimum.x * 16), 0, 15), clampi(floori(maximum.x * 16), 0, 15) + 1):
				var key := Vector3i(islands[f], bx, by)
				if not uv_buckets.has(key):
					uv_buckets[key] = []
				uv_buckets[key].append(f)
	bvh = _build_bvh(faces)

func island_tile_mask(island: int, tile: Vector2i, resolution: Vector2i) -> Image:
	var candidates: Dictionary = {}
	var first := Vector2(tile * 64) / Vector2(resolution) * 16.0
	var last := Vector2(tile * 64 + Vector2i(63, 63)) / Vector2(resolution) * 16.0
	for by in range(clampi(floori(first.y), 0, 15), clampi(floori(last.y), 0, 15) + 1):
		for bx in range(clampi(floori(first.x), 0, 15), clampi(floori(last.x), 0, 15) + 1):
			for f in uv_buckets.get(Vector3i(island, bx, by), []):
				candidates[f] = true
	var masks: Dictionary = {}
	for f in candidates:
		var triangle := PackedVector2Array()
		for c in 3:
			triangle.append(uvs[f * 3 + c] * Vector2(resolution) - Vector2(tile * 64))
		UVRaster.triangle(masks, triangle, Vector2i(64, 64), Color.WHITE)
	return masks.get(Vector2i.ZERO)

func surface_at_uv(uv: Vector2, island: int, preferred_face: int = -1) -> Dictionary:
	if island < 0 or uv_buckets.is_empty():
		return {}
	var cell := Vector3i(island, clampi(floori(uv.x * 16.0), 0, 15), clampi(floori(uv.y * 16.0), 0, 15))
	var candidates: Array = uv_buckets.get(cell, [])
	if preferred_face >= 0 and candidates.has(preferred_face):
		var preferred := _surface_on_face(preferred_face, uv)
		if not preferred.is_empty(): return preferred
	for face in candidates:
		var found := _surface_on_face(face, uv)
		if not found.is_empty(): return found
	return {}

func _surface_on_face(face: int, uv: Vector2) -> Dictionary:
	var at := face * 3
	var a := uvs[at]
	var ab := uvs[at + 1] - a
	var ac := uvs[at + 2] - a
	var det := ab.cross(ac)
	if absf(det) < 0.00000001: return {}
	var offset := uv - a
	var u := offset.cross(ac) / det
	var v := ab.cross(offset) / det
	if u < -0.0001 or v < -0.0001 or u + v > 1.0001: return {}
	return {"face": face, "position": positions[at] * (1.0 - u - v) + positions[at + 1] * u + positions[at + 2] * v}

func face_world_per_pixel(face: int, resolution: Vector2i) -> float:
	var at := face * 3
	var world_area := (positions[at + 1] - positions[at]).cross(positions[at + 2] - positions[at]).length()
	var uv_area := ((uvs[at + 1] - uvs[at]) * Vector2(resolution)).cross((uvs[at + 2] - uvs[at]) * Vector2(resolution))
	return sqrt(world_area / maxf(absf(uv_area), 0.000001))

## Map the portion of a UV dab that crosses a shared 3D edge onto the
## neighboring chart. The projected center stays outside that chart by the
## source point's edge distance, so only the overlapping portion is painted.
func edge_wrap_targets(face: int, point: Vector3, diameter: int, resolution: Vector2i, allowed_faces: Dictionary, camera_position: Vector3 = Vector3.ZERO, visible_only := false) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if face < 0 or face >= face_count() or not allowed_faces.is_empty() and not allowed_faces.has(face): return targets
	var radius_world := float(diameter) * 0.5 * face_world_per_pixel(face, resolution)
	for neighbor in neighbors[face]:
		if islands[neighbor] == islands[face] or not allowed_faces.is_empty() and not allowed_faces.has(neighbor): continue
		if visible_only and face_normals[neighbor].dot(camera_position - point) < -bounds.size.length() * 0.00001: continue
		var pairs: Array[Vector2i] = []
		for a in 3:
			for b in 3:
				if positions[face * 3 + a].is_equal_approx(positions[neighbor * 3 + b]): pairs.append(Vector2i(a, b))
		if pairs.size() != 2: continue
		var p0 := positions[face * 3 + pairs[0].x]
		var p1 := positions[face * 3 + pairs[1].x]
		var edge := p1 - p0
		var fraction := clampf((point - p0).dot(edge) / maxf(edge.length_squared(), 0.00000001), 0.0, 1.0)
		var distance := point.distance_to(p0 + edge * fraction)
		if distance > radius_world: continue
		var uv0 := uvs[neighbor * 3 + pairs[0].y] * Vector2(resolution)
		var uv1 := uvs[neighbor * 3 + pairs[1].y] * Vector2(resolution)
		var third := uvs[neighbor * 3 + 3 - pairs[0].y - pairs[1].y] * Vector2(resolution)
		var uv_edge := uv1 - uv0
		if uv_edge.length_squared() < 0.000001: continue
		var inward := Vector2(-uv_edge.y, uv_edge.x).normalized()
		if inward.dot(third - uv0) < 0.0: inward = -inward
		var center := uv0.lerp(uv1, fraction) - inward * (distance / maxf(face_world_per_pixel(neighbor, resolution), 0.00000001))
		targets.append({"uv": center / Vector2(resolution), "island": islands[neighbor], "face": neighbor})
	return targets

func _vertex_key(v: Vector3, q: float) -> String:
	return "%d,%d,%d" % [roundi(v.x / q), roundi(v.y / q), roundi(v.z / q)]

func _uv_connected(a: int, b: int) -> bool:
	if materials[a] != materials[b]:
		return false
	var common := 0
	for i in 3:
		for j in 3:
			if positions[a * 3 + i].is_equal_approx(positions[b * 3 + j]) and uvs[a * 3 + i].is_equal_approx(uvs[b * 3 + j]):
				common += 1
	return common >= 2

func _build_bvh(faces: Array[int]) -> Dictionary:
	var box := AABB(positions[faces[0] * 3], Vector3.ZERO)
	for f in faces:
		for c in 3:
			box = box.expand(positions[f * 3 + c])
	box = box.grow(maxf(bounds.size.length() * 0.0000001, 0.000001))
	if faces.size() <= 8:
		return {"box": box, "faces": faces}
	var axis := box.size.max_axis_index()
	faces.sort_custom(func(a: int, b: int) -> bool:
		return (positions[a * 3][axis] + positions[a * 3 + 1][axis] + positions[a * 3 + 2][axis]) < (positions[b * 3][axis] + positions[b * 3 + 1][axis] + positions[b * 3 + 2][axis]))
	var half := faces.size() >> 1
	return {"box": box, "left": _build_bvh(faces.slice(0, half)), "right": _build_bvh(faces.slice(half))}

func ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if bvh.is_empty():
		return {}
	var best := {"distance": INF}
	_trace(bvh, origin, direction, best)
	return best if best.has("face") else {}

## A bounded, two-sided ray query for texture baking. The paint picker above
## intentionally ignores back faces; ambient occlusion must see both sides of
## open geometry and must not allocate a hit dictionary for every sample.
func occlusion_distance(origin: Vector3, direction: Vector3, limit: float, ignore_face: int = -1) -> float:
	if bvh.is_empty() or limit <= 0.0:
		return INF
	return _trace_occlusion(bvh, origin, direction, limit, ignore_face)

func _trace_occlusion(node: Dictionary, origin: Vector3, direction: Vector3, limit: float, ignore_face: int) -> float:
	var box: AABB = node.box
	if not box.intersects_segment(origin, origin + direction * limit):
		return INF
	var best := INF
	if node.has("faces"):
		for f in node.faces:
			if f == ignore_face:
				continue
			var i: int = f * 3
			var e1 := positions[i + 1] - positions[i]
			var e2 := positions[i + 2] - positions[i]
			var p := direction.cross(e2)
			var det := e1.dot(p)
			if absf(det) < 0.00000001:
				continue
			var t := origin - positions[i]
			var u := t.dot(p) / det
			if u < -0.00001 or u > 1.00001:
				continue
			var q := t.cross(e1)
			var v := direction.dot(q) / det
			if v < -0.00001 or u + v > 1.00001:
				continue
			var distance := e2.dot(q) / det
			if distance > 0.0 and distance <= limit:
				best = minf(best, distance)
	else:
		best = minf(best, _trace_occlusion(node.left, origin, direction, limit, ignore_face))
		best = minf(best, _trace_occlusion(node.right, origin, direction, minf(limit, best), ignore_face))
	return best

func mirrored_hit(hit: Dictionary, axes: int) -> Dictionary:
	if hit.is_empty() or axes == 0: return {}
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var center := bounds.get_center()
	if axes & 1: point.x = center.x*2.0-point.x; normal.x = -normal.x
	if axes & 2: point.y = center.y*2.0-point.y; normal.y = -normal.y
	if axes & 4: point.z = center.z*2.0-point.z; normal.z = -normal.z
	var tolerance := maxf(bounds.size.length()*0.002,0.0001)
	if point.distance_to(hit.position) <= tolerance*0.5: return {}
	var mirror := ray_hit(point+normal*tolerance,-normal)
	if mirror.is_empty() or mirror.position.distance_to(point)>tolerance*2.0: return {}
	return mirror

func _trace(node: Dictionary, origin: Vector3, direction: Vector3, best: Dictionary) -> void:
	if node.box.intersects_ray(origin, direction) == null:
		return
	if node.has("faces"):
		for f in node.faces:
			if face_normals[f].dot(direction) >= -0.000001:
				continue
			var i: int = f * 3
			var e1 := positions[i + 1] - positions[i]
			var e2 := positions[i + 2] - positions[i]
			var p := direction.cross(e2)
			var det := e1.dot(p)
			if absf(det) < 0.00000001:
				continue
			var t := origin - positions[i]
			var u := t.dot(p) / det
			if u < -0.00001 or u > 1.00001:
				continue
			var q := t.cross(e1)
			var v := direction.dot(q) / det
			if v < -0.00001 or u + v > 1.00001:
				continue
			var distance := e2.dot(q) / det
			if distance > 0.0 and distance < best.distance:
				best.distance = distance
				best.face = f
				best.uv = uvs[i] * (1.0 - u - v) + uvs[i + 1] * u + uvs[i + 2] * v
				best.position = origin + direction * distance
				best.normal = face_normals[f]
	else:
		_trace(node.left, origin, direction, best)
		_trace(node.right, origin, direction, best)

func to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var ids := PackedVector2Array()
	for f in face_count():
		for c in 3:
			ids.append(Vector2(islands[f], 0))
	arrays[Mesh.ARRAY_TEX_UV2] = ids
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func serialized() -> Dictionary:
	return {"positions": positions, "normals": normals, "uvs": uvs, "materials": materials,
		"objects": objects, "islands": islands, "has_uv": has_uv, "label": label}

static func from_data(data: Dictionary) -> ModelGeometry:
	var result := ModelGeometry.new()
	result.positions = data.get("positions", PackedVector3Array()).duplicate()
	result.normals = data.get("normals", PackedVector3Array()).duplicate()
	result.uvs = data.get("uvs", PackedVector2Array()).duplicate()
	result.materials = data.get("materials", PackedInt32Array()).duplicate()
	result.objects = data.get("objects", PackedInt32Array()).duplicate()
	result.islands = data.get("islands", PackedInt32Array()).duplicate()
	result.has_uv = data.get("has_uv", true)
	result.label = data.get("label", "Model")
	return result

static func demo() -> ModelGeometry:
	var model := ModelGeometry.new()
	model.label = "Field crate"
	model._box(Vector3(0, 0, 0), Vector3(2.0, 1.5, 1.35), 0)
	model._box(Vector3(0, 0.82, 0), Vector3(2.14, 0.15, 1.49), 1)
	model._box(Vector3(0, -0.77, 0), Vector3(2.14, 0.12, 1.49), 1)
	for x in [-0.81, 0.81]:
		model._box(Vector3(x, 0, 0.70), Vector3(0.18, 1.5, 0.12), 2)
		model._box(Vector3(x, 0, -0.70), Vector3(0.18, 1.5, 0.12), 2)
	model._box(Vector3(0, 0.05, 0.72), Vector3(0.60, 0.42, 0.12), 3)
	model.build_cache()
	return model

func _box(center: Vector3, size: Vector3, mat: int) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tex: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var obj := objects.size()
	for i in indices.size():
		var idx := indices[i]
		positions.append(verts[idx] + center)
		normals.append(norms[idx])
		uvs.append(tex[idx])
		if i % 3 == 0:
			materials.append(mat)
			objects.append(obj)
