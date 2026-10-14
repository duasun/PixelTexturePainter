class_name UVMaxRects
extends RefCounted
## Best short-side fit, 90-degree rotation, splitting and pruning free rectangles.
## Algorithm reference: Jukka Jylanki, A Thousand Ways to Pack the Bin (2010).
static func pack(sizes: Array[Vector2i], atlas: Vector2i, progress: BackgroundJob.JobProgress = null) -> Array[Rect2i]:
	var free: Array[Rect2i] = [Rect2i(Vector2i.ZERO, atlas)]
	var placed: Array[Rect2i] = []
	for dim in sizes:
		if progress != null and progress.is_cancelled():
			return []
		var best := Rect2i()
		var short_fit := 2147483647
		var long_fit := 2147483647
		for space in free:
			for rotated in 2:
				var candidate := Vector2i(dim.y, dim.x) if rotated else dim
				if candidate.x > space.size.x or candidate.y > space.size.y:
					continue
				var gap := space.size - candidate
				var small := mini(gap.x, gap.y)
				var large := maxi(gap.x, gap.y)
				if small < short_fit or (small == short_fit and large < long_fit):
					best = Rect2i(space.position, candidate)
					short_fit = small
					long_fit = large
		if best.size == Vector2i.ZERO:
			return []
		var next: Array[Rect2i] = []
		var untouched: Array[Rect2i] = []
		for space in free:
			if not space.intersects(best):
				untouched.append(space)
				continue
			if best.position.x > space.position.x:
				next.append(Rect2i(space.position, Vector2i(best.position.x - space.position.x, space.size.y)))
			if best.end.x < space.end.x:
				next.append(Rect2i(Vector2i(best.end.x, space.position.y), Vector2i(space.end.x - best.end.x, space.size.y)))
			if best.position.y > space.position.y:
				next.append(Rect2i(space.position, Vector2i(space.size.x, best.position.y - space.position.y)))
			if best.end.y < space.end.y:
				next.append(Rect2i(Vector2i(space.position.x, best.end.y), Vector2i(space.size.x, space.end.y - best.end.y)))
		free = untouched
		for candidate in next:
			if progress != null and progress.is_cancelled():
				return []
			var contained := false
			for space in free:
				if space.encloses(candidate):
					contained = true
					break
			if contained: continue
			for i in range(free.size()-1,-1,-1):
				if candidate.encloses(free[i]): free.remove_at(i)
			free.append(candidate)
		placed.append(best)
	return placed
