extends Node

class OBJExporter:
	var obj_buffer = ""
	var last_vertex_index = 0
	
	func print_vertex_data(mdt: MeshDataTool):
		for i in range(mdt.get_vertex_count()):
			var vertex = mdt.get_vertex(i)
			self.obj_buffer += "v %f %f %f\n" % [vertex.x, vertex.y, vertex.z]
		
	
	
	func print_uv_data(mdt: MeshDataTool, use_uv2 = false):
		for i in range(mdt.get_vertex_count()):
			var uv = mdt.get_vertex_uv(i)
			
			if use_uv2:
				uv = mdt.get_vertex_uv2(i)
			
			
			
			uv = Vector2(uv.x, 1.0 - uv.y)
			
			self.obj_buffer += "vt %f %f\n" % [uv.x, uv.y]
		
	
	
	func print_normal_data(mdt: MeshDataTool):
		for i in range(mdt.get_vertex_count()):
			var normal = mdt.get_vertex_normal(i)
			self.obj_buffer += "vn %f %f %f\n" % [normal.x, normal.y, normal.z]
		
	
	
	func print_face_data(mdt: MeshDataTool):
		var obj_face_vertex = 0
		for i in range(mdt.get_face_count()):
			self.obj_buffer += "f"
			for j in range(3):
				var face_vertex = mdt.get_face_vertex(i, j)
				obj_face_vertex = (face_vertex + 1) + self.last_vertex_index
				self.obj_buffer += " %d/%d/%d" % [obj_face_vertex, obj_face_vertex, obj_face_vertex]
			self.obj_buffer += "\n"
		
		
		self.last_vertex_index = obj_face_vertex
	
	
	
	
	
	func export_mesh(mesh_data, path, use_uv2 = false):
		
		self.obj_buffer = ""
		self.last_vertex_index = 0
		var mdt_list = []
		var index = 0
		
		if typeof(mesh_data) != TYPE_ARRAY:
			mesh_data = [mesh_data]
		
		
		for data in mesh_data:
			var mdt = MeshDataTool.new()
			mdt.create_from_surface(data, 0)
			mdt_list.append(mdt)
		
		
		self.obj_buffer += "# HeyThereCoffee Debug Export Tool\n"
		
		
		self.obj_buffer += "o godot_mesh\n"
		
		self.obj_buffer += "# Vertex Data\n"
		index = 0
		for mdt in mdt_list:
			self.obj_buffer += "# Mesh %d\n" % index
			self.print_vertex_data(mdt)
			index += 1
		
		
		self.obj_buffer += "# UV Data\n"
		index = 0
		for mdt in mdt_list:
			self.obj_buffer += "# Mesh %d\n" % index
			self.print_uv_data(mdt, use_uv2)
			index += 1
		
		
		
		self.obj_buffer += "# Vertex Normal Data\n"
		index = 0
		for mdt in mdt_list:
			self.obj_buffer += "# Mesh %d\n" % index
			self.print_normal_data(mdt)
			index += 1
		

		self.obj_buffer += "# Misc\n"
		self.obj_buffer += "usemtl None\n"
		self.obj_buffer += "s off\n"
		
		self.obj_buffer += "# Face Data\n"
		index = 0
		for mdt in mdt_list:
			self.obj_buffer += "# Mesh %d\n" % index
			self.print_face_data(mdt)
			index += 1
		
		
		self.obj_buffer += "# Fin\n"
		
		var file = File.new()
		file.open(path, File.WRITE)
		file.store_string(obj_buffer)
		file.close()
	
