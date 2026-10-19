extends Control
var image: Image
var ink := Color.WHITE
var _texture: ImageTexture
var _last_pixel := Vector2i(-1,-1)

func _ready() -> void:
	set_image(null)

func set_image(source: Image) -> void:
	image = source.duplicate() if source != null else Image.create(16,16,false,Image.FORMAT_RGBA8)
	if source == null: image.fill(Color.TRANSPARENT)
	image.convert(Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(image)
	_last_pixel = Vector2i(-1,-1)
	queue_redraw()

func new_canvas(width: int, height: int) -> void:
	image = Image.create(clampi(width,1,128),clampi(height,1,128),false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_texture = ImageTexture.create_from_image(image)
	_last_pixel = Vector2i(-1,-1)
	queue_redraw()

func _draw() -> void:
	if image == null: return
	var pixel_scale := floorf(minf(size.x/image.get_width(),size.y/image.get_height()))
	pixel_scale = maxf(1.0,pixel_scale)
	var bounds := Rect2((size-Vector2(image.get_size())*pixel_scale)*0.5,Vector2(image.get_size())*pixel_scale)
	draw_rect(bounds,Color(0.18,0.18,0.18),true)
	draw_texture_rect(_texture,bounds,false)
	if pixel_scale >= 8:
		for x in image.get_width()+1:
			var px := bounds.position.x+x*pixel_scale
			draw_line(Vector2(px,bounds.position.y),Vector2(px,bounds.end.y),Color(0.35,0.35,0.35,0.7))
		for y in image.get_height()+1:
			var py := bounds.position.y+y*pixel_scale
			draw_line(Vector2(bounds.position.x,py),Vector2(bounds.end.x,py),Color(0.35,0.35,0.35,0.7))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and event.pressed:
		_paint(event.position,event.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()
	elif event is InputEventMouseButton and not event.pressed:
		_last_pixel = Vector2i(-1,-1)
	elif event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
		_paint(event.position,bool(event.button_mask & MOUSE_BUTTON_MASK_RIGHT))
		accept_event()

func _paint(point: Vector2, erase: bool) -> void:
	var pixel_scale := maxf(1.0,floorf(minf(size.x/image.get_width(),size.y/image.get_height())))
	var origin := (size-Vector2(image.get_size())*pixel_scale)*0.5
	var pixel := Vector2i(((point-origin)/pixel_scale).floor())
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
		_last_pixel = Vector2i(-1,-1)
		return
	var start := _last_pixel if _last_pixel.x >= 0 else pixel
	var distance := maxi(absi(pixel.x-start.x),absi(pixel.y-start.y))
	for step in distance+1:
		var target := Vector2i(Vector2(start).lerp(Vector2(pixel),float(step)/maxi(1,distance)).round())
		image.set_pixelv(target,Color.TRANSPARENT if erase else ink)
	_last_pixel = pixel
	_texture.update(image)
	queue_redraw()
