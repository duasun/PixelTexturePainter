class_name ModelExport
extends RefCounted

static func save(progress: BackgroundJob.JobProgress, doc: PaintDocument, path: String) -> Dictionary:
	if doc.geometry == null: return {"error": "Import a model before exporting."}
	if path.get_extension().to_lower() == "obj": return ProjectIO.export_obj(doc.geometry, path)
	if not path.get_extension().to_lower() in ["glb", "gltf"]:
		return {"error": "Choose .glb, .gltf or .obj."}
	var result := ProjectIO.render_image(progress, doc, "albedo")
	if not result.has("image"): return result
	if doc.uv_export_padding > 0:
		result = ProjectTransforms.dilate_uv(progress,result.image,doc.geometry,doc.uv_export_padding)
		if not result.has("image"): return result
	if progress.report(0.96, "Exporting model, UV coordinates and painted texture…"):
		return {"cancelled": true}
	var root := Node3D.new()
	root.name = doc.geometry.label.validate_node_name()
	var instance := MeshInstance3D.new()
	instance.name = "PaintedMesh"
	instance.mesh = doc.geometry.to_mesh()
	var material := StandardMaterial3D.new()
	material.resource_name = "PaintedColor"
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = ImageTexture.create_from_image(result.image)
	material.albedo_texture.resource_name = path.get_file().get_basename() + "_color"
	if result.image.detect_alpha() != Image.ALPHA_NONE:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for channel in ["roughness","metallic","normal","ao","emission"]:
		if not doc.has_channel(channel): continue
		var map := ProjectIO.render_image(progress,doc,channel)
		if not map.has("image"):
			root.free(); instance.free()
			return map
		if doc.uv_export_padding > 0:
			map = ProjectTransforms.dilate_uv(progress,map.image,doc.geometry,doc.uv_export_padding)
			if not map.has("image"):
				root.free(); instance.free()
				return map
		var texture := ImageTexture.create_from_image(map.image)
		texture.resource_name = path.get_file().get_basename()+"_"+channel
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		match channel:
			"roughness":
				material.roughness_texture = texture
				material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			"metallic":
				material.metallic = 1.0
				material.metallic_texture = texture
				material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			"normal":
				material.normal_enabled = true
				material.normal_texture = texture
			"ao":
				material.ao_enabled = true
				material.ao_texture = texture
				material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			"emission":
				material.emission_enabled = true
				material.emission = Color.WHITE
				material.emission_texture = texture
	instance.material_override = material
	root.add_child(instance)
	instance.owner = root
	var exporter := GLTFDocument.new()
	var state := GLTFState.new()
	var error := exporter.append_from_scene(root, state)
	if error == OK: error = exporter.write_to_filesystem(state, path)
	root.free()
	return {"path": path} if error == OK else {"error": "Model export failed: " + error_string(error)}

static func export_maps(progress: BackgroundJob.JobProgress, doc: PaintDocument, path: String) -> Dictionary:
	var paths := PackedStringArray()
	for channel in PaintChannels.IDS:
		if not doc.has_channel(channel): continue
		var rendered := ProjectIO.render_image(progress,doc,channel)
		if not rendered.has("image"): return rendered
		if doc.uv_export_padding > 0 and doc.geometry != null and doc.geometry.has_uv:
			rendered = ProjectTransforms.dilate_uv(progress,rendered.image,doc.geometry,doc.uv_export_padding)
			if not rendered.has("image"): return rendered
		var destination: String = path.get_basename()+"_"+channel+".png"
		var error: Error = rendered.image.save_png(destination)
		if error != OK: return {"error":"Map export failed: "+error_string(error)}
		paths.append(destination)
	return {"path":path.get_base_dir(),"paths":paths}
