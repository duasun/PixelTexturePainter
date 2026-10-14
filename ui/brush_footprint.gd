class_name BrushFootprint
extends RefCounted
## Pixel-cell outline uses the same center test as PaintEngine's raster stamp.
static func outline(diameter: int, round_brush: bool) -> PackedVector2Array:
	var lines := PackedVector2Array()
	if not round_brush:
		var d := float(diameter)
		return PackedVector2Array([Vector2.ZERO, Vector2(d, 0), Vector2(d, 0), Vector2(d, d), Vector2(d, d), Vector2(0, d), Vector2(0, d), Vector2.ZERO])
	var radius := diameter / 2.0
	var previous := Vector2i(-1, -1)
	for y in range(diameter + 1):
		var row := Vector2i(-1, -1)
		if y < diameter:
			var dy := y + 0.5 - radius
			var half := sqrt(maxf(0.0, radius * radius - dy * dy))
			row = Vector2i(ceili(radius - half - 0.5), floori(radius + half - 0.5) + 1)
			lines.append_array(PackedVector2Array([Vector2(row.x, y), Vector2(row.x, y + 1), Vector2(row.y, y), Vector2(row.y, y + 1)]))
		if previous.x < 0:
			lines.append_array(PackedVector2Array([Vector2(row.x, y), Vector2(row.y, y)]))
		elif row.x < 0:
			lines.append_array(PackedVector2Array([Vector2(previous.x, y), Vector2(previous.y, y)]))
		else:
			lines.append_array(PackedVector2Array([Vector2(previous.x, y), Vector2(row.x, y), Vector2(previous.y, y), Vector2(row.y, y)]))
		previous = row
	return lines
