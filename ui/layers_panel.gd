extends VSplitContainer
signal action_requested(action: String, value: Variant)
var refreshing := false
const ROW = preload("res://scenes/layer_row.tscn")
var rows: Dictionary = {}
var _active_id := ""
var _context_id := ""
var _current_document: PaintDocument

func _ready() -> void:
	for action_name in ["Add", "Duplicate", "Delete", "Up", "Down"]:
		get_node("ListSection/Actions/" + action_name).pressed.connect(func(): action_requested.emit(action_name.to_lower(), null))
	$Properties/ClearMap.pressed.connect(func(): action_requested.emit("clear_map",null))
	$Properties/Opacity.value_changed.connect(func(v: float):
		if not refreshing: action_requested.emit("opacity", v / 100.0))
	$Properties/Blend.item_selected.connect(func(v: int):
		if not refreshing: action_requested.emit("blend_mode", v))
	$Properties/Name.text_submitted.connect(_rename_name)
	$Properties/Name.focus_exited.connect(func(): _rename_name($Properties/Name.text))
	$LayerMenu.id_pressed.connect(_menu_action)
	$FlattenAllConfirm.confirmed.connect(func(): action_requested.emit("flatten_all",null))

func refresh(doc: PaintDocument) -> void:
	_current_document = doc
	refreshing = true
	var ids: Array[String] = []
	for i in range(doc.layers.size() - 1, -1, -1):
		var layer := doc.layers[i]
		ids.append(layer.id)
		if not rows.has(layer.id):
			var row = ROW.instantiate()
			$ListSection/List/Rows.add_child(row)
			rows[layer.id] = row
			row.selected.connect(func(id: String): action_requested.emit("select_id",id))
			row.visibility_requested.connect(func(id: String,on: bool): action_requested.emit("visibility_at",{"id":id,"visible":on}))
			row.lock_requested.connect(func(id: String,on: bool): action_requested.emit("lock_at",{"id":id,"locked":on}))
			row.rename_requested.connect(func(id: String,title: String): action_requested.emit("rename_at",{"id":id,"title":title}))
			row.context_requested.connect(_open_context)
		rows[layer.id].configure(layer,i == doc.active_layer)
		$ListSection/List/Rows.move_child(rows[layer.id],ids.size()-1)
	for id in rows.keys():
		if not id in ids:
			rows[id].queue_free()
			rows.erase(id)
	var active := doc.selected_layer()
	$Properties/Opacity.set_value(active.opacity * 100, false)
	$Properties/Blend.selected = active.blend_mode
	if not $Properties/Name.has_focus() or _active_id != active.id: $Properties/Name.text = active.title
	_active_id = active.id
	refreshing = false

func _open_context(id: String, at: Vector2i) -> void:
	_context_id = id
	var doc := _current_document
	if doc == null: return
	$LayerMenu.set_item_disabled(0,not LayerFlatten.can_down(doc,id))
	$LayerMenu.set_item_tooltip(0,"Both layers must use Normal blend and have the same visibility.")
	var visible_by_channel: Dictionary = {}
	for layer in doc.layers:
		if layer.visible: visible_by_channel[layer.channel] = int(visible_by_channel.get(layer.channel,0)) + 1
	var can_all := false
	for count in visible_by_channel.values():
		if count >= 2: can_all = true
	$LayerMenu.set_item_disabled(1,not can_all)
	$LayerMenu.position = at
	$LayerMenu.popup()

func _menu_action(id: int) -> void:
	if id == 0: action_requested.emit("flatten_down",_context_id)
	elif id == 1: $FlattenAllConfirm.popup_centered()

func _rename_name(value: String) -> void:
	value = value.strip_edges().left(128)
	if not refreshing and not value.is_empty(): action_requested.emit("rename_at",{"id":_active_id,"title":value})

func rename_active() -> void:
	if rows.has(_active_id): rows[_active_id].begin_rename()
