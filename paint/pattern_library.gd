class_name PatternLibrary
extends RefCounted

const MODES := ["Color", "Texture", "Grid", "Checker", "Stripes", "Dots", "Brick", "Weave", "Custom"]

static func image_for(mode: int, first: Color, second: Color) -> Image:
	var image := Image.create(16,16,false,Image.FORMAT_RGBA8)
	image.fill(second)
	for y in 16:
		for x in 16:
			var on := false
			match mode:
				2: on = x % 8 == 0 or y % 8 == 0
				3: on = ((x >> 2) + (y >> 2)) % 2 == 0
				4: on = x % 8 < 3
				5: on = (Vector2(x % 8,y % 8)-Vector2(3.5,3.5)).length_squared() <= 5.0
				6: on = y % 8 == 0 or (x + (4 if (y >> 3) % 2 else 0)) % 8 == 0
				7: on = (x % 8 < 3 and y % 8 < 6) or (y % 8 < 3 and x % 8 < 6)
			if on: image.set_pixel(x,y,first)
	return image
