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

	func create_property(value=''):
		return self.create_child('', value)

	func create_container():
		return self.create_child('', null)

	func create_child(name, attribute=null):
		var node = LTANode.new(name, attribute)
		node._depth = self._depth + 1
		self._children.append(node)
		return node

	func create_prop_entry(type, name, data):
		var item = self.create_child(type, name)
		item.create_container()
		if data != null and not (typeof(data) == TYPE_STRING and data.strip_edges() == ""):
			item.create_child('data', data)
		return item

	func serialize():
		var output_string = self._write_depth() + "(" + self._name + " "
		if self._attribute != null:
			output_string += self._resolve_type(self._attribute)
		if len(self._children) == 0:
			output_string += ")\n"
			return output_string
		output_string += "\n"
		for child in self._children:
			output_string += child.serialize()
		output_string += self._write_depth() + ")\n"
		return output_string

	func _write_depth():
		var output_string = ""
		for _i in range(self._depth):
			output_string += "\t"
		return output_string

	func _resolve_type(value):
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
		if value.find("___") == 0:
			value.erase(0, 3)
			return value
		return "\"" + value + "\""

	func _serialize_float(value):
		return str(value)

	func _serialize_vector(value):
		return str(value.x) + " " + str(value.y) + " " + str(value.z)

	func _serialize_quat(value):
		return str(value.x) + " " + str(value.y) + " " + str(value.z) + " " + str(value.w)

	func _serialize_matrix(value):
		var output_string = ""
		for row in value:
			output_string += "\n" + self._write_depth() + "("
			for column in row:
				output_string += " " + self._serialize_float(column)
			output_string += " )"
		output_string += "\n" + self._write_depth()
		return output_string

	func _serialize_list(value):
		var output_string = ""
		for i in range(value.size()):
			output_string += self._resolve_type(value[i])
			if i != value.size() - 1:
				output_string += " "
		return output_string

class LTAWriter:
	const CLASS_GROUP_MAP = {
		"AINode": "AINodes",
		"AINodeCover": "AINodes",
		"AINodePatrol": "AINodes",
		"Trigger": "Triggers",
		"Switch": "Switches",
		"SpawnPoint": "Spawns",
		"WorldModel": "Brushes",
		"Default": "Objects"
	}

	const ALLOWED_PROPS = {
		"brush": [
			"Name", "Pos", "Rotation", "Solid", "Nonexistant", "Invisible", "Translucent", "SkyPortal",
			"FullyBright", "FlatShade", "GouraudShade", "LightMap", "Subdivide", "HullMaker",
			"AlwaysLightMap", "DirectionalLight", "Portal", "NoSnap", "SkyPan", "Additive",
			"TerrainOccluder", "TimeOfDay", "VisBlocker", "NotAStep", "NoWallWalk", "BlockLight",
			"DetailLevel", "Effect", "EffectParam", "FrictionCoefficient"
		],
		"object": [
			"Name", "Class", "Pos", "Rotation", "StartOn", "TriggerOnce", "RemoveWhenDone",
			"SoundName", "Volume", "Target", "KeyList", "ModelName", "Filename", "Health",
			"HitPoints", "Command0", "Command1", "Command2", "Command3", "Locked", "LoopSound"
		]
	}

	func is_prop_allowed(prop_name: String, type: String) -> bool:
		if not ALLOWED_PROPS.has(type):
			return false
		return prop_name in ALLOWED_PROPS[type]

	func get_pos_from_props(props: Array) -> Vector3:
		for p in props:
			if p.name == "Pos" and typeof(p.value) == TYPE_VECTOR3:
				return p.value
		return Vector3(0, 0, 0)

	func get_rot_from_props(props: Array) -> Vector3:
		for p in props:
			if p.name == "Rotation" and typeof(p.value) == TYPE_VECTOR3:
				return p.value
		return Vector3(0, 0, 0)

	func group_objects_by_class(world_objects: Array) -> Dictionary:
		var result := {}
		for obj in world_objects:
			var obj_class_name = "Default"
			for prop in obj.properties:
				if prop.name == "Class" and prop.code == 0: # PROP_STRING
					obj_class_name = prop.value
					break
			var group = CLASS_GROUP_MAP.get(obj_class_name, CLASS_GROUP_MAP["Default"])
			if not result.has(group):
				result[group] = []
			result[group].append({ "object": obj, "class_type": obj_class_name })
		return result

	func fix_property_data(data: Array) -> Array:
		if len(data) < 3:
			return data
		var type = data[0]
		var name = data[1]
		var value = data[2]

		# Volume bleibt in ltb_ps2 gefixt, daher hier keine Anpassung

		# Boolean-Strings fixen
		var bool_names = ["StartOn", "TriggerOnce", "RemoveWhenDone", "Locked", "LoopSound"]
		if name in bool_names:
			if typeof(value) == TYPE_STRING:
				value = value.strip_edges().to_lower() in ["true", "1", "yes"]
			elif typeof(value) == TYPE_INT:
				value = value != 0
			type = "bool"
			return [type, name, value]

		# KeyList → Array
		if name == "KeyList" and typeof(value) == TYPE_STRING:
			var keys = value.split(",")
			return ["array", name, keys]

		return data

	var _version = 'not-set'

	func write(model, path, version):
		self._version = version
		var root_node = LTANode.new('world')

		# Header
		var world_header = root_node.create_child('header')
		var world_header_list = world_header.create_container()
		world_header_list.create_child('versioncode', 2)
		world_header_list.create_child('infostring', model.world_info.properties)

		var polyhedron_list_node = root_node.create_child('polyhedronlist')
		var polyhedron_list = polyhedron_list_node.create_container()

		var node_hierarchy = root_node.create_child('nodehierarchy')
		var world_node = node_hierarchy.create_child('worldnode')
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

		# Welt-Objekte
		if model.world_object_data != null:
			var grouped = self.group_objects_by_class(model.world_object_data.world_objects)
			for group_name in grouped.keys():
				var container_node = child_list.create_child('worldnode')
				container_node.create_child('label', group_name)
				container_node.create_child('nodeid', running_node_id)
				container_node.create_child('flags').create_container()
				container_node.create_child('properties').create_child('propid', 0)
				var container_child_list = container_node.create_child('childlist').create_container()
				running_node_id += 1

				var entries = grouped[group_name]
				for i in range(entries.size()):
					var entry = entries[i]
					var obj = entry["object"]
					var class_type = entry["class_type"]
					var label = class_type + "_" + str(i)

					var obj_node = container_child_list.create_child('worldnode')
					obj_node.create_child('type', "___object")
					obj_node.create_child('label', label)
					obj_node.create_child('nodeid', running_node_id)
					obj_node.create_child('flags').create_container()
					obj_node.create_child('pos', ['___vector', self.get_pos_from_props(obj.properties)])
					obj_node.create_child('rotation', ['___eulerangles', self.get_rot_from_props(obj.properties)])
					obj_node.create_child('scale', ['___vector', Vector3(1, 1, 1)])

					var prop_list = global_prop_container.create_child('proplist').create_container()
					for prop in obj.properties:
						if not self.is_prop_allowed(prop.name, "object"):
							continue
						var data = prop.get_lta_property_data()
						if data == null:
							continue
						data = self.fix_property_data(data)
						if len(data) == 3:
							prop_list.create_prop_entry(data[0], data[1], data[2])
						else:
							prop_list.create_prop_entry(data[0], data[1], null).create_property(data[2]).create_property(data[3])

					running_prop_id += 1
					running_node_id += 1

		# Brushes
		for world_model in model.world_models:
			if world_model.world_name == "VisBSP":
				continue

			var wm_node = child_list.create_child('worldnode')
			wm_node.create_child('label', world_model.world_name)
			wm_node.create_child('nodeid', running_node_id)
			wm_node.create_child('flags').create_container()
			var props = wm_node.create_child('properties')
			props.create_child('propid', 0)
			var wm_child_list = wm_node.create_child('childlist').create_container()
			running_node_id += 1

			var created_brush_node = false
			var allow_multi_edit_polies = world_model.world_name != "PhysicsBSP"
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
				if first_run == false and not allow_multi_edit_polies:
					created_brush_node = false
					running_face_index = 0
					saved_poly_points = []
					polyhedron = polyhedron_list.create_child('polyhedron')
					polyhedron_container = polyhedron.create_container()
					polyhedron_container.create_child('color', [255, 255, 255])
					point_list = polyhedron_container.create_child('pointlist')
					poly_list = polyhedron_container.create_child('polylist')
					poly_list_container = poly_list.create_container()
				first_run = false

				var plane = world_model.planes[poly.plane_index]
				var surface = world_model.surfaces[poly.surface_index]
				var face_indexes = []
				for vert in poly.disk_verts:
					var points = world_model.points[vert.vertex_index]
					var search = saved_poly_points.find(points)
					if search != -1:
						face_indexes.append(search)
						continue
					face_indexes.append(running_face_index)
					point_list.create_property([points.x, points.y, points.z, 255, 255, 255, 255])
					running_face_index += 1

				var edit_poly = poly_list_container.create_child('editpoly')
				edit_poly.create_child('f', face_indexes)
				edit_poly.create_child('n', plane.normal)
				edit_poly.create_child('dist', plane.distance)
				var texture_name = "missing_texture"
				if surface.texture_index >= 0 and surface.texture_index < model.texture_list.size():
					texture_name = model.texture_list[surface.texture_index]
				var texture_info_node = edit_poly.create_child('textureinfo')
				texture_info_node.create_property(surface.uv1)
				texture_info_node.create_property(surface.uv2)
				texture_info_node.create_property(surface.uv3)
				texture_info_node.create_child('sticktopoly', 1)
				texture_info_node.create_child('name', texture_name)
				edit_poly.create_child('flags')
				edit_poly.create_child('shade', [0, 0, 0])

				if created_brush_node:
					continue
				var p_node = wm_child_list.create_child('worldnode')
				p_node.create_child('type', '___brush')
				p_node.create_child('brushindex', running_brush_id)
				p_node.create_child('nodeid', running_node_id)
				p_node.create_child('flags').create_container()
				var p_props = p_node.create_child('properties')
				p_props.create_child('name', 'Brush')
				p_props.create_child('propid', running_prop_id)
				var prop_list = global_prop_container.create_child('proplist').create_container()
				prop_list.create_prop_entry('string', 'Name', "Brush_" + world_model.world_name + "_" + str(running_prop_id))
				prop_list.create_prop_entry('vector', 'Pos', null).create_property('vector').create_property(Vector3(0,0,0))
				prop_list.create_prop_entry('rotation', 'Rotation', null).create_property('eulerangles').create_property(Vector3(0,0,0))
				prop_list.create_prop_entry('bool', 'Solid', int(surface.flags & (1<<0) != 0))
				created_brush_node = true
				running_prop_id += 1
				running_brush_id += 1
				running_node_id += 1

		# Schreiben
		var file = File.new()
		file.open(path, File.WRITE)
		file.store_string(root_node.serialize())
		file.close()
		print("Finished serializing node list!")
		return OK
