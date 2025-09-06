class_name LTB

# PS2 LTB Model Reader for Godot
# Based on PS2 LTB Model Reader by Jake Breen
# Adapted for GDScript

# Constants
const REQUESTED_FILE_TYPE = 2
const REQUESTED_VERSION = 16

# Model Types
const MT_RIGID = 4
const MT_SKELETAL = 5
const MT_VERTEX_ANIMATED = 6

# Winding orders
const WO_NORMAL = 0x412
const WO_REVERSED = 0x8412

# VIF commands
const VIF_FLUSH = 0x11
const VIF_MSCALF = 0x15000000
const VIF_DIRECT = 0x50
const VIF_UNPACK = 0x6C

# Main LTB data
var name = ""
var version = 0
var node_count = 0
var lod_count = 0
var command_string = ""
var internal_radius = 0.0

# Model components
var pieces = []
var nodes = []
var animations = []
var sockets = []
var child_models = []
var weight_sets = []

# Internal counters
var _socket_counter = 0
var _animations_processed = 0

enum IMPORT_RETURN {SUCCESS, ERROR}

func read(file: File):
	print("=== Reading PS2 LTB file ===")
	
	# Read header
	var file_type = file.get_32()
	version = file.get_16()
	
	var reserved1 = file.get_16()
	var reserved2 = file.get_32()
	var reserved3 = file.get_32()
	var reserved4 = file.get_32()
	
	print("LithTech LTB (PS2) Model Reader")
	print("Loading ltb version ", version)
	
	# Verify file type and version
	if file_type != REQUESTED_FILE_TYPE:
		file.close()
		return _make_response(IMPORT_RETURN.ERROR, "LTB Importer only supports PS2 LTB files.")
	
	if version != REQUESTED_VERSION:
		file.close()
		return _make_response(IMPORT_RETURN.ERROR, "LTB Importer only supports version " + str(REQUESTED_VERSION))
	
	# Read offsets from header
	var offset_offset = file.get_32()
	var piece_offset = file.get_32()
	var node_offset = file.get_32()
	var child_model_offset = file.get_32()
	var animation_offset = file.get_32()
	var socket_offset = file.get_32()
	var file_size = file.get_32()
	var padding = file.get_32()
	
	# Read model info
	var keyframe_count = file.get_32()
	var animation_count = file.get_32()
	node_count = file.get_32()
	var piece_count = file.get_32()
	var child_model_count = file.get_32()
	var triangle_count = file.get_32()
	var vertex_count = file.get_32()
	var weight_count = file.get_32()
	lod_count = file.get_32()
	var socket_count = file.get_32()
	var weight_set_count = file.get_32()
	var string_count = file.get_32()
	var string_length_count = file.get_32()
	var model_info_unknown = file.get_32()
	
	# Read command string and internal radius
	command_string = read_string(file)
	internal_radius = file.get_float()
	
	# Read ModelInfoExtended
	var hash_magic_number = file.get_32()
	var model_info_unk1 = file.get_32()
	var model_info_unk2 = file.get_32()
	
	print("Model Info:")
	print(" - Node Count: ", node_count)
	print(" - Piece Count: ", piece_count)
	print(" - LOD Count: ", lod_count)
	print(" - Command String: ", command_string)
	
	# Read pieces
	file.seek(piece_offset)
	var piece_info_count = file.get_32()
	print("Found ", piece_info_count, " pieces in PieceInfo")
	
	for piece_index in range(piece_info_count):
		print("------------------------------------")
		print("Processing Piece ", piece_index)
		
		var piece = _read_piece(file, piece_index, hash_magic_number)
		pieces.append(piece)
	
	# Read nodes
	file.seek(node_offset)
	for i in range(node_count):
		var node = _read_node(file)
		nodes.append(node)
	
	# Link nodes
	_build_node_tree()
	
	# Read other sections (optional)
	_read_weight_sets(file)
	_read_child_models(file, child_model_offset, child_model_count)
	_read_animations(file, animation_offset, animation_count, hash_magic_number)
	_read_sockets(file, socket_offset, socket_count, hash_magic_number)
	
	name = "LTB_Model"
	
	print("=== LTB Import Complete ===")
	return _make_response(IMPORT_RETURN.SUCCESS)

func _read_piece(file: File, piece_index: int, hash_magic: int) -> Piece:
	var piece = Piece.new()
	
	# Read Piece structure
	var hashed_piece_name = file.get_32()
	var specular_power = file.get_float()
	var specular_scale = file.get_float()
	var lod_weight = file.get_float()
	
	# Skip floaty padding (9 floats)
	file.seek(file.get_position() + 4 * 9)
	
	var texture_index = file.get_32()
	var unknown1 = file.get_32()
	var unknown2 = file.get_32()
	var four = file.get_32()
	
	# Set piece properties
	piece.name = "Piece " + str(piece_index)
	piece.material_index = texture_index
	piece.specular_power = specular_power
	piece.specular_scale = specular_scale
	piece.lod_weight = lod_weight
	
	# Process LODs (but we only need LOD 0)
	for lod_index in range(lod_count):
		print("Processing LOD ", lod_index, " for Piece ", piece_index)
		
		var lod = _read_lod(file, lod_index)
		piece.lods.append(lod)
		
		# Only keep LOD 0 if specified
		if lod_index == 0:
			piece.primary_lod = lod
	
	return piece

func _read_lod(file: File, lod_index: int) -> LOD:
	var lod = LOD.new()
	
	# Read mesh type for this LOD
	var mesh_type = file.get_32()
	lod.mesh_type = mesh_type
	
	print("LOD ", lod_index, " Mesh Type: ", mesh_type)
	if mesh_type == MT_RIGID:
		print("Rigid Mesh")
	elif mesh_type == MT_SKELETAL:
		print("Skeletal Mesh")
	elif mesh_type == MT_VERTEX_ANIMATED:
		print("Vertex Animated Mesh")
	
	var vertex_list = VertexList.new()
	var mesh_set_index = 1
	var mesh_index = 0
	var lod_skeletal_unk_sector_count = 0
	
	# Read skeletal mesh data if needed
	if mesh_type == MT_SKELETAL:
		var skel_unk = file.get_32()
		lod_skeletal_unk_sector_count = file.get_32()
		print("Skeletal mesh with UnknownSectorSize: ", lod_skeletal_unk_sector_count)
	
	# Read geometry batch header
	var lod_vertex_count = file.get_32()
	var lod_node_binding = file.get_32()
	lod.node_binding = lod_node_binding
	
	print("Geometry batch: ", lod_vertex_count, " vertices, ", lod_node_binding, " target node index/bone count")
	
	# Process batch data
	var finished_lods = false
	var check_for_more_data = false
	
	while not finished_lods:
		if check_for_more_data:
			# Check for more batches (simplified)
			var peek_pos = file.get_position()
			file.seek(file.get_position() + 28)  # BatchConnector size
			
			# Try to read VIF command
			var vif_constant = file.get_16()
			var vif_variable = file.get_8()
			var vif_code = file.get_8()
			
			file.seek(peek_pos)
			
			if vif_constant != VIF_DIRECT or vif_code != VIF_UNPACK:
				print("No more data found!")
				finished_lods = true
				break
			
			print("Found additional batch!")
			check_for_more_data = false
		
		# Read batch connector
		_read_vif_command(file)  # unknown_command
		file.seek(file.get_position() + 4)  # skip unknown
		_read_vif_command(file)  # flush_command
		file.seek(file.get_position() + 4 * 4)  # skip unknowns
		_read_vif_command(file)  # unpack_command
		
		var mesh_set_count = file.get_32()
		var mesh_data_count = file.get_32()
		file.seek(file.get_position() + 4 * 2)  # skip zeros
		
		var size_start = file.get_position()
		var running_mesh_set_count = 0
		
		# Process mesh sets
		while true:
			var data_count = file.get_8()
			var unknown_flag = file.get_8()
			file.seek(file.get_position() + 2)  # padding
			
			# Read render patch details
			var unknown_val_1 = file.get_32()
			var face_winding_order = file.get_32()
			var unknown_val_2 = file.get_32()
			
			# Process vertices in this mesh set
			for i in range(data_count):
				# Check for 1.0f padding marker
				file.seek(file.get_position() + 4 * 3)
				var constant_one = file.get_float()
				
				if constant_one == 1.0:
					file.seek(file.get_position() - 4 * 4)
				
				# Read vertex data
				var vertex = Vertex.new()
				vertex.sublod_vertex_index = 0xCDCD
				
				var vertex_data = read_vector3(file)
				var vertex_padding = file.get_float()
				var normal_data = read_vector3(file)
				var normal_padding = file.get_float()
				
				var uv_data = Vector2()
				uv_data.x = file.get_float()
				uv_data.y = file.get_float()
				
				var vertex_index_float = file.get_float()
				var unknown_padding = file.get_float()
				
				# Create face vertex
				var face_vertex = FaceVertex.new()
				face_vertex.texcoord = uv_data
				face_vertex.vertex_index = mesh_index
				face_vertex.reversed = (face_winding_order == WO_REVERSED)
				
				# Set vertex attributes
				vertex.location = vertex_data
				vertex.normal = normal_data
				
				# Add to vertex list
				vertex_list.append_vertex(vertex, mesh_set_index, face_vertex)
				mesh_index += 1
			
			mesh_set_index += 1
			running_mesh_set_count += 1
			
			if unknown_flag == 128:
				print("Found last mesh set (flag 128)")
				break
		
		# Skip to end command
		var end_command_peek = []
		for i in range(4):
			end_command_peek.append(file.get_32())
		
		if end_command_peek[0] == 0 and end_command_peek[1] == 0 and end_command_peek[2] == 0 and end_command_peek[3] == VIF_MSCALF:
			print("Found End Command")
			file.seek(file.get_position() - 4 * 4)
		else:
			print("Skipping extra data before end command")
		
		# Read end command (skip 12 bytes, read int)
		file.seek(file.get_position() + 12)
		var end_code = file.get_32()
		
		var size_end = file.get_position()
		var batch_size = size_end - size_start
		print("Batch size: ", batch_size, " bytes")
		
		# Check for more batches
		var peek_pos = file.get_position()
		file.seek(file.get_position() + 28)  # BatchConnector size
		
		var vif_constant = file.get_16()
		var vif_variable = file.get_8()
		var vif_code = file.get_8()
		
		file.seek(peek_pos)
		
		if vif_constant == VIF_DIRECT and vif_code == VIF_UNPACK:
			print("Found another batch")
			check_for_more_data = true
		else:
			print("No more batches found")
			finished_lods = true
	
	# Finalize LOD data
	lod.vertices = vertex_list.get_vertex_list()
	vertex_list.generate_faces()
	lod.faces = vertex_list.get_face_list()
	
	# Handle skeletal mesh weights if needed
	if mesh_type == MT_SKELETAL:
		_process_skeletal_weights(file, lod, lod_vertex_count, lod_node_binding, lod_skeletal_unk_sector_count)
	
	print("LOD ", lod_index, " Final vertices: ", lod.vertices.size())
	print("LOD ", lod_index, " Final faces: ", lod.faces.size())
	
	return lod

func _process_skeletal_weights(file: File, lod: LOD, vertex_count: int, node_binding: int, unk_sector_count: int):
	# Process unknown sector (simplified)
	var unk_sector_start = file.get_position()
	
	# Skip unknown sector data
	while true:
		var unk_amount_to_skip = file.get_16()
		file.seek(file.get_position() + unk_amount_to_skip * 2)
		
		var current_total = (file.get_position() - unk_sector_start) / 2
		if current_total >= unk_sector_count:
			# Look for 1.0f marker
			while true:
				var test_values = []
				for i in range(4):
					test_values.append(file.get_float())
				
				if test_values[3] == 1.0:
					file.seek(file.get_position() - 16)
					break
				
				file.seek(file.get_position() - 14)
			break
	
	# Read ordered vertices
	var ordered_vertices = []
	print("Reading ", vertex_count, " ordered vertices")
	
	for i in range(vertex_count):
		var ordered_vertex = OrderedVertex.new()
		ordered_vertex.location = read_vector3(file)
		ordered_vertex.location_padding = file.get_float()
		ordered_vertex.normal = read_vector3(file)
		ordered_vertex.normal_padding = file.get_float()
		ordered_vertices.append(ordered_vertex)
	
	# Read node map
	var node_map = []
	print("Reading ", node_binding, " node map entries")
	
	for i in range(node_binding):
		node_map.append(file.get_32())
	
	print("Node map: ", node_map)
	
	# Read and process vertex weights
	for i in range(vertex_count):
		var weights = []
		for j in range(4):
			weights.append(file.get_16())
		
		var node_indices = []
		for j in range(4):
			node_indices.append(file.get_8())
		
		var normalized_weights = []
		for weight in weights:
			if weight != 0:
				normalized_weights.append(float(weight) / 4096.0)
		
		var processed_weights = []
		for j in range(normalized_weights.size()):
			var weight = Weight.new()
			weight.bias = normalized_weights[j]
			weight.node_index = node_indices[j]
			
			if weight.node_index != 0:
				weight.node_index = int(weight.node_index / 4)
			
			weight.node_index = node_map[weight.node_index]
			processed_weights.append(weight)
		
		# Match weights to vertices by position
		var ordered_vertex = ordered_vertices[i]
		
		for vi in range(lod.vertices.size()):
			var vertex = lod.vertices[vi]
			
			if ordered_vertex.location.is_equal_approx(vertex.location):
				lod.vertices[vi].weights = processed_weights.duplicate()
				for weight in lod.vertices[vi].weights:
					weight.location = ordered_vertex.location
				break

func _read_node(file: File) -> LTNode:
	var node = LTNode.new()
	node.name = read_string(file)
	node.bind_matrix = read_matrix(file)
	file.seek(file.get_position() + 4)  # skip unknown
	node.child_count = file.get_32()
	node.index = file.get_16()
	file.seek(file.get_position() + 2)  # skip padding
	return node

func _read_vif_command(file: File) -> VIFCommand:
	var cmd = VIFCommand.new()
	cmd.constant = file.get_16()
	cmd.variable = file.get_8()
	cmd.code = file.get_8()
	return cmd

func _build_node_tree():
	# Simplified node tree building
	for i in range(nodes.size()):
		var node = nodes[i]
		# Link children based on hierarchy (simplified)
		# This would need more complex logic for proper parent-child relationships

func _read_weight_sets(file: File):
	# Simplified weight set reading
	pass

func _read_child_models(file: File, offset: int, count: int):
	if offset <= 0 or count <= 0:
		return
	
	file.seek(offset)
	var child_count = file.get_32()
	
	if child_count > 0:
		var actual_count = child_count - 1  # Character models subtract 1
		for i in range(actual_count):
			var child_model = ChildModel.new()
			child_model.name = read_string(file)
			child_models.append(child_model)

func _read_animations(file: File, offset: int, count: int, hash_magic: int):
	if offset <= 0 or count <= 0:
		return
	
	file.seek(offset)
	var local_count = file.get_32()
	
	for i in range(min(local_count, count)):
		var animation = LTAnimation.new()
		animation.name = "Animation_" + str(_animations_processed)
		animation.extents = read_vector3(file)
		
		var unknown_vector = read_vector3(file)
		var hashed_string = file.get_32()
		animation.interpolation_time = file.get_32()
		animation.keyframe_count = file.get_32()
		
		# Read keyframes (simplified)
		for j in range(animation.keyframe_count):
			var keyframe = LTKeyframe.new()
			keyframe.time = file.get_32()
			keyframe.command_string = read_string(file)
			animation.keyframes.append(keyframe)
		
		# Skip node keyframe transforms for now
		for k in range(node_count):
			var start_marker = file.get_32()
			for l in range(animation.keyframe_count):
				_read_transform(file)
		
		animations.append(animation)
		_animations_processed += 1

func _read_sockets(file: File, offset: int, count: int, hash_magic: int):
	if offset <= 0 or count <= 0:
		return
	
	file.seek(offset)
	
	for i in range(count):
		var socket = Socket.new()
		file.seek(file.get_position() + 4)  # skip unknown
		socket.rotation = read_quaternion(file)
		socket.location = read_vector3(file)
		file.seek(file.get_position() + 4)  # skip unknown
		socket.node_index = file.get_32()
		var hashed_string = file.get_32()
		file.seek(file.get_position() + 4)  # skip unknown
		
		socket.name = "Socket" + str(_socket_counter)
		_socket_counter += 1
		
		sockets.append(socket)

func _read_transform(file: File) -> LTTransform:
	var transform = LTTransform.new()
	
	var location = []
	for i in range(3):
		location.append(file.get_16())
	var location_small_scale = file.get_16()
	
	var rotation = []
	for i in range(4):
		rotation.append(file.get_16())
	
	var SCALE_ROT = 0x4000
	var SCALE_LOC = 0x10
	
	if location_small_scale == 0:
		SCALE_LOC = 0x1000
	
	transform.location.x = float(location[0]) / SCALE_LOC
	transform.location.y = float(location[1]) / SCALE_LOC
	transform.location.z = float(location[2]) / SCALE_LOC
	
	transform.rotation.x = float(rotation[0]) / SCALE_ROT
	transform.rotation.y = float(rotation[1]) / SCALE_ROT
	transform.rotation.z = float(rotation[2]) / SCALE_ROT
	transform.rotation.w = float(rotation[3]) / SCALE_ROT
	
	return transform

# Helper functions
func read_string(file: File) -> String:
	var length = file.get_16()
	return file.get_buffer(length).get_string_from_ascii()

func read_vector2(file: File) -> Vector2:
	return Vector2(file.get_float(), file.get_float())

func read_vector3(file: File) -> Vector3:
	return Vector3(file.get_float(), file.get_float(), file.get_float())

func read_quaternion(file: File) -> Quat:
	var x = file.get_float()
	var y = file.get_float()
	var z = file.get_float()
	var w = file.get_float()
	return Quat(x, y, z, w)

func read_matrix(file: File) -> Transform:
	var matrix_data = []
	for i in range(16):
		matrix_data.append(file.get_float())
	
	return Transform(
		Vector3(matrix_data[0], matrix_data[4], matrix_data[8]),
		Vector3(matrix_data[1], matrix_data[5], matrix_data[9]),
		Vector3(matrix_data[2], matrix_data[6], matrix_data[10]),
		Vector3(matrix_data[3], matrix_data[7], matrix_data[11])
	)

func _make_response(code, message = ''):
	return { 'code': code, 'message': message }

# Internal Classes
class VIFCommand:
	var constant = 0
	var variable = 0
	var code = 0

class LocalVertex:
	var id = 0
	var merge_string = ""
	var vertex = null
	var associated_ids = []

class LocalFace:
	var group_id = 0
	var face_vertex = null

class VertexList:
	var auto_increment = 0
	var groups = []
	var list = []
	var face_verts = []
	var faces = []
	
	func append_vertex(vertex, group_id, face_vertex):
		var local_vertex = LocalVertex.new()
		local_vertex.id = auto_increment
		local_vertex.vertex = vertex
		local_vertex.merge_string = generate_merge_string(vertex.location)
		local_vertex.associated_ids.append(group_id)
		
		var local_face = LocalFace.new()
		local_face.group_id = group_id
		
		var vertex_index = find_in_list(local_vertex.merge_string)
		
		if vertex_index == -1:
			list.append(local_vertex)
			vertex_index = auto_increment
			auto_increment += 1
		else:
			list[vertex_index].associated_ids.append(group_id)
		
		face_vertex.vertex_index = vertex_index
		local_face.face_vertex = face_vertex
		
		if not groups.has(group_id):
			groups.append(group_id)
		
		face_verts.append(local_face)
	
	func generate_faces():
		faces.clear()
		
		for group_id in groups:
			var flip = false
			var grouped_faces = []
			
			for face_vert in face_verts:
				if face_vert.group_id == group_id:
					grouped_faces.append(face_vert)
			
			for i in range(2, grouped_faces.size()):
				var face = Face.new()
				
				if grouped_faces[i].face_vertex.reversed:
					if flip:
						face.vertices = [grouped_faces[i-1].face_vertex, grouped_faces[i].face_vertex, grouped_faces[i-2].face_vertex]
					else:
						face.vertices = [grouped_faces[i-2].face_vertex, grouped_faces[i].face_vertex, grouped_faces[i-1].face_vertex]
				else:
					if flip:
						face.vertices = [grouped_faces[i].face_vertex, grouped_faces[i-1].face_vertex, grouped_faces[i-2].face_vertex]
					else:
						face.vertices = [grouped_faces[i].face_vertex, grouped_faces[i-2].face_vertex, grouped_faces[i-1].face_vertex]
				
				faces.append(face)
				flip = not flip
	
	func find_in_list(merge_string: String) -> int:
		for i in range(list.size()):
			if merge_string == list[i].merge_string:
				return i
		return -1
	
	func generate_merge_string(vector: Vector3) -> String:
		return str(vector.x) + "/" + str(vector.y) + "/" + str(vector.z)
	
	func get_vertex_list() -> Array:
		var out_list = []
		for local_vertex in list:
			out_list.append(local_vertex.vertex)
		return out_list
	
	func get_face_list() -> Array:
		return faces

class Piece:
	var name = ""
	var material_index = 0
	var specular_power = 0.0
	var specular_scale = 0.0
	var lod_weight = 0.0
	var mesh_type = 0
	var lods = []
	var primary_lod = null  # LOD 0

class LOD:
	var mesh_type = 0
	var node_binding = 0
	var vertices = []
	var faces = []

class Face:
	var vertices = []  # Array of FaceVertex

class FaceVertex:
	var texcoord = Vector2()
	var vertex_index = 0
	var reversed = false

class Vertex:
	var sublod_vertex_index = 0xCDCD
	var weights = []
	var location = Vector3()
	var normal = Vector3()

class Weight:
	var node_index = 0
	var location = Vector3()
	var bias = 0.0

class LTNode:
	var name = ""
	var index = 0
	var bind_matrix = Transform()
	var child_count = 0
	var parent = null
	var children = []

class OrderedVertex:
	var location = Vector3()
	var location_padding = 0.0
	var normal = Vector3()
	var normal_padding = 1.0

class LTTransform:
	var location = Vector3()
	var rotation = Quat()

class ChildModel:
	var name = ""

class LTAnimation:
	var name = ""
	var extents = Vector3()
	var interpolation_time = 0
	var keyframe_count = 0
	var keyframes = []

class LTKeyframe:
	var time = 0
	var command_string = ""

class Socket:
	var name = ""
	var location = Vector3()
	var rotation = Quat()
	var node_index = 0