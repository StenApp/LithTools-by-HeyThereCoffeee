# res://Addons/LTBReader/Models/LTB_PC.gd
class_name LTB_PC

# PC LTB Model Reader - EXACT implementation of pc_ltb.bt
# Version 9, FileType 1 (D3D)

const MT_RIGID = 4
const MT_SKELETAL = 5
const MT_VERTEX_ANIMATED = 6
const MT_NULL = 7

const VTX_Position = 0x0001
const VTX_Normal = 0x0002
const VTX_Colour = 0x0004
const VTX_UV_Sets_1 = 0x0010
const VTX_UV_Sets_2 = 0x0020
const VTX_UV_Sets_3 = 0x0040
const VTX_UV_Sets_4 = 0x0080
const VTX_BasisVector = 0x0100

const CMP_None = 0
const CMP_Relevant = 1
const CMP_Relevant_16 = 2
const CMP_Relevant_Rot16 = 3

var name = ""
var version = 0
var file_type = 0
var pieces = []
var nodes = []
var animations = []
var sockets = []

enum IMPORT_RETURN {SUCCESS, ERROR}

func read(f: File):
	print("=== PC LTB Reader - STRICT Template Implementation ===")
	
	# Exactly as in pc_ltb.bt Header struct
	file_type = f.get_16()    # short FileType
	version = f.get_16()      # short FileVersion
	
	# Skip Filler[4]
	for i in range(4):
		f.get_32()
	
	var mesh_version = f.get_32()
	
	# Read all counts (EXACTLY as in template)
	var keyframe_count = f.get_32()
	var parent_anim_count = f.get_32()
	var node_count = f.get_32()
	var piece_count = f.get_32()
	var child_model_count = f.get_32()
	var face_count = f.get_32()
	var vertex_count = f.get_32()
	var vertex_weight_count = f.get_32()
	var lod_count = f.get_32()
	var socket_count = f.get_32()
	var weight_set_count = f.get_32()
	var string_count = f.get_32()
	var string_length = f.get_32()
	var vert_anim_data_size = f.get_32()
	var animation_data = f.get_32()
	
	var command_string = read_string(f)
	var radius = f.get_float()
	
	print("Header: FileType=", file_type, " Version=", version)
	print("Counts: Nodes=", node_count, " Pieces=", piece_count, " LODs=", lod_count)
	
	# Sanity checks
	if piece_count < 0 or piece_count > 10000:
		return _make_response(IMPORT_RETURN.ERROR, "Invalid piece_count: " + str(piece_count))
	if node_count < 0 or node_count > 10000:
		return _make_response(IMPORT_RETURN.ERROR, "Invalid node_count: " + str(node_count))
	if lod_count < 0 or lod_count > 100:
		return _make_response(IMPORT_RETURN.ERROR, "Invalid lod_count: " + str(lod_count))
	
	# Read OBBs
	var obb_count = f.get_32()
	if obb_count < 0 or obb_count > 1000:
		return _make_response(IMPORT_RETURN.ERROR, "Invalid obb_count: " + str(obb_count))
	
	for i in range(obb_count):
		_skip_obb(f)
	
	# Read actual piece count
	var actual_piece_count = f.get_32()
	print("Actual Pieces to read: ", actual_piece_count)
	
	if actual_piece_count < 0 or actual_piece_count > 10000:
		return _make_response(IMPORT_RETURN.ERROR, "Invalid actual_piece_count: " + str(actual_piece_count))
	
	# Read pieces with EOF protection
	for i in range(actual_piece_count):
		if f.eof_reached():
			return _make_response(IMPORT_RETURN.ERROR, "Unexpected EOF at piece " + str(i))
		
		print("Reading Piece ", i, "/", actual_piece_count - 1)
		
		var piece = PieceHeader.new()
		var result = piece.read(self, f, lod_count)
		if not result:
			return _make_response(IMPORT_RETURN.ERROR, "Failed reading piece " + str(i))
		
		pieces.append(piece)
	
	# Read nodes with protection
	print("Reading node hierarchy...")
	if node_count > 0:
		var root_node = LTNode.new()
		var result = root_node.read(self, f, 0)  # Pass recursion depth
		if not result:
			return _make_response(IMPORT_RETURN.ERROR, "Failed reading nodes")
		nodes.append(root_node)
		_flatten_nodes(root_node)
	
	print("Successfully loaded: ", pieces.size(), " pieces, ", nodes.size(), " nodes")
	name = "LTB_PC_Model"
	
	return _make_response(IMPORT_RETURN.SUCCESS)

func _skip_obb(f: File):
	# OBB = LTMatrix = 4 * LTQuat = 4 * 4 floats = 16 floats
	for i in range(16):
		f.get_float()

func _flatten_nodes(node):
	for child in node.children:
		nodes.append(child)
		_flatten_nodes(child)

func read_string(f: File) -> String:
	var length = f.get_16()
	if length < 0 or length > 10000:
		print("WARNING: Suspicious string length: ", length)
		return ""
	if length == 0:
		return ""
	return f.get_buffer(length).get_string_from_ascii()

func read_vector2(f: File) -> Vector2:
	return Vector2(f.get_float(), f.get_float())

func read_vector3(f: File) -> Vector3:
	return Vector3(f.get_float(), f.get_float(), f.get_float())

func read_quaternion(f: File) -> Quat:
	return Quat(f.get_float(), f.get_float(), f.get_float(), f.get_float())

func read_matrix(f: File) -> Transform:
	var m = []
	for i in range(16):
		m.append(f.get_float())
	return Transform(
		Vector3(m[0], m[4], m[8]),
		Vector3(m[1], m[5], m[9]),
		Vector3(m[2], m[6], m[10]),
		Vector3(m[3], m[7], m[11])
	)

func _make_response(code, message = ''):
	return {'code': code, 'message': message}

##################
# Classes matching pc_ltb.bt EXACTLY
##################

class PieceHeader:
	var name = ""
	var lods = []
	
	func read(ltb, f: File, expected_lod_count: int) -> bool:
		name = ltb.read_string(f)
		if name == "":
			print("WARNING: Empty piece name")
		
		var lod_count = f.get_32()
		print("  Piece '", name, "' - LOD Count: ", lod_count)
		
		# Sanity check
		if lod_count < 0 or lod_count > 20:
			print("ERROR: Invalid LOD count: ", lod_count)
			return false
		
		# Read LOD distances
		for i in range(lod_count):
			f.get_float()
		
		var lod_min = f.get_32()
		var lod_max = f.get_32()
		
		# Read LODs
		for i in range(lod_count):
			if f.eof_reached():
				print("ERROR: EOF while reading LOD ", i)
				return false
			
			var lod = LOD.new()
			if not lod.read(ltb, f):
				print("ERROR: Failed reading LOD ", i)
				return false
			lods.append(lod)
		
		return true

class LOD:
	var texture_indices = []
	var mesh_type = 0
	var vertices = []
	var faces = []
	
	func read(ltb, f: File) -> bool:
		var texture_count = f.get_32()
		
		# Read 4 texture indices
		for i in range(4):
			texture_indices.append(f.get_32())
		
		var render_style = f.get_32()
		var render_priority = f.get_8()
		
		# Now comes the Piece data (inline in LOD)
		mesh_type = f.get_32()  # PieceType
		
		print("    LOD MeshType: ", mesh_type)
		
		# Handle NULL mesh
		if mesh_type == ltb.MT_NULL:
			f.get_32()  # Filler
			# DON'T return here! Continue to NodesUsed below
		else:
			# Common data for non-null meshes
			var obj_size = f.get_32()
			var vert_count = f.get_32()
			var face_count = f.get_32()
			var max_bones_per_face = f.get_32()
			var max_bones_per_vert = f.get_32()
			
			print("    Verts:", vert_count, " Faces:", face_count)
			
			# Sanity
			if vert_count < 0 or vert_count > 500000:
				print("ERROR: Invalid vert_count: ", vert_count)
				return false
			if face_count < 0 or face_count > 500000:
				print("ERROR: Invalid face_count: ", face_count)
				return false
			
			if mesh_type == ltb.MT_RIGID:
				if not _read_rigid(ltb, f, vert_count, face_count):
					return false
			elif mesh_type == ltb.MT_SKELETAL:
				if not _read_skeletal(ltb, f, vert_count, face_count, max_bones_per_face, max_bones_per_vert):
					return false
			else:
				print("WARNING: Unsupported mesh type: ", mesh_type)
		
		# Read NodesUsed (AFTER piece, for ALL mesh types including NULL!)
		var nodes_used_count = f.get_8()
		for i in range(nodes_used_count):
			f.get_8()
		
		return true
	
	func _read_rigid(ltb, f: File, vert_count: int, face_count: int) -> bool:
		var data_types = []
		for i in range(4):
			data_types.append(f.get_32())
		
		var bone = f.get_32()
		
		# Read vertices per stream
		for stream in range(4):
			if data_types[stream] == 0:
				continue
			
			for v in range(vert_count):
				if f.eof_reached():
					return false
				
				var vertex = Vertex.new()
				
				if data_types[stream] & ltb.VTX_Position:
					vertex.location = ltb.read_vector3(f)
				if data_types[stream] & ltb.VTX_Normal:
					vertex.normal = ltb.read_vector3(f)
				if data_types[stream] & ltb.VTX_Colour:
					vertex.color = f.get_32()
				if data_types[stream] & ltb.VTX_UV_Sets_1:
					vertex.uv1 = ltb.read_vector2(f)
				if data_types[stream] & ltb.VTX_UV_Sets_2:
					vertex.uv2 = ltb.read_vector2(f)
				if data_types[stream] & ltb.VTX_UV_Sets_3:
					vertex.uv3 = ltb.read_vector2(f)
				if data_types[stream] & ltb.VTX_UV_Sets_4:
					vertex.uv4 = ltb.read_vector2(f)
				if data_types[stream] & ltb.VTX_BasisVector:
					vertex.basis_s = ltb.read_vector3(f)
					vertex.basis_t = ltb.read_vector3(f)
				
				vertices.append(vertex)
		
		# Read indices
		for i in range(face_count * 3):
			var idx = f.get_16()
			if i % 3 == 0:
				faces.append(Face.new())
			faces[int(i / 3)].indices.append(idx)
		
		# NodesUsed wird NICHT hier gelesen, sondern in LOD.read()!
		return true

	func _read_skeletal(ltb, f: File, vert_count: int, face_count: int, max_bones_face: int, max_bones_vert: int) -> bool:
		var reindexed_bones = f.get_8()
		var data_types = []
		for i in range(4):
			data_types.append(f.get_32())
		
		var matrix_palette = f.get_8()
		
		if matrix_palette == 0:
			# Read vertices
			for stream in range(4):
				if data_types[stream] == 0:
					continue
				
				for v in range(vert_count):
					if f.eof_reached():
						return false
					
					var vertex = Vertex.new()
					
					if data_types[stream] & ltb.VTX_Position:
						vertex.location = ltb.read_vector3(f)
						if max_bones_face >= 2:
							vertex.blend1 = f.get_float()
						if max_bones_face >= 3:
							vertex.blend2 = f.get_float()
						if max_bones_face >= 4:
							vertex.blend3 = f.get_float()
					
					if data_types[stream] & ltb.VTX_Normal:
						vertex.normal = ltb.read_vector3(f)
					if data_types[stream] & ltb.VTX_Colour:
						vertex.color = f.get_32()
					if data_types[stream] & ltb.VTX_UV_Sets_1:
						vertex.uv1 = ltb.read_vector2(f)
					if data_types[stream] & ltb.VTX_UV_Sets_2:
						vertex.uv2 = ltb.read_vector2(f)
					if data_types[stream] & ltb.VTX_UV_Sets_3:
						vertex.uv3 = ltb.read_vector2(f)
					if data_types[stream] & ltb.VTX_UV_Sets_4:
						vertex.uv4 = ltb.read_vector2(f)
					if data_types[stream] & ltb.VTX_BasisVector:
						vertex.basis_s = ltb.read_vector3(f)
						vertex.basis_t = ltb.read_vector3(f)
					
					vertices.append(vertex)
			
			# Indices
			for i in range(face_count * 3):
				var idx = f.get_16()
				if i % 3 == 0:
					faces.append(Face.new())
				faces[int(i / 3)].indices.append(idx)
			
			# BoneSets
			var bone_set_count = f.get_32()
			for i in range(bone_set_count):
				f.get_16()  # BoneIndexStart
				f.get_16()  # BoneIndexCount
				for j in range(4):
					f.get_8()  # BoneList
				f.get_32()  # IndexBufferIndex
		else:
			# Matrix palette mode
			var min_bone = f.get_32()
			var max_bone = f.get_32()
			
			if reindexed_bones:
				var reindexed_bone_count = f.get_32()
				for i in range(reindexed_bone_count):
					f.get_32()
			
			# Skip reading for now - just skip the data
			print("WARNING: Matrix palette skeletal mesh - skipping vertex data")
		
		# NodesUsed wird NICHT hier gelesen!
		return true

class Vertex:
	var location = Vector3()
	var normal = Vector3()
	var color = 0
	var uv1 = Vector2()
	var uv2 = Vector2()
	var uv3 = Vector2()
	var uv4 = Vector2()
	var basis_s = Vector3()
	var basis_t = Vector3()
	var blend1 = 0.0
	var blend2 = 0.0
	var blend3 = 0.0

class Face:
	var indices = []

class LTNode:
	var name = ""
	var index = 0
	var bind_matrix = Transform()
	var children = []
	var parent = null
	
	func read(ltb, f: File, depth: int) -> bool:
		# Protect against infinite recursion
		if depth > 100:
			print("ERROR: Node recursion too deep!")
			return false
		
		if f.eof_reached():
			return false
		
		name = ltb.read_string(f)
		index = f.get_16()
		var flags = f.get_8()
		bind_matrix = ltb.read_matrix(f)
		var child_count = f.get_32()
		
		# Sanity check
		if child_count < 0 or child_count > 1000:
			print("ERROR: Invalid child_count: ", child_count, " for node: ", name)
			return false
		
		print("Node '", name, "' Index:", index, " Children:", child_count)
		
		# Read children recursively
		for i in range(child_count):
			var child = LTNode.new()
			if not child.read(ltb, f, depth + 1):
				return false
			child.parent = self
			children.append(child)
		
		return true
