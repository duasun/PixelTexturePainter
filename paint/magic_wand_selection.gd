class_name MagicWandSelection
extends RefCounted
## Builds a pixel selection from the existing tiled flood fill, without painting the document.

static func select(progress: BackgroundJob.JobProgress, doc: PaintDocument, pixel: Vector2i, island: int, mode: int, tolerance: float, existing: Dictionary, operation: int) -> Dictionary:
	if operation == 2 and existing.is_empty(): return {"selection":{},"boundary":null}
	var picked: Dictionary = {}
	if mode == 2:
		if island < 0 or doc.geometry == null: return {"error":"Click a UV island on the model or UV canvas."}
		var faces := PackedInt32Array()
		for face in doc.geometry.face_count():
			if doc.geometry.islands[face] == island: faces.append(face)
		if progress.report(0.2,"Selecting UV island…"): return {"cancelled":true}
		picked = UVRaster.selection(doc.geometry,faces,Vector2i(doc.width,doc.height))
	else:
		var work := doc.read_copy()
		var mask_layer := PaintLayer.new()
		mask_layer.channel = work.current_channel()
		work.layers.append(mask_layer)
		work.active_layer = work.layers.size()-1
		var fill := PaintFloodFill.run(progress,work,pixel,island if mode == 0 else -1,Color.WHITE,tolerance,mode == 0)
		if fill.has("error") or fill.get("cancelled",false): return fill
		picked = fill.command.after
	var mask := combine(existing,picked,operation)
	if progress.report(0.96,"Tracing selection outline…"): return {"cancelled":true}
	return {"selection":mask,"boundary":LassoSelection.boundary(mask,Vector2i(doc.width,doc.height)) if not mask.is_empty() else null}

static func combine(existing: Dictionary, picked: Dictionary, operation: int) -> Dictionary:
	if operation == 0: return picked
	var result := existing.duplicate()
	for key in picked:
		if operation == 2 and not result.has(key): continue
		if not result.has(key):
			result[key] = picked[key]
			continue
		var current: PackedByteArray = result[key].get_data()
		var incoming: PackedByteArray = picked[key].get_data()
		var any_selected := false
		for index in range(3,current.size(),4):
			if operation == 1:
				if incoming[index] > 0:
					current[index-3] = 255
					current[index-2] = 255
					current[index-1] = 255
					current[index] = 255
			else:
				if incoming[index] > 0: current[index] = 0
			if current[index] > 0: any_selected = true
		if any_selected: result[key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,current)
		else: result.erase(key)
	return result
