class_name ModelIO
extends RefCounted

static func load_model(progress: BackgroundJob.JobProgress, path: String, target_width := 0, target_height := 0) -> Dictionary:
	progress.report(0.1, "Reading model…")
	var result: Dictionary
	if path.get_extension().to_lower() == "obj":
		result = _load_obj(path)
	else:
		var loader := GLTFDocument.new()
		var state := GLTFState.new()
		var error := loader.append_from_file(path, state)
		if error != OK:
			return {"error": "Model import failed: " + error_string(error)}
		var root := loader.generate_scene(state)
		if root == null:
			return {"error": "The file contains no loadable scene."}
		var model := ModelGeometry.new()
		model.label = path.get_file().get_basename()
		var material_sources := {}
		_collect(root, Transform3D.IDENTITY, model,material_sources)
		root.free()
		result = {"geometry": model,"material_sources":material_sources}
	if result.has("error"):
		return result
	var model: ModelGeometry = result.geometry
	if model.face_count() == 0:
		return {"error": "No triangle geometry was found."}
	if model.face_count() > 150000:
		return {"error": "This build supports up to 150,000 triangles. Simplify the mesh before importing."}
	for uv in model.uvs:
		if not uv.is_finite() or uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
			model.has_uv = false
			break
	progress.report(0.65, "Building surface lookup…")
	model.build_cache()
	if model.has_uv and target_width >= 16 and target_height >= 16 and result.has("material_sources"):
		var any_source := false
		for source in result.material_sources.values():
			if not source.is_empty(): any_source = true; break
		if any_source:
			var baked := ProjectTransforms.import_materials(progress,model,result.material_sources,Vector2i(target_width,target_height))
			if baked.has("error") or baked.has("cancelled"): return baked
			result.merge(baked,true)
	progress.report(1.0, "Model ready")
	return result

static func _collect(node: Node, parent_transform: Transform3D, model: ModelGeometry, sources: Dictionary) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var object_id := model.objects.size()
		for surface in node.mesh.get_surface_count():
			if node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material_id := sources.size()
			var material: Material = node.material_override if node.material_override != null else node.get_surface_override_material(surface)
			if material == null: material = node.mesh.surface_get_material(surface)
			sources[material_id] = _material_sources(material)
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var tex: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else verts.size()
			for i in range(0, count - 2, 3):
				var tri := PackedVector3Array()
				var corner_indices: Array[int] = []
				for c in 3:
					var idx: int = indices[i + c] if not indices.is_empty() else i + c
					corner_indices.append(idx)
					tri.append(transform * verts[idx])
				# Mirrored transforms must preserve Godot's clockwise front-face winding.
				if transform.basis.determinant() < 0.0:
					var swap := tri[1]
					tri[1] = tri[2]
					tri[2] = swap
					var ii := corner_indices[1]
					corner_indices[1] = corner_indices[2]
					corner_indices[2] = ii
				var normal := (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				if normal.length_squared() < 0.1:
					continue
				for c in 3:
					var idx := corner_indices[c]
					model.positions.append(tri[c])
					model.normals.append((transform.basis.inverse().transposed() * norms[idx]).normalized() if idx < norms.size() else normal)
					model.uvs.append(tex[idx] if idx < tex.size() else Vector2.ZERO)
					if idx >= tex.size():
						model.has_uv = false
				model.materials.append(material_id)
				model.objects.append(object_id)
	for child in node.get_children():
		_collect(child, transform, model,sources)

static func _material_sources(material: Material) -> Dictionary:
	var sources := {}
	if not material is StandardMaterial3D: return sources
	var standard: StandardMaterial3D = material
	for channel in ["albedo","roughness","metallic","normal","ao","emission"]:
		var texture: Texture2D
		var component := -1
		var factor := Color.WHITE
		match channel:
			"albedo": texture = standard.albedo_texture; factor = standard.albedo_color
			"roughness": texture = standard.roughness_texture; component = int(standard.roughness_texture_channel); factor = Color(standard.roughness,standard.roughness,standard.roughness)
			"metallic": texture = standard.metallic_texture; component = int(standard.metallic_texture_channel); factor = Color(standard.metallic,standard.metallic,standard.metallic)
			"normal":
				if standard.normal_enabled: texture = standard.normal_texture
			"ao":
				if standard.ao_enabled: texture = standard.ao_texture; component = int(standard.ao_texture_channel)
			"emission":
				if standard.emission_enabled: texture = standard.emission_texture; factor = standard.emission
		if texture == null:
			if channel == "albedo" and factor != Color.WHITE:
				var solid := Image.create(1,1,false,Image.FORMAT_RGBA8); solid.fill(factor)
				sources[channel] = {"image":solid,"component":-1,"factor":Color.WHITE}
			continue
		var image := texture.get_image()
		if image == null or image.is_empty(): continue
		if image.get_width()>4096 or image.get_height()>4096:
			image.resize(mini(image.get_width(),4096),mini(image.get_height(),4096),Image.INTERPOLATE_NEAREST)
		image.convert(Image.FORMAT_RGBA8)
		sources[channel] = {"image":image,"component":component,"factor":factor}
	return sources

static func _load_obj(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Could not open OBJ."}
	var verts := PackedVector3Array()
	var tex := PackedVector2Array()
	var model := ModelGeometry.new()
	model.label = path.get_file().get_basename()
	var obj := 0
	var mat := 0
	var mat_names: Dictionary = {}
	while not file.eof_reached():
		var parts := file.get_line().get_slice("#", 0).replace("\t", " ").strip_edges().split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"v":
				if parts.size() >= 4:
					verts.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
			"vt":
				if parts.size() >= 3:
					tex.append(Vector2(float(parts[1]), 1.0 - float(parts[2])))
			"o", "g":
				obj += 1
			"usemtl":
				var name := parts[1] if parts.size() > 1 else "Default"
				if not mat_names.has(name):
					mat_names[name] = mat_names.size()
				mat = mat_names[name]
			"f":
				if parts.size() < 4:
					continue
				var face_positions := PackedVector3Array()
				var face_uv := PackedVector2Array()
				for token in parts.slice(1):
					var indices := token.split("/")
					var vi := int(indices[0])
					vi = vi - 1 if vi > 0 else verts.size() + vi
					if vi < 0 or vi >= verts.size():
						return {"error": "Invalid vertex index in OBJ."}
					face_positions.append(verts[vi])
					var ti := int(indices[1]) if indices.size() > 1 and not indices[1].is_empty() else 0
					if ti == 0:
						model.has_uv = false
						face_uv.append(Vector2.ZERO)
					else:
						ti = ti - 1 if ti > 0 else tex.size() + ti
						if ti < 0 or ti >= tex.size():
							return {"error": "Invalid texture index in OBJ."}
						face_uv.append(tex[ti])
				var n := (face_positions[1] - face_positions[0]).cross(face_positions[2] - face_positions[0]).normalized()
				var axis := n.abs().max_axis_index()
				var poly := PackedVector2Array()
				for p in face_positions:
					poly.append(Vector2(p[(axis + 1) % 3], p[(axis + 2) % 3]))
				var tris := Geometry2D.triangulate_polygon(poly)
				if tris.is_empty():
					return {"error": "OBJ has a degenerate or self-intersecting polygon."}
				for t in range(0, tris.size(), 3):
					var order := [tris[t], tris[t + 1], tris[t + 2]]
					var tn := (face_positions[order[2]] - face_positions[order[0]]).cross(face_positions[order[1]] - face_positions[order[0]])
					if tn.dot(n) < 0:
						order.reverse()
					for c in order:
						model.positions.append(face_positions[c])
						model.normals.append(n)
						model.uvs.append(face_uv[c])
					model.materials.append(mat)
					model.objects.append(obj)
	return {"geometry": model}
