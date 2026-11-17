# res://Addons/LTBReader/Models/LTB_PC.gd
class_name LTB_PC

const BinPrim = preload("res://Addons/LTDatReader/BinaryReadPrimitives.gd")

# PC LTB Model Reader - Implementierung von pc_ltb.bt / LTB_PC_Model18_25.bt
# Raw: FileType 1 (D3D), Container 9, MeshVersion 18, 20..25 (v19 ohne Sample; v24 nur aus dem Source).
# Es werden nur Pieces und Nodes gelesen (Viewer ohne Animation). Versionsgrenzen (an ~1800 Dateien belegt):
#   AnimationData im Header ab v23, RenderPriority im LOD ab v20, NodesUsed im LOD ab v22,
#   OBB-Groesse 44 (v18) / 64 (v23) / 68 (v24+).
# Mit read_wrapped() werden auch die LTB-wrap-Bodies 14..17 (Wrapper, FileType 1) gelesen: gleiche Pieces und Nodes.

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
var mesh_version = 0  # raw: MeshVersion (18..25), wrapped: Body-Version (14..17)
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
	
	mesh_version = f.get_32()
	if mesh_version == 19:
		return _make_response(IMPORT_RETURN.ERROR, "MeshVersion 19: kein Sample, Layout unbekannt")
	if mesh_version < 18 or mesh_version > 25:
		return _make_response(IMPORT_RETURN.ERROR, "Nicht unterstuetzte MeshVersion " + str(mesh_version) + " (unterstuetzt: 18, 20..25)")
	
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
	var animation_data = 0
	if mesh_version >= 23:
		animation_data = f.get_32()  # Header-Feld erst ab v23
	
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
	#
	# BESTAETIGT (2026-09, Sten/Claude, gegen reader_ltb_pc.py, byte-exakt
	# an PLAYER_ACTION.LTB/PLAYERBASE.LTB/DEATHBASE.LTB/HERO_ACTION.LTB
	# verifiziert): Nodes stehen im File als FLACHE Liste von genau
	# node_count Eintraegen -- die Baumstruktur (wer ist wessen Kind) ist
	# NICHT im Byte-Layout kodiert, sondern wird erst nachtraeglich aus der
	# Reihenfolge + ChildCount rekonstruiert (Tiefensuche ueber die flache
	# Liste, wie ABC.gd's LTNode.link_children es schon richtig macht).
	# Vorher wurde hier ein SELBST-REKURSIVES Node-Struct gelesen (ein
	# Aufruf "root_node.read(...)", das reihum "child_count" weitere Nodes
	# direkt aus dem File nachliest) -- funktioniert nur, wenn die Datei
	# genau EINEN Wurzelknoten hat, dessen Kinder-Baum die GESAMTE Liste
	# deckt; bei mehreren Wurzelknoten oder einer abweichenden Tiefe wuerde
	# das zu wenige/zu viele Bytes konsumieren und alles Folgende (Weight-
	# Sets, ChildModels, Animationen, ...) verschieben. Gleiche Ursache,
	# die vermutlich fuer den "Template passed end of file"-Fehler im
	# pc_ltb.bt-Template verantwortlich war -- dort aus demselben Grund auf
	# ein flaches Array umgestellt.
	print("Reading node hierarchy...")
	if node_count > 0:
		for i in range(node_count):
			if f.eof_reached():
				return _make_response(IMPORT_RETURN.ERROR, "Unexpected EOF at node " + str(i))
			var node = LTNode.new()
			if not node.read(self, f):
				return _make_response(IMPORT_RETURN.ERROR, "Failed reading node " + str(i))
			nodes.append(node)
		# End For
		LTNode.link_children(nodes, 0, null)
	
	print("Successfully loaded: ", pieces.size(), " pieces, ", nodes.size(), " nodes")
	name = "LTB_PC_Model"
	
	return _make_response(IMPORT_RETURN.SUCCESS)

# Liest ein LTB-wrap-Modell mit Body-Version 14..17 (FileType 1, Container 3 oder 9; "LTBHeader"-Wrapper, 7 Sections).
# Pieces und Nodes sind identisch zu raw v18 (ohne RenderPriority und NodesUsed). Body 13 (D3D) liest LTB_Wrap_D3D.gd,
# Container 8 (Body-13-Hybrid mit PC-Pieces, nur EXITONLYSIGN) wird nicht unterstuetzt.
func read_wrapped(f: File):
	print("=== LTB wrap Body 14-17 Reader ===")
	f.seek(0)
	var text_len = f.get_16()
	f.seek(2 + text_len)
	var first_section = f.get_32()
	file_type = f.get_16() & 0xFF
	version = f.get_16()  # Container-Version
	for i in range(4):
		f.get_32()

	# Section-Tabelle: Name -> Beginn des Section-Inhalts (hinter Name und NextSection)
	var sections = {}
	var next_offset = first_section
	var guard = 0
	while next_offset != 0xFFFFFFFF and guard < 16:
		guard += 1
		f.seek(next_offset)
		var name_len = f.get_16()
		var section_name = f.get_buffer(name_len).get_string_from_ascii()
		var next_section = f.get_32()
		sections[section_name] = f.get_position()
		if next_section != 0xFFFFFFFF and next_section <= next_offset:
			break
		next_offset = next_section
	for required in ["Header", "Pieces", "Nodes"]:
		if not sections.has(required):
			return _make_response(IMPORT_RETURN.ERROR, "Section fehlt oder Kette abgeschnitten: " + required)

	# Header-Body: Version, 11 Zaehler, Unknown, StringCount, StringLength, CommandString, Radius, OBBCount, OBBs (44 Byte)
	f.seek(sections["Header"])
	mesh_version = f.get_32()
	if mesh_version < 14 or mesh_version > 17:
		return _make_response(IMPORT_RETURN.ERROR, "Body-Version " + str(mesh_version) + " nicht unterstuetzt (14..17; Body 13 liest LTB_Wrap_D3D.gd)")
	var counts = []
	for i in range(11):
		counts.append(f.get_32())  # KeyFrames, Anims, Nodes, Pieces, ChildModels, Faces, Verts, VertWeights, LODs, Sockets, WeightSets
	var node_count = counts[2]
	var lod_count = counts[8]
	f.get_32()  # Unknown
	f.get_32()  # StringCount
	f.get_32()  # StringLength
	var command_string = read_string(f)
	var radius = f.get_float()
	var obb_count = f.get_32()
	if node_count < 0 or node_count > 10000 or counts[3] < 0 or counts[3] > 10000 or lod_count < 0 or lod_count > 100 or obb_count < 0 or obb_count > 1000:
		return _make_response(IMPORT_RETURN.ERROR, "Unplausible Zaehler im Header")
	print("Body v", mesh_version, " Container=", version, " Nodes=", node_count, " Pieces=", counts[3], " LODs=", lod_count)

	# Pieces
	f.seek(sections["Pieces"])
	var piece_count = f.get_32()
	if piece_count < 0 or piece_count > 10000:
		return _make_response(IMPORT_RETURN.ERROR, "Invalid piece_count: " + str(piece_count))
	for i in range(piece_count):
		if f.eof_reached():
			return _make_response(IMPORT_RETURN.ERROR, "Unexpected EOF at piece " + str(i))
		var piece = PieceHeader.new()
		if not piece.read(self, f, lod_count):
			return _make_response(IMPORT_RETURN.ERROR, "Failed reading piece " + str(i))
		pieces.append(piece)

	# Nodes (flache Liste, Baum aus Reihenfolge + ChildCount)
	f.seek(sections["Nodes"])
	if node_count > 0:
		for i in range(node_count):
			if f.eof_reached():
				return _make_response(IMPORT_RETURN.ERROR, "Unexpected EOF at node " + str(i))
			var node = LTNode.new()
			if not node.read(self, f):
				return _make_response(IMPORT_RETURN.ERROR, "Failed reading node " + str(i))
			nodes.append(node)
		LTNode.link_children(nodes, 0, null)

	name = "LTB_Wrap_PC_Model"
	return _make_response(IMPORT_RETURN.SUCCESS)

func _skip_obb(f: File):
	# OBB-Groesse je Version: v18 44 Byte (Position, Dims, Quaternion, NodeIndex; v19-22 Vermutung), v23 64 Byte
	# (Position, Size, Basis[3], NodeIndex), v24+ 68 Byte (+Radius). Nur v18 ist an Dateien belegt, v23/v24+ aus dem Source.
	var size = 44
	if mesh_version >= 24:
		size = 68
	elif mesh_version >= 23:
		size = 64
	f.seek(f.get_position() + size)

func read_string(f: File) -> String:
	var length = f.get_16()
	if length < 0 or length > 10000:
		print("WARNING: Suspicious string length: ", length)
		return ""
	if length == 0:
		return ""
	return f.get_buffer(length).get_string_from_ascii()

func read_vector2(f: File) -> Vector2:
	return BinPrim.read_vector2(f)

func read_vector3(f: File) -> Vector3:
	return BinPrim.read_vector3(f)

func read_quaternion(f: File) -> Quat:
	return BinPrim.read_quat(f)

func read_matrix(f: File) -> Transform:
	return BinPrim.read_matrix(f)

func _make_response(code, message = ''):
	return BinPrim.make_response(code, message)

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
			
			var lod = MeshLod.new()
			if not lod.read(ltb, f):
				print("ERROR: Failed reading LOD ", i)
				return false
			lods.append(lod)
		
		return true

class MeshLod:
	var texture_indices = []
	var mesh_type = 0
	var bone_index = -1  # Rigid: Node des Pieces; VertexAnimated: AnimNodeIdx (Node mit den Vertexlisten der Animation)
	var vertices = []
	var faces = []
	
	func read(ltb, f: File) -> bool:
		var texture_count = f.get_32()
		
		# Read 4 texture indices
		for i in range(4):
			texture_indices.append(f.get_32())
		
		var render_style = f.get_32()
		var render_priority = 0
		if ltb.mesh_version >= 20:
			render_priority = f.get_8()
		
		# Now comes the Piece data (inline in LOD)
		mesh_type = f.get_32()  # PieceType
		
		print("    LOD MeshType: ", mesh_type)
		
		# Handle NULL mesh
		if mesh_type == ltb.MT_NULL:
			f.get_32()  # Filler
			# DON'T return here! Continue to NodesUsed below
		else:
			# Common data for non-null meshes
			var obj_start = f.get_position()  # Position des ObjSize-Feldes: Piece-Ende = obj_start + 4 + obj_size
			var obj_size = f.get_32()
			var piece_end = obj_start + 4 + obj_size
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
			elif mesh_type == ltb.MT_VERTEX_ANIMATED:
				if not _read_vertex_animated(ltb, f, vert_count, max_bones_per_face):
					return false
			else:
				print("WARNING: Unsupported mesh type: ", mesh_type)

			# ObjSize ist verbindlich (Layout-Ende laut Datei): ueberspringt auch Reste, die wir nicht lesen
			# (VertexAnimated: DupMap; Skeletal mit Matrix-Palette bei MaxBonesPerVert <= 1; unbekannte Typen).
			f.seek(piece_end)
		
		# NodesUsed (AFTER piece, for ALL mesh types including NULL) -- erst ab v22
		if ltb.mesh_version >= 22:
			var nodes_used_count = f.get_8()
			for i in range(nodes_used_count):
				f.get_8()
		
		return true
	
	func _read_rigid(ltb, f: File, vert_count: int, face_count: int) -> bool:
		var data_types = []
		for i in range(4):
			data_types.append(f.get_32())
		
		var bone = f.get_32()
		bone_index = bone
		
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

	func _read_vertex_animated(ltb, f: File, vert_count: int, poly_count: int) -> bool:
		# Jupiter CD3DVAMesh::Load: die gemeinsamen Kopffelder heissen hier ObjSize, VertCount, UnDupVertCount (=FaceCount),
		# PolyCount (=MaxBonesPerFace), MaxBonesPerTri (=MaxBonesPerVert). Danach: uint32 MaxBonesPerVert, DataType[4],
		# AnimNodeIdx, BoneEffector, Vertices je Stream, uint16 Index[PolyCount*3], uint32 DupMapCount, DupMap[] (per seek uebersprungen).
		# Das Basismesh ist das Bild vor jeder Animation; die Vertexlisten je Keyframe liegen im Anim-Node AnimNodeIdx.
		f.get_32()  # MaxBonesPerVert
		var data_types = []
		for i in range(4):
			data_types.append(f.get_32())
		bone_index = f.get_32()  # AnimNodeIdx
		f.get_32()  # BoneEffector
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
		for i in range(poly_count * 3):
			var idx = f.get_16()
			if i % 3 == 0:
				faces.append(Face.new())
			faces[int(i / 3)].indices.append(idx)
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
			
			# Matrix-Palette-Modus (an Dateien belegt fuer MaxBonesPerVert 2..4): Position, (MaxBonesPerVert-1) Blend-Floats,
			# 4 x uint8 Bone-Index (liegen in MinBone..MaxBone), dann Normale, UVs ...; danach Indizes, keine BoneSets.
			if max_bones_vert < 2:
				# MaxBonesPerVert <= 1 mit Matrix-Palette kommt in keiner Datei vor (Layout unbekannt) -> per ObjSize uebersprungen
				print("WARNING: Matrix palette skeletal mesh with MaxBonesPerVert <= 1 - skipping vertex data")
				return true
			for stream in range(4):
				if data_types[stream] == 0:
					continue
				for v in range(vert_count):
					if f.eof_reached():
						return false
					var vertex = Vertex.new()
					if data_types[stream] & ltb.VTX_Position:
						vertex.location = ltb.read_vector3(f)
						vertex.blend1 = f.get_float()
						if max_bones_vert >= 3:
							vertex.blend2 = f.get_float()
						if max_bones_vert >= 4:
							vertex.blend3 = f.get_float()
						for j in range(4):
							vertex.bone_indices.append(f.get_8())
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
			for i in range(face_count * 3):
				var idx = f.get_16()
				if i % 3 == 0:
					faces.append(Face.new())
				faces[int(i / 3)].indices.append(idx)
		
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
	var bone_indices = []  # Matrix-Palette: 4 Bone-Indizes je Vertex

class Face:
	var indices = []

class LTNode:
	var name = ""
	var index = 0
	var child_count = 0
	var bind_matrix = Transform()
	var parent = null  # weakref(), um Referenzzyklus mit children zu vermeiden
	var children = []

	# Liest EINEN Node flach (kein Rekurs, keine Children im File-Layout --
	# siehe Kommentar am Aufrufer). Die Baumverknuepfung passiert danach
	# separat per link_children() ueber die komplette flache Liste.
	func read(ltb, f: File) -> bool:
		if f.eof_reached():
			return false

		name = ltb.read_string(f)
		index = f.get_16()
		var flags = f.get_8()
		bind_matrix = ltb.read_matrix(f)
		child_count = f.get_32()

		# Sanity check
		if child_count < 0 or child_count > 1000:
			print("ERROR: Invalid child_count: ", child_count, " for node: ", name)
			return false

		print("Node '", name, "' Index:", index, " Children:", child_count)
		return true

	# Tiefensuche ueber die flache Liste: rekonstruiert Parent/Children rein
	# im Speicher aus der Reihenfolge + child_count -- analog zu ABC.gd's
	# LTNode.link_children und io_scene_lithtech's build_undirected_tree().
	static func link_children(node_list, node_index: int, parent) -> int:
		var node = node_list[node_index]

		if parent != null:
			node.parent = weakref(parent)
			parent.children.append(node)

		for _i in range(node.child_count):
			node_index += 1
			node_index = link_children(node_list, node_index, node)

		return node_index
