class_name PaintHistory
extends RefCounted
## Stores before/after touched tiles only; structure actions keep layer references.
const MEMORY_LIMIT := 192 * 1024 * 1024
var actions: Array[Dictionary] = []
var cursor := 0
var memory_bytes := 0
var next_revision := 1

func clear() -> void:
	actions.clear()
	cursor = 0
	memory_bytes = 0
	next_revision = 1

func push(doc: PaintDocument, action: Dictionary) -> void:
	if not action.has("bytes"):
		var estimate := 0
		if action.kind == "layers":
			for layer in action.before + action.after:
				estimate += (layer.tiles.size() + layer.masks.size()+layer.pattern_tiles.size()) * 64 * 64 * 4
		elif action.kind == "geometry":
			if action.before != null:
				estimate += action.before.positions.size() * 32
			if action.after != null:
				estimate += action.after.positions.size() * 32
		elif action.kind == "document":
			for state in [action.before,action.after]:
				for layer in state.layers:
					estimate += (layer.tiles.size()+layer.masks.size()+layer.pattern_tiles.size())*64*64*4
		elif action.kind == "property":
			for value in [action.before, action.after]:
				if value is Image:
					estimate += value.get_width() * value.get_height() * 4
		elif action.kind == "stamp":
			for state in [action.before, action.after]:
				if state.image is Image:
					estimate += state.image.get_width() * state.image.get_height() * 4
		action["bytes"] = estimate
	while actions.size() > cursor:
		memory_bytes -= int(actions.pop_back().get("bytes", 0))
	action["revision_before"] = doc.revision
	action["revision_after"] = next_revision
	next_revision += 1
	doc.revision = action.revision_after
	actions.append(action)
	memory_bytes += int(action.get("bytes", 0))
	cursor = actions.size()
	while (memory_bytes > MEMORY_LIMIT or actions.size() > 256) and actions.size() > 1:
		memory_bytes -= int(actions.pop_front().get("bytes", 0))
		cursor -= 1

func undo(doc: PaintDocument) -> Array[Vector2i]:
	if cursor == 0:
		return []
	cursor -= 1
	return _apply(doc, actions[cursor], false)

func redo(doc: PaintDocument) -> Array[Vector2i]:
	if cursor >= actions.size():
		return []
	var changed := _apply(doc, actions[cursor], true)
	cursor += 1
	return changed

func _apply(doc: PaintDocument, action: Dictionary, forward: bool) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	if action.kind == "tiles":
		var layer: PaintLayer = action.layer
		var bank: Dictionary = layer.masks if action.mask else layer.tiles
		var state: Dictionary = action.after if forward else action.before
		for key in state:
			if state[key] == null:
				bank.erase(key)
			else:
				bank[key] = state[key].duplicate()
			keys.append(key)
			layer.invalidate(key)
	elif action.kind == "layers":
		doc.layers.assign(action.after if forward else action.before)
		doc.active_layer = clampi(action.get("active_after" if forward else "active_before",doc.active_layer),0,doc.layers.size()-1)
		if action.has("editing_mask_before"):
			doc.editing_mask = action.editing_mask_after if forward else action.editing_mask_before
		keys = doc.all_keys()
	elif action.kind == "property":
		action.target.set(action.property, action.after if forward else action.before)
		keys = doc.all_keys()
	elif action.kind == "stamp":
		var state: Dictionary = action.after if forward else action.before
		doc.stamp_image = state.image
		doc.stamp_region = state.region
		doc.stamp_name = state.name
	elif action.kind == "effects":
		doc.effects = (action.after if forward else action.before).duplicate(true)
	elif action.kind == "palette":
		var state: Dictionary = action.after if forward else action.before
		doc.palette = state.colors.duplicate()
		doc.palette_name = state.name
		if state.has("primary"): doc.primary_color = state.primary
		if state.has("secondary"): doc.secondary_color = state.secondary
		doc.palette_lookup = null
	elif action.kind == "geometry":
		doc.geometry = action.after if forward else action.before
	elif action.kind == "document":
		var state: Dictionary = action.after if forward else action.before
		doc.width = state.width
		doc.height = state.height
		doc.geometry = state.geometry
		doc.layers.assign(state.layers)
		doc.active_layer = clampi(int(state.active_layer),0,doc.layers.size()-1)
		doc.editing_mask = state.editing_mask
		keys = doc.all_keys()
	doc.revision = action.revision_after if forward else action.revision_before
	return keys
