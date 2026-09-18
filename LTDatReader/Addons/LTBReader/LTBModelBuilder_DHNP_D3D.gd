# res://Addons/LTBReader/LTBModelBuilder_DHNP_D3D.gd
tool
extends Reference

# DHNP-D3D-Hybrid Model Builder - konvertiert LTB_DHNP_D3D-Daten in eine
# Godot-Szene. Nach LTBModelBuilder_PC.gd modelliert (gleiche Struktur:
# Skeleton + ein MeshInstance pro Piece), aber mit Bone-Gewichtung ueber
# SurfaceTool.add_bones/add_weights wie in ABCReader/ModelBuilder.gd, weil
# DHNP-D3D-Vertices (anders als beim einfachen LTB-PC-Reader hier) echte
# Pro-Vertex-Bone-Weights tragen und wir nur die Ruhepose zeigen wollen:
# ein Skeleton MIT gesetzten Bone-Rest-Transforms, aber OHNE AnimationPlayer,
# rendert automatisch in Bind-/Ruhepose (kein Backen von Welt-Koordinaten
# noetig).

func build(source_file, options, start_offset: int = 0):
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		print("Failed to open " + source_file)
		return FAILED

	print("Building DHNP D3D-Hybrid LTB Model from: " + source_file)

	var dhnp = preload("res://Addons/LTBReader/Models/LTB_DHNP_D3D.gd").new()
	var response = dhnp.read(file, start_offset)

	file.close()

	if response.code == dhnp.IMPORT_RETURN.ERROR:
		print("IMPORT ERROR (DHNP D3D-Hybrid): " + str(response.message))
		return FAILED

	# Create Godot scene
	var scene = PackedScene.new()
	var root = Spatial.new()
	root.name = source_file.get_file().get_basename()

	# Create skeleton if nodes exist
	var skeleton = Skeleton.new()
	skeleton.name = "Skeleton"
	if dhnp.nodes.size() > 0:
		_fill_skeleton(dhnp, skeleton)
	root.add_child(skeleton)
	skeleton.owner = root

	# Convert each piece to mesh (nur erstes LOD -- wir zeigen nur die Ruhepose,
	# keine Animation, siehe Auftrag)
	for piece in dhnp.pieces:
		if piece.lods.size() == 0:
			continue

		var lod = piece.lods[0]

		if lod.vertices.size() == 0 or lod.faces.size() == 0:
			continue

		var mesh_instance = _create_mesh_instance(piece, lod, dhnp, source_file)

		if mesh_instance:
			skeleton.add_child(mesh_instance)
			mesh_instance.owner = root

	# Pack scene
	scene.pack(root)
	print("DHNP D3D-Hybrid Model built successfully - Total Pieces: ", dhnp.pieces.size())

	root.free()

	return scene


func _fill_skeleton(dhnp, skeleton: Skeleton):
	print("Creating skeleton with ", dhnp.nodes.size(), " bones (DHNP D3D-Hybrid)")

	for node in dhnp.nodes:
		skeleton.add_bone(node.name)

	# Bind-Matrix relativ zum Parent setzen -- gleiches Muster wie
	# ABCReader/ModelBuilder.gd's build_skeleton() fuer ABC v9-13
	# (bind_matrix ist objektraum-relativ-zum-Parent gespeichert).
	for i in range(dhnp.nodes.size()):
		var node = dhnp.nodes[i]
		var bind_matrix = node.bind_matrix

		if node.parent != null:
			var parent_node = node.parent.get_ref()
			var parent_idx = dhnp.nodes.find(parent_node)
			if parent_idx >= 0:
				skeleton.set_bone_parent(i, parent_idx)
				bind_matrix = parent_node.bind_matrix.inverse() * bind_matrix

		skeleton.set_bone_rest(i, bind_matrix)


func _create_mesh_instance(piece, lod, dhnp, source_file = "") -> MeshInstance:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	print("Building mesh for piece: ", piece.name, " - Vertices: ", lod.vertices.size(), " Faces: ", lod.faces.size())

	for face in lod.faces:
		if face.vertices.size() != 3:
			continue

		# Wickelrichtung umgekehrt (0,2,1 statt 0,1,2) -- gleiches Vorgehen wie
		# in LTBModelBuilder_PC.gd, "um nach innen zeigende Flaechen zu fixen".
		# VERMUTUNG: fuer DHNP-D3D nicht an echtem Rendering ueberprueft (in
		# dieser Session stand keine laufende Godot-Instanz zur Verfuegung) --
		# falls Meshes nach innen zeigen, hier auf [0,1,2] zuruecktauschen.
		for i in [0, 2, 1]:
			var face_vertex = face.vertices[i]
			var vertex_index = face_vertex.vertex_index

			if vertex_index < 0 or vertex_index >= lod.vertices.size():
				continue

			var vertex = lod.vertices[vertex_index]

			st.add_uv(face_vertex.texcoord)
			st.add_normal(vertex.normal)

			var bones = PoolIntArray()
			var weights = PoolRealArray()
			for w in vertex.weights:
				bones.append(w.node_index)
				weights.append(w.bias)

			# Wie in ABCReader/ModelBuilder.gd's fill_array_mesh: SurfaceTool
			# braucht immer genau 4 Bone/Weight-Eintraege pro Vertex.
			var remainder = 4 - vertex.weights.size()
			for filler in range(remainder):
				bones.append(-1)
				weights.append(0.0)

			if vertex.weights.size() > 0:
				st.add_bones(bones)
				st.add_weights(weights)

			st.add_vertex(vertex.location)

	var mesh = st.commit()

	if mesh.get_surface_count() == 0:
		print("WARNING: No surfaces generated for piece: ", piece.name)
		return null

	var mesh_instance = MeshInstance.new()
	mesh_instance.name = piece.name
	mesh_instance.mesh = mesh

	# Material mit Textur
	var material = SpatialMaterial.new()
	material.flags_unshaded = false

	if source_file != "":
		var texture_builder = preload("res://Addons/DTXReader/TextureBuilder.gd").new()
		var texture_path = _get_dtx_path(source_file, piece.material_index)
		print("Piece: ", piece.name, " Material_Index: ", piece.material_index, " -> Texture: ", texture_path)

		if File.new().file_exists(texture_path):
			var texture = texture_builder.build(texture_path, {})
			if texture != null:
				material.albedo_texture = texture
			else:
				print("ERROR: Texture nicht geladen: ", texture_path)
				material.albedo_color = Color(0.5, 0.5, 0.5)
		else:
			print("DTX nicht gefunden: ", texture_path)
			material.albedo_color = Color(0.5, 0.5, 0.5)
	else:
		material.albedo_color = Color(0.5, 0.5, 0.5)

	mesh_instance.material_override = material

	# ABC/LTB --> Godot Koordinatensystem-Korrektur (X-Spiegelung), wie an
	# allen anderen Stellen dieses Projekts.
	mesh_instance.scale = Vector3(-1.0, 1.0, 1.0)

	return mesh_instance


# Angelehnt an ABCReader/ModelBuilder.gd's get_dtx_path, aber ohne die dort
# vorhandene Gun/Head-Sonderbehandlung, die auf Charaktermodelle zugeschnitten
# ist. DHNP-D3D-Modelle in den bisher gesehenen Beispielen (VASE2, SANTA_STATUE,
# ALEXANDER, ...) sind ueberwiegend Requisiten mit wenigen Materialien; das
# "_<index>"-Namensschema wird als VERMUTUNG aus der ABC-Konvention
# uebernommen und ist fuer DHNP nicht eigens bestaetigt.
func _get_dtx_path(model_path: String, material_index: int) -> String:
	var base_dir = model_path.get_base_dir()
	var base_name = model_path.get_file().get_basename()
	var skin_dir = base_dir.replace("models_pv", "skins_pv").replace("models", "skins")

	var suffix = ""
	if material_index != 0:
		suffix = "_" + str(material_index)

	var dtx_name = base_name + suffix + ".dtx"

	var candidates = [skin_dir + "/" + dtx_name]
	if skin_dir != base_dir:
		candidates.append(base_dir + "/" + dtx_name)

	var f = File.new()
	for candidate in candidates:
		var upper = candidate.get_base_dir() + "/" + candidate.get_file().get_basename() + ".DTX"
		if f.file_exists(candidate) or f.file_exists(upper):
			return candidate

	return candidates[0]
