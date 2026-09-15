extends Node

class GLTFExporter:
	
	const MIN_INT = - -1
	const MAX_INT = -1
	
	
	
	
	enum ComponentTypes{
		BYTE = 5120, 
		UNSIGNED_BYTE = 5121, 
		SHORT = 5122, 
		UNSIGNED_SHORT = 5123, 
		
		UNSIGNED_INT = 5125, 
		FLOAT = 5126, 
	}
	
	enum PrimitiveModes{
		POINTS = 0, 
		LINES = 1, 
		LINE_LOOP = 2, 
		LINE_STRIP = 3, 
		TRIANGLES = 4, 
		TRIANGLE_STRIP = 5, 
		TRIANGLE_FAN = 6, 
	}
	
	
	var gltf = {}
	
	var scene_node = null
	var scene_meshes = []
	var mesh_buffers = []
	
	func process(scene: Node):
		
		self.scene_node = scene
		
		var mesh_root = scene.get_node("/root/Root/UI/ModelRenderer/Root")
		self.scene_meshes = mesh_root.get_children()
		var children_count = mesh_root.get_child_count()
		
		
		
		
		self.gltf = {
			"asset": {
				"generator": "HeyThereCoffeee's GLTF Exporter for LithTools v0.3", 
				"version": "2.0"
			}, 
			
			
			
		}
		
		build_buffers()
		build_node_list()
		build_scene()
		
		var json_gltf = JSON.print(gltf)
		
		var file = File.new()
		file.open("./export/exported_scene.gltf", File.WRITE)
		file.store_string(json_gltf)
		file.close()
		
		file = File.new()
		file.open("./export/exported_scene.bin", File.WRITE)
		
		for mesh_buffer in self.mesh_buffers:
			file.store_buffer(mesh_buffer.buffer)
		file.close()
		
		
		pass
	
	
	func append_buffer_view(length, offset):
		self.gltf["bufferViews"].append({
			"buffer": 0, 
			"byteLength": length, 
			"byteOffset": offset, 
		})
		
	func append_accessor(comp_type, type, count, min_value = null, max_value = null):
		var accessor = {
			"bufferView": len(self.gltf["bufferViews"]) - 1, 
			"componentType": comp_type, 
			"count": count, 
			"type": type, 
		}
		
		
		if min_value != null:
			if type == "VEC3":
				accessor["min"] = [min_value.x, min_value.y, min_value.z]
			elif type == "VEC2":
				accessor["min"] = [min_value.x, min_value.y]
			elif type == "SCALAR":
				accessor["min"] = min_value
		if max_value != null:
			if type == "VEC3":
				accessor["max"] = [max_value.x, max_value.y, max_value.z]
			elif type == "VEC2":
				accessor["max"] = [max_value.x, max_value.y]
			elif type == "SCALAR":
				accessor["max"] = max_value
			
		self.gltf["accessors"].append(accessor)
	
	func build_buffers():
		
		var current_texture_source = 0
		var current_buffer_offset = 0
		var current_accessor_position = 0
		var total_buffer_size = 0

		var buffer_length = 0
		var buffer_offset = 0
		
		self.gltf["bufferViews"] = []
		self.gltf["accessors"] = []
		self.gltf["meshes"] = []
		
		self.gltf["textures"] = []
		self.gltf["images"] = []
		self.gltf["materials"] = []
		
		for mesh in self.scene_meshes:
			
			if true:
				
				mesh = mesh as MeshInstance
				var mdt = MeshDataTool.new()
				mdt.create_from_surface(mesh.mesh, 0)
				
				var mesh_buffer = StreamPeerBuffer.new()
				
				var buffer_size_in_bytes = mdt.get_vertex_count() * 3 * 4
				
				
				var posnorm_buffer_length = mdt.get_vertex_count() * 3 * 4
				var uv_buffer_length = mdt.get_vertex_count() * 2 * 4
				var index_buffer_length = mdt.get_face_count() * 3 * 2
				
				var min_vec_len = MAX_INT
				var max_vec_len = MIN_INT
				
				var min_value = Vector3()
				var max_value = Vector3()
				
				
				for i in range(0, mdt.get_vertex_count()):
					var vert = mdt.get_vertex(i)
					mesh_buffer.put_float(vert.x)
					mesh_buffer.put_float(vert.y)
					mesh_buffer.put_float(vert.z)

					
					var mag = vert.length_squared()

					if mag < min_vec_len:
						min_value = vert
						min_vec_len = mag

					if mag > max_vec_len:
						max_value = vert
						max_vec_len = mag
					
				
				
				self.append_buffer_view(posnorm_buffer_length, buffer_offset)
				self.append_accessor(ComponentTypes.FLOAT, "VEC3", mdt.get_vertex_count(), min_value, max_value)
				buffer_offset += posnorm_buffer_length
					
				
				for i in range(0, mdt.get_vertex_count()):
					var normal = mdt.get_vertex_normal(i)
					mesh_buffer.put_float(normal.x)
					mesh_buffer.put_float(normal.y)
					mesh_buffer.put_float(normal.z)
					
				self.append_buffer_view(posnorm_buffer_length, buffer_offset)
				self.append_accessor(ComponentTypes.FLOAT, "VEC3", mdt.get_vertex_count())
				buffer_offset += posnorm_buffer_length
				
				
				for i in range(0, mdt.get_vertex_count()):
					var uv = mdt.get_vertex_uv(i)
					mesh_buffer.put_float(uv.x)
					mesh_buffer.put_float(uv.y)
					

				self.append_buffer_view(uv_buffer_length, buffer_offset)
				self.append_accessor(ComponentTypes.FLOAT, "VEC2", mdt.get_vertex_count())
				buffer_offset += uv_buffer_length
					
				
				for i in range(0, mdt.get_vertex_count()):
					var uv = mdt.get_vertex_uv2(i)
					mesh_buffer.put_float(uv.x)
					mesh_buffer.put_float(uv.y)

				self.append_buffer_view(uv_buffer_length, buffer_offset)
				self.append_accessor(ComponentTypes.FLOAT, "VEC2", mdt.get_vertex_count())
				buffer_offset += uv_buffer_length
				
				
				for i in range(0, mdt.get_face_count()):
					var v1 = mdt.get_face_vertex(i, 0)
					var v2 = mdt.get_face_vertex(i, 1)
					var v3 = mdt.get_face_vertex(i, 2)
					
					mesh_buffer.put_16(v1)
					mesh_buffer.put_16(v2)
					mesh_buffer.put_16(v3)
				
				self.append_buffer_view(index_buffer_length, buffer_offset)
				self.append_accessor(ComponentTypes.UNSIGNED_SHORT, "SCALAR", mdt.get_face_count() * 3)
				buffer_offset += index_buffer_length
				
				total_buffer_size += (posnorm_buffer_length * 2) + (uv_buffer_length * 2) + index_buffer_length
				
				self.mesh_buffers.append({
					"name": mesh.name, 
					"length": mesh_buffer.get_size(), 
					"buffer": mesh_buffer.data_array
				})
				
				var meshes_entry = {
					"name": mesh.name, 
					"primitives": [{
						"attributes": {
							"POSITION": current_accessor_position, 
							"NORMAL": current_accessor_position + 1, 
							"TEXCOORD_0": current_accessor_position + 2, 
							"TEXCOORD_1": current_accessor_position + 3, 
						}, 
						"indices": current_accessor_position + 4, 
					}]
				}
				
				current_accessor_position += 5
				
				var mat = mesh.get_surface_material(0) as ShaderMaterial

				if mat != null:

					var main_tex = mat.get_shader_param("main_texture") as ImageTexture
					var lm_tex = mat.get_shader_param("lm_texture") as ImageTexture
					var use_alpha = mat.get_shader_param("use_alpha")
					
					
					
					var tex_name = mesh.name + ".png"
					
					if main_tex != null:
						main_tex.get_data().save_png("./export/" + tex_name)
					if lm_tex != null:
						lm_tex.get_data().save_png("./export/lm_tex.png")
						
					
					if main_tex == null:
						self.gltf["meshes"].append(meshes_entry)
						continue
					
					self.gltf["textures"].append({
						"source": current_texture_source
					})
					
					self.gltf["images"].append({
						"uri": tex_name
					})
					
					self.gltf["materials"].append({
						"doubleSided": false, 
						
						"name": mesh.name + " - Material", 
						"pbrMetallicRoughness": {
							"baseColorFactor": [1.0, 1.0, 1.0, 1.0], 
							"baseColorTexture": {
								"index": current_texture_source, 
							}, 
							"metallicFactor": 0.0, 
							"roughnessFactor": 1.0, 
						}, 
						
						
						
						
						
						
					})
					
					
					meshes_entry["primitives"][0]["material"] = current_texture_source
				
				self.gltf["meshes"].append(meshes_entry)
				
				current_texture_source += 1
				
				
				
		
		self.gltf["buffers"] = [{"byteLength": total_buffer_size, "uri": "exported_scene.bin"}]
	
	func build_node_list():
		
		
		var nodes = []
		var mesh_index = 0

		
		for mesh in self.scene_meshes:
			
			var rot = Quat(mesh.rotation)
			var loc = mesh.translation
			var node = {
				"name": mesh.name, 
				"rotation": [rot.x, rot.y, rot.z, rot.w], 
				"translation": [loc.x, loc.y, loc.z], 
			}
			
			node["mesh"] = mesh_index
			mesh_index += 1
			
			if mesh.get_class() == "WorldMesh":
				node["mesh"] = mesh_index
				mesh_index += 1
			elif mesh.get_class() == "WorldItem":
				node["extras"] = mesh.get_extras()
			
			nodes.append(node)
			
			
			
			pass
		
		self.gltf["nodes"] = nodes
		
		pass
	
	func build_scene():
		
		var nodes_written_out = []
		
		for i in range(0, len(self.scene_meshes)):
			nodes_written_out.append(i)
		
		self.gltf["scenes"] = [
			{
				"name": "Scene", 
				"nodes": nodes_written_out
			}
		]
		self.gltf["scene"] = 0
		
		pass
