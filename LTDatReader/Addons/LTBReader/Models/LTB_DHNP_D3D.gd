# res://Addons/LTBReader/Models/LTB_DHNP_D3D.gd
class_name LTB_DHNP_D3D

const BinPrim = preload("res://Addons/LTDatReader/BinaryReadPrimitives.gd")

# Die-Hard:-Nakatomi-Plaza (DHNP) D3D-Hybrid-LTB-Body-Reader.
#
# 1:1-Portierung der bereits gegen 7 echte DHNP-D3D-Hybrid-LTBs
# (ALEXANDER, TERRORIST_1, POWEL2, ULI, BUILDING, LOGO, V_ZIPPO) byte-perfekt
# validierten Python-Referenz (io_scene_lithtech/src/reader_ltb_dhnp.py,
# Klasse DHNPD3DModelReader). Kein neues Reverse-Engineering hier -- nur
# Uebertragung der schon bestaetigten Logik nach GDScript.
#
# Genutzt wird das hier IMMER ueber den DHNP-Wrapper (siehe DHNPWrapper.gd);
# start_offset ist die Position direkt hinter dem Wrapper, ab der die normale
# Section-Scan-Schleife beginnt (Header/Pieces/Nodes/ChildModels/Animation/
# Sockets/AnimBindings -- gleiches Section-Layout wie beim ABC-Body, nur die
# Pieces-Sektion ist strukturell komplett anders, siehe unten).
#
# Zwei Felder bleiben bewusst ungeklaert (read-but-unused, wie im Python-
# Original kommentiert):
#   - LODHeader.UnknownFloats[7] -- vermutlich Materialfarbe (VERMUTUNG,
#     nicht bestaetigt).
#   - LODHeader.Unknown3 -- in allen getesteten Dateien konstant 2, Bedeutung
#     unbekannt.

const MT_RIGID = 4
const MT_SKELETAL = 5
const INVALID_BONE = 255

var name = ""
var version = 0
var node_count = 0
var lod_count = 0
var pieces = []
var nodes = []
var weight_sets = []
var child_models = []
var animations = []
var sockets = []
var anim_bindings = []
var command_string = ""
var internal_radius = 0.0
var lod_distances = []

enum IMPORT_RETURN {SUCCESS, ERROR}


func read(f: File, start_offset: int = 0) -> Dictionary:
	var next_section_offset = start_offset
	while next_section_offset != -1:
		f.seek(next_section_offset)

		var section_name = self.read_string(f)
		next_section_offset = f.get_32()

		if section_name == 'Header':
			self.version = f.get_32()
			print("DHNP D3D Version: " + str(self.version))

			f.seek(f.get_position() + 8)  # KeyframeCount, AnimationCount
			self.node_count = f.get_32()
			f.seek(f.get_position() + 4)   # PieceCount (wird aus der Pieces-Sektion selbst gelesen)
			f.seek(f.get_position() + 16)  # ChildModelCount, FaceCount, VertexCount, WeightCount
			self.lod_count = f.get_32()
			f.seek(f.get_position() + 4)   # SocketCount
			f.get_32()  # WeightSetCount (Header-Kopie, ungenutzt -- die echte Zahl steht in der Nodes-Sektion)

			if self.version >= 13:
				f.seek(f.get_position() + 4)  # Unknown (nur v13+)

			f.seek(f.get_position() + 8)  # StringCount, StringLengthTotal
			self.command_string = self.read_string(f)
			self.internal_radius = f.get_float()
			var distance_count = f.get_32()
			f.seek(f.get_position() + 60)  # Padding

			for i in range(distance_count):
				self.lod_distances.append(f.get_float())
			# End For

			print("Header Info:\n - Node Count: " + str(self.node_count) + "\n - LOD Count: " + str(self.lod_count))
		elif section_name == 'Pieces':
			# DHNP-D3D-PieceHeader hat KEIN WeightCount-Feld, nur PieceCount
			# (bestaetigt anders als beim ABC-Body).
			var piece_count = f.get_32()
			for i in range(piece_count):
				var piece = Piece.new()
				piece.read(self, f)
				self.pieces.append(piece)
			# End For
		elif section_name == 'Nodes':
			for i in range(self.node_count):
				var node = LTNode.new()
				node.read(self, f)
				self.nodes.append(node)
			# End For

			LTNode.link_children(self.nodes, 0, null)

			var weight_set_count = f.get_32()
			for i in range(weight_set_count):
				var weight_set = WeightSet.new()
				weight_set.read(self, f)
				self.weight_sets.append(weight_set)
			# End For
		elif section_name == 'ChildModels':
			var child_model_count = f.get_16()
			for i in range(child_model_count):
				var child_model = ChildModel.new()
				child_model.read(self, f)
				self.child_models.append(child_model)
			# End For
		elif section_name == 'Animation':
			var animation_count = f.get_32()
			for i in range(animation_count):
				var animation = LTAnim.new()
				animation.read(self, f)
				self.animations.append(animation)
			# End For
		elif section_name == 'Sockets':
			var socket_count = f.get_32()
			for i in range(socket_count):
				var socket = Socket.new()
				socket.read(self, f)
				self.sockets.append(socket)
			# End For
		elif section_name == 'AnimBindings':
			var anim_binding_count = f.get_32()
			for i in range(anim_binding_count):
				var anim_binding = AnimBinding.new()
				anim_binding.read(self, f)
				self.anim_bindings.append(anim_binding)
			# End For
		else:
			break
		# End If

		print("Finished " + section_name + "\n -> Next section at " + str(next_section_offset))
	# End While

	print("Finished loading DHNP D3D-Hybrid")
	return self._make_response(IMPORT_RETURN.SUCCESS)
# End Func


##################
# Shared Helpers
##################

func read_string(file: File) -> String:
	return BinPrim.read_string(file)

func read_vector2(file: File) -> Vector2:
	return BinPrim.read_vector2(file)

func read_vector3(file: File) -> Vector3:
	return BinPrim.read_vector3(file)

func read_quat(file: File) -> Quat:
	return BinPrim.read_quat(file)

func read_matrix(file: File) -> Transform:
	return BinPrim.read_matrix(file)

func _make_response(code, message = ''):
	return BinPrim.make_response(code, message)


##################
# Internal Classes
##################

class Weight:
	var node_index = 0
	var bias = 0.0


class Vertex:
	var location = Vector3()
	var normal = Vector3()
	var weights = []


class FaceVertex:
	var texcoord = Vector2()
	var vertex_index = 0


class Face:
	var vertices = []


class MeshLod:
	var vert_count = 0
	var face_count = 0
	var max_bones_per_face = 0
	var max_bones_per_vert = 0
	var type = 0
	var textures = []

	# Nicht Teil des ABC-Vertex-Layouts, hier aber gebraucht, weil Piece.read()
	# unten Material-Index/Specular vom ersten LOD hochreicht -- der DHNP-D3D-
	# Piece-Struct hat selbst keine Materialfelder (siehe LODHeader).
	var specular_power = 0.0
	var specular_scale = 0.0

	var vertices = []
	var faces = []

	func _read_lod_header(dhnp, f: File) -> Dictionary:
		var mesh_type = f.get_32()
		var obj_size = f.get_32()
		for i in range(7):
			f.get_float()  # UnknownFloats[7] -- VERMUTUNG: Materialfarbe, ungenutzt
		for i in range(10):
			f.get_32()  # UnknownInt[10] -- bestaetigt uninitialisiertes Padding, ungenutzt
		var texture_index = f.get_32()
		for i in range(3):
			f.get_32()  # efef[3] -- bestaetigt konstant (-1,-1,-1), ungenutzt
		var specular_power = f.get_float()
		var specular_scale = f.get_float()
		f.get_32()  # Unknown3 -- bestaetigt konstant 2, ungenutzt
		var vert_count = f.get_32()
		var face_count = f.get_32()
		var max_bones_per_tri = f.get_32()
		var max_bones_per_vert = f.get_32()
		return {
			"mesh_type": mesh_type,
			"obj_size": obj_size,
			"texture_index": texture_index,
			"specular_power": specular_power,
			"specular_scale": specular_scale,
			"vert_count": vert_count,
			"face_count": face_count,
			"max_bones_per_tri": max_bones_per_tri,
			"max_bones_per_vert": max_bones_per_vert,
		}

	func _read_uv_and_faces(dhnp, f: File, vert_count: int, face_count: int):
		var uvs = []
		for i in range(vert_count):
			uvs.append(dhnp.read_vector2(f))
		for i in range(face_count):
			var face = Face.new()
			for j in range(3):
				var vertex_index = f.get_16()
				var face_vertex = FaceVertex.new()
				face_vertex.vertex_index = vertex_index
				if vertex_index >= 0 and vertex_index < uvs.size():
					face_vertex.texcoord = uvs[vertex_index]
				face.vertices.append(face_vertex)
			# End For
			self.faces.append(face)
		# End For

	func _read_rigid_lod(dhnp, f: File, hdr: Dictionary):
		# BESTAETIGT per Hex-Abgleich: ein uint32 Bone-Index direkt vor den
		# Vertices -- ein einzelner, fuer das ganze Piece geltender Bone-Index.
		var bone_index = f.get_32()
		for i in range(hdr.vert_count):
			var vertex = Vertex.new()
			vertex.location = dhnp.read_vector3(f)
			vertex.normal = dhnp.read_vector3(f)
			var weight = Weight.new()
			weight.node_index = bone_index
			weight.bias = 1.0
			vertex.weights = [weight]
			self.vertices.append(vertex)
		# End For
		self._read_uv_and_faces(dhnp, f, hdr.vert_count, hdr.face_count)

	func _read_skeletal_lod_fmt1(dhnp, f: File, hdr: Dictionary):
		# NewVertFormat == 1: gepacktes Multi-Bone-Blending, Stride haengt von
		# MaxBonesPerVert ab (2/3/4 -> 32/36/40 Bytes; alles andere faellt wie
		# im .bt-Template auf 36 zurueck).
		var max_bones = hdr.max_bones_per_vert
		var n_blend_floats = 2
		if max_bones == 2:
			n_blend_floats = 1
		elif max_bones == 3:
			n_blend_floats = 2
		elif max_bones == 4:
			n_blend_floats = 3

		f.get_32()  # Streamdata, ungenutzt
		f.get_32()  # Streamdata, ungenutzt

		for i in range(hdr.vert_count):
			var vertex = Vertex.new()
			vertex.location = dhnp.read_vector3(f)

			var blend_weights = []
			for j in range(n_blend_floats):
				blend_weights.append(f.get_float())

			var bone_indices = []
			for j in range(4):
				bone_indices.append(f.get_8())  # gepackt [idx0..idx(n-1), 0-gepolstert]

			vertex.normal = dhnp.read_vector3(f)

			var n = 3
			if max_bones == 2 or max_bones == 3 or max_bones == 4:
				n = max_bones

			var weights = []
			var remaining_bias = 1.0
			for j in range(n - 1):
				var w = Weight.new()
				w.node_index = bone_indices[j]
				w.bias = blend_weights[j]
				remaining_bias -= blend_weights[j]
				weights.append(w)
			# End For
			var last = Weight.new()
			last.node_index = bone_indices[n - 1]
			last.bias = remaining_bias
			weights.append(last)
			vertex.weights = weights

			self.vertices.append(vertex)
		# End For
		self._read_uv_and_faces(dhnp, f, hdr.vert_count, hdr.face_count)

	func _read_skeletal_lod_fmt0(dhnp, f: File, hdr: Dictionary, lod_start: int):
		# NewVertFormat == 0: ein Weight pro Vertex (BoneWeight ist laut
		# .bt-Template-Kommentar immer 1.0), der echte Bone-Index kommt aus
		# der BoneSet-Tabelle nach den Faces. Stride haengt von
		# MaxBonesPerTri ab (1/2 -> 24/28 Bytes; alles andere -> 32).
		var max_bones_per_tri = hdr.max_bones_per_tri
		for i in range(hdr.vert_count):
			var vertex = Vertex.new()
			vertex.location = dhnp.read_vector3(f)
			if max_bones_per_tri == 1:
				pass  # SkeletalVertex_Fmt0_24: kein BoneWeight/BoneIndex-Feld
			elif max_bones_per_tri == 2:
				f.get_float()  # BoneWeight, immer 1.0
			else:
				f.get_float()  # BoneWeight, immer 1.0
				f.get_32()     # BoneIndex, Platzhalter (echter kommt via BoneSet)
			vertex.normal = dhnp.read_vector3(f)
			var weight = Weight.new()
			weight.node_index = 0
			weight.bias = 1.0
			vertex.weights = [weight]
			self.vertices.append(vertex)
		# End For
		self._read_uv_and_faces(dhnp, f, hdr.vert_count, hdr.face_count)

		# BoneSet-Tabelle: vorhanden, wenn die uebrigen Bytes vor dem Ende von
		# ObjSize wie "Anzahl + N*12-Byte-Eintraege" aussehen (bestaetigtes
		# Muster, identisches 12-Byte-BoneSet-Struct wie beim normalen LTB-PC).
		var bytes_read = f.get_position() - (lod_start + 8)
		var padding_needed = hdr.obj_size - bytes_read
		if padding_needed > 4 and (padding_needed - 4) % 12 == 0:
			var bone_set_count = f.get_32()
			for i in range(bone_set_count):
				var index_start = f.get_16()
				var index_count = f.get_16()
				var bone_list = []
				for j in range(4):
					bone_list.append(f.get_8())
				f.get_32()  # IndexBufferIndex, ungenutzt

				var real_bone = 0
				for b in bone_list:
					if b != INVALID_BONE:
						real_bone = b
						break
				# End For

				for vertex_index in range(index_start, index_start + index_count):
					if vertex_index >= 0 and vertex_index < self.vertices.size():
						self.vertices[vertex_index].weights[0].node_index = real_bone
				# End For
			# End For
		elif padding_needed > 0:
			f.seek(f.get_position() + padding_needed)

	func read(dhnp, f: File):
		var lod_start = f.get_position()
		var hdr = self._read_lod_header(dhnp, f)
		self.vert_count = hdr.vert_count
		self.face_count = hdr.face_count
		self.max_bones_per_face = hdr.max_bones_per_tri
		self.max_bones_per_vert = hdr.max_bones_per_vert
		self.type = hdr.mesh_type
		self.textures = [hdr.texture_index]
		self.specular_power = hdr.specular_power
		self.specular_scale = hdr.specular_scale

		if hdr.mesh_type == MT_RIGID:
			self._read_rigid_lod(dhnp, f, hdr)
		elif hdr.mesh_type == MT_SKELETAL:
			var new_vert_format = f.get_8()
			if new_vert_format == 1:
				self._read_skeletal_lod_fmt1(dhnp, f, hdr)
			else:
				self._read_skeletal_lod_fmt0(dhnp, f, hdr, lod_start)
		else:
			print("  WARNUNG: unbehandelter DHNP-D3D-MeshType=" + str(hdr.mesh_type) + ", LOD-Payload wird uebersprungen")

		# Sicherheitsnetz: unabhaengig davon, wie die Payload oben interpretiert
		# wurde, ist ObjSize die massgebliche Laenge dieses LODs (bestaetigt
		# exakt -- "Perfect fit" -- bei jedem der 15+ getesteten Pieces/LODs).
		f.seek(lod_start + 8 + hdr.obj_size)
# End MeshLod


class Piece:
	var name = ""
	var material_index = 0
	var specular_power = 0.0
	var specular_scale = 0.0
	var lods = []

	func read(dhnp, f: File):
		self.name = dhnp.read_string(f)
		for i in range(dhnp.lod_count):
			var lod = MeshLod.new()
			lod.read(dhnp, f)
			self.lods.append(lod)
		# End For

		# DHNPs D3D-Piece-Struct hat selbst keine Material-Index/Specular-
		# Felder (anders als beim ABC-Body) -- die liegen pro LOD im
		# LODHeader. Wie in reader_ltb_pc.py wird LOD[0]s Wert auf die
		# Piece hochgereicht.
		if self.lods.size() > 0:
			var first_lod = self.lods[0]
			if first_lod.textures.size() > 0:
				self.material_index = first_lod.textures[0]
			self.specular_power = first_lod.specular_power
			self.specular_scale = first_lod.specular_scale
# End Piece


class LTNode:
	var name = ""
	var index = 0
	var flags = 0
	var bind_matrix = Transform()
	var child_count = 0

	var parent = null  # weakref(), um Referenzzyklus mit children zu vermeiden
	var children = []

	func read(dhnp, f: File):
		self.name = dhnp.read_string(f)
		self.index = f.get_16()
		# HINWEIS: Python-Referenz liest hier ein VORZEICHENBEHAFTETES Byte
		# (unpack('b', f)); Godots File.get_8() ist immer unsigned. Gleiche,
		# bereits bestehende und bewusst nicht behobene Diskrepanz wie in
		# ABCReader/Models/ABC.gd. Ohne Belang hier, da flags fuer DHNP-D3D
		# an keiner Stelle per Bitmaske ausgewertet wird.
		self.flags = f.get_8()
		self.bind_matrix = dhnp.read_matrix(f)
		self.child_count = f.get_32()

	static func link_children(node_list, node_index, parent):
		var node = node_list[node_index]

		if parent != null:
			node.parent = weakref(parent)
			parent.children.append(node)

		for i in range(node.child_count):
			node_index += 1
			node_index = link_children(node_list, node_index, node)

		return node_index
# End LTNode


class WeightSet:
	var name = ""
	var node_weights = []

	func read(dhnp, f: File):
		self.name = dhnp.read_string(f)
		var node_count = f.get_32()
		for i in range(node_count):
			self.node_weights.append(f.get_float())
# End WeightSet


class LTTransform:
	var location = Vector3()
	var rotation = Quat()

	func read(dhnp, f: File):
		self.location = dhnp.read_vector3(f)
		self.rotation = dhnp.read_quat(f)
		if dhnp.version >= 13:
			f.seek(f.get_position() + 8)  # zwei unbekannte Floats (nur v13)
# End LTTransform


class ChildModel:
	var name = ""
	var build_number = 0
	var transforms = []

	func read(dhnp, f: File):
		self.name = dhnp.read_string(f)
		self.build_number = f.get_32()
		for i in range(dhnp.node_count):
			var t = LTTransform.new()
			t.read(dhnp, f)
			self.transforms.append(t)
# End ChildModel


class LTKeyframe:
	var time = 0
	var command_string = ""

	func read(dhnp, f: File):
		self.time = f.get_32()
		self.command_string = dhnp.read_string(f)
# End LTKeyframe


class LTAnim:
	var name = ""
	var extents = Vector3()
	var interpolation_time = 200
	var keyframe_count = 0
	var keyframes = []
	var node_keyframes = []

	func read(dhnp, f: File):
		self.extents = dhnp.read_vector3(f)
		self.name = dhnp.read_string(f)
		f.get_32()  # unknown1, ungenutzt

		if dhnp.version >= 12:
			self.interpolation_time = f.get_32()

		self.keyframe_count = f.get_32()
		for i in range(self.keyframe_count):
			var kf = LTKeyframe.new()
			kf.read(dhnp, f)
			self.keyframes.append(kf)
		# End For

		for i in range(dhnp.node_count):
			if dhnp.version >= 13:
				f.seek(f.get_position() + 4)  # -1-Marker

			var per_node_transforms = []
			for j in range(self.keyframe_count):
				var t = LTTransform.new()
				t.read(dhnp, f)
				per_node_transforms.append(t)
			# End For
			self.node_keyframes.append(per_node_transforms)
		# End For
# End LTAnim


class Socket:
	var node_index = 0
	var name = ""
	var rotation = Quat()
	var location = Vector3()

	func read(dhnp, f: File):
		self.node_index = f.get_32()
		self.name = dhnp.read_string(f)
		self.rotation = dhnp.read_quat(f)
		self.location = dhnp.read_vector3(f)
# End Socket


class AnimBinding:
	var name = ""
	var extents = Vector3()
	var origin = Vector3()

	func read(dhnp, f: File):
		self.name = dhnp.read_string(f)
		self.extents = dhnp.read_vector3(f)
		self.origin = dhnp.read_vector3(f)
# End AnimBinding
