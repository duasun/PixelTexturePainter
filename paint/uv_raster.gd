class_name UVRaster
extends RefCounted
## Conservative scanline coverage: every texel touched by a triangle is paintable,
## including slivers smaller than one pixel. Native fill_rect keeps large spans fast.
static func selection(model: ModelGeometry, faces: PackedInt32Array, size: Vector2i) -> Dictionary:
	var tiles: Dictionary = {}
	for face in faces:
		var tri := PackedVector2Array()
		for c in 3:
			tri.append(model.uvs[face * 3 + c] * Vector2(size))
		triangle(tiles, tri, size, Color.WHITE)
	return tiles

static func triangle(tiles: Dictionary, p: PackedVector2Array, size: Vector2i, color: Color) -> void:
	var first := maxi(0, floori(minf(p[0].y, minf(p[1].y, p[2].y))))
	var last := mini(size.y - 1, ceili(maxf(p[0].y, maxf(p[1].y, p[2].y))) - 1)
	for y in range(first, last + 1):
		var intersections: Array[float] = []
		var top := float(y)
		var bottom := float(y + 1)
		for vertex in p:
			if vertex.y >= top and vertex.y <= bottom:
				intersections.append(vertex.x)
		for e in 3:
			var a := p[e]
			var b := p[(e + 1) % 3]
			if not is_equal_approx(a.y,b.y):
				for line in [top,bottom]:
					if line >= minf(a.y,b.y) and line <= maxf(a.y,b.y):
						intersections.append(a.x + (line-a.y)*(b.x-a.x)/(b.y-a.y))
		if not intersections.is_empty():
			var left := intersections.min()
			var right := intersections.max()
			var x0 := maxi(0,floori(left))
			var x1 := mini(size.x-1,maxi(x0,ceili(right)-1))
			span(tiles,y,x0,x1,color)

static func span(tiles: Dictionary, y: int, x0: int, x1: int, color: Color) -> void:
	if x1 < x0:
		return
	for tx in range(x0 >> 6, (x1 >> 6) + 1):
		var key := Vector2i(tx, y >> 6)
		if not tiles.has(key):
			var tile := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			tile.fill(Color.TRANSPARENT)
			tiles[key] = tile
		var start := maxi(x0, tx * 64)
		var end := mini(x1 + 1, tx * 64 + 64)
		tiles[key].fill_rect(Rect2i(start % 64, y % 64, end - start, 1), color)
