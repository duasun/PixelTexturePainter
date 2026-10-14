class_name UVUnwrapper
extends RefCounted
## Dependency-free chart projection for low-poly assets. Runs on the job worker.
const PACK_ATTEMPTS := 10
static func unwrap(source: ModelGeometry, width: int, height: int, angle := 45.0, padding := 2, progress: BackgroundJob.JobProgress = null) -> Dictionary:
	var model := ModelGeometry.from_data(source.serialized())
	model.build_cache()
	var assigned := PackedByteArray()
	assigned.resize(model.face_count())
	var charts: Array[Dictionary] = []
	var threshold := cos(deg_to_rad(clampf(angle, 1.0, 80.0)))
	for seed in model.face_count():
		if progress != null and progress.report(0.05 + 0.35 * seed / float(model.face_count()), "Projecting UV charts…"):
			return {"cancelled": true}
		if assigned[seed]:
			continue
		var faces: Array[int] = []
		var queue: Array[int] = [seed]
		assigned[seed] = 1
		var normal: Vector3 = model.face_normals[seed]
		while not queue.is_empty():
			if progress != null and progress.is_cancelled():
				return {"cancelled": true}
			var current: int = queue.pop_back()
			faces.append(current)
			for other in model.neighbors[current]:
				if not assigned[other] and model.materials[other] == model.materials[seed] and model.face_normals[other].dot(normal) >= threshold:
					assigned[other] = 1
					queue.append(other)
		var chart := _project(model, faces, normal)
		# Conservative validation: overlapping projected triangles become separate charts.
		if _overlapping(chart, progress):
			for f in faces:
				charts.append(_project(model, [f], model.face_normals[f]))
		else:
			charts.append(chart)
	charts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.area > b.area)
	var area := 0.0
	for chart in charts:
		area += maxf(chart.size.x * chart.size.y, 0.000000001)
	var low := 0.0
	var high := sqrt(float(width * height) / maxf(area, 0.00000001)) * 2.0
	var best: Array[Rect2i] = []
	var best_sizes: Array[Vector2i] = []
	for attempt in PACK_ATTEMPTS:
		if progress != null and progress.report(0.4 + 0.5 * attempt / PACK_ATTEMPTS, "Packing %d UV islands…" % charts.size()):
			return {"cancelled": true}
		var scale := (low + high) * 0.5
		var sizes: Array[Vector2i] = []
		for chart in charts:
			sizes.append(Vector2i(maxi(2, ceili(chart.size.x * scale)), maxi(2, ceili(chart.size.y * scale))) + Vector2i.ONE * padding * 2)
		var rectangles := UVMaxRects.pack(sizes, Vector2i(width, height), progress)
		if rectangles.is_empty():
			high = scale
		else:
			low = scale
			best = rectangles
			best_sizes = sizes
	if best.is_empty():
		return {"error": "UV islands do not fit. Increase resolution or reduce padding."}
	model.islands.resize(model.face_count())
	var used_area := 0
	for ci in charts.size():
		var chart: Dictionary = charts[ci]
		var rect := best[ci]
		var rotated := rect.size != best_sizes[ci]
		used_area += rect.get_area()
		for local in chart.faces.size():
			var f: int = chart.faces[local]
			model.islands[f] = ci
			for c in 3:
				var point: Vector2 = (chart.points[local * 3 + c] - chart.origin) * low
				if rotated:
					point = Vector2(point.y, chart.size.x * low - point.x)
				var pixel := Vector2(rect.position + Vector2i.ONE * padding) + Vector2(0.5, 0.5) + point
				model.uvs[f * 3 + c] = pixel / Vector2(width, height)
	model.has_uv = true
	model.build_cache()
	var subpixel_faces := 0
	for face in model.face_count():
		var a := model.uvs[face*3]*Vector2(width,height)
		var b := model.uvs[face*3+1]*Vector2(width,height)
		var c := model.uvs[face*3+2]*Vector2(width,height)
		if absf((b-a).cross(c-a))*0.5 < 1.0: subpixel_faces += 1
	return {"geometry": model, "islands": charts.size(), "occupancy": float(used_area) / (width * height),
		"subpixel_faces":subpixel_faces}

static func _project(model: ModelGeometry, faces: Array, normal: Vector3) -> Dictionary:
	var reference := Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	var u := reference.cross(normal).normalized()
	var v := normal.cross(u).normalized()
	var points := PackedVector2Array()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for f in faces:
		for c in 3:
			var p := model.positions[f * 3 + c]
			var point := Vector2(p.dot(u), p.dot(v))
			points.append(point)
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	var size := (maximum - minimum).max(Vector2(0.000001, 0.000001))
	return {"faces": faces, "points": points, "origin": minimum, "size": size, "area": size.x * size.y}

static func _overlapping(chart: Dictionary, progress: BackgroundJob.JobProgress = null) -> bool:
	var points: PackedVector2Array = chart.points
	# Broad phase avoids polygon intersections for disjoint triangle bounds.
	var boxes: Array[Rect2] = []
	for i in chart.faces.size():
		boxes.append(Rect2(points[i * 3], Vector2.ZERO).expand(points[i * 3 + 1]).expand(points[i * 3 + 2]))
	for a in chart.faces.size():
		if progress != null and progress.is_cancelled():
			return false
		var tri_a := PackedVector2Array([points[a * 3], points[a * 3 + 1], points[a * 3 + 2]])
		for b in range(a + 1, chart.faces.size()):
			if not boxes[a].intersects(boxes[b]):
				continue
			var tri_b := PackedVector2Array([points[b * 3], points[b * 3 + 1], points[b * 3 + 2]])
			var intersection := Geometry2D.intersect_polygons(tri_a, tri_b)
			for polygon in intersection:
				var signed_area := 0.0
				for i in polygon.size():
					signed_area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
				if absf(signed_area) > maxf(chart.area * 0.0000001, 0.0000000001):
					return true
	return false
