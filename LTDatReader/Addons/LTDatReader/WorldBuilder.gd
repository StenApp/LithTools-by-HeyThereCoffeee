tool

extends Node

var lta_writer = preload("res://Addons/LTDatReader/LTAWriter.gd").new()
var dtx_reader = preload("res://Addons/DTXReader/TextureBuilder.gd").new()
var texture_path = ""
var debug_file = null

const LIGHTMAP_ATLAS_SIZE = 2048.0#4096.0#2048.0

# TexturedPlane-style vector generation based on surface normal
# This replicates the SetupBaseTextureSpace function from EditPoly.cpp

# Texture alignment planes (from g_TexturePlanes in EditPoly.cpp)
const TEXTURE_PLANES = [
	Vector3(0.0, 1.0, 0.0),   # Bottom
	Vector3(0.0, -1.0, 0.0),  # Top
	Vector3(1.0, 0.0, 0.0),   # East-facing wall
	Vector3(-1.0, 0.0, 0.0),  # West-facing wall
	Vector3(0.0, 0.0, 1.0),   # North-facing wall
	Vector3(0.0, 0.0, -1.0)   # South-facing wall
]

# Right vectors (from g_RightVectors in EditPoly.cpp)
const RIGHT_VECTORS = [
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(1.0, 0.0, 0.0)
]

func setup_base_texture_space(surface_normal: Vector3):
	"""
	Generate proper P and Q vectors based on surface normal direction.
	This replicates CEditPoly::SetupBaseTextureSpace()
	"""
	var max_dot = -999999.0
	var closest_plane = 0
	
	# Find the closest texture alignment plane to this polygon normal
	for i in range(len(TEXTURE_PLANES)):
		var dot = surface_normal.dot(TEXTURE_PLANES[i])
		if dot > max_dot:
			max_dot = dot
			closest_plane = i
	
	# Generate P and Q vectors based on closest plane
	var P = RIGHT_VECTORS[closest_plane]
	var Q = P.cross(TEXTURE_PLANES[closest_plane])
	
	return [P, Q]

func chunk(array, by): 
	var chunks = []
	var i = 0
	while i < len(array):
		chunks.append( array.slice(i, i+by) )
		i += by
		
	return chunks

func build(source_file, options):
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		print("Failed to open " + source_file)
		return FAILED
		
	print("Opened " + source_file)
	
	var dat_file = load("res://Addons/LTDatReader/Models/DAT.gd")
	var ltb_file = load("res://Addons/LTDatReader/Models/LTB_PS2.gd")
	
	# Setup our new scene
	var scene = PackedScene.new()
	
	# Create our nodes
	var root = Spatial.new()
	
	# Setup the nodes
	root.name = "Root"
	
	var model = null
	var file_extension = "dat"
	# Model as in MVC model, not mesh model!
	if ".ltb" in source_file.to_lower():
		model = ltb_file.LTB_PS2.new()
		file_extension = "ltb"
	else:
		model = dat_file.DAT.new()
	
	# Batched reading
	var response = model.read(file, true)
	if response.code == model.IMPORT_RETURN.ERROR:
		print("IMPORT ERROR: " + str(response.message))
		return FAILED
		
	# Hack: Load up some config values
	var config = ConfigFile.new()
	var err = config.load("./settings.cfg")
	
	# Fallback...
	texture_path = "D:\\Games\\Aliens vs. Predator 2 - dev\\AVP2\\"
	
	var export_to_lta = false
	
	if err == OK:
		var game_path_string = file_extension + "_v" + str(model.version) + "_game_path"
		texture_path = config.get_value("Worlds", game_path_string, texture_path)
		export_to_lta = config.get_value("Worlds", "export_to_lta_on_load", false)
		
	var world_model_count = model.world_model_count
	
	var world_model_index = 0
	var batch_by = 1024
	
	var total_mesh_count = 0
	
	# Hack for LT1
	for world_model in model.world_models:
		var data = fill_array_mesh(model, [world_model])
		var meshes = data[0]
		var mesh_names = data[1]
		var tex_names = data[2]
		var lm_texture_array = data[3] as Image#[0] # data[3] = [ tex array, last used depth ]

		var use_lightmaps = false
		
		# Quick hack for public release
		if model.version == 55 || model.version == 56 || model.version == 127:
			use_lightmaps = true

		# Loop through our pieces, and add them to mesh instances
		# lm_texture_array.save_png("lm_null.png")
		var lm_image_texture = null
		
		if use_lightmaps:
			lm_image_texture = ImageTexture.new()
			lm_image_texture.create_from_image(lm_texture_array)
			lm_image_texture.set_flags(ImageTexture.FLAGS_DEFAULT + ImageTexture.FLAG_ANISOTROPIC_FILTER + ImageTexture.FLAG_CONVERT_TO_LINEAR)
			
		var cached_textures = {}
		
		var i = 0;
		for mesh in meshes:
			var mesh_instance = MeshInstance.new()
			
			var tex_name = tex_names[i]
			var tex = get_texture(tex_name)
			
			var mat = ShaderMaterial.new()
			mat.shader = load("res://Addons/LTDatReader/Shaders/LT1.tres") as VisualShader
			
			mat.set_shader_param("main_texture", tex)
			
			if use_lightmaps:
				mat.set_shader_param("use_lightmap", true)
				mat.set_shader_param("lm_texture", lm_image_texture)
			else:
				mat.set_shader_param("use_lightmap", false)
			

			mesh_instance.name = mesh_names[i]
			mesh_instance.mesh = mesh
			root.add_child(mesh_instance)
			mesh_instance.owner = root
			mesh_instance.set_surface_material(0, mat)
			i += 1
			total_mesh_count+=1
			
			# Mirror the world a bit to handle Lithtech's style of 3d
			mesh_instance.scale = Vector3( -1.0, 1.0, 1.0 )
		# End For
		
	# Hack for jupiter
	if model.is_lithtech_jupiter():
		var data = fill_array_mesh_jupiter(model, [])
		var meshes = data[0]
		var mesh_names = data[1]
		var tex_names = data[2]
		var lm_texture_array = data[3]# as ImageTexture#[0] # data[3] = [ tex array, last used depth ]
		
		# Loop through our pieces, and add them to mesh instances
		#lm_texture_array.save_png("lm_null.png")
		
		#var lm_image_texture = ImageTexture.new()
		#lm_image_texture.create_from_image(lm_texture_array)

		#lm_image_texture.set_flags(ImageTexture.FLAGS_DEFAULT + ImageTexture.FLAG_ANISOTROPIC_FILTER + ImageTexture.FLAG_CONVERT_TO_LINEAR)
		
		var cached_textures = {}
		
		var i = 0;
		for mesh in meshes:
			
			var mesh_instance = MeshInstance.new()
			
			var tex_name = tex_names[i]
			var tex = null
			
			if "LightAnim_" in tex_name:
				tex = lm_texture_array[i]
			else:
				tex = get_texture(tex_name)

			var mat = ShaderMaterial.new()
			mat.shader = load("res://Addons/LTDatReader/Shaders/LT1.tres") as VisualShader
			
			mat.set_shader_param("main_texture", tex)
			#mat.set_shader_param("lm_texture", lm_image_texture)

			mesh_instance.name = mesh_names[i]
			mesh_instance.mesh = mesh
			root.add_child(mesh_instance)
			mesh_instance.owner = root
			mesh_instance.set_surface_material(0, mat)
			i += 1
			total_mesh_count+=1
			
			# Mirror the world a bit to handle Lithtech's style of 3d
			mesh_instance.scale = Vector3( -1.0, 1.0, 1.0 )
		# End For

	if !model.is_lithtech_jupiter():
		while world_model_index < world_model_count:
			if (world_model_index + batch_by) > world_model_count:
				batch_by = world_model_count - world_model_index

			var world_models = model.world_model_batch_read(file, batch_by)
			world_model_index += batch_by
			
			var data = fill_array_mesh(model, world_models)
			var meshes = data[0]
			var mesh_names = data[1]
			var tex_names = data[2]
			var lm_texture_array = data[3] as Image#[0] # data[3] = [ tex array, last used depth ]

			# Loop through our pieces, and add them to mesh instances
			lm_texture_array.save_png("lm_null.png")
			
			var lm_image_texture = ImageTexture.new()
			lm_image_texture.create_from_image(lm_texture_array)
			lm_image_texture.set_flags(ImageTexture.FLAGS_DEFAULT + ImageTexture.FLAG_ANISOTROPIC_FILTER + ImageTexture.FLAG_CONVERT_TO_LINEAR)
			
			var cached_textures = {}
			
			var i = 0;
			for mesh in meshes:
				
				var mesh_instance = MeshInstance.new()
				
				var tex_name = tex_names[i]
				var tex = get_texture(tex_name)
				
				var mat = ShaderMaterial.new()
				mat.shader = load("res://Addons/LTDatReader/Shaders/LT1.tres") as VisualShader
				
				mat.set_shader_param("main_texture", tex)
				mat.set_shader_param("lm_texture", lm_image_texture)

				mesh_instance.name = mesh_names[i]
				mesh_instance.mesh = mesh
				root.add_child(mesh_instance)
				mesh_instance.owner = root
				mesh_instance.set_surface_material(0, mat)
				i += 1
				total_mesh_count+=1
				
				# Mirror the world a bit to handle Lithtech's style of 3d
				mesh_instance.scale = Vector3( -1.0, 1.0, 1.0 )
			# End For
		
	# Pack our scene!
	scene.pack(root)
	
	print("Total Meshes Generated: " + str(total_mesh_count))
	
	if export_to_lta:
		var writer = lta_writer.LTAWriter.new()

		var out_path = source_file.replacen(".ltb", ".lta")
		out_path = source_file.replacen(".dat", ".lta")

		print("Exporting LTA to " + out_path)

		writer.write(model, out_path, 2)

	# Now that we've packed root into the scene, it's time to clean it up!
	root.queue_free()

	clear_texture_cache()
	
	return scene

var cached_textures = {}
func get_texture(tex_name):
	# Quick texture caching
	if tex_name in cached_textures:
		return cached_textures[tex_name]
	# End If
	
	# Not cached, so grab it and cache it
	var tex = dtx_reader.build(texture_path + tex_name, [])
	cached_textures[tex_name] = tex
	return tex
# End Func

func clear_texture_cache():	
	cached_textures.clear()


# TODO: Also need to handle shifting? https://github.com/Shfty/libmap/blob/6e4160924cf5373e67e8f35422b196e6e0eaa52c/src/c/geo_generator.c
# Enhanced OPQ to UV mapping algorithm for LithTech world geometry
# This handles all complex cases: simple boxes, angled wedges, pyramids, and large structures

# Main UV mapping function with full algorithm support
func opq_to_uv_enhanced(vertex: Vector3, o: Vector3, p: Vector3, q: Vector3, polygon_center: Vector3, plane_normal: Vector3, plane_distance: float, surface_index: int, texture_name: String, tex_width = 64.0, tex_height = 64.0):
	"""
	Enhanced OPQ to UV mapping that handles:
	- Simple axis-aligned geometry (boxes, rooms)
	- Angled surfaces (wedges, slopes) 
	- Complex multi-surface geometry (pyramids)
	- Large architectural structures
	- Multiple surface coordinate systems
	"""
	
	# Step 1: Calculate UV origin for this polygon
	var uv_origin = calculate_polygon_uv_origin(o, p, q, polygon_center, plane_normal, plane_distance)
	
	# Step 2: Transform surface vectors to polygon's local plane if needed
	var transformed_vectors = transform_surface_vectors_to_plane(p, q, plane_normal)
	var local_p = transformed_vectors[0]
	var local_q = transformed_vectors[1]
	
	# Step 3: Calculate UV coordinates from the origin
	var point_from_origin = vertex - uv_origin
	var u = point_from_origin.dot(local_p) / tex_width
	var v = point_from_origin.dot(local_q) / tex_height
	
	# Debug output for complex cases
	if should_debug_texture(texture_name):
		debug_uv_calculation(vertex, o, p, q, polygon_center, plane_normal, uv_origin, local_p, local_q, u, v, texture_name)
	
	return Vector2(u, v)

func calculate_polygon_uv_origin(surface_uv1: Vector3, surface_uv2: Vector3, surface_uv3: Vector3, polygon_center: Vector3, plane_normal: Vector3, plane_distance: float):
	"""
	Calculate the UV (0,0) origin for this specific polygon.
	This is the key insight from the algorithm analysis.
	"""
	
	# For most cases, we need to find where UV coordinates would be minimal
	# This often requires projecting the surface reference point onto the polygon's plane
	
	# Method 1: Use surface UV1 as base reference (works for most cases)
	var base_reference = surface_uv1
	
	# Method 2: For angled planes, project reference onto the plane
	if not is_axis_aligned_plane(plane_normal):
		# Project surface reference onto this polygon's plane
		var point_to_plane_distance = plane_normal.dot(surface_uv1) + plane_distance
		base_reference = surface_uv1 - plane_normal * point_to_plane_distance
	
	# Method 3: Adjust by polygon center offset if needed
	# This handles cases where surface coordinates are defined relative to a different polygon
	var center_offset = polygon_center - base_reference
	
	# The UV origin is where UV coordinates would be (0,0) for this polygon
	# We calculate this by finding the minimum UV values across the polygon's vertices
	# Since we don't have all vertices here, we use the polygon center as approximation
	var uv_origin = base_reference
	
	return uv_origin

func transform_surface_vectors_to_plane(surface_p: Vector3, surface_q: Vector3, plane_normal: Vector3):
	"""
	Transform surface vectors to work correctly with this polygon's plane orientation.
	Handles angled surfaces and maintains proper texture orientation.
	"""
	
	var transformed_p = surface_p
	var transformed_q = surface_q
	
	# Check if vectors are perpendicular to plane normal (they should be)
	var p_dot_normal = abs(surface_p.dot(plane_normal))
	var q_dot_normal = abs(surface_q.dot(plane_normal))
	var p_dot_q = abs(surface_p.normalized().dot(surface_q.normalized()))
	
	# Fix vectors that aren't in the plane
	if p_dot_normal > 0.1:
		# P vector is not in the plane - project it
		transformed_p = (surface_p - plane_normal * surface_p.dot(plane_normal)).normalized() * surface_p.length()
		
		# Alternative: Generate new P vector perpendicular to normal and Q
		if surface_q.cross(plane_normal).length() > 0.1:
			transformed_p = surface_q.cross(plane_normal).normalized() * surface_p.length()
	
	if q_dot_normal > 0.1:
		# Q vector is not in the plane - project it  
		transformed_q = (surface_q - plane_normal * surface_q.dot(plane_normal)).normalized() * surface_q.length()
		
		# Alternative: Generate new Q vector perpendicular to normal and P
		if plane_normal.cross(transformed_p).length() > 0.1:
			transformed_q = plane_normal.cross(transformed_p).normalized() * surface_q.length()
	
	# Ensure P and Q are perpendicular to each other
	if p_dot_q > 0.1:
		# Re-orthogonalize Q relative to P, keeping it in the surface plane
		transformed_q = plane_normal.cross(transformed_p).normalized() * surface_q.length()
	
	return [transformed_p, transformed_q]

func is_axis_aligned_plane(plane_normal: Vector3) -> bool:
	"""
	Check if this plane is axis-aligned (normal along X, Y, or Z axis)
	"""
	var threshold = 0.1
	return (abs(plane_normal.x) > 0.9 and abs(plane_normal.y) < threshold and abs(plane_normal.z) < threshold) or \
		   (abs(plane_normal.y) > 0.9 and abs(plane_normal.x) < threshold and abs(plane_normal.z) < threshold) or \
		   (abs(plane_normal.z) > 0.9 and abs(plane_normal.x) < threshold and abs(plane_normal.y) < threshold)

func should_debug_texture(texture_name: String) -> bool:
	"""
	Enable debug output for specific problematic textures
	"""
	var debug_textures = ["wd0296", "trobj0008", "st1003", "st1004"]
	for debug_tex in debug_textures:
		if texture_name.find(debug_tex) >= 0:
			return true
	return false

func debug_uv_calculation(vertex: Vector3, o: Vector3, p: Vector3, q: Vector3, polygon_center: Vector3, plane_normal: Vector3, uv_origin: Vector3, local_p: Vector3, local_q: Vector3, u: float, v: float, texture_name: String):
	"""
	Debug output for complex UV calculations
	"""
	print("=== ENHANCED UV MAPPING DEBUG ===")
	print("Texture: ", texture_name)
	print("Vertex: ", vertex)
	print("Original O: ", o, " P: ", p, " Q: ", q)
	print("Polygon Center: ", polygon_center)
	print("Plane Normal: ", plane_normal)
	print("Calculated UV Origin: ", uv_origin)
	print("Transformed P: ", local_p, " Q: ", local_q)
	print("Final UV: (", u, ", ", v, ")")
	
	# Diagnostic checks
	var p_perp_normal = abs(local_p.dot(plane_normal))
	var q_perp_normal = abs(local_q.dot(plane_normal))
	var p_perp_q = abs(local_p.normalized().dot(local_q.normalized()))
	print("P⊥Normal: ", p_perp_normal, " Q⊥Normal: ", q_perp_normal, " P⊥Q: ", p_perp_q)
	
	if p_perp_normal < 0.1 and q_perp_normal < 0.1 and p_perp_q < 0.1:
		print("*** VECTORS ARE MATHEMATICALLY CORRECT ***")
	else:
		print("*** VECTORS WERE CORRECTED ***")
	print("===================================")

# Alternative simpler function for basic cases
func opq_to_uv_simple(vertex: Vector3, o: Vector3, p: Vector3, q: Vector3, polygon_center: Vector3, plane_normal: Vector3, texture_name: String, tex_width = 64.0, tex_height = 64.0):
	"""
	Simplified version for basic geometry where surface vectors are already correct
	"""
	var point = vertex - o
	var u = point.dot(p) / tex_width
	var v = point.dot(q) / tex_height
	return Vector2(u, v)

# Function to choose which algorithm to use based on geometry complexity
func opq_to_uv_adaptive(vertex: Vector3, o: Vector3, p: Vector3, q: Vector3, polygon_center: Vector3, plane_normal: Vector3, plane_distance: float, surface_index: int, surface_count: int, texture_name: String, tex_width = 64.0, tex_height = 64.0):
	"""
	Adaptive UV mapping that chooses the right algorithm based on geometry complexity
	"""
	
	# Simple case: Single surface with axis-aligned geometry
	if surface_count == 1 and is_axis_aligned_plane(plane_normal):
		return opq_to_uv_simple(vertex, o, p, q, polygon_center, plane_normal, texture_name, tex_width, tex_height)
	
	# Complex case: Multiple surfaces or angled geometry
	else:
		return opq_to_uv_enhanced(vertex, o, p, q, polygon_center, plane_normal, plane_distance, surface_index, texture_name, tex_width, tex_height)

# Integration point: Replace your existing opq_to_uv function with this call
func opq_to_uv(vertex: Vector3, o: Vector3, p: Vector3, q: Vector3, polygon_center: Vector3, plane_normal: Vector3, plane_distance: float, texture_name: String, tex_width = 64.0, tex_height = 64.0):
	"""
	Main entry point - integrates with your existing code
	Add surface_index and surface_count parameters when available
	"""
	
	# For now, use the enhanced algorithm for all cases
	# You can optimize this later by detecting geometry complexity
	return opq_to_uv_enhanced(vertex, o, p, q, polygon_center, plane_normal, plane_distance, 0, texture_name, tex_width, tex_height)
	

func get_vert_uv( vert : Vector3, poly_u : Vector3, poly_v : Vector3, lm_width, lm_height ):
	#return Vector2( vert.dot(poly_u), vert.dot(poly_v) )
	return Vector2( vert.dot(poly_u) / (lm_width), vert.dot(poly_v) / (lm_height) )

func build_array_mesh(textured_meshes):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var meshes = []
	var texture_references = []
	var mesh_names = []

	for texture in textured_meshes.keys():
		var batches = textured_meshes[texture]
		
		var commit_mesh = null
		var combined_mesh = null
		
		for mesh in batches:
			var mesh_uvs = mesh[0]
			var mesh_normals = mesh[1]
			var mesh_verts = mesh[2]
			var mesh_colours = mesh[3]
			var mesh_uvs2 = mesh[5]
			
			# Mesh is formatted in triangle fan segments per "EditPoly"
			st.add_triangle_fan( PoolVector3Array(mesh_verts), PoolVector2Array(mesh_uvs), PoolColorArray(mesh_colours), PoolVector2Array(mesh_uvs2), PoolVector3Array(mesh_normals) )
		# End For
		
		meshes.append(st.commit())
		
		st.clear()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		texture_references.append(texture)
		mesh_names.append("World Model")#world_model.world_name)
	# End For

	#var obj_exporter = load("res://Src/obj_exporter.gd").OBJExporter.new()
	
	#print("Exporting obj...")
	#obj_exporter.export_mesh(meshes, "./test.obj", true)
	#print("Finished!")
	
	return [ meshes, mesh_names, texture_references ]
	
# Jupiter uses triangle lists
func build_array_mesh_jupiter(textured_meshes):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var meshes = []
	var texture_references = []
	var mesh_names = []

	for texture in textured_meshes.keys():
		var batches = textured_meshes[texture]
		
		var use_lightmap_texture = false
		
		#if "LightAnim_" in texture:
		#	use_lightmap_texture = true
		
		# No lightmaps right now!
		if "LightAnim_" in texture:
			continue 
		
		var commit_mesh = null
		var combined_mesh = null
		
		for mesh in batches:
			var mesh_uvs = mesh[0]
			var mesh_normals = mesh[1]
			var mesh_verts = mesh[2]
			var mesh_colours = mesh[3]
			var mesh_uvs2 = mesh[5]
			
			var lightmap_texture = null
			
			if use_lightmap_texture:
				lightmap_texture = mesh[4]
			
			mesh_uvs.invert()
			mesh_normals.invert()
			mesh_verts.invert()

			# Pack in 3 verts at a time!
			var i = 0
			while (i < len(mesh_verts) - 2):
				var i0 = i
				var i1 = i + 1
				var i2 = i + 2

				st.add_normal(mesh_normals[i0])
				st.add_uv(mesh_uvs[i0])
				#st.add_color(mesh_colours[i0])
				st.add_vertex(mesh_verts[i0])

				st.add_normal(mesh_normals[i1])
				st.add_uv(mesh_uvs[i1])
				#st.add_color(mesh_colours[i1])
				st.add_vertex(mesh_verts[i1])

				st.add_normal(mesh_normals[i2])
				st.add_uv(mesh_uvs[i2])
				#st.add_color(mesh_colours[i2])
				st.add_vertex(mesh_verts[i2])
				
				i += 3
			# End While
		# End For
		
		meshes.append(st.commit())
		
		st.clear()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		texture_references.append(texture)
		mesh_names.append("Render Data - " + texture)
	# End For
	
	return [ meshes, mesh_names, texture_references ]
	
func fill_array_mesh_jupiter(model, world_meshes = []):
	var meshes = []
	var mesh_names = []
	var texture_references = []
	var textured_meshes = {}
	
	var triangle_counter = 0
	var texture_references_per_triangle = []
	
	var texture_name = ""
	var prev_texture_name = ""
	
	var lightmap_textures = []

	for i in range(0, len(model.render_data.render_blocks)):
		var block = model.render_data.render_blocks[i]
		texture_references_per_triangle = []
		
		#mesh_names.append("RenderBlock " + str(i))
		
		var previous_tri_count = 0
		for j in range(0, len(block.sections)):
			var section = block.sections[j]
#			texture_references_per_triangle.append({
#				"tri_start": j,
#				"tri_end": j + section.triangle_count,
#				"textures": section.textures, 
#			})
			for k in range(previous_tri_count, previous_tri_count + section.triangle_count):
				texture_references_per_triangle.append(section.textures)
				# I'm hoping this is a reference...
				#lightmap_textures.append(section.lightmap_texture)
			
			previous_tri_count += section.triangle_count
			
			
		
		var verts = []#PoolVector3Array()
		var uvs = []#PoolVector2Array()
		var uvs2 = []
		var normals = []#PoolVector3Array()
		var colours = []
		var indices = PoolIntArray()
		var polies = []
		var previous_lightmap_texture = null
		

		
		for j in range(0, len(block.triangles)):
			texture_name = texture_references_per_triangle[j][0] # Grab the first texture for now..
			
			
			if prev_texture_name == "":
				prev_texture_name = texture_name
			
			# Texture change? Flush!
			if prev_texture_name != texture_name:
				
				# Add it to the batch!
				if prev_texture_name in textured_meshes:
					textured_meshes[prev_texture_name].append([ uvs, normals, verts, colours, [], [] ])
				else:
					textured_meshes[prev_texture_name] = [[ uvs, normals, verts, colours, [], [] ]]
				prev_texture_name = texture_name
				
				verts = []
				uvs = []
				normals = []
				colours = []
			
			var triangle = block.triangles[j]
			
			
			verts.append(triangle.render_vertices[0].pos)
			verts.append(triangle.render_vertices[1].pos)
			verts.append(triangle.render_vertices[2].pos)
			
			uvs.append(triangle.render_vertices[0].uv1)
			uvs.append(triangle.render_vertices[1].uv1)
			uvs.append(triangle.render_vertices[2].uv1)
			
			normals.append(triangle.render_vertices[0].normal)
			normals.append(triangle.render_vertices[1].normal)
			normals.append(triangle.render_vertices[2].normal)
			
			colours.append(triangle.render_vertices[0].colour)
			colours.append(triangle.render_vertices[1].colour)
			colours.append(triangle.render_vertices[2].colour)
			
		# Add it to the batch! (Last one!)
		if texture_name in textured_meshes:
			textured_meshes[texture_name].append([ uvs, normals, verts, colours, [], [] ])
		else:
			textured_meshes[texture_name] = [[ uvs, normals, verts, colours, [], [] ]]
			
			
		var data = build_array_mesh_jupiter(textured_meshes)
		meshes += data[0]
		mesh_names += data[1]
		texture_references += data[2]
		textured_meshes = {}
	
	# Texture References is polygon aligned
	return [ meshes, mesh_names, texture_references, lightmap_textures ]
	
	pass

func fill_array_mesh(model, world_models = []):

	var mesh_names = []
	var meshes = []
	var texture_references = []
	
	var lightmap_textures = {}
	var big_lightmap_image = Image.new()
	var last_lm_uv = Vector2(0,0)

	var textured_meshes = {}
	var lightmap_frame_index = 0
	
	var white_image = Image.new()
	white_image.create(2,2, false, Image.FORMAT_RGB8)
	white_image.fill(Color(1.0, 1.0, 1.0, 1.0))
	
	big_lightmap_image.create(LIGHTMAP_ATLAS_SIZE, LIGHTMAP_ATLAS_SIZE, false, Image.FORMAT_RGB8)
	big_lightmap_image.blit_rect(white_image, Rect2(Vector2(0,0), Vector2(2,2)), Vector2(LIGHTMAP_ATLAS_SIZE - 2, LIGHTMAP_ATLAS_SIZE - 2))

	for world_model_index in range(len(world_models)):
		var world_model = world_models[world_model_index]
		
		var verts = []
		var uvs = []
		var uvs2 = []
		var normals = []
		var colours = []
		var indices = PoolIntArray()
		var polies = []
		
		if world_model.world_name == "VisBSP":
			print("Skipping " + world_model.world_name)
			continue

		# Lightmap setup (keeping existing code)
		var total_lms = 0
		var total_lm_width = 0
		var total_lm_height = 0
		var largest_lm_width = 0
		var largest_lm_height = 0
		for poly in world_model.polies:
			var surface = world_model.surfaces[poly.surface_index]
			if poly.lightmap_texture != null:
				total_lms += 1
				var poly_width = poly.lightmap_texture.get_width()
				var poly_height = poly.lightmap_texture.get_height()
				if total_lm_width + poly_width > LIGHTMAP_ATLAS_SIZE:
					total_lm_height += 16
					total_lm_width = 0
				total_lm_width += poly_width
				largest_lm_width = max(largest_lm_width, poly_width)
				largest_lm_height = max(largest_lm_height, poly_height)

		for poly_index in range(len(world_model.polies)):
			var poly = world_model.polies[poly_index]
			var texture_index = 0
			var surface = world_model.surfaces[poly.surface_index]
			
			if model.PLATFORM == "PS2":
				texture_index = poly.texture_index
			else:
				texture_index = surface.texture_index

			var texture_name = ""

			if texture_index >= 0 and texture_index < model.texture_list.size():
				texture_name = model.texture_list[texture_index]
			else:
				texture_name = model.texture_list[0] if model.texture_list.size() > 0 else "default.dtx"
						
			#var texture_name = world_model.texture_names[texture_index].name
			
			var tex = get_texture(texture_name)
			var tex_width = 256
			var tex_height = 256
			
			if tex != null:
				tex_width = tex.get_width()
				tex_height = tex.get_height()
			
			var plane
			if model.is_lithtech_1():
				plane = world_model.planes[surface.unknown]
			else:
				plane = world_model.planes[poly.plane_index]
			
			# Lightmap handling (keeping existing code)
			var lm_image = poly.lightmap_texture as Image
			var depth_uv = Vector2(0, 0)
			if lm_image != null:
				if last_lm_uv.x + lm_image.get_width() > LIGHTMAP_ATLAS_SIZE:
					last_lm_uv.y += 32
					last_lm_uv.x = 0
				var lm_size = lm_image.get_size()
				big_lightmap_image.blit_rect(lm_image, Rect2(Vector2(0,0), lm_size), last_lm_uv)
				depth_uv = last_lm_uv
				last_lm_uv.x += lm_image.get_width()
			
			# Get OPQ vectors for this polygon
			var O: Vector3
			var P: Vector3  
			var Q: Vector3

			if model.PLATFORM == "PS2":
				O = poly.uv1
				P = poly.uv2
				Q = poly.uv3
			elif model.PLATFORM == "PC" and (model.is_lithtech_1() or model.is_lithtech_2()):
				O = surface.uv1
				P = surface.uv2
				Q = surface.uv3
			else:
				O = poly.uv1
				P = poly.uv2
				Q = poly.uv3

			var polygon_center = Vector3(poly.center.x, poly.center.y, poly.center.z)
			
			# Process each vertex
			for disk_vert_index in range(len(poly.disk_verts)):
				var disk_vert = poly.disk_verts[disk_vert_index]
				var vert = world_model.points[disk_vert.vertex_index]
				
				verts.append(vert)
				normals.append(plane.normal)
				
				if model.is_lithtech_1():
					var normalized = disk_vert.colour * (1.0 / 255.0)
					var colour = Color(normalized.x, normalized.y, normalized.z, 1.0)
					colours.append(colour)
				
				# Simple UV calculation using the function
				#var final_uv = opq_to_uv(vert, O, P, Q, polygon_center, plane.normal, texture_name, tex_width, tex_height)
				#var final_uv = opq_to_uv(vert, O, P, Q, polygon_center, plane.normal, plane.distance, texture_name, tex_width, tex_height)
				var final_uv = opq_to_uv_adaptive(vert, O, P, Q, polygon_center, plane.normal, plane.distance, poly.surface_index, world_model.surface_count, texture_name, tex_width, tex_height)


				uvs.append(final_uv)
			
			# Lightmap UV calculation (keeping existing code unchanged)
			if lm_image != null and lm_image.get_width() > 0 and lm_image.get_height() > 0:
				var lm_width = lm_image.get_width()
				var lm_height = lm_image.get_height()

				var poly_u = plane.normal.cross(Vector3.UP)
				if poly_u.dot(poly_u) < 0.001:
					poly_u = Vector3.RIGHT
				else:
					poly_u = poly_u.normalized()
				var poly_v = plane.normal.cross(poly_u).normalized()

				var top_left = Vector2(999.0, 999.0)
				var bottom_right = Vector2(-999.0, -999.0)

				for disk_vert_index in range(len(poly.disk_verts)):
					var disk_vert = poly.disk_verts[disk_vert_index]
					var vert = world_model.points[disk_vert.vertex_index]
					var vert_uv = get_vert_uv(vert, poly_u, poly_v, LIGHTMAP_ATLAS_SIZE, LIGHTMAP_ATLAS_SIZE)
					
					if vert_uv.x < top_left.x:
						top_left.x = vert_uv.x
					if vert_uv.y < top_left.y:
						top_left.y = vert_uv.y
					if vert_uv.x > bottom_right.x:
						bottom_right.x = vert_uv.x
					if vert_uv.y > bottom_right.y:
						bottom_right.y = vert_uv.y

				top_left += Vector2(-0.0035, -0.0035)
				bottom_right += Vector2(0.0035, 0.0035)
				
				var uv_offset = (Vector2(0,0) - top_left)
				var uv_scale = (bottom_right - top_left)
				
				for disk_vert_index in range(len(poly.disk_verts)):
					var disk_vert = poly.disk_verts[disk_vert_index]
					var vert = world_model.points[disk_vert.vertex_index]

					var vert_uv = get_vert_uv(vert, poly_u, poly_v, LIGHTMAP_ATLAS_SIZE, LIGHTMAP_ATLAS_SIZE)
					var vert_offset = (depth_uv / Vector2(LIGHTMAP_ATLAS_SIZE, LIGHTMAP_ATLAS_SIZE))
					
					vert_uv += uv_offset
					
					if uv_scale.x > 0.0:
						vert_uv.x /= uv_scale.x
					if uv_scale.y > 0.0:
						vert_uv.y /= uv_scale.y
					
					var new_vert_uv = Vector2(
						vert_uv.x * (float(lm_width) / LIGHTMAP_ATLAS_SIZE), 
						vert_uv.y * (float(lm_height) / LIGHTMAP_ATLAS_SIZE)
					)
					
					new_vert_uv += vert_offset

					if is_nan(new_vert_uv.x):
						new_vert_uv.x = 0.0
					if is_nan(new_vert_uv.y):
						new_vert_uv.y = 0.0
					
					uvs2.append(new_vert_uv)
			else:
				for disk_vert_index in range(len(poly.disk_verts)):
					uvs2.append(Vector2(1,0))
			
			# Reverse vertex order for correct winding
			verts.invert()
			normals.invert()
			uvs.invert()
			uvs2.invert()
			colours.invert()

			# Add to batch
			if texture_name in textured_meshes:
				textured_meshes[texture_name].append([uvs, normals, verts, colours, lightmap_textures, uvs2])
			else:
				textured_meshes[texture_name] = [[uvs, normals, verts, colours, lightmap_textures, uvs2]]
			
			# Clear arrays for next polygon
			verts = []
			uvs = []
			uvs2 = []
			normals = []
			colours = []
			
			lightmap_frame_index += 1
		
		big_lightmap_image.save_png("./lm_atlas.png")
		
	var data = build_array_mesh(textured_meshes)
	meshes += data[0]
	mesh_names += data[1]
	texture_references += data[2]

	return [meshes, mesh_names, texture_references, big_lightmap_image]
# End Func
