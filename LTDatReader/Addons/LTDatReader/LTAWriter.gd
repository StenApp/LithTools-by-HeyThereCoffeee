#
# LithTech Ascii Format
# ---------------------
# Basically this a pretty simple human readable model format. 
# Note: Names, attributes, and properties are not unique!
# --
# Each node is contained within braces `(` and `)`, the number of open braces determines depth.
# --
# Some nodes have attributes, these are on the same level as their name. 
# An example/ ( name "base" ), the node name is "name" and the attribute is "base".
# --
# Some nodes have properties, these are basically unnamed nodes with just attributes.
# An example/ ( dims (24.000000 53.000000 24.000000) ). "Dims" is the node, and "(24.000000 53.000000 24.000000 )" is a property. 
# There can be more than one property per node, they act like children, but should not have any additional children themselves.
# --
# And finally, nodes can have child nodes. 
# An example/ (lt-model-0 (on-load-cmds ( ... ) ). "lt-model-0" is our depth=0 node, and "on-load-cmds" is our depth=1 node, and a child node of "lt-model-0". 
#
tool

const INDENT = "\t"
const PROP_LABELS = preload("res://Addons//LTDatReader//PROP_LABELS.gd").PROP_LABELS

class LTANode:
	var _name = ""
	var _attribute = null
	var _depth = 0
	var _children = []

	func _init(name='unnamed-node', attribute=null):
		self._name = name
		self._attribute = attribute
		self._depth = 0
		self._children = []

	# Originally its own node type, but it's basically a nameless child..so eh.
	# func create_property(value=''):
		# return self.create_child('', value)
	func create_property(value):
		if typeof(value) == TYPE_STRING and (value == "vector" or value == "eulerangles"):
			return self.create_child(value)
		elif typeof(value) == TYPE_VECTOR3:
			return self.create_child('', [ "%.6f" % value.x, "%.6f" % value.y, "%.6f" % value.z ])
		else:
			return self.create_child('', value)

	# Container is just an empty set of braces
	func create_container():
		return self.create_child('', null)

	func create_child(name, attribute=null):
		var node = LTANode.new(name, attribute)

		# Increase the depth by one
		node._depth = self._depth + 1

		# Add it to this node's children list
		self._children.append(node)

		return node
		
	# func create_prop_entry(type, name, data):
		# var item = self.create_child(type, name)
		# item.create_container()
		# return item.create_child('data', data)

	# func create_prop_entry(type, name, data):
		# var item = self.create_child(type, name)
		# item.create_container()
		# if data != null:
			# item.create_child('data', data)
		# return item
		
	func create_prop_entry(type, name, data):
		var item = self.create_child(type, name)
		item.create_container()
		if PROP_LABELS.has(name):
			item.create_child(PROP_LABELS[name])
		if data != null:
			item.create_child('data', data)
		return item	

		
	# Loop through all the children and write out their props and depth
	func serialize():
		var output_string = ""

		# Add our current depth in tabs
		output_string += self._write_depth()

		output_string += "(" + self._name + " "

		if self._attribute != null:
			output_string += self._resolve_type(self._attribute)

		# If we have no children, let's early out
		if len(self._children) == 0:
			output_string += ")\n"
			return output_string

		# Ok add a new line for our children!
		output_string += "\n"

		for child in self._children:
			output_string += child.serialize()

		# Once again...add our current depth in tabs
		output_string += self._write_depth()

		output_string += ")\n"

		return output_string
		
	func serialize_to_file(file):
		var stack = [{"node": self, "child_idx": 0, "phase": 0}]
		
		while stack.size() > 0:
			var top = stack.size() - 1
			var node = stack[top].node
			var phase = stack[top].phase
			
			if phase == 0:
				for _i in range(node._depth):
					file.store_string("\t")
				file.store_string("(" + node._name + " ")
				if node._attribute != null:
					file.store_string(node._resolve_type(node._attribute))
				if len(node._children) == 0:
					file.store_string(")\n")
					stack.pop_back()
				else:
					file.store_string("\n")
					stack[top].phase = 1
			
			elif phase == 1:
				var child_idx = stack[top].child_idx
				if child_idx < len(node._children):
					stack[top].child_idx += 1
					stack.append({"node": node._children[child_idx], "child_idx": 0, "phase": 0})
				else:
					stack[top].phase = 2
			
			elif phase == 2:
				for _i in range(node._depth):
					file.store_string("\t")
				file.store_string(")\n")
				stack.pop_back()

	func create_vector_node(values: Vector3):
		var node = LTANode.new('vector')
		node._children.append(LTANode.new('', [values.x, values.y, values.z]))
		self._children.append(node)
		return node

	func create_eulerangles_node(values: Vector3):
		var node = LTANode.new('eulerangles')
		node._children.append(LTANode.new('', [values.x, values.y, values.z]))
		self._children.append(node)
		return node
	
	func _write_depth():
		var output_string = ""
		for _i in range(self._depth):
			output_string += "\t"
		return output_string

	# Some handy private functions
	func _resolve_type(value):
		
		# Handle special cases if required
		if typeof(value) == TYPE_STRING:
			return self._serialize_string(value)

		if typeof(value) == TYPE_REAL:
			return self._serialize_float(value)

		if typeof(value) == TYPE_VECTOR3:
			return self._serialize_vector(value)

		if typeof(value) == TYPE_QUAT:
			return self._serialize_quat(value)

		if typeof(value) == TYPE_BASIS:
			return self._serialize_matrix(value)

		if typeof(value) == TYPE_ARRAY:
			return self._serialize_list(value)
		
		return str(value)

	func _serialize_string(value):
		
		# Special string, for "types"..
		if value.find("___") == 0:
			value.erase(0, 3)
			return value
		
		return "\"" + value + "\""

	# func _serialize_float(value):
		# return str(value)

	# func _serialize_vector(value):
		# return str(value.x) + " " + str(value.y) + " " + str(value.z)
	
	func _serialize_float(value):
		return "%.6f" % float(value)

	func _serialize_vector(value):
		return "%.6f %.6f %.6f" % [value.x, value.y, value.z]
		

	func _serialize_quat(value):
		return str(value.x) + " " + str(value.y) + " " + str(value.z) + " " + str(value.w)

	func _serialize_matrix(value):
		var output_string = ""

		for row in value:
			output_string += "\n"
			output_string += self._write_depth()
			output_string += "("
			for column in row:
				output_string += " "
				output_string += self._serialize_float(column)
			# End For
			output_string += " )"
		# End For

		output_string += "\n"
		output_string += self._write_depth()

		return output_string


	func _serialize_list(value):
		var output_string = ""
		
		var i = 0
		for item in value:
			output_string += self._resolve_type(item)

			# If we're not the last item, add a space
			if i != len(value) - 1:
				output_string += " "
			# End For
			i += 1
		# End For

		return output_string
# End Class

# Nodes are nested for as many children they have
# so it's easier to handle this in its own class.
class NodeWriter:
	var _index = 0

	# Simply create a "children" node.
	func create_children_node(root_node):
		var children_node = root_node.create_child('children')
		return children_node.create_container()

	func write_node_recursively(root_node, model):
		var model_node = model.nodes[self._index]

		var transform_node = root_node.create_child('transform', model_node.name)
		transform_node.create_child('matrix').create_property(model_node.bind_matrix)

		if model_node.child_count == 0:
			return
		# End If

		var children_container_node = self.create_children_node(transform_node)

		for _i in range(model_node.child_count):
			self._index += 1
			self.write_node_recursively(children_container_node, model)
		# End For
# End Class

class LTAWriter:
	var _version = 'not-set'
	
	func format_float(value):
		return "%.6f" % float(value)
	
	func write(model, path, version):
		# Set the version
		self._version = version

		# This is the main node! Everything is a child of this duder.
		var root_node = LTANode.new('world')
		
		#
		# Create the header jazz
		#
		var world_header = root_node.create_child('header')
		var world_header_list = world_header.create_container()
		world_header_list.create_child('versioncode', 2)
		world_header_list.create_child('infostring', model.world_info.properties)
		
		#
		# Polyhedrons!
		#
		var polyhedron_list_node = root_node.create_child('polyhedronlist')
		var polyhedron_list = polyhedron_list_node.create_container()
		
		var node_hierarchy = root_node.create_child('nodehierarchy')
		
		var world_node = node_hierarchy.create_child('worldnode')
		world_node.create_child('type', "___null")
		world_node.create_child('label', 'WorldRoot')
		world_node.create_child('nodeid', 1)
		world_node.create_child('flags').create_property('___worldroot expanded')
		world_node.create_child('properties').create_child('propid', 0)
		var child_list = world_node.create_child('childlist').create_container()
		
		var global_prop_list = root_node.create_child('globalproplist')
		var global_prop_container = global_prop_list.create_container()
		global_prop_container.create_child('proplist').create_container()
		
		root_node.create_child('navigatorposlist').create_container()
		
		var running_node_id = 2
		var running_prop_id = 1
		var running_brush_id = 0
		
		var object_nodes = {}
		
		if model.world_object_data != null:
			for world_object in model.world_object_data.world_objects:
				
				var add_to_object_nodes = false
				
				# Generic fallback
				var label = world_object.name + "_Group"
				
				for prop in world_object.properties:
					var data = prop.get_lta_property_data()
					
					if data[1] == "Name":
						label = data[2]
						add_to_object_nodes = true
						break
					# End If	
				# End If
				
				var header_node = child_list.create_child('worldnode')
				header_node.create_child('type', "___null")
				header_node.create_child('label', label)
				header_node.create_child('nodeid', running_node_id)
				header_node.create_child('flags').create_container()
				header_node.create_child('properties').create_child('propid', 0)
				var object_children = header_node.create_child('childlist').create_container()
				
				running_node_id += 1
				
				# Not confusing at all!
				#for obj in world_object.world_objects:
					
				# Node Hierarchy
					
				var obj_node = object_children.create_child('worldnode')
				obj_node.create_child('type', "___object")
				obj_node.create_child('label', world_object.name) #label to update objects properly in DEdit
				obj_node.create_child('nodeid', running_node_id)
				obj_node.create_child('flags').create_container()
				var node_props = obj_node.create_child('properties')
				node_props.create_child('name', world_object.name)
				node_props.create_child('propid', running_prop_id)
				
				object_nodes[label] = obj_node.create_child('childlist').create_container()

				# Prop List

				# Create the proplist entry
				var prop_list = global_prop_container.create_child('proplist').create_container()
				for prop in world_object.properties:
					var data = prop.get_lta_property_data()
					if data == null:
						continue
					# End if
					
					if len(data) == 3:
						var node = prop_list.create_prop_entry(data[0], data[1], data[2])
					else:
						var node = prop_list.create_prop_entry(data[0], data[1], null)
						if data[2] == "___vector" or data[2] == "___eulerangles":
							var data_node = node.create_child('data')
							if data[2] == "___vector":
								data_node.create_vector_node(data[3])
							else:  # eulerangles
								data_node.create_eulerangles_node(data[3])
						else:
							# Andere 4-Werte Properties
							node.create_property(data[2]).create_property(data[3])
					# End If
				# End For
				
				# Increment those counters!
				running_prop_id += 1
				running_node_id += 1
				# End For

				
				pass
			# End For
		# End If
		
		for world_model in model.world_models:
			if world_model.world_name == "VisBSP":
				continue
				
			# Check if we already have an existing node group
			# If we do, we can be a child again!
			var wm_child_list = null
			
			if world_model.world_name in object_nodes:
				wm_child_list = object_nodes[world_model.world_name]
			else:
				var wm_node = child_list.create_child('worldnode')
				wm_node.create_child('type', '___null')
				wm_node.create_child('label', world_model.world_name)
				wm_node.create_child('nodeid', running_node_id)
				wm_node.create_child('flags').create_container()
				var props = wm_node.create_child('properties')
				props.create_child('propid', 0)
				wm_child_list = wm_node.create_child('childlist').create_container()
			
			running_node_id += 1
			
			var created_brush_node = false
			var allow_multi_edit_polies = false
			if world_model.world_name != "PhysicsBSP":
				allow_multi_edit_polies = true
				
			var running_face_index = 0
			
			var polyhedron = polyhedron_list.create_child('polyhedron')
			var polyhedron_container = polyhedron.create_container()
			polyhedron_container.create_child('color', [255, 255, 255])
			var point_list = polyhedron_container.create_child('pointlist')
				
			var poly_list = polyhedron_container.create_child('polylist')
			var poly_list_container = poly_list.create_container()
			
			var saved_poly_points = []
			
			var first_run = true
			for poly in world_model.polies:

				# For sections like PhysicsBSP we can't reliably re-create brush data
				if first_run == false && allow_multi_edit_polies == false:
					created_brush_node = false
					running_face_index = 0
					saved_poly_points = []
					
					# Can't have multiple editpolies? Then let's recreate our parents
					polyhedron = polyhedron_list.create_child('polyhedron')
					polyhedron_container = polyhedron.create_container()
					polyhedron_container.create_child('color', [255, 255, 255])
					point_list = polyhedron_container.create_child('pointlist')
					
					poly_list = polyhedron_container.create_child('polylist')
					poly_list_container = poly_list.create_container()
				# End If
				
				first_run = false
					
				var plane = world_model.planes[poly.plane_index]
				var surface = world_model.surfaces[poly.surface_index]
				
				var face_indexes = []

				# Lazy process the point list...
				for vert in poly.disk_verts:
					var points = world_model.points[vert.vertex_index]
					var search = saved_poly_points.find(points)
					
					# If we already have this face, don't need to create it!
					if search != -1:
						face_indexes.append(search)
						continue

					face_indexes.append(running_face_index) 
					#point_list.create_property([ points.x, points.y, points.z, 255, 255, 255, 255 ])
					point_list.create_property([points.x, points.y, points.z])

					running_face_index += 1
				# End For
			

				var edit_poly = poly_list_container.create_child('editpoly')
				
				var f_node = edit_poly.create_child('f', face_indexes)
				
				var normal = [plane.normal.x, plane.normal.y, plane.normal.z]
				var n_node = edit_poly.create_child('n', normal)
				
				var distance_node = edit_poly.create_child('dist', plane.distance)
				
				var texture_name = "missing_texture"
				var texture_index = 0

				if "texture_index" in poly:
					texture_index = poly.texture_index
				else:
					texture_index = surface.texture_index

				if texture_index >= 0 and texture_index < world_model.texture_names.size():
					texture_name = world_model.texture_names[texture_index].name
				else:
					push_error("Ungueltiger Texturindex: %d (WorldModel '%s', %d Texturen)" % [
						texture_index, world_model.world_name, world_model.texture_names.size()
					])
					
				var texture_info_node = edit_poly.create_child('textureinfo')
				

				if "uv1" in poly and poly.uv1 != null:
					texture_info_node.create_property([poly.uv1.x, poly.uv1.y, poly.uv1.z])
					texture_info_node.create_property([poly.uv2.x, poly.uv2.y, poly.uv2.z])
					texture_info_node.create_property([poly.uv3.x, poly.uv3.y, poly.uv3.z])
					
				else:
					texture_info_node.create_property([surface.uv1.x, surface.uv1.y, surface.uv1.z])
					texture_info_node.create_property([surface.uv2.x, surface.uv2.y, surface.uv2.z])
					texture_info_node.create_property([surface.uv3.x, surface.uv3.y, surface.uv3.z])

				
				texture_info_node.create_child('sticktopoly', 1)
				texture_info_node.create_child('name', texture_name)
				
				edit_poly.create_child('flags')
				edit_poly.create_child('shade', [0,0,0])
				# edit_poly.create_child('physicsmaterial', 'Default')
				# edit_poly.create_child('surfacekey', "")
				# edit_poly.create_child('textures').create_container()
				
				# If we've already created the brush node and props,
				# we don't need to do it again!
				if created_brush_node == true:
					continue
				
				# Okay create the rest...
				
				# Create the childlist node entry
				var p_node = wm_child_list.create_child('worldnode')
				p_node.create_child('type', '___brush')
				p_node.create_child('brushindex', running_brush_id)
				p_node.create_child('nodeid', running_node_id)
				p_node.create_child('flags').create_container()
				var p_props = p_node.create_child('properties')
				p_props.create_child('name', 'Brush')
				p_props.create_child('propid', running_prop_id)
				
				# Create the proplist entry
				var prop_list = global_prop_container.create_child('proplist').create_container()
				prop_list.create_prop_entry('string', 'Name', "Brush_" + world_model.world_name + "_" + str(running_prop_id))

				var pos_prop = prop_list.create_child('vector', 'Pos')
				pos_prop.create_container()
				var pos_data = pos_prop.create_child('data')
				pos_data.create_vector_node(Vector3(0.0, 0.0, 0.0))

				var rot_prop = prop_list.create_child('rotation', 'Rotation')
				rot_prop.create_container()
				var rot_data = rot_prop.create_child('data')
				rot_data.create_eulerangles_node(Vector3(0.0, 0.0, 0.0))
				
				# Holy heck!
				prop_list.create_prop_entry('bool', 'Solid', int( surface.flags & (1<<0) != 0 ))
				prop_list.create_prop_entry('bool', 'Nonexistant', int( surface.flags & (1<<1) != 0 ))
				#prop_list.create_prop_entry('bool', 'Invisible', int( surface.flags & (1<<2) != 0 ))
				#Fix for translucent world models:
				# Invisible just if all Faces of the WorldModel have Invisible.dtx
				var all_invisible_dtx = true
				for check_poly in world_model.polies:
					var check_tex_idx = check_poly.texture_index if "texture_index" in check_poly else world_model.surfaces[check_poly.surface_index].texture_index
					var check_tex_name = ""
					if check_tex_idx >= 0 and check_tex_idx < world_model.texture_names.size():
						check_tex_name = world_model.texture_names[check_tex_idx].name
					if not ("invisible" in check_tex_name.to_lower()):
						all_invisible_dtx = false
						break

				prop_list.create_prop_entry('bool', 'Invisible', int(all_invisible_dtx))
				
				prop_list.create_prop_entry('bool', 'Translucent', int( surface.flags & (1<<3) != 0 ))
				prop_list.create_prop_entry('bool', 'SkyPortal', int( surface.flags & (1<<4) != 0 ))
				prop_list.create_prop_entry('bool', 'FullyBright', int( surface.flags & (1<<5) != 0 ))
				prop_list.create_prop_entry('bool', 'FlatShade', int( surface.flags & (1<<6) != 0 ))
				prop_list.create_prop_entry('bool', 'GouraudShade', int( surface.flags & (1<<12) != 0 ))
				prop_list.create_prop_entry('bool', 'LightMap', int( surface.flags & (1<<7) != 0 ))
				prop_list.create_prop_entry('bool', 'Subdivide', int( surface.flags & (1<<8) == 0 )) # Flipped!
				prop_list.create_prop_entry('bool', 'HullMaker', int( surface.flags & (1<<9) != 0 ))
				prop_list.create_prop_entry('bool', 'AlwaysLightMap', int( surface.flags & (1<<10) != 0 ))
				prop_list.create_prop_entry('bool', 'DirectionalLight', int( surface.flags & (1<<11) != 0 ))
				prop_list.create_prop_entry('bool', 'Portal', int( surface.flags & (1<<13) != 0 ))
				prop_list.create_prop_entry('bool', 'NoSnap', ( 1 ))
				prop_list.create_prop_entry('bool', 'SkyPan', int( surface.flags & (1<<15) != 0 ))
				prop_list.create_prop_entry('bool', 'Additive', int( surface.flags & (1<<19) != 0 ))
				prop_list.create_prop_entry('bool', 'TerrainOccluder', int( surface.flags & (1<<18) != 0 ))
				prop_list.create_prop_entry('bool', 'TimeOfDay', int( surface.flags & (1<<20) != 0 ))
				prop_list.create_prop_entry('bool', 'VisBlocker', int( surface.flags & (1<<21) != 0 ))
				prop_list.create_prop_entry('bool', 'NotAStep', int( surface.flags & (1<<22) != 0 ))
				#prop_list.create_prop_entry('bool', 'NoWallWalk', int( surface.flags & (1<<23) != 0 ))
				#prop_list.create_prop_entry('bool', 'BlockLight', int( surface.flags & (1<<24) == 0 ))
				# var block_light = int(surface.flags & (1 << 30) != 0)
				# prop_list.create_prop_entry('bool', 'BlockLight', block_light)

				prop_list.create_prop_entry('longint', 'DetailLevel', 0)
				#prop_list.create_prop_entry('string', 'Effect', '')
				#prop_list.create_prop_entry('string', 'EffectParam', '')
				if surface.use_effects == 1:
					prop_list.create_prop_entry('string', 'Effect', surface.effect_name)
					prop_list.create_prop_entry('string', 'EffectParam', surface.effect_param)
				else:
					prop_list.create_prop_entry('string', 'Effect', null)
					prop_list.create_prop_entry('string', 'EffectParam', null)
				prop_list.create_prop_entry('real', 'FrictionCoefficient', 1.000000)
				
				created_brush_node = true
				
				running_prop_id += 1
				running_brush_id += 1
				running_node_id += 1
				
			# End For
		# End For
		
		##########################################################
		# WRITE TO FILE
		##########################################################

		var file = File.new()
		file.open(path, File.WRITE)
		root_node.serialize_to_file(file)  # statt file.store_string(root_node.serialize())
		file.close()
		
		print("Finished serializing node list!")
		
		var dtx_reader = preload("res://Addons/DTXReader/TextureBuilder.gd").new()
		
		var txt_path = path + "_missing_tex.txt"

		print("Finished!")
		
		return OK

	# End func
# End Class
