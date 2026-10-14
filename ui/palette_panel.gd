extends VBoxContainer
signal color_selected(color: Color, slot: int)
signal load_requested
signal palette_change_requested(action: String, index: int, color: Color)
const SWATCH = preload("res://scenes/palette_swatch.tscn")
var colors := PackedColorArray()
var primary := Color("eea765")
var secondary := Color.BLACK
var primary_index := -1
var secondary_index := -1
var _editing_index := -1

func _ready() -> void:
	$Header/Load.pressed.connect(func(): load_requested.emit())
	$EditActions/Add.pressed.connect(func(): _open_color(-1))
	$EditActions/Edit.pressed.connect(func(): _open_color(primary_index))
	$EditActions/Remove.pressed.connect(func():
		if primary_index >= 0: palette_change_requested.emit("remove",primary_index,Color.TRANSPARENT))
	$ColorDialog.confirmed.connect(func(): palette_change_requested.emit("add" if _editing_index < 0 else "edit",_editing_index,$ColorDialog/Picker.color))
	$Scroll.resized.connect(_columns)

func refresh(palette: PackedColorArray, title := "Palette") -> void:
	if colors == palette:
		$Header/Name.text = "%s  /  %d colors" % [title, colors.size()]
		return
	colors = palette.duplicate()
	$Header/Name.text = "%s  /  %d colors" % [title, colors.size()]
	for child in $Scroll/Grid.get_children():
		$Scroll/Grid.remove_child(child)
		child.queue_free()
	for i in colors.size():
		var swatch: PaletteSwatch = SWATCH.instantiate()
		$Scroll/Grid.add_child(swatch)
		swatch.chosen.connect(_chosen.bind(i))
		swatch.edit_requested.connect(_open_color.bind(i))
	primary_index = -1
	secondary_index = -1
	set_colors(primary, secondary)
	_columns()

func _open_color(index: int) -> void:
	if index >= colors.size(): return
	_editing_index = index
	$ColorDialog.title = "Add palette color" if index < 0 else "Edit palette color %d" % (index+1)
	$ColorDialog/Picker.color = primary if index < 0 else colors[index]
	$ColorDialog.popup_centered()

func _columns() -> void:
	$Scroll/Grid.columns = maxi(1, floori(($Scroll.size.x - 16) / 40.0))

func _chosen(slot: int, index: int) -> void:
	if slot == 1:
		primary_index = index
	else:
		secondary_index = index
	color_selected.emit(colors[index], slot)

func set_colors(a: Color, b: Color) -> void:
	primary = a
	secondary = b
	primary_index = _matching(a, primary_index)
	secondary_index = _matching(b, secondary_index)
	for i in $Scroll/Grid.get_child_count():
		var label := ""
		if i == primary_index: label = "1"
		if i == secondary_index: label += " 2" if not label.is_empty() else "2"
		$Scroll/Grid.get_child(i).configure(colors[i], label)
	$Header/Primary.configure(a,"1")
	$Header/Secondary.configure(b,"2")
	$Header/PrimaryHex.text = "#" + a.to_html(a.a < 1.0).to_upper()
	$Header/SecondaryHex.text = "#" + b.to_html(b.a < 1.0).to_upper()
	$Header/PrimaryHex.tooltip_text = "Primary color" + (" (outside this palette)" if primary_index < 0 else "")
	$Header/SecondaryHex.tooltip_text = "Secondary color" + (" (outside this palette)" if secondary_index < 0 else "")
	$EditActions/Edit.disabled = primary_index < 0
	$EditActions/Remove.disabled = primary_index < 0 or colors.size() <= 1
	$EditActions/Add.disabled = colors.size() >= PaletteIO.MAX_COLORS

func _matching(color: Color, previous: int) -> int:
	if previous >= 0 and previous < colors.size() and colors[previous].to_rgba32() == color.to_rgba32():
		return previous
	for i in colors.size():
		if colors[i].to_rgba32() == color.to_rgba32(): return i
	return -1
