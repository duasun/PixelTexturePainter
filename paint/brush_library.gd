class_name BrushLibrary
extends RefCounted

const BUNDLED := "res://assets/brushes"
const USER := "user://brushes"
const BUILTIN := ["01_round", "02_square", "03_diamond", "04_cross", "05_ring", "06_star", "07_soft_round", "08_soft_square", "09_splatter", "10_speckle", "11_hatch", "12_diagonal", "13_checker", "14_brick", "15_stipple", "16_grunge", "17_leaf", "18_slash", "19_triangles", "20_cloud"]

static func list_brushes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for name in BUILTIN:
		result.append({"name":name.substr(3).replace("_"," ").capitalize(),"path":BUNDLED.path_join(name+".png")})
	var dir := DirAccess.open(USER)
	if dir != null:
		for file in dir.get_files():
			if file.get_extension().to_lower() != "png": continue
			result.append({"name":file.get_basename().replace("_"," ").capitalize(),"path":USER.path_join(file)})
	return result

static func load_tip(path: String) -> Image:
	var image: Image
	if path.begins_with("res://"):
		var texture := load(path) as Texture2D
		image = texture.get_image() if texture != null else null
	else:
		image = Image.load_from_file(path)
	if image == null or image.get_width() < 1 or image.get_height() < 1 or image.get_width() > 512 or image.get_height() > 512: return null
	image.convert(Image.FORMAT_RGBA8)
	return image

static func import_tip(path: String) -> Dictionary:
	var image := load_tip(path)
	if image == null: return {"error":"Choose a PNG brush up to 512 × 512 px."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER))
	var name := path.get_file().get_basename().validate_filename()
	var destination := USER.path_join(name+".png")
	var suffix := 2
	while FileAccess.file_exists(destination):
		destination = USER.path_join("%s_%d.png" % [name,suffix])
		suffix += 1
	if image.save_png(destination) != OK: return {"error":"Could not save the brush in user://brushes."}
	return {"path":destination}

static func save_tip(name: String, image: Image) -> Dictionary:
	if image == null or image.get_width() < 1 or image.get_height() < 1 or image.get_width() > 128 or image.get_height() > 128:
		return {"error":"Brush canvas must be between 1 and 128 px per side."}
	var clean := name.strip_edges().validate_filename()
	if clean.is_empty(): return {"error":"Give the brush a name."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER))
	var destination := USER.path_join(clean + ".png")
	var suffix := 2
	while FileAccess.file_exists(destination):
		destination = USER.path_join("%s_%d.png" % [clean,suffix])
		suffix += 1
	var tip := image.duplicate()
	tip.convert(Image.FORMAT_RGBA8)
	for y in tip.get_height():
		for x in tip.get_width():
			var pixel: Color = tip.get_pixel(x,y)
			tip.set_pixel(x,y,Color(1,1,1,pixel.a * pixel.get_luminance()))
	if tip.save_png(destination) != OK: return {"error":"Could not save the brush in user://brushes."}
	return {"path":destination}

static func rotated_tip(source: Image, side: int, angle: float) -> Image:
	var tip := source.duplicate()
	tip.resize(side,side,Image.INTERPOLATE_NEAREST)
	if is_zero_approx(angle): return tip
	var output := Image.create(side,side,false,Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	var center := Vector2.ONE * (side-1)*0.5
	var cosine := cos(deg_to_rad(angle))
	var sine := sin(deg_to_rad(angle))
	for y in side:
		for x in side:
			var delta := Vector2(x,y)-center
			var sample := Vector2(cosine*delta.x+sine*delta.y,-sine*delta.x+cosine*delta.y)+center
			var pixel := Vector2i(sample.round())
			if pixel.x >= 0 and pixel.y >= 0 and pixel.x < side and pixel.y < side:
				output.set_pixel(x,y,tip.get_pixelv(pixel))
	return output
