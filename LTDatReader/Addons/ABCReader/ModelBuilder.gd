extends Node

# ABC --> Godot Koordinatensystem-Korrektur
var mirror_abc_for_godot = true  # Für Links-Rechts Spiegelung

# Just the skeleton I can access anywhere, mostly for debug purposes
var cheat_skeleton := Skeleton.new()

var model = null

func build(source_file, options):
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		print("Failed to open " + source_file)
		return FAILED
		
	print("Opened " + source_file)
	
	var path = self.get_script().get_path().get_base_dir() + "/Models"
	var abc_file = load(path + "/ABC.gd")
	var abc6_file = load(path + "/ABC6.gd")
	
	# Our helper script
	var abc_helper_script = load(self.get_script().get_path().get_base_dir() + "/ABCHelper.gd")
	
	var model = abc_file.ABC.new()
	
	var response = model.read(file)
	if response.code == model.IMPORT_RETURN.ERROR:
		print("Checking ABC version 6 reader!")
		# Try ABC 6
		model = abc6_file.ABC.new()
		response = model.read(file)
		
		#...nope, we're ded.
		if response.code == model.IMPORT_RETURN.ERROR:
			file.close()
			print("IMPORT ERROR: " + str(response.message))
			return FAILED
	
	self.model = model	
		
	# Actually close the darn thing
	file.close()
		
	# Setup our new scene
	var scene = PackedScene.new()
	
	# Create our nodes
	var root = Spatial.new()
	
	# Setup the nodes
	root.name = "Root"
	
	root.set_script(abc_helper_script)
	
	var skeleton = Skeleton.new()
	skeleton.name = "Skeleton"
	skeleton = build_skeleton(model, skeleton)
	root.add_child(skeleton)
	skeleton.owner = root
	self.cheat_skeleton = skeleton
	
	#print("=== SKELETON DEBUG ===")
	#print("Skeleton hat ", skeleton.get_bone_count(), " Bones")
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)
		var parent_idx = skeleton.get_bone_parent(i)
		var rest_transform = skeleton.get_bone_rest(i)
		#print("Bone ", i, ": ", bone_name, " | Parent: ", parent_idx)
		#print("  Rest Transform: ", rest_transform)
	
	var meshes = fill_array_mesh(model, skeleton)
	
	# DTX Texture Loading Setup
	#var texture_path = get_dtx_path(source_file)
	var texture_builder = load("res://addons/DTXReader/TextureBuilder.gd").new()
	
	
	# Loop through our pieces, and add them to mesh instances
	for i in range(len(meshes)):
		var mesh = meshes[i]
		var piece = model.pieces[i]
		var mesh_instance = MeshInstance.new()
		mesh_instance.name = piece.name
		mesh_instance.mesh = mesh
		
		# ABC --> Godot Koordinatensystem-Korrektur
		if mirror_abc_for_godot and model.version != 6:
			mesh_instance.scale = Vector3(-1.0, 1.0, 1.0)
			
		# Create material with DTX texture
		var material = SpatialMaterial.new()
		material.flags_unshaded = true
		#material.flags_albedo_tex_force_srgb = true
		
		# HIER: Texture-Path für jedes Piece einzeln berechnen
		var texture_path = get_dtx_path(source_file, piece.material_index)
		print("Piece: ", piece.name, " Material_Index: ", piece.material_index, " -> Texture: ", texture_path)
		
		if File.new().file_exists(texture_path):
			var texture = texture_builder.build(texture_path, {})
			if texture != null:
				material.albedo_texture = texture
			else:
				print("ERROR: Texture nicht geladen: ", texture_path)
		else:
			print("DTX nicht gefunden: ", texture_path)
			material.albedo_color = Color(0.5, 0.5, 0.5)
		
		mesh_instance.material_override = material
		skeleton.add_child(mesh_instance)
		mesh_instance.owner = root
	# End For
	
	# Animation time!
	var anim_player = AnimationPlayer.new()
	anim_player.name = "AnimPlayer"
	root.add_child(anim_player)
	anim_player.owner = root
	# v6: Vertices sind bereits in World-Space gebaked -> kein AnimPlayer befuellen,
	# sonst wuerde der Skeleton animiert und das Mesh doppelt verschoben.
	# v9-13: AnimPlayer liefert die Ruhepose via process_animations.
	if model.version != 6:
		anim_player = process_animations(model, anim_player)
	
	#autoset camera to scene
	# called from ModelRendererController after add_child
	
	# Model aufrecht stellen:
	#root.rotation_degrees = Vector3(0, 0, -90)
	
	# Pack our scene!
	scene.pack(root)
	
	# Clean up!
	#root.queue_free()
	
	return scene

func get_dtx_path(abc_path: String, material_index: int) -> String:
	var base_dir = abc_path.get_base_dir()
	var base_name = abc_path.get_file().get_basename()
	var skin_dir = base_dir\
		.replace("models_pv", "skins_pv")\
		.replace("models", "skins")
	
	var is_gun = abc_path.to_lower().find("guns") != -1
	
	var suffix = ""
	if material_index == 0:
		suffix = ""
	elif material_index == 1:
		suffix = "_head" if not is_gun else ""  # guns haben keine head-tex
	else:
		suffix = "_" + str(material_index)
	
	var dtx_name = base_name + suffix + ".dtx"
	
	# Versuche skin_dir zuerst, dann denselben Ordner wie die ABC (z.B. Desktop/ENEMIES/)
	var candidates = [skin_dir + "/" + dtx_name]
	if skin_dir != base_dir:
		candidates.append(base_dir + "/" + dtx_name)
	
	var f = File.new()
	for candidate in candidates:
		var upper = candidate.get_base_dir() + "/" + candidate.get_file().get_basename() + ".DTX"
		if f.file_exists(candidate) or f.file_exists(upper):
			return candidate
	
	# Kein Treffer -> skin_dir zurückgeben (TextureBuilder gibt null zurück)
	return candidates[0]

# func get_dtx_path(abc_path: String) -> String:
	# var base_dir = abc_path.get_base_dir()
	# var file_name = abc_path.get_file().replace(".abc", ".dtx")
	
	# # models_pv --> skins_pv
	# if base_dir.ends_with("models_pv"):
		# return base_dir.replace("models_pv", "skins_pv") + "/" + file_name
	
	# # models --> skins  
	# elif base_dir.ends_with("models"):
		# return base_dir.replace("models", "skins") + "/" + file_name
	
	# # Fallback: gleicher Ordner
	# return base_dir + "/" + file_name


func fill_array_mesh(model, skeleton):
	var meshes = []
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	print("=== SKELETON INFO ===")
	print("Skeleton hat ", skeleton.get_bone_count(), " Bones")
	
	# Waehle die beste Anim als Ruhepose:
	# 1. 'static_model' (explizite Ruhepose) bevorzugt
	# 2. Sonst: Anim mit kleinster Differenz zwischen Deform-Node und Pelvis
	# 3. Fallback: anim[0]
	var rest_anim = null
	if model.version == 6 and model.animations.size() > 0:
		for anim in model.animations:
			if anim.name == "static_model":
				rest_anim = anim
				break
		if rest_anim == null:
			rest_anim = _find_neutral_anim(model)
	
	# Baue einen Lookup: vertex_global_index -> expandierte World-Position
	# fuer alle Deform-Verts (MDVertList pro Deform-Node)
	var deform_vert_positions = {}
	if rest_anim != null:
		for node_idx in range(model.nodes.size()):
			var node = model.nodes[node_idx]
			if (node.flags & 4) and node.mesh_deformation_vertex_count > 0:
				var expanded = rest_anim.vertex_deformations[node_idx]
				var md_count = node.mesh_deformation_vertex_count
				var bone_world = _bone_world_transform(model, skeleton, node_idx)
				for vi in range(min(md_count, expanded.size())):
					var global_vert_idx = node.mesh_deformation_vertex_list[vi]
					deform_vert_positions[global_vert_idx] = bone_world.xform(expanded[vi])

	# Zaehler fuer globalen Vertex-Index (fuer deform_vert_positions Lookup)
	var global_vert_counter = 0

	for piece in model.pieces:
		var verts = PoolVector3Array()
		var uvs = PoolVector2Array()
		var normals = PoolVector3Array()
		var indices = PoolIntArray()
		
		# Holds vertex_bone_data
		# Basically the weights per a vertex
		var piece_bone_data = []
		
		# Count
		var vert_weight_count = PoolIntArray()
		
		for lod in piece.lods:
			for vertex in lod.vertices:
				var node_flags = 0
				var bone_idx = -1
				if vertex.weights.size() > 0:
					bone_idx = vertex.weights[0].node_index
					if bone_idx < model.nodes.size():
						node_flags = model.nodes[bone_idx].flags
				
				if model.version == 6:
					if node_flags & 4:
						# Deform-Node: expandierte Position aus Rest-Anim KF0
						if deform_vert_positions.has(global_vert_counter):
							verts.append(deform_vert_positions[global_vert_counter])
						else:
							verts.append(Vector3(0, 0, 0))
					else:
						var world_pos = vertex.location
						if bone_idx >= 0 and bone_idx < model.nodes.size():
							world_pos = _bone_world_transform(model, skeleton, bone_idx).xform(vertex.location)
						verts.append(world_pos)
				else:
					# ABC v9-13: original - bone-lokal, AnimPlayer macht die Pose
					verts.append(vertex.location)
				
				global_vert_counter += 1
				normals.append(vertex.normal)
				vert_weight_count.append(vertex.weight_count)
				var vertex_bone_data = []
				for weight in vertex.weights:
					vertex_bone_data.append([weight.node_index, weight.bias])
				piece_bone_data.append(vertex_bone_data)
			# End For
			for face in lod.faces:
				for vertex in face.vertices:
					var texcoord = vertex.texcoord
					var vertex_index = vertex.vertex_index
					
					uvs.append( Vector2( texcoord.x, texcoord.y ) )
					
					indices.append(vertex_index)
				# End For
			# End For
			# Only want the first LOD
			break
		# End For
		
		# If we need to flip the indices, then do so
		# This applies to pretty much every model except for Shogo, and Blood 2...
		if !model.front_to_back_indices:
			indices.invert()
			uvs.invert()
			
		var i = 0
		for index in indices:
			st.add_uv(uvs[i])
			st.add_normal(normals[index])
			
			var this_vert_bones = PoolIntArray()
			var this_vert_weights = PoolRealArray()
			
			# Index 0: Node Index
			# Index 1: Bias
			for bone_data in piece_bone_data[index]:
				this_vert_bones.append(bone_data[0])
				this_vert_weights.append(bone_data[1])
			# End For
			
			# For some reason these MUST be 4 values each!
			var remainder = 4 - vert_weight_count[index]
			for filler in range(remainder):
				this_vert_bones.append(-1)
				this_vert_weights.append(0.0)
			# End For
				
			if vert_weight_count[index] > 0:
				st.add_bones(this_vert_bones)
				st.add_weights(this_vert_weights)
			
			st.add_vertex(verts[index])
			i += 1
		
		meshes.append(st.commit())
		
		# Clear out the previous piece
		st.clear()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)


	return meshes
# End Func


		
func build_skeleton(model, skeleton : Skeleton):
	# Pass 1: alle Bones hinzufuegen
	for i in range(model.node_count):
		skeleton.add_bone(model.nodes[i].name)
	
	# Pass 2: Parent und Rest-Transform setzen
	for i in range(model.node_count):
		var lt_node = model.nodes[i]
		
		if lt_node.parent != null:
			skeleton.set_bone_parent(i, lt_node.parent.index)
		
		if model.version == 6:
			if not model.has_meta("_rest_anim_cached"):
				var ra = null
				for anim in model.animations:
					if anim.name == "static_model":
						ra = anim
						break
				if ra == null:
					ra = _find_neutral_anim(model)
				model.set_meta("_rest_anim_cached", ra)
			var rest_anim = model.get_meta("_rest_anim_cached")
			
			if rest_anim != null and rest_anim.keyframe_count > 0:
				var kf0 = rest_anim.node_keyframes[i][0]
				var rot = kf0.rotation.normalized()
				if model.flip_anim:
					rot = rot.inverse()
				skeleton.set_bone_rest(i, lt_transform_to_godot_transform(kf0.location, rot))
		else:
			# ABC v9-13: bind_matrix relativ zum Parent setzen (original).
			var bind_matrix = lt_node.bind_matrix
			if lt_node.parent != null:
				bind_matrix = lt_node.parent.bind_matrix.inverse() * bind_matrix
			skeleton.set_bone_rest(i, bind_matrix)
	# End For
	
	return skeleton
# End Func


func process_animations(model, anim_player : AnimationPlayer):
	
	for lt_anim in model.animations:
		var anim = Animation.new()
		# Pre-make our track ids
		for ni in range(model.node_count):
			var key = "Skeleton:" + model.nodes[ni].name
			var track_id = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(track_id, key)
		# End For
		
		var last_scaled_key = 0
		for kfi in range(lt_anim.keyframe_count):
			var lt_keyframe = lt_anim.keyframes[kfi]
			var scaled_key = lt_keyframe.time
			if scaled_key != 0:
				scaled_key /= 1000.0
			# End If
			self.recursively_apply_transform(model, 0, kfi, lt_anim, anim, scaled_key, Transform.IDENTITY)
			last_scaled_key = scaled_key

			# Check for command string...
			if lt_keyframe.command_string != "":
				var key = "." # Root
				var track_id = anim.add_track(Animation.TYPE_METHOD)
				anim.track_set_path(track_id, key)
				anim.track_insert_key(track_id, scaled_key, {"method": "run_command_string", "args": [ lt_keyframe.command_string ]})
			# End If	

		# End For
		
		anim.length = last_scaled_key
		anim_player.add_animation(lt_anim.name, anim)
	# End For
	
	return anim_player
# End Func

func auto_frame_camera(model_root, camera = null):
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
	var camera_distance = model_size * 1.5  # 1.5x Abstand für gute Sicht
	
	# Kamera positionieren (45° Winkel von vorne-rechts-oben)
	var camera_offset = Vector3(camera_distance * 0.7, camera_distance * 0.5, camera_distance * 0.7)
	var camera_position = model_center + camera_offset
	
	print("Model AABB: ", aabb)
	print("Kamera Position: ", camera_position, " -> Ziel: ", model_center)
	
	# Falls Sie Zugriff auf die Kamera haben:
	# camera.global_transform.origin = camera_position
	# camera.look_at(model_center, Vector3.UP)

# This is quite a function!
# Call this within a keyframe loop
func recursively_apply_transform(model, node_index, keyframe_index, lt_anim, godot_anim : Animation, scaled_key, parent_matrix):
	var node = model.nodes[node_index]
	
	var transform = lt_anim.node_keyframes[node_index][keyframe_index]
	var matrix = self.lt_transform_to_godot_transform(transform.location, transform.rotation)
	var matrix_copy = matrix
	
	# This is the thing that's broken for version 9-13 animations!
	if model.version > 6:
		matrix = parent_matrix * matrix 
		matrix_copy = matrix
		#matrix = node.inverse_bind_matrix * matrix
		matrix = cheat_skeleton.get_bone_rest(node_index).inverse() * matrix
		#matrix *= node.bind_matrix
		#matrix = parent_matrix * matrix 

	var translation = matrix.origin 
	var rotation  = matrix.basis.get_rotation_quat()
	
	# Needed for v6!
	if model.flip_anim:
		rotation = rotation.inverse()
	
	# Node index SHOULD equal track id!
	godot_anim.transform_track_insert_key(node_index, scaled_key, translation, rotation, Vector3(1.0, 1.0, 1.0))
	
	# Now recursively crawl through the child nodes
	for child_index in node.child_count:
		node_index += 1
		node_index = recursively_apply_transform(model, node_index, keyframe_index, lt_anim, godot_anim, scaled_key, matrix_copy)
	# End For
	
	return node_index
# End Func

func lt_transform_to_godot_transform(loc, rot):
	var transform = Transform()
	var basis = Basis(rot)
	transform.basis = basis
	transform.origin = loc
	return transform

# Berechnet die akkumulierte World-Transform eines Bones
# durch Verkettung aller Rest-Transforms von Root bis zum Bone.
func _find_neutral_anim(model):
	# Findet die Anim wo Deform-Nodes am naechsten am Koerper-Zentrum sind.
	# Kriterium: kleinste Y-Differenz zwischen erstem Deform-Node und Pelvis-Node.
	# Fallback: anim[0]
	if model.animations.size() == 0:
		return null
	
	# Finde Pelvis- und Deform-Node-Indices
	var pelvis_idx = -1
	var deform_idx = -1
	for i in range(model.nodes.size()):
		var n = model.nodes[i]
		if pelvis_idx == -1 and n.name.to_lower().find("pelvis") >= 0:
			pelvis_idx = i
		if deform_idx == -1 and (n.flags & 4) and n.mesh_deformation_vertex_count > 0:
			deform_idx = i
	
	if pelvis_idx < 0 or deform_idx < 0:
		return model.animations[0]
	
	var best_anim = model.animations[0]
	var best_diff = INF
	
	for anim in model.animations:
		if anim.keyframe_count == 0:
			continue
		var pelvis_y = anim.node_keyframes[pelvis_idx][0].location.y
		var deform_y = anim.node_keyframes[deform_idx][0].location.y
		var diff = abs(deform_y - pelvis_y)
		if diff < best_diff:
			best_diff = diff
			best_anim = anim
	
	print("Neutralste Anim fuer Deform-Nodes: ", best_anim.name, " (diff=", best_diff, ")")
	return best_anim
# End Func

func _bone_world_transform(model, skeleton : Skeleton, bone_idx : int) -> Transform:
	# KF0-Transforms (v6) und relativierte bind_matrices (v9-13) sind beide
	# relativ zum Parent-Bone -> Kette vom Root akkumulieren.
	var result = skeleton.get_bone_rest(bone_idx)
	var parent_idx = skeleton.get_bone_parent(bone_idx)
	while parent_idx >= 0:
		result = skeleton.get_bone_rest(parent_idx) * result
		parent_idx = skeleton.get_bone_parent(parent_idx)
	return result
