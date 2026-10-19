extends HBoxContainer
signal import_requested
signal draw_requested
signal tip_selected(path: String, tip: Image)
signal angle_changed(angle: float)
var _paths: Array[String] = []

func _ready() -> void:
	$Import.pressed.connect(func(): import_requested.emit())
	$Draw.pressed.connect(func(): draw_requested.emit())
	$Tips.item_selected.connect(_choose)
	$Angle.value_changed.connect(func(value: float): angle_changed.emit(value))
	reload()

func reload(select_path := "") -> void:
	$Tips.clear()
	_paths.clear()
	$Tips.add_item("Default square / round")
	_paths.append("")
	for entry in BrushLibrary.list_brushes():
		var image := BrushLibrary.load_tip(entry.path)
		if image == null: continue
		image.resize(20,20,Image.INTERPOLATE_NEAREST)
		$Tips.add_icon_item(ImageTexture.create_from_image(image),entry.name)
		_paths.append(entry.path)
	set_selected_path(select_path)

func set_selected_path(path: String) -> void:
	var index := _paths.find(path)
	$Tips.select(maxi(0,index))
	_choose($Tips.selected)

func _choose(index: int) -> void:
	if index < 0 or index >= _paths.size(): return
	var path := _paths[index]
	tip_selected.emit(path,BrushLibrary.load_tip(path) if not path.is_empty() else null)

func set_angle(angle: float) -> void:
	$Angle.set_value(angle,false)
