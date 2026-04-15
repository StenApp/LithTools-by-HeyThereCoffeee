extends Node

# Just the skeleton I can access anywhere, mostly for debug purposes
var cheat_skeleton := Skeleton.new()

var model = null

var fix_winding_for_godot = true  # Für inside-out
var mirror_for_godot = true       # Für links-rechts

func build(source_file, options):
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		print("Failed to open " + source_file)
		return FAILED
		
	print("Opening LTB file: " + source_file)
	
	# Load our LTB reader
	var ltb_file = load(self.get_script().get_path().get_base_dir() + "/Models/LTB_PS2.gd")
	
	# Our helper script
	var ltb_helper_script = load(self.get_script().get_path().get_base_dir() + "/LTBHelper.gd")
	
	var model = ltb_file.new()
	
	var response = model.read(file)
	if response.code == model.IMPORT_RETURN.ERROR:
		file.close()
		print("LTB IMPORT ERROR: " + str(response.message))
		return FAILED
	
	self.model = model	
	file.close()
	
	print("LTB model loaded successfully: ", model.name)
	print("Pieces: ", model.pieces.size())
	print("Nodes: ", model.nodes.size())
	print("LOD Count: ", model.lod_count)
		
	# Setup our new scene
	var scene = PackedScene.new()
	
	# Create our nodes
	var root = Spatial.new()
	
	# Setup the nodes
	root.name = "Root"
	root.set_script(ltb_helper_script)
	
	var skeleton = Skeleton.new()
	skeleton.name = "Skeleton"
	skeleton = build_skeleton(model, skeleton)
	root.add_child(skeleton)
	skeleton.owner = root
	self.cheat_skeleton = skeleton
	
	print("=== SKELETON DEBUG ===")
	print("Skeleton hat ", skeleton.get_bone_count(), " Bones")
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)
		var parent_idx = skeleton.get_bone_parent(i)
		var rest_transform = skeleton.get_bone_rest(i)
		print("Bone ", i, ": ", bone_name, " | Parent: ", parent_idx)
		print("  Rest Transform: ", rest_transform)
	
	var meshes = fill_array_mesh(model, skeleton)
	
	# DTX Texture Loading Setup
	var texture_builder = load("res://addons/DTXReader/TextureBuilder.gd").new()
	
	# Loop through our pieces, and add them to mesh instances
	for i in range(len(meshes)):
		var mesh = meshes[i]
		var piece = model.pieces[i]
		var mesh_instance = MeshInstance.new()
		mesh_instance.name = piece.name
		mesh_instance.mesh = mesh
		
		# PS2 --> Godot Koordinatensystem-Korrektur
		if mirror_for_godot:
			mesh_instance.scale = Vector3(-1.0, 1.0, 1.0)
		
		# Create material with DTX texture
		var material = SpatialMaterial.new()
		material.flags_unshaded = true
		
		# Texture-Path für jedes Piece einzeln berechnen
		var texture_path = get_dtx_path(source_file, piece.material_index)
		print("Piece: ", piece.name, " Material_Index: ", piece.material_index, " -> Texture: ", texture_path)
		
		if File.new().file_exists(texture_path):
			var texture = texture_builder.build(texture_path, {})
			if texture != null:
				material.albedo_texture = texture
				print("Texture geladen: ", texture_path)
			else:
				print("DTX-Fehler: ", texture_path)
		else:
			print("DTX nicht gefunden: ", texture_path)
		
		mesh_instance.material_override = material
		skeleton.add_child(mesh_instance)
		mesh_instance.owner = root
	# End For
	
	# Animation time!
	var anim_player = AnimationPlayer.new()
	anim_player.name = "AnimPlayer"
	root.add_child(anim_player)
	anim_player.owner = root
	anim_player = process_animations(model, anim_player)
	
	# Autoset camera to scene
	#auto_frame_camera(root)
	
	# Model aufrecht stellen:
	#root.rotation_degrees = Vector3(0, 0, -90)
	
	# Pack our scene!
	scene.pack(root)
	
	# Clean up!
	
	return scene

func get_dtx_path(ltb_path: String, material_index: int) -> String:
	var base_dir = ltb_path.get_base_dir()
	var base_name = ltb_path.get_file().get_basename()
	var skin_dir = base_dir.replace("models_pv", "skins_pv").replace("models", "skins")
	
	# Prüfe ob es ein Gun-Model ist
	var is_gun = ltb_path.to_lower().find("guns") != -1
	
	if material_index == 0:
		# Index 0 = Haupt-Model-Texture (für alle)
		return skin_dir + "/" + base_name + ".dtx"
	elif material_index == 1:
		if is_gun:
			# Guns: Index 1 = Action Hands
			return skin_dir + "/actionhands_pv.dtx"
		else:
			# Characters: Index 1 = Head Texture
			return skin_dir + "/" + base_name + "_head.dtx"
	else:
		# Fallback für andere Indices
		return skin_dir + "/" + base_name + "_" + str(material_index) + ".dtx"

func fill_array_mesh(model, skeleton):
	var meshes = []
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	print("=== MESH CREATION DEBUG ===")
	print("Creating meshes for ", model.pieces.size(), " pieces")

	for piece_index in range(model.pieces.size()):
		var piece = model.pieces[piece_index]
		print("Processing piece ", piece_index, ": ", piece.name)
		
		var verts = PoolVector3Array()
		var uvs = PoolVector2Array()
		var normals = PoolVector3Array()
		var indices = PoolIntArray()
		
		# Holds vertex_bone_data
		var piece_bone_data = []
		var vert_weight_count = PoolIntArray()
		
		# Use primary_lod (LOD 0) from LTB structure
		var primary_lod = null
		if piece.primary_lod != null:
			primary_lod = piece.primary_lod
		elif piece.lods.size() > 0:
			primary_lod = piece.lods[0]
		else:
			print("Warning: No LOD data for piece ", piece.name)
			continue
		
		print("  LOD 0 - Vertices: ", primary_lod.vertices.size(), " Faces: ", primary_lod.faces.size())
		
		# Process vertices
		for vertex in primary_lod.vertices:
			verts.append(vertex.location)
			normals.append(vertex.normal)
			vert_weight_count.append(vertex.weights.size())
			var vertex_bone_data = []
			for weight in vertex.weights:
				vertex_bone_data.append([weight.node_index, weight.bias])
			piece_bone_data.append(vertex_bone_data)
		
		# Process faces
		for face in primary_lod.faces:
			for vertex in face.vertices:
				var texcoord = vertex.texcoord
				var vertex_index = vertex.vertex_index
				
				uvs.append(Vector2(texcoord.x, texcoord.y))
				indices.append(vertex_index)
		
		print("  Final data - Verts: ", verts.size(), " Indices: ", indices.size(), " UVs: ", uvs.size())
		
		var i = 0
		for index in indices:
			if index >= verts.size():
				print("Warning: Index ", index, " out of range for vertex array size ", verts.size())
				continue
				
			st.add_uv(uvs[i])
			st.add_normal(normals[index])
			
			var this_vert_bones = PoolIntArray()
			var this_vert_weights = PoolRealArray()
			
			if index < piece_bone_data.size():
				for bone_data in piece_bone_data[index]:
					this_vert_bones.append(bone_data[0])
					this_vert_weights.append(bone_data[1])
				
				# For some reason these MUST be 4 values each!
				var remainder = 4 - vert_weight_count[index]
				for filler in range(remainder):
					this_vert_bones.append(-1)
					this_vert_weights.append(0.0)
			else:
				# Fallback: no bone weights
				for filler in range(4):
					this_vert_bones.append(-1)
					this_vert_weights.append(0.0)
			
			st.add_bones(this_vert_bones)
			st.add_weights(this_vert_weights)
			
			st.add_vertex(verts[index])
			i += 1
		
		var mesh = st.commit()
		meshes.append(mesh)
		
		# Clear out the previous piece
		st.clear()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	print("Created ", meshes.size(), " meshes")
	return meshes

func build_skeleton(model, skeleton: Skeleton):
	print("=== BUILDING SKELETON ===")
	print("Node count: ", model.node_count)
	
	for i in range(model.node_count):
		var lt_node = model.nodes[i]
		var bind_matrix = lt_node.bind_matrix
		
		print("Adding bone ", i, ": ", lt_node.name)
		skeleton.add_bone(lt_node.name)

		if lt_node.parent != null:
			skeleton.set_bone_parent(i, lt_node.parent.index)
			bind_matrix = lt_node.parent.bind_matrix.inverse() * bind_matrix
		
		skeleton.set_bone_rest(i, bind_matrix)
	
	return skeleton

func process_animations(model, anim_player: AnimationPlayer):
	print("=== PROCESSING ANIMATIONS ===")
	print("Animation count: ", model.animations.size())
	
	for lt_anim in model.animations:
		print("Processing animation: ", lt_anim.name)
		var anim = Animation.new()
		
		# Pre-make our track ids
		for ni in range(model.node_count):
			var key = "Skeleton:" + model.nodes[ni].name
			var track_id = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(track_id, key)
		
		var last_scaled_key = 0
		for kfi in range(lt_anim.keyframe_count):
			var lt_keyframe = lt_anim.keyframes[kfi]
			var scaled_key = lt_keyframe.time
			if scaled_key != 0:
				scaled_key /= 1000.0
			
			# Note: LTB doesn't have node_keyframes structure like ABC
			# This would need to be adapted based on actual LTB animation data
			
			last_scaled_key = scaled_key

			# Check for command string...
			if lt_keyframe.command_string != "":
				var key = "." # Root
				var track_id = anim.add_track(Animation.TYPE_METHOD)
				anim.track_set_path(track_id, key)
				anim.track_insert_key(track_id, scaled_key, {"method": "run_command_string", "args": [lt_keyframe.command_string]})
		
		anim.length = last_scaled_key
		anim_player.add_animation(lt_anim.name, anim)
	
	return anim_player

func auto_frame_camera(model_root):
	# Berechne die Bounding Box des gesamten Models
	var aabb = AABB()
	var first_mesh = true
	
	for child in model_root.get_children():
		if child is Skeleton:
			for mesh_child in child.get_children():
				if mesh_child is MeshInstance and mesh_child.mesh != null:
					var mesh_aabb = mesh_child.mesh.get_aabb()
					mesh_aabb = mesh_child.transform.xform(mesh_aabb)
					
					if first_mesh:
						aabb = mesh_aabb
						first_mesh = false
					else:
						aabb = aabb.merge(mesh_aabb)
	
	if first_mesh:  # Kein Mesh gefunden
		return
	
	# Berechne Kamera-Position
	var model_center = aabb.position + aabb.size * 0.5
	var model_size = aabb.size.length()
	var camera_distance = model_size * 1.5
	
	# Kamera positionieren
	var camera_offset = Vector3(camera_distance * 0.7, camera_distance * 0.5, camera_distance * 0.7)
	var camera_position = model_center + camera_offset
	
	print("Model AABB: ", aabb)
	print("Kamera Position: ", camera_position, " -> Ziel: ", model_center)

func lt_transform_to_godot_transform(loc, rot):
	var transform = Transform()
	var basis = Basis(rot)
	transform.basis = basis
	transform.origin = loc
	return transform
