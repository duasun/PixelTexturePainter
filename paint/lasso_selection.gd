class_name LassoSelection
extends RefCounted
## Builds tiled UV masks away from the UI thread. Model lasso tests visibility in
## coarse screen cells so a hidden side is never selected by a front-side stroke.

static func snap_uv(point: Vector2, tile: Image, tile_origin: Vector2i, radius := 3) -> Vector2:
	if tile == null: return point
	var center := Vector2i(point.floor())-tile_origin
	if center.x < radius or center.y < radius or center.x >= tile.get_width()-radius-1 or center.y >= tile.get_height()-radius-1: return point
	var best := point
	var best_score := 0.12
	for y in range(center.y-radius,center.y+radius+1):
		for x in range(center.x-radius,center.x+radius+1):
			var current := tile.get_pixel(x,y)
			var right := tile.get_pixel(x+1,y)
			var down := tile.get_pixel(x,y+1)
			var contrast := maxf(_color_gap(current,right),_color_gap(current,down))
			var candidate := Vector2(tile_origin+Vector2i(x,y))+Vector2.ONE*0.5
			var score := contrast-point.distance_to(candidate)*0.025
			if score > best_score:
				best_score = score
				best = candidate
	return best

static func _color_gap(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),maxf(absf(a.b-b.b),absf(a.a-b.a)))

static func uv_mask(points: PackedVector2Array, size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	if points.size() < 3: return result
	var low := size.y - 1
	var high := 0
	for point in points:
		low = mini(low,floori(point.y))
		high = maxi(high,ceili(point.y))
	for y in range(maxi(0,low),mini(size.y-1,high)+1):
		var crossings: Array[float] = []
		var row := float(y)+0.5
		for i in points.size():
			var a := points[i]
			var b := points[(i+1)%points.size()]
			if (a.y <= row and b.y > row) or (b.y <= row and a.y > row):
				crossings.append(a.x+(row-a.y)*(b.x-a.x)/(b.y-a.y))
		crossings.sort()
		for pair in floori(float(crossings.size())/2.0):
			var left := maxi(0,ceili(crossings[pair*2]-0.5))
			var right := mini(size.x-1,floori(crossings[pair*2+1]-0.5))
			UVRaster.span(result,y,left,right,Color.WHITE)
	return result

static func model_mask(progress: BackgroundJob.JobProgress, model: ModelGeometry, polygon: PackedVector2Array, size: Vector2i, view_size: Vector2, camera_transform: Transform3D, projection: Projection) -> Dictionary:
	var result: Dictionary = {}
	if polygon.size() < 3: return result
	var view := camera_transform.affine_inverse()
	var camera_position := camera_transform.origin
	var visible_cells: Dictionary = {}
	var texture_size := Vector2(size)
	for face in model.face_count():
		if progress.report(float(face)/maxi(1,model.face_count()),"Selecting visible texels…"): return {}
		var vertices: Array[Vector3] = [model.positions[face*3],model.positions[face*3+1],model.positions[face*3+2]]
		var center: Vector3 = (vertices[0]+vertices[1]+vertices[2])/3.0
		if model.face_normals[face].dot(camera_position-center) <= 0.0: continue
		var uv: Array[Vector2] = [model.uvs[face*3]*texture_size,model.uvs[face*3+1]*texture_size,model.uvs[face*3+2]*texture_size]
		var determinant: float = (uv[1]-uv[0]).cross(uv[2]-uv[0])
		if absf(determinant) < 0.00001: continue
		var x0 := maxi(0,floori(minf(uv[0].x,minf(uv[1].x,uv[2].x))))
		var x1 := mini(size.x-1,ceili(maxf(uv[0].x,maxf(uv[1].x,uv[2].x)))-1)
		var y0 := maxi(0,floori(minf(uv[0].y,minf(uv[1].y,uv[2].y))))
		var y1 := mini(size.y-1,ceili(maxf(uv[0].y,maxf(uv[1].y,uv[2].y)))-1)
		for y in range(y0,y1+1):
			if y % 64 == 0 and progress.is_cancelled(): return {}
			for x in range(x0,x1+1):
				var p := Vector2(x+0.5,y+0.5)-uv[0]
				var b: float = p.cross(uv[2]-uv[0])/determinant
				var c: float = (uv[1]-uv[0]).cross(p)/determinant
				var a: float = 1.0-b-c
				if a < -0.001 or b < -0.001 or c < -0.001: continue
				var position: Vector3 = vertices[0]*a+vertices[1]*b+vertices[2]*c
				var local := view * position
				var clip := projection * Vector4(local.x,local.y,local.z,1.0)
				if clip.w <= 0.0: continue
				var screen := Vector2((clip.x/clip.w*0.5+0.5)*view_size.x,(0.5-clip.y/clip.w*0.5)*view_size.y)
				if not Geometry2D.is_point_in_polygon(screen,polygon): continue
				var cell := Vector2i(screen/4.0)
				if not visible_cells.has(cell):
					var ray_direction := (position-camera_position).normalized()
					visible_cells[cell] = int(model.ray_hit(camera_position,ray_direction).get("face",-1))
				if int(visible_cells[cell]) != face: continue
				var key := Vector2i(x>>6,y>>6)
				if not result.has(key):
					var tile := Image.create(64,64,false,Image.FORMAT_RGBA8)
					tile.fill(Color.TRANSPARENT)
					result[key] = tile
				result[key].set_pixel(x&63,y&63,Color.WHITE)
	return result

static func boundary(selection: Dictionary, size: Vector2i) -> Image:
	var full: Dictionary = {}
	var partial: Dictionary = {}
	for key in selection:
		var data: PackedByteArray = selection[key].get_data()
		if data.has(0): partial[key] = data
		else: full[key] = true
	var border := PackedByteArray()
	border.resize(size.x*size.y)
	for key in selection:
		var width := mini(64,size.x-key.x*64)
		var height := mini(64,size.y-key.y*64)
		if full.has(key):
			if not full.has(key+Vector2i.LEFT):
				for y in height:
					var py: int = key.y*64+y
					var px: int = key.x*64
					if not _selected_at(px-1,py,size,full,partial): border[py*size.x+px] = 255
			if not full.has(key+Vector2i.RIGHT):
				for y in height:
					var py: int = key.y*64+y
					var px: int = key.x*64+width-1
					if not _selected_at(px+1,py,size,full,partial): border[py*size.x+px] = 255
			if not full.has(key+Vector2i.UP):
				for x in width:
					var px: int = key.x*64+x
					var py: int = key.y*64
					if not _selected_at(px,py-1,size,full,partial): border[py*size.x+px] = 255
			if not full.has(key+Vector2i.DOWN):
				for x in width:
					var px: int = key.x*64+x
					var py: int = key.y*64+height-1
					if not _selected_at(px,py+1,size,full,partial): border[py*size.x+px] = 255
		else:
			var alpha: PackedByteArray = partial[key]
			for y in height:
				for x in width:
					if alpha[(y*64+x)*4+3] == 0: continue
					var px: int = key.x*64+x
					var py: int = key.y*64+y
					if not _selected_at(px-1,py,size,full,partial) or not _selected_at(px+1,py,size,full,partial) or not _selected_at(px,py-1,size,full,partial) or not _selected_at(px,py+1,size,full,partial):
						border[py*size.x+px] = 255
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_R8,border)

static func _selected_at(x: int, y: int, size: Vector2i, full: Dictionary, partial: Dictionary) -> bool:
	if x < 0 or y < 0 or x >= size.x or y >= size.y: return false
	var key := Vector2i(x>>6,y>>6)
	if full.has(key): return true
	if not partial.has(key): return false
	var data: PackedByteArray = partial[key]
	return data[(((y&63)*64)+(x&63))*4+3] != 0
