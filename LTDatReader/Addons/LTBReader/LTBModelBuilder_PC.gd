# res://Addons/LTBReader/LTBModelBuilder_PC.gd
tool
extends Node

# PC LTB Model Builder - Converts LTB_PC data to Godot meshes
# For NOLF2, Tron 2.0 PC Character Models

func build(source_file, options):
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		print("Failed to open " + source_file)
		return FAILED
	
	print("Building PC LTB Model from: " + source_file)
	
	# Read the model using LTB_PC reader
	var ltb_pc = load("res://Addons/LTBReader/Models/LTB_PC.gd").new()
	var response = ltb_pc.read(file)
	
	if response.code != ltb_pc.IMPORT_RETURN.SUCCESS:
		print("Failed to read PC LTB file: ", response.message)
		file.close()
		return FAILED
	
	file.close()
	
	# Create Godot scene
	var scene = PackedScene.new()
	var root = Spatial.new()
	root.name = ltb_pc.name
	
	# Create skeleton if nodes exist
	var skeleton = null
	if ltb_pc.nodes.size() > 0:
		skeleton = _create_skeleton(ltb_pc)
		root.add_child(skeleton)
		skeleton.owner = root
	
	# Convert each piece to mesh
	for piece in ltb_pc.pieces:
		if piece.lods.size() == 0:
			continue
		
		# Use LOD 0
		var lod = piece.lods[0]
		
		if lod.vertices.size() == 0 or lod.faces.size() == 0:
			continue
		
		var mesh_instance = _create_mesh_instance(piece, lod, ltb_pc, skeleton)
		
		if mesh_instance:
			root.add_child(mesh_instance)
			mesh_instance.owner = root
	
	# Pack scene
	scene.pack(root)
	print("PC LTB Model built successfully - Total Pieces: ", ltb_pc.pieces.size())
	
	return scene

func _create_skeleton(ltb_pc) -> Skeleton:
	var skeleton = Skeleton.new()
	skeleton.name = "Skeleton"
	
	print("Creating skeleton with ", ltb_pc.nodes.size(), " bones")
	
	# Add bones
	for node in ltb_pc.nodes:
		var bone_idx = skeleton.get_bone_count()
		skeleton.add_bone(node.name)
		
		# Set bone rest
		skeleton.set_bone_rest(bone_idx, node.bind_matrix)
		
		# Link parent
		if node.parent:
			var parent_idx = ltb_pc.nodes.find(node.parent)
			if parent_idx >= 0:
				skeleton.set_bone_parent(bone_idx, parent_idx)
	
	return skeleton

func _create_mesh_instance(piece, lod, ltb_pc, skeleton) -> MeshInstance:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	print("Building mesh for piece: ", piece.name, " - Vertices: ", lod.vertices.size(), " Faces: ", lod.faces.size())
	
	# Add vertices
	for face in lod.faces:
		if face.indices.size() != 3:
			continue

		# reverse order to fix inside-out geometry
		for i in [0, 2, 1]:  # instead of [0,1,2]
			var idx = face.indices[i]
			if idx >= lod.vertices.size():
				continue

			var vertex = lod.vertices[idx]

			if vertex.normal != Vector3.ZERO:
				st.add_normal(vertex.normal)

			if vertex.uv1 != Vector2.ZERO:
				st.add_uv(vertex.uv1)

			if vertex.color != 0:
				var r = float((vertex.color >> 16) & 0xFF) / 255.0
				var g = float((vertex.color >> 8) & 0xFF) / 255.0
				var b = float(vertex.color & 0xFF) / 255.0
				var a = float((vertex.color >> 24) & 0xFF) / 255.0
				st.add_color(Color(r, g, b, a))

			st.add_vertex(vertex.location)
	
	# Generate normals if needed
	if lod.vertices.size() > 0 and lod.vertices[0].normal == Vector3.ZERO:
		st.generate_normals()
	
	var mesh = st.commit()
	
	if mesh.get_surface_count() == 0:
		print("WARNING: No surfaces generated for piece: ", piece.name)
		return null
	
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = piece.name
	mesh_instance.mesh = mesh
	
	# Apply basic material
	var material = SpatialMaterial.new()
	material.vertex_color_use_as_albedo = true
	mesh_instance.set_surface_material(0, material)
	
	# Mirror for Godot coordinates (like in WorldBuilder)
	mesh_instance.scale = Vector3(-1.0, 1.0, 1.0)
	
	return mesh_instance
