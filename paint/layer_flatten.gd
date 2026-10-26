class_name LayerFlatten
extends RefCounted
## Bakes only the requested layers; the live document is replaced after the worker finishes.

static func lower_index(doc: PaintDocument, id: String) -> int:
	var index := _index_of(doc,id)
	if index < 0: return -1
	for i in range(index - 1, -1, -1):
		if doc.layers[i].channel == doc.layers[index].channel: return i
	return -1

static func _index_of(doc: PaintDocument, id: String) -> int:
	for i in doc.layers.size():
		if doc.layers[i].id == id: return i
	return -1

static func can_down(doc: PaintDocument, id: String) -> bool:
	var lower := lower_index(doc,id)
	if lower < 0: return false
	var upper := doc.layers[_index_of(doc,id)]
	var bottom := doc.layers[lower]
	return upper.effect_kind.is_empty() and bottom.effect_kind.is_empty() and upper.visible == bottom.visible and upper.blend_mode == 0 and bottom.blend_mode == 0

static func down(progress: BackgroundJob.JobProgress, doc: PaintDocument, id: String) -> Dictionary:
	var lower := lower_index(doc,id)
	if lower < 0 or not can_down(doc,id): return {"error":"Flatten down needs two layers in the same map, with matching visibility and Normal blend."}
	var upper := doc.layers[_index_of(doc,id)]
	var bottom := doc.layers[lower]
	var merged := PaintLayer.new()
	merged.id = bottom.id
	merged.title = bottom.title + " + " + upper.title
	merged.channel = bottom.channel
	merged.visible = bottom.visible
	merged.locked = bottom.locked or upper.locked
	var base := _blend_pair(bottom,upper,Vector2i(-1,-1))
	merged.base_color = base.get_pixel(0,0)
	var pair: Array[PaintLayer] = [bottom,upper]
	var keys := _keys(pair)
	for i in keys.size():
		if i % 32 == 0 and progress.report(float(i)/maxi(1,keys.size()),"Flattening two layers…"): return {"cancelled":true}
		merged.tiles[keys[i]] = _blend_pair(bottom,upper,keys[i])
	var result: Array[PaintLayer] = []
	for layer in doc.layers:
		if layer == bottom: result.append(merged)
		elif layer != upper: result.append(layer)
	return {"layers":result,"active_id":merged.id,"channels":[merged.channel]}

static func all_visible(progress: BackgroundJob.JobProgress, doc: PaintDocument) -> Dictionary:
	var replacements: Dictionary = {}
	var removed: Dictionary = {}
	var channels: Array[String] = []
	for channel in PaintChannels.IDS:
		var group: Array[PaintLayer] = []
		for layer in doc.layers:
			if layer.channel == channel and layer.visible and layer.effect_kind.is_empty(): group.append(layer)
		if group.size() < 2: continue
		var merged := PaintLayer.new()
		merged.title = "Flattened " + PaintChannels.label(channel)
		merged.channel = channel
		merged.base_color = doc.compose_tile(Vector2i(-1,-1),channel).get_pixel(0,0)
		var keys := _keys(group)
		for i in keys.size():
			if i % 32 == 0 and progress.report(float(i)/maxi(1,keys.size()),"Flattening " + PaintChannels.label(channel) + "…"): return {"cancelled":true}
			merged.tiles[keys[i]] = doc.compose_tile(keys[i],channel)
		replacements[group[0].id] = merged
		for layer in group: removed[layer.id] = merged.id
		channels.append(channel)
	if channels.is_empty(): return {"error":"There are no visible layers to flatten in the same map."}
	var active_id := doc.selected_layer().id
	var result: Array[PaintLayer] = []
	for layer in doc.layers:
		if replacements.has(layer.id): result.append(replacements[layer.id])
		elif not removed.has(layer.id): result.append(layer)
	if removed.has(active_id): active_id = removed[active_id]
	return {"layers":result,"active_id":active_id,"channels":channels}

static func _keys(group: Array[PaintLayer]) -> Array[Vector2i]:
	var found: Dictionary = {}
	for layer in group:
		for bank in [layer.tiles,layer.pattern_tiles,layer.masks]:
			for key in bank: found[key] = true
	var result: Array[Vector2i] = []
	result.assign(found.keys())
	return result

static func _blend_pair(bottom: PaintLayer, upper: PaintLayer, key: Vector2i) -> Image:
	var result := Image.create(64,64,false,Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blend_rect(bottom.prepared_tile(key),Rect2i(0,0,64,64),Vector2i.ZERO)
	result.blend_rect(upper.prepared_tile(key),Rect2i(0,0,64,64),Vector2i.ZERO)
	return result
