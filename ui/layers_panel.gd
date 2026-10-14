extends VBoxContainer
signal action_requested(action: String, value: Variant)
var refreshing := false
const ROW = preload("res://scenes/layer_row.tscn")
var rows: Dictionary = {}
var _active_id := ""

func _ready() -> void:
	for name in ["Add", "Duplicate", "Delete", "Up", "Down"]:
		get_node("Actions/" + name).pressed.connect(func(): action_requested.emit(name.to_lower(), null))
	$ClearMap.pressed.connect(func(): action_requested.emit("clear_map",null))
	$Opacity.value_changed.connect(func(v: float):
		if not refreshing: action_requested.emit("opacity", v / 100.0))
	$Blend.item_selected.connect(func(v: int):
		if not refreshing: action_requested.emit("blend_mode", v))
	$Name.text_submitted.connect(_rename_name)
	$Name.focus_exited.connect(func(): _rename_name($Name.text))
	$Mask/Enable.toggled.connect(func(v: bool):
		if not refreshing: action_requested.emit("mask_enabled", v))
	$Mask/Edit.toggled.connect(func(v: bool):
		if not refreshing: action_requested.emit("editing_mask", v))
	$MaskHint.text = "Masks: white reveals, black hides.\nChoose a grayscale brush color."

func refresh(doc: PaintDocument) -> void:
	refreshing = true
	var ids: Array[String] = []
	for i in range(doc.layers.size() - 1, -1, -1):
		var layer := doc.layers[i]
		ids.append(layer.id)
		if not rows.has(layer.id):
			var row = ROW.instantiate()
			$List/Rows.add_child(row)
			rows[layer.id] = row
			row.selected.connect(func(id: String): action_requested.emit("select_id",id))
			row.visibility_requested.connect(func(id: String,on: bool): action_requested.emit("visibility_at",{"id":id,"visible":on}))
			row.lock_requested.connect(func(id: String,on: bool): action_requested.emit("lock_at",{"id":id,"locked":on}))
			row.rename_requested.connect(func(id: String,title: String): action_requested.emit("rename_at",{"id":id,"title":title}))
		rows[layer.id].configure(layer,i == doc.active_layer)
		$List/Rows.move_child(rows[layer.id],ids.size()-1)
	for id in rows.keys():
		if not id in ids:
			rows[id].queue_free()
			rows.erase(id)
	var active := doc.selected_layer()
	$Opacity.set_value(active.opacity * 100, false)
	$Blend.selected = active.blend_mode
	if not $Name.has_focus() or _active_id != active.id: $Name.text = active.title
	_active_id = active.id
	$Mask/Enable.button_pressed = active.mask_enabled
	$Mask/Edit.button_pressed = doc.editing_mask
	refreshing = false

func _rename_name(value: String) -> void:
	value = value.strip_edges().left(128)
	if not refreshing and not value.is_empty(): action_requested.emit("rename_at",{"id":_active_id,"title":value})

func rename_active() -> void:
	if rows.has(_active_id): rows[_active_id].begin_rename()
