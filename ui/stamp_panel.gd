extends VBoxContainer

signal load_requested
signal region_changed(region: Rect2i)
signal navigation_changed

var source: Image
var region := Rect2i()
var _source_texture: ImageTexture
var _atlas: AtlasTexture
var _syncing := false

func _ready() -> void:
	$Actions/Load.pressed.connect(func(): load_requested.emit())
	$Full.pressed.connect(func():
		if source != null: _commit_region(Rect2i(Vector2i.ZERO, source.get_size())))
	$Preview.region_previewed.connect(_preview_region)
	$Preview.region_committed.connect(_commit_region)
	$Preview.navigation_changed.connect(func(): navigation_changed.emit())
	for field_name in ["X", "Y", "W", "H"]:
		$Fields.get_node(field_name).value_changed.connect(func(_value: float): _fields_changed())
	_refresh()

func set_source(image: Image, title: String, selected: Rect2i) -> void:
	if source != image:
		source = image
		_source_texture = ImageTexture.create_from_image(image) if image != null else null
		_atlas = AtlasTexture.new() if image != null else null
		if _atlas != null: _atlas.atlas = _source_texture
	region = _valid_region(selected)
	$SourceName.text = "%s · %d × %d px" % [title if not title.is_empty() else "Embedded stamp", image.get_width(), image.get_height()] if image != null else "No stamp image loaded"
	$Preview.set_source(image, region)
	_refresh()

func view_state() -> Dictionary:
	return $Preview.view_state()

func restore_view_state(state: Dictionary) -> void:
	$Preview.restore_view_state(state)

func _valid_region(value: Rect2i) -> Rect2i:
	if source == null: return Rect2i()
	var full := Rect2i(Vector2i.ZERO, source.get_size())
	if value.size.x <= 0 or value.size.y <= 0: return full
	var clipped := value.intersection(full)
	return clipped if clipped.has_area() else full

func _refresh() -> void:
	var enabled := source != null
	$Full.disabled = not enabled
	$Preview.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	_syncing = true
	for field_name in ["X", "Y", "W", "H"]:
		var field: NumberField = $Fields.get_node(field_name)
		field.maximum = float((source.get_width() if field_name in ["X", "W"] else source.get_height()) - (1 if field_name in ["X", "Y"] else 0)) if enabled else 0.0
	var values := [region.position.x, region.position.y, region.size.x, region.size.y]
	for index in 4:
		$Fields.get_node(["X", "Y", "W", "H"][index]).set_value(values[index], false)
	_syncing = false
	if enabled:
		_atlas.region = Rect2(region)
		$SelectedPreview.texture = _atlas
		$CropSummary.text = "Selected: %d × %d px · dragged area becomes one stamp" % [region.size.x, region.size.y]
	else:
		$SelectedPreview.texture = null
		$CropSummary.text = "Load an image, then drag on its preview to choose the stamp area."

func _preview_region(value: Rect2i) -> void:
	if source == null: return
	region = _valid_region(value)
	_refresh()

func _commit_region(value: Rect2i) -> void:
	if source == null: return
	var selected := _valid_region(value)
	region = selected
	$Preview.region = selected
	$Preview.queue_redraw()
	_refresh()
	region_changed.emit(selected)

func _fields_changed() -> void:
	if _syncing or source == null: return
	var value := Rect2i(int($Fields/X.value), int($Fields/Y.value), int($Fields/W.value), int($Fields/H.value))
	_commit_region(value)
