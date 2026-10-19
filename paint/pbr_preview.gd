class_name PBRPreview
extends RefCounted
## Builds a bounded-size viewport preview off the UI thread. Export uses full resolution.
static func build(progress: BackgroundJob.JobProgress, document: PaintDocument) -> Dictionary:
	var maps := {}
	# Albedo already streams through TileDisplay; rebuilding it here stalls painting.
	var channels := ["roughness","metallic","normal","ao","emission"]
	var limit := 1024
	var has_material_maps := false
	# Outside Albedo editing, the tile display contains the selected map instead.
	if document.current_channel() != "albedo":
		var albedo_painted := false
		for layer in document.layers:
			if layer.channel == "albedo" and layer.visible and (not layer.tiles.is_empty() or not layer.pattern_tiles.is_empty()):
				albedo_painted = true
				break
		albedo_painted = albedo_painted or document.effects != PaintDocument.new().effects
		var albedo: Image
		if albedo_painted:
			var albedo_result := ProjectIO.render_image(progress,document,"albedo")
			if not albedo_result.has("image"): return albedo_result
			albedo = albedo_result.image
			if albedo.get_width() > limit or albedo.get_height() > limit:
				var factor := minf(float(limit)/albedo.get_width(),float(limit)/albedo.get_height())
				albedo.resize(maxi(1,roundi(albedo.get_width()*factor)),maxi(1,roundi(albedo.get_height()*factor)),Image.INTERPOLATE_NEAREST)
		else:
			albedo = Image.create(1,1,false,Image.FORMAT_RGBA8)
			albedo.fill(document.compose_tile(Vector2i(-1,-1),"albedo").get_pixel(0,0))
		maps["albedo"] = albedo
	for i in channels.size():
		if progress.report(float(i)/channels.size(),"Preparing lit material preview…"): return {"cancelled":true}
		var channel: String = channels[i]
		var has_pixels := false
		for layer in document.layers:
			if layer.channel == channel and layer.visible and layer.opacity > 0.0 and (layer.base_color.a > 0.0 or not layer.tiles.is_empty() or not layer.pattern_tiles.is_empty()):
				has_pixels = true
				break
		if not has_pixels:
			var solid := Image.create(1,1,false,Image.FORMAT_RGBA8)
			solid.fill(PaintChannels.background(channel))
			maps[channel] = solid
			continue
		has_material_maps = true
		var result := ProjectIO.render_image(progress,document,channel)
		if not result.has("image"): return result
		var image: Image = result.image
		if image.get_width()>limit or image.get_height()>limit:
			var factor := minf(float(limit)/image.get_width(),float(limit)/image.get_height())
			image.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)),Image.INTERPOLATE_NEAREST)
		maps[channel] = image
	return {"maps":maps,"simple":not has_material_maps}
