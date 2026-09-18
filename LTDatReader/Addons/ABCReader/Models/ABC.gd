const BinPrim = preload("res://Addons/LTDatReader/BinaryReadPrimitives.gd")

class ABC:
	var name = ""
	
	var mirror_abc_for_godot = true  # Fuer Links-Rechts Spiegelung
	
	# Header
	var version = 0
	var node_count = 0
	var lod_count = 0
	var weight_set_count = 0
	var command_string = ""
	var internal_radius = 0
	var lod_distances = []

	# Piece
	var pieces = []
	
	# Node
	var nodes = []
	var weight_sets = []
	
	# Child Models
	var child_models = []
	
	# Animations
	var animations = []

	# AnimDims
	var anim_dims = []
	
	# Transform Info
	var front_to_back_indices = false
	var flip_anim = false

	func _init():
		pass
	# End Func
	
	enum IMPORT_RETURN{SUCCESS, ERROR}
	
	func read(f : File, start_offset : int = 0):
		# start_offset: normale, eigenstaendige .abc-Dateien starten den
		# Section-Scan bei Byte 0 ("Header" ist die erste Section). Die
		# Die-Hard:-Nakatomi-Plaza-Sondervariante von LTB wickelt einen
		# sonst identischen ABC-Body in einen aeusseren LTB-Container ein
		# (LTBHeader-String + LTB_Header); LTBImporter.gd/DHNPWrapper.gd
		# uebergeben hier die Groesse dieses Wrappers, damit dieselbe
		# Section-Scan-Schleife unveraendert fuer beide Faelle funktioniert
		# (siehe io_scene_lithtech's reader_abc_pc.py fuer denselben Trick
		# auf der Blender-Seite).
		var next_section_offset = start_offset
		while next_section_offset != -1:
			f.seek(next_section_offset)
			
			var section_name = self.read_string(f)
			next_section_offset = f.get_32()
			
			if section_name == 'Header':
				self.version = f.get_32()
				print("ABC Version: " + str(self.version))
				
				if [9, 10, 11, 12, 13].has(self.version) == false:
					return self._make_response(IMPORT_RETURN.ERROR, 'Unsupported file version (' + str(self.version) + ')')
				
				f.seek(f.get_position() + 8)
				self.node_count = f.get_32()
				f.seek(f.get_position() + 20)
				self.lod_count = f.get_32()
				f.seek(f.get_position() + 4)
				self.weight_set_count = f.get_32()
				f.seek(f.get_position() + 8)
				
				# Unknown new value
				if self.version >= 13:
					f.seek(f.get_position() + 4)
					
				self.command_string = self.read_string(f)
				self.internal_radius = f.get_float()
				var distance_count = f.get_32()
				f.seek(f.get_position() + 60)
				
				for i in range(distance_count):
					self.lod_distances.append(f.get_float())
					
				print("Header Info:\n - Node Count: " + str(self.node_count) + "\n - LOD Count: " + str(self.lod_count) + "\n - Weight Set Count: " + str(self.weight_set_count) + "\n - Command String: " + self.command_string + "\n - Internal Radius: " + str(self.internal_radius) + "\n - Distance Count: " + str(distance_count))
				# End For
			elif section_name == 'Pieces':
				var weight_count = f.get_32()
				var pieces_count = f.get_32()
				
				for i in range(pieces_count):
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
				
				# Link up the nodes
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
			elif section_name == "Animation":
				var animation_count = f.get_32()
				for i in range(animation_count):
					var animation = LTAnim.new()
					animation.read(self, f)
					self.animations.append(animation)
				# End For
			else:
				break
			# End If
			
			print("Finished " + section_name + "\n -> Next section at " + str(next_section_offset))
			
		# End While
		
		print("Finished loading ABC")
		print("-------------------------")
		return self._make_response(IMPORT_RETURN.SUCCESS)
	# End Func
	
	#
	# Helpers
	# 
	func _make_response(code, message = ''):
		return BinPrim.make_response(code, message)
	# End Func
	
	func read_string(file : File):
		return BinPrim.read_string(file)
	# End Func
	
	func read_vector2(file : File):
		return BinPrim.read_vector2(file)
	# End Func
		
	func read_vector3(file : File):
		return BinPrim.read_vector3(file)
	# End Func
	
	func read_quat(file : File):
		return BinPrim.read_quat(file)

	func read_matrix(file : File):
		return BinPrim.read_matrix(file)
	#End Func
		
	func convert_4x4_to_transform(matrix):
		return Transform(
			Vector3( matrix[0], matrix[4], matrix[8]  ),
			Vector3( matrix[1], matrix[5], matrix[9]  ),
			Vector3( matrix[2], matrix[6], matrix[10] ),
			Vector3( matrix[3], matrix[7], matrix[11] )
		)

	##################
	# Internal Classes
	##################
	class Piece:
		var name = ""
		
		var material_index = 0
		var specular_power = 0.0
		var specular_scale = 0.0
		var lod_weight = 0.0
		var padding = 0
		
		var lods = []
		
		func read(abc : ABC, f : File):
			self.material_index = f.get_16()
			self.specular_power = f.get_float()
			self.specular_scale = f.get_float()
			if abc.version > 9:
				self.lod_weight = f.get_float()
			# End If
			self.padding = f.get_16()
			self.name = abc.read_string(f)
			
			for i in range(abc.lod_count):
				var lod = abc.MeshLod.new()
				lod.read(abc, f)
				lods.append(lod)
			# End For
	# End Piece
		
	class MeshLod:
		var face_count = 0
		var vertex_count = 0
		
		var faces = []
		var vertices = []
		
		func read(abc : ABC, f : File):
			self.face_count = f.get_32()

			for i in range(self.face_count):
				var face = abc.Face.new()
				face.read(abc, f)
				self.faces.append(face)
			# End For
			self.vertex_count = f.get_32()

			for i in range(self.vertex_count):
				var vertex = abc.Vertex.new()
				vertex.read(abc, f)
				self.vertices.append(vertex)
			# End For
		# End Func
	# End LOD
		
	class Face:
		var vertices = []
		
		func read(abc : ABC, f : File):
			for i in range(3):
				var face_vertex = abc.FaceVertex.new()
				face_vertex.read(abc, f)
				self.vertices.append(face_vertex)
			# End For
		# End Func
	# End Face
	
	class FaceVertex:
		var texcoord = Vector2()
		var vertex_index = 0
		var reversed = false
		
		func read(abc : ABC, f : File):
			self.texcoord = abc.read_vector2(f)
			self.vertex_index = f.get_16()
		# End Func
	# End FaceVertex
	
	class Vertex:
		var sublod_vertex_index = 0xCDCD
		var weight_count = 0
		var weights = []
		var location = Vector3()
		var normal = Vector3()
		
		func read(abc : ABC, f : File):
			self.weight_count = f.get_16()
			self.sublod_vertex_index = f.get_16()
			for i in range(self.weight_count):
				var weight = abc.Weight.new()
				weight.read(abc, f)
				self.weights.append(weight)
			# End For
			self.location = abc.read_vector3(f)
			self.normal = abc.read_vector3(f)
		# End Func
	# End Vertex
	
	class Weight:
		var node_index = 0
		var location = Vector3()
		var bias = 0.0
		
		func read(abc : ABC, f : File):
			self.node_index = f.get_32()
			self.location = abc.read_vector3(f)
			self.bias = f.get_float()
		# End Func
	# End Weight

	# I miss namespaces...
	class LTNode:
		var name = ""
		var index = 0
		var flags = 0
		var bind_matrix = Transform()
		var inverse_bind_matrix = Transform()
		var child_count = 0
		
		# Links
		var parent = null  # weakref(), um Referenzzyklus mit children zu vermeiden
		var children = []
		
		func read(abc : ABC, f : File):
			self.name = abc.read_string(f)
			self.index = f.get_16()
			self.flags = f.get_8()
			self.bind_matrix = abc.read_matrix(f)
			self.inverse_bind_matrix = self.bind_matrix.inverse()
			self.child_count = f.get_32()
			pass
		# End Func
		
		# Static for convience
		static func link_children(node_list, node_index, parent : LTNode):
			var node = node_list[node_index]
			
			if (parent != null):
				node.parent = weakref(parent)
				parent.children.append(node)
			
			for _i in range(node.child_count):
				node_index += 1
				node_index = link_children(node_list, node_index, node)
			
			return node_index
		# End Func
	# End Node
	
	class WeightSet:
		var name = ""
		var node_count = 0
		var node_weights = []
		
		func read(abc : ABC, f : File):
			self.name = abc.read_string(f)
			self.node_count = f.get_32()
			for i in range(self.node_count):
				node_weights.append(f.get_float())
			# End For
		# End Func
	# End Weightset
	
	class LTTransform:
		var location = Vector3()
		var rotation = Quat()
		
		func read(abc : ABC, f : File):
			self.location = abc.read_vector3(f)
			self.rotation = abc.read_quat(f)
			
			# Two unknown floats
			if (abc.version >= 13):
				f.seek(f.get_position() + 8)
		# End Func
	# End LTTransform
	
	class ChildModel:
		var name = ""
		var build_number = 0
		var lt_transform = null
		
		func read(abc : ABC, f : File):
			self.name = abc.read_string(f)
			self.build_number = f.get_32()
			self.lt_transform = LTTransform.new()
			self.lt_transform.read(abc, f)
			# End If
		# End Func
	# End ChildModel
	
	class LTAnim:
		var name = ""
		var extents = Vector3()
		var unknown = 0
		var interp_time = 200
		var keyframe_count = 0
		var keyframes = []
		var node_keyframes = []
		
		func read(abc : ABC, f : File):
			self.extents = abc.read_vector3(f)
			self.name = abc.read_string(f)
			self.unknown = f.get_32()
			# Only valid for 12 and up!
			if abc.version >= 12:
				self.interp_time = f.get_32()
			# End If
			self.keyframe_count = f.get_32()
			
			for i in range (self.keyframe_count):
				var lt_keyframe = LTKeyframe.new()
				lt_keyframe.read(abc, f)
				self.keyframes.append(lt_keyframe)
			# End For
			
			for i in range(abc.node_count):
				# Skip some unknown data
				if abc.version >= 13:
					f.seek(f.get_position() + 4)
				# End If
				
				var keyframes_per_node = []
				for j in range(self.keyframe_count):
					var lt_transform = LTTransform.new()
					lt_transform.read(abc, f)
					keyframes_per_node.append(lt_transform)
				# End For
				self.node_keyframes.append(keyframes_per_node)
			# End For
			
		# End Func
	# End LTAnim
	
	class LTKeyframe:
		var time = 0
		var command_string = ""
		
		func read(abc : ABC, f : File):
			self.time = f.get_32()
			self.command_string = abc.read_string(f)
			# End For
		# End Func
	
