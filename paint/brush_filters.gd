class_name BrushFilters
extends RefCounted
## Local native image filtering; no full-atlas readback. Effect brushes are bounded to 64px.
static func sample(doc: PaintDocument, layer: PaintLayer, mask: bool, rect: Rect2i) -> Image:
	var result := Image.create(rect.size.x,rect.size.y,false,Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	var clipped := rect.intersection(Rect2i(0,0,doc.width,doc.height))
	if not clipped.has_area(): return result
	for ty in range(clipped.position.y >> 6, ((clipped.end.y-1) >> 6)+1):
		for tx in range(clipped.position.x >> 6, ((clipped.end.x-1) >> 6)+1):
			var key := Vector2i(tx,ty)
			var source := layer.tile_at(key,true,false) if mask else doc.compose_tile(key)
			var part := clipped.intersection(Rect2i(key*64,Vector2i(64,64)))
			result.blit_rect(source,Rect2i(part.position-key*64,part.size),part.position-rect.position)
	return result

static func strength(image: Image, amount: float, shape: Image = null) -> Image:
	var result: Image = image.duplicate()
	if shape != null:
		var masked_data := result.get_data()
		var mask := shape.get_data()
		for i in range(3,masked_data.size(),4): masked_data[i] = roundi(masked_data[i] * mask[i] / 255.0)
		return Image.create_from_data(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8,masked_data)
	if amount >= 1.0: return result
	var data := result.get_data()
	for i in range(3,data.size(),4): data[i] = roundi(data[i]*amount)
	return Image.create_from_data(result.get_width(),result.get_height(),false,Image.FORMAT_RGBA8,data)

static func blur(image: Image) -> Image:
	# Bilinear down/up sampling gives a bounded 2px box-like smoothing kernel.
	var size := image.get_size()
	var result: Image = image.duplicate()
	var transparent := image.detect_alpha() != Image.ALPHA_NONE
	if transparent: result.premultiply_alpha()
	result.resize(maxi(1,size.x >> 1),maxi(1,size.y >> 1),Image.INTERPOLATE_BILINEAR)
	result.resize(size.x,size.y,Image.INTERPOLATE_BILINEAR)
	if transparent:
		var data := result.get_data()
		for i in range(0,data.size(),4):
			var alpha := int(data[i+3])
			if alpha == 0: continue
			for c in 3: data[i+c] = clampi(roundi(data[i+c]*255.0/alpha),0,255)
		result = Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,data)
	return result
