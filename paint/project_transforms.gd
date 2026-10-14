class_name ProjectTransforms
extends RefCounted
## Full-document edits run on BackgroundJob; original layers remain untouched for Undo.

static func import_materials(progress: BackgroundJob.JobProgress, source: ModelGeometry, materials: Dictionary, size: Vector2i) -> Dictionary:
	# Material import must not replace UVs authored in the source model.
	var banks := {}
	var source_bytes := {}
	var owners := {}
	var overlaps := 0
	var textured_materials := 0
	for material_id in materials:
		var entries: Dictionary = materials[material_id]
		var prepared := {}
		for channel in entries:
			var entry: Dictionary = entries[channel]
			var image: Image = entry.image
			prepared[channel] = {"bytes":image.get_data(),"size":image.get_size(),
				"component":int(entry.component),"factor":entry.factor}
			if not banks.has(channel): banks[channel] = {}
		source_bytes[material_id] = prepared
		if not prepared.is_empty(): textured_materials += 1
	for face in source.face_count():
		if face % 16 == 0 and progress.report(0.25+0.7*float(face)/maxi(1,source.face_count()),"Transferring source material %d / %d…" % [face+1,source.face_count()]): return {"cancelled":true}
		var entries: Dictionary = source_bytes.get(source.materials[face],{})
		if entries.is_empty(): continue
		var tri := PackedVector2Array()
		for corner in 3: tri.append(source.uvs[face*3+corner]*Vector2(size))
		var area := (tri[1]-tri[0]).cross(tri[2]-tri[0])
		if absf(area) < 0.00000001: continue
		var coverage := {}
		UVRaster.triangle(coverage,tri,size,Color.WHITE)
		for key in coverage:
			var mask: PackedByteArray = coverage[key].get_data()
			if textured_materials > 1 and not owners.has(key):
				var new_owners := PackedInt32Array()
				new_owners.resize(4096)
				new_owners.fill(-1)
				owners[key] = new_owners
			var tile_owners: PackedInt32Array = owners.get(key,PackedInt32Array())
			for y in mini(64,size.y-key.y*64):
				for x in mini(64,size.x-key.x*64):
					var pixel := y*64+x
					if mask[pixel*4+3] == 0: continue
					if not tile_owners.is_empty():
						if tile_owners[pixel] == -2: continue
						if tile_owners[pixel] >= 0 and tile_owners[pixel] != source.materials[face]:
							tile_owners[pixel] = -2
							overlaps += 1
							continue
						tile_owners[pixel] = source.materials[face]
					var point := Vector2(key*64+Vector2i(x,y))+Vector2.ONE*0.5
					var u := (point-tri[0]).cross(tri[2]-tri[0])/area
					var v := (tri[1]-tri[0]).cross(point-tri[0])/area
					var weights := Vector3(maxf(0.0,1.0-u-v),maxf(0.0,u),maxf(0.0,v))
					weights /= maxf(0.000001,weights.x+weights.y+weights.z)
					var original_uv := source.uvs[face*3]*weights.x+source.uvs[face*3+1]*weights.y+source.uvs[face*3+2]*weights.z
					for channel in entries:
						var entry: Dictionary = entries[channel]
						var bank: Dictionary = banks[channel]
						var bytes: PackedByteArray = bank.get(key,PackedByteArray())
						if bytes.is_empty():
							bytes.resize(64*64*4)
						var source_size: Vector2i = entry.size
						var sx := clampi(floori(original_uv.x*source_size.x),0,source_size.x-1)
						var sy := clampi(floori(original_uv.y*source_size.y),0,source_size.y-1)
						var image_data: PackedByteArray = entry.bytes
						var from := (sy*source_size.x+sx)*4
						var to := pixel*4
						var component: int = entry.component
						var factor: Color = entry.factor
						if PaintChannels.scalar(channel):
							var component_index := clampi(component,0,3) if component >= 0 else 0
							var value := clampi(roundi(image_data[from+component_index]*factor.r),0,255)
							for c in 3: bytes[to+c] = value
							bytes[to+3] = 255
						else:
							for c in 4: bytes[to+c] = clampi(roundi(image_data[from+c]*factor[c]),0,255) if channel != "normal" else image_data[from+c]
						bank[key] = bytes
			if not tile_owners.is_empty(): owners[key] = tile_owners
	var layers: Array[PaintLayer] = []
	for channel in PaintChannels.IDS:
		if not banks.has(channel): continue
		var layer := PaintLayer.new()
		layer.title = "Imported " + PaintChannels.label(channel)
		layer.channel = channel
		for key in banks[channel]:
			layer.tiles[key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,banks[channel][key])
		layers.append(layer)
	var message := "Imported material textures on the original UV layout."
	if overlaps > 0: message += " %d shared texels between materials kept their first texture." % overlaps
	return {"geometry":source,"imported_layers":layers,"warning":message,"material_overlap":overlaps}

static func resize(progress: BackgroundJob.JobProgress, doc: PaintDocument, width: int, height: int) -> Dictionary:
	width = clampi(width,16,4096)
	height = clampi(height,16,4096)
	if width == doc.width and height == doc.height: return {"unchanged":true}
	var output: Array[PaintLayer] = []
	for i in doc.layers.size():
		if progress.report(float(i)/maxi(1,doc.layers.size()),"Resizing layer %d / %d…" % [i+1,doc.layers.size()]): return {"cancelled":true}
		var old_layer := doc.layers[i]
		var layer := PaintLayer.from_metadata(old_layer.metadata())
		layer.tiles = _resize_bank(old_layer.tiles,old_layer.base_color,Vector2i(doc.width,doc.height),Vector2i(width,height),false,progress)
		if progress.is_cancelled(): return {"cancelled":true}
		layer.masks = _resize_bank(old_layer.masks,Color.WHITE,Vector2i(doc.width,doc.height),Vector2i(width,height),true,progress)
		if progress.is_cancelled(): return {"cancelled":true}
		layer.pattern_tiles = _resize_bank(old_layer.pattern_tiles,Color.TRANSPARENT,Vector2i(doc.width,doc.height),Vector2i(width,height),false,progress)
		layer.pattern_image = old_layer.pattern_image
		output.append(layer)
	return {"width":width,"height":height,"layers":output}

static func _resize_bank(bank: Dictionary, default_color: Color, old_size: Vector2i, new_size: Vector2i, _mask: bool, progress: BackgroundJob.JobProgress) -> Dictionary:
	var destinations := {}
	for source_key in bank:
		var start := Vector2i(floori(source_key.x*64.0*new_size.x/old_size.x),floori(source_key.y*64.0*new_size.y/old_size.y))
		var end := Vector2i(ceili(mini(old_size.x,(source_key.x+1)*64)*float(new_size.x)/old_size.x)-1,
			ceili(mini(old_size.y,(source_key.y+1)*64)*float(new_size.y)/old_size.y)-1)
		for y in range(start.y >> 6,(end.y >> 6)+1):
			for x in range(start.x >> 6,(end.x >> 6)+1): destinations[Vector2i(x,y)] = true
	var source_bytes := {}
	for key in bank: source_bytes[key] = bank[key].get_data()
	var output := {}
	for target_key in destinations:
		if progress.is_cancelled(): return {}
		var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
		image.fill(default_color)
		var bytes := image.get_data()
		for y in mini(64,new_size.y-target_key.y*64):
			var sy := clampi(floori((target_key.y*64+y+0.5)*old_size.y/new_size.y),0,old_size.y-1)
			for x in mini(64,new_size.x-target_key.x*64):
				var sx := clampi(floori((target_key.x*64+x+0.5)*old_size.x/new_size.x),0,old_size.x-1)
				var source_key := Vector2i(sx >> 6,sy >> 6)
				if not source_bytes.has(source_key): continue
				var source: PackedByteArray = source_bytes[source_key]
				var from := ((sy%64)*64+sx%64)*4
				var to := (y*64+x)*4
				for c in 4: bytes[to+c] = source[from+c]
		output[target_key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,bytes)
	return output

static func reproject_uv(progress: BackgroundJob.JobProgress, doc: PaintDocument, new_geometry: ModelGeometry) -> Dictionary:
	if doc.geometry == null or not doc.geometry.has_uv or doc.geometry.face_count() != new_geometry.face_count():
		return {"geometry":new_geometry,"layers":doc.layers.duplicate(),"transferred":false,"overlap":0,"uncovered":0}
	var mapping := {}
	var owners := {}
	var overlap := 0
	var uncovered := 0
	var size := Vector2i(doc.width,doc.height)
	for face in new_geometry.face_count():
		if face % 16 == 0 and progress.report(float(face)/maxi(1,new_geometry.face_count())*0.55,"Mapping UV face %d / %d…" % [face+1,new_geometry.face_count()]): return {"cancelled":true}
		var tri := PackedVector2Array()
		for c in 3: tri.append(new_geometry.uvs[face*3+c]*Vector2(size))
		var area := (tri[1]-tri[0]).cross(tri[2]-tri[0])
		var coverage := {}
		UVRaster.triangle(coverage,tri,size,Color.WHITE)
		if coverage.is_empty(): uncovered += 1
		for key in coverage:
			if not mapping.has(key):
				var new_table := PackedInt32Array(); new_table.resize(4096); new_table.fill(-1); mapping[key] = new_table
				var new_owner := PackedInt32Array(); new_owner.resize(4096); new_owner.fill(-1); owners[key] = new_owner
			var table: PackedInt32Array = mapping[key]
			var owner: PackedInt32Array = owners[key]
			var mask: Image = coverage[key]
			for y in 64:
				var py: int = key.y*64+y
				if py >= doc.height: break
				for x in 64:
					if mask.get_pixel(x,y).a == 0.0: continue
					var px: int = key.x*64+x
					if px >= doc.width: continue
					var index := y*64+x
					if table[index] >= 0:
						if owner[index] != new_geometry.islands[face]: overlap += 1
						continue
					var point := Vector2(px+0.5,py+0.5)
					var u := (point-tri[0]).cross(tri[2]-tri[0])/area if absf(area)>0.00000001 else 0.0
					var v := (tri[1]-tri[0]).cross(point-tri[0])/area if absf(area)>0.00000001 else 0.0
					var weights := Vector3(maxf(0.0,1.0-u-v),maxf(0.0,u),maxf(0.0,v))
					weights /= maxf(0.000001,weights.x+weights.y+weights.z)
					var old_uv := doc.geometry.uvs[face*3]*weights.x+doc.geometry.uvs[face*3+1]*weights.y+doc.geometry.uvs[face*3+2]*weights.z
					var source := Vector2i(clampi(floori(old_uv.x*doc.width),0,doc.width-1),clampi(floori(old_uv.y*doc.height),0,doc.height-1))
					table[index] = source.y*doc.width+source.x
					owner[index] = new_geometry.islands[face]
	var output: Array[PaintLayer] = []
	for i in doc.layers.size():
		if progress.report(0.55+0.45*i/maxi(1,doc.layers.size()),"Transferring paint layer %d / %d…" % [i+1,doc.layers.size()]): return {"cancelled":true}
		var old_layer := doc.layers[i]
		var layer := PaintLayer.from_metadata(old_layer.metadata())
		layer.tiles = _map_bank(old_layer.tiles,old_layer.base_color,mapping,doc.width,progress)
		if progress.is_cancelled(): return {"cancelled":true}
		layer.masks = _map_bank(old_layer.masks,Color.WHITE,mapping,doc.width,progress)
		if progress.is_cancelled(): return {"cancelled":true}
		layer.pattern_tiles = _map_bank(old_layer.pattern_tiles,Color.TRANSPARENT,mapping,doc.width,progress)
		layer.pattern_image = old_layer.pattern_image
		output.append(layer)
	return {"geometry":new_geometry,"layers":output,"transferred":true,"overlap":overlap,"uncovered":uncovered}

static func _map_bank(bank: Dictionary, default_color: Color, mapping: Dictionary, width: int, progress: BackgroundJob.JobProgress) -> Dictionary:
	var output := {}
	var cache := {}
	for key in mapping:
		if progress.is_cancelled(): return {}
		var table: PackedInt32Array = mapping[key]
		var bytes := PackedByteArray()
		var changed := false
		for i in 4096:
			var source_index := table[i]
			if source_index < 0: continue
			var sx := source_index % width
			var sy := floori(float(source_index) / width)
			var source_key := Vector2i(sx >> 6,sy >> 6)
			if not bank.has(source_key): continue
			if bytes.is_empty():
				var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
				image.fill(default_color)
				bytes = image.get_data()
			if not cache.has(source_key): cache[source_key] = bank[source_key].get_data()
			var source: PackedByteArray = cache[source_key]
			var from := ((sy%64)*64+sx%64)*4
			for c in 4: bytes[i*4+c] = source[from+c]
			changed = true
		if changed: output[key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,bytes)
	return output

static func dilate_uv(progress: BackgroundJob.JobProgress, image: Image, model: ModelGeometry, radius: int) -> Dictionary:
	radius = clampi(radius,0,16)
	if radius == 0 or model == null or not model.has_uv: return {"image":image}
	var size := image.get_size()
	var owner := PackedInt32Array(); owner.resize(size.x*size.y); owner.fill(-1)
	for face in model.face_count():
		if face % 32 == 0 and progress.report(float(face)/maxi(1,model.face_count())*0.7,"Preparing UV edge padding…"): return {"cancelled":true}
		var tri := PackedVector2Array()
		for c in 3: tri.append(model.uvs[face*3+c]*Vector2(size))
		var masks := {}
		UVRaster.triangle(masks,tri,size,Color.WHITE)
		for key in masks:
			var mask: Image = masks[key]
			for y in mini(64,size.y-key.y*64):
				for x in mini(64,size.x-key.x*64):
					if mask.get_pixel(x,y).a > 0.0:
						var index: int = (key.y*64+y)*size.x+key.x*64+x
						if owner[index] < 0: owner[index] = model.islands[face]
	var bytes := image.get_data()
	var frontier := PackedInt32Array()
	for y in size.y:
		for x in size.x:
			var index := y*size.x+x
			if owner[index] < 0: continue
			if (x>0 and owner[index-1]<0) or (x+1<size.x and owner[index+1]<0) or (y>0 and owner[index-size.x]<0) or (y+1<size.y and owner[index+size.x]<0): frontier.append(index)
	for step in radius:
		if progress.report(0.7+0.3*step/maxi(1,radius),"Extending UV colors %d / %d…" % [step+1,radius]): return {"cancelled":true}
		var next := PackedInt32Array()
		for index in frontier:
			var x := index%size.x
			var y := floori(float(index) / size.x)
			for neighbor in [index-1 if x>0 else -1,index+1 if x+1<size.x else -1,index-size.x if y>0 else -1,index+size.x if y+1<size.y else -1]:
				if neighbor < 0 or owner[neighbor] >= 0: continue
				owner[neighbor] = owner[index]
				for c in 4: bytes[neighbor*4+c] = bytes[index*4+c]
				next.append(neighbor)
		frontier = next
	return {"image":Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,bytes)}

static func inspect_uv(progress: BackgroundJob.JobProgress, model: ModelGeometry, size: Vector2i) -> Dictionary:
	var owners := {}
	var subpixel := 0
	var uncovered := 0
	var overlap := 0
	for face in model.face_count():
		if face % 32 == 0 and progress.report(float(face)/maxi(1,model.face_count()),"Inspecting UV face %d / %d…" % [face+1,model.face_count()]): return {"cancelled":true}
		var tri := PackedVector2Array()
		for c in 3: tri.append(model.uvs[face*3+c]*Vector2(size))
		if absf((tri[1]-tri[0]).cross(tri[2]-tri[0])) < 2.0: subpixel += 1
		var masks := {}
		UVRaster.triangle(masks,tri,size,Color.WHITE)
		var covered := false
		for key in masks:
			if not owners.has(key):
				var new_bank := PackedInt32Array(); new_bank.resize(4096); new_bank.fill(-1); owners[key] = new_bank
			var bank: PackedInt32Array = owners[key]
			var mask: Image = masks[key]
			for y in mini(64,size.y-key.y*64):
				for x in mini(64,size.x-key.x*64):
					if mask.get_pixel(x,y).a == 0.0: continue
					covered = true
					var index := y*64+x
					if bank[index] >= 0 and bank[index] != model.islands[face]: overlap += 1
					elif bank[index] < 0: bank[index] = model.islands[face]
		if not covered: uncovered += 1
	return {"subpixel":subpixel,"uncovered":uncovered,"overlap":overlap}

static func replace_color(progress: BackgroundJob.JobProgress, doc: PaintDocument, source_color: Color, target_color: Color, tolerance: float) -> Dictionary:
	var source_image := Image.create(1,1,false,Image.FORMAT_RGBA8)
	source_image.set_pixel(0,0,source_color)
	var source := source_image.get_data()
	var target_image := Image.create(1,1,false,Image.FORMAT_RGBA8)
	target_image.set_pixel(0,0,target_color)
	var target := target_image.get_data()
	var threshold := clampi(roundi(tolerance*255.0),0,255)
	var output: Array[PaintLayer] = []
	var changed := 0
	for i in doc.layers.size():
		if progress.report(float(i)/maxi(1,doc.layers.size()),"Replacing colors in layer %d / %d…" % [i+1,doc.layers.size()]): return {"cancelled":true}
		var old_layer := doc.layers[i]
		if old_layer.channel != doc.current_channel():
			output.append(old_layer)
			continue
		var layer := PaintLayer.from_metadata(old_layer.metadata())
		var base_bytes := Image.create(1,1,false,Image.FORMAT_RGBA8)
		base_bytes.set_pixel(0,0,old_layer.base_color)
		if _matches_rgba(base_bytes.get_data(),0,source,threshold):
			layer.base_color = target_color
			changed += 1
		for key in old_layer.tiles:
			if progress.is_cancelled(): return {"cancelled":true}
			var bytes: PackedByteArray = old_layer.tiles[key].get_data()
			var modified := false
			for pixel in 4096:
				var offset := pixel*4
				if not _matches_rgba(bytes,offset,source,threshold): continue
				for c in 4: bytes[offset+c] = target[c]
				changed += 1
				modified = true
			layer.tiles[key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,bytes) if modified else old_layer.tiles[key]
		layer.masks = old_layer.masks.duplicate()
		for key in old_layer.pattern_tiles:
			if progress.is_cancelled(): return {"cancelled":true}
			var pattern_bytes: PackedByteArray = old_layer.pattern_tiles[key].get_data()
			var pattern_changed := false
			for pixel in 4096:
				var offset := pixel*4
				if not _matches_rgba(pattern_bytes,offset,source,threshold): continue
				for c in 4: pattern_bytes[offset+c] = target[c]
				changed += 1
				pattern_changed = true
			layer.pattern_tiles[key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,pattern_bytes) if pattern_changed else old_layer.pattern_tiles[key]
		if old_layer.pattern_image != null:
			var pattern_source: PackedByteArray = old_layer.pattern_image.get_data()
			var source_changed := false
			for pixel in old_layer.pattern_image.get_width()*old_layer.pattern_image.get_height():
				if pixel % 4096 == 0 and progress.is_cancelled(): return {"cancelled":true}
				var offset := pixel*4
				if not _matches_rgba(pattern_source,offset,source,threshold): continue
				for c in 4: pattern_source[offset+c] = target[c]
				changed += 1
				source_changed = true
			layer.pattern_image = Image.create_from_data(old_layer.pattern_image.get_width(),old_layer.pattern_image.get_height(),false,Image.FORMAT_RGBA8,pattern_source) if source_changed else old_layer.pattern_image
		output.append(layer)
	return {"layers":output,"changed":changed}

static func _matches_rgba(data: PackedByteArray, offset: int, sample: PackedByteArray, threshold: int) -> bool:
	for c in 4:
		if absi(int(data[offset+c])-int(sample[c])) > threshold: return false
	return true
