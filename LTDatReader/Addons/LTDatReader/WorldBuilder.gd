tool

extends Reference

var export_to_lta = false

var lta_writer = preload("res://Addons/LTDatReader/LTAWriter.gd").new()
var dtx_reader = preload("res://Addons/DTXReader/TextureBuilder.gd").new()
const UVMath = preload("res://Addons/LTDatReader/UVMath.gd")
const LightmapAtlas = preload("res://Addons/LTDatReader/LightmapAtlas.gd")
const LT1_SHADER = preload("res://Addons/LTDatReader/Shaders/LT1.shader")
var texture_path = ""
var debug_file = null
var last_build_type = "level"  # "level", "model_ps2", "model_pc"

const LIGHTMAP_ATLAS_SIZE = 2048.0#4096.0#2048.0
const ENABLE_LT2_LIGHTMAPS = false
const EPS = 0.001

# Fallback-Material fuer fehlende Texturen (Spiel nicht installiert/kein Pfad) -
# spiegelt genau das, was LTBModelBuilder.gd fuer Modelle schon macht: normales
# schattiertes SpatialMaterial statt des unshaded Level-Shaders, damit man
# wenigstens die Geometrie/Normalen sieht statt reinem Weiss.
func _build_fallback_material() -> SpatialMaterial:
	var mat = SpatialMaterial.new()
	mat.flags_unshaded = false
	return mat

# Gemeinsamer Kern der drei fast identischen Mesh-Instanziierungs-Schleifen in
# build() (LT1-Hack, Jupiter-Hack, Batch-Zweig). Die Material-Erstellung (welche
# Shader-Parameter gesetzt werden) bleibt bewusst in jeder Schleife selbst, da
# sich das zwischen den drei Zweigen unterscheidet - hier nur der wirklich
# identische Teil: MeshInstance anlegen, an root haengen, LithTech-Spiegelung.
func _create_mesh_instance(root: Spatial, mesh, mesh_name: String, mat: Material) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)
	mesh_instance.owner = root
	mesh_instance.set_surface_material(0, mat)
	# Mirror the world a bit to handle Lithtech's style of 3d
	mesh_instance.scale = Vector3(-1.0, 1.0, 1.0)
	return mesh_instance

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
	
	var dat_file = preload("res://Addons/LTDatReader/Models/DAT.gd")
	var ltb_file = preload("res://Addons/LTDatReader/Models/LTB_PS2.gd")
	
	# Setup our new scene FIRST
	var scene = null
	var root = Spatial.new()
	root.name = "Root"
	
	var model = null
	var file_extension = "dat"
	
	if ".ltb" in source_file.to_lower():
		# Peek first 4 bytes
		var first32 = file.get_32()
		file.seek(0)

		# Level-LTB erkennt man daran, dass diese 4 Bytes bereits 66 oder 4694 ergeben
		if first32 == 66 or first32 == 4694:
			print("Level-LTB (PS2) detected - processing with LTDatReader")
			self.last_build_type = "level"
			model = ltb_file.LTB_PS2.new()
			file_extension = "ltb"

		else:
			# Model-LTB: Lese als 32-bit + 16-bit (funktioniert für PC und PS2!)
			file.seek(0)  # Zurück zum Anfang
			var file_type = file.get_32()  # 4 Bytes: 0x00000001 (PC) oder 0x00000002 (PS2)
			var version = file.get_16()    # 2 Bytes: Version
			
			print("LTB Model - FileType: ", file_type, " Version: ", version)
			
			if file_type == 589825 and version == 0:
				# PC D3D Model (NOLF2)
				print("Loading PC LTB Model (v9)")
				file.close()
				self.last_build_type = "model_pc"
				var ltb_pc_builder = preload("res://Addons/LTBReader/LTBModelBuilder_PC.gd").new()
				return ltb_pc_builder.build(source_file, options)
			
			elif file_type == 2 and version == 16:
				# PS2 Model
				print("Loading PS2 LTB Model (v16)")
				file.close()
				self.last_build_type = "model_ps2"
				var ltb_ps2_builder = preload("res://Addons/LTBReader/LTBModelBuilder.gd").new()
				return ltb_ps2_builder.build(source_file, options)
			
			else:
				print("Unknown LTB Model format - FileType: ", file_type, " Version: ", version)
				file.close()
				root.free()  # Leak-Fix: root existiert bereits, sonst als Node nie freigegeben
				return FAILED
	else:
		self.last_build_type = "level"
		model = dat_file.DAT.new()	
		
	# Batched reading
	#var response = model.read(file, true)
	var response = model.read(file, true, not ENABLE_LT2_LIGHTMAPS)
	if response.code == model.IMPORT_RETURN.ERROR:
		print("IMPORT ERROR: " + str(response.message))
		root.free()  # Leak-Fix: siehe oben
		return FAILED
		
	# Hack: Load up some config values
	var config = ConfigFile.new()
	var err = config.load("./settings.cfg")
	
	# Fallback: kein Eintrag in settings.cfg fuer dieses Format/diese Version gefunden
	texture_path = ""
	
	var export_to_lta = self.export_to_lta
	
	if err == OK:
		var game_path_string = file_extension + "_v" + str(model.version) + "_game_path"
		texture_path = config.get_value("Worlds", game_path_string, texture_path)
	
	if texture_path == "":
		print("WARNUNG: Kein Textur-Pfad fuer '", file_extension, "_v", model.version, "_game_path' in settings.cfg gefunden - Texturen werden vermutlich nicht geladen.")
		
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
		
		# LT2 (NOLF1/AVP2): Lightmaps aktivieren wenn dieses WM Lightmap-Daten hat
		if model.version == 66 and ENABLE_LT2_LIGHTMAPS:
			for poly in world_model.polies:
				if poly.lightmap_texture != null:
					use_lightmaps = true
					break

		# Loop through our pieces, and add them to mesh instances
		# lm_texture_array.save_png("lm_null.png")
		var lm_image_texture = null
		
		if use_lightmaps:
			lm_image_texture = ImageTexture.new()
			lm_image_texture.create_from_image(lm_texture_array)
			lm_image_texture.set_flags(ImageTexture.FLAGS_DEFAULT + ImageTexture.FLAG_ANISOTROPIC_FILTER)
			
		
		var i = 0;
		for mesh in meshes:
			var tex_name = tex_names[i]
			var tex = dtx_reader.get_cached(texture_path, tex_name)
			
			var mat
			if tex == null:
				mat = _build_fallback_material()
			else:
				mat = ShaderMaterial.new()
				mat.shader = LT1_SHADER
				mat.set_shader_param("main_texture", tex)
				
				if use_lightmaps:
					mat.set_shader_param("use_lightmap", true)
					mat.set_shader_param("lm_texture", lm_image_texture)
				else:
					mat.set_shader_param("use_lightmap", false)

			_create_mesh_instance(root, mesh, mesh_names[i], mat)
			i += 1
			total_mesh_count+=1
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
		
		
		var i = 0;
		for mesh in meshes:
			var tex_name = tex_names[i]
			var tex = null
			
			if "LightAnim_" in tex_name:
				tex = lm_texture_array[i]
			else:
				tex = dtx_reader.get_cached(texture_path, tex_name)

			var mat
			if tex == null:
				mat = _build_fallback_material()
			else:
				mat = ShaderMaterial.new()
				mat.shader = LT1_SHADER
				mat.set_shader_param("main_texture", tex)

			_create_mesh_instance(root, mesh, mesh_names[i], mat)
			i += 1
			total_mesh_count+=1
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
			var lm_image_texture = ImageTexture.new()
			lm_image_texture.create_from_image(lm_texture_array)
			lm_image_texture.set_flags(ImageTexture.FLAGS_DEFAULT + ImageTexture.FLAG_ANISOTROPIC_FILTER + ImageTexture.FLAG_CONVERT_TO_LINEAR)
			
				
			var i = 0;
			for mesh in meshes:
				var tex_name = tex_names[i]
				var tex = dtx_reader.get_cached(texture_path, tex_name)
				
				var mat
				if tex == null:
					mat = _build_fallback_material()
				else:
					mat = ShaderMaterial.new()
					mat.shader = LT1_SHADER
					mat.set_shader_param("main_texture", tex)
					mat.set_shader_param("lm_texture", lm_image_texture)

				_create_mesh_instance(root, mesh, mesh_names[i], mat)
				i += 1
				total_mesh_count+=1
			# End For
		
	# Pack our scene!
	scene = root
	
	print("Total Meshes Generated: " + str(total_mesh_count))
	
	if export_to_lta:
		var writer = lta_writer.LTAWriter.new()

		var dir_path = source_file.get_base_dir()
		var base_name = source_file.get_file().get_basename()
		var out_path = dir_path.plus_file(base_name + ".lta")
		var missing_tex_path = dir_path.plus_file(base_name + "_missing_tex.txt")

		print("Exporting LTA to " + out_path)
		
		var result = writer.write(model, out_path, 2, dtx_reader.missing_textures, missing_tex_path)
		if result != OK:
			push_error("Failed to write LTA file: " + str(result))
			root.free()  # Leak-Fix: root traegt an dieser Stelle bereits alle MeshInstances
			return FAILED

	# Now that we've packed root into the scene, it's time to clean it up!
	# root is returned directly, not freed

	dtx_reader.clear_cache()
	
	return scene

# Fallback für degenerierte OPQ, OPQ<->UV-Mathematik: ausgelagert nach
# UVMath.gd (siehe const UVMath oben), hier nur noch Aufrufe.

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
			
			# if len(mesh_uvs2) > 0:
				# print("UV2 check: verts=", len(mesh_verts), " uvs2=", len(mesh_uvs2), " first=", mesh_uvs2[0])
			
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
	#print("DEBUG fill_array_mesh called, world_models count: ", len(world_models))

	var mesh_names = []
	var meshes = []
	var texture_references = []
	
	var lightmap_textures = {}

	var textured_meshes = {}
	var lightmap_frame_index = 0

	# Gleiche Bedingung wie spaeter in build() fuer use_lightmaps - nur wenn sie
	# zutrifft, lohnt sich die Atlas-Allokation (2048x2048x3 Byte) und die
	# komplette Pro-Polygon-Lightmap-UV-Berechnung ueberhaupt.
	var lightmaps_possible = (
		model.version == 55 or model.version == 56 or model.version == 127
		or (model.version == 66 and ENABLE_LT2_LIGHTMAPS)
	)

	var lightmap_atlas = LightmapAtlas.new(lightmaps_possible, LIGHTMAP_ATLAS_SIZE)

	for world_model_index in range(len(world_models)):
		var world_model = world_models[world_model_index]
		
		if world_model.world_name == "VisBSP":
			continue
		
		print("Processing World Model " + world_model.world_name)
		
		var verts = []
		var uvs = []
		var uvs2 = []
		var normals = []
		var colours = []
		var indices = PoolIntArray()
		var polies = []
		

		# Lightmap setup (keeping existing code)
		# Ergebnisse (total_lm_width/height, largest_lm_width/height) werden aktuell
		# nirgends im Rest der Datei gelesen - trotzdem hinter lightmaps_possible
		# gegated statt geloescht, falls das fuer spaeteres Atlas-Packing gedacht war.
		if lightmaps_possible:
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
			
			texture_index = surface.texture_index

			var texture_name = ""
				
			if model.PLATFORM == "PS2":
				if texture_index >= 0 and texture_index < model.texture_list.size():
					texture_name = model.texture_list[texture_index].to_lower()
				else:
					push_error("Ungültiger PS2 Texturindex: %d" % texture_index)
					texture_name = ""
			else:
				# DAT/PC: Verwende die ursprüngliche Methode
				if texture_index >= 0 and texture_index < world_model.texture_names.size():
					texture_name = world_model.texture_names[texture_index].name.to_lower()
				else:
					push_error("Ungültiger DAT Texturindex: %d" % texture_index)
					texture_name = ""	
			
			#print("World '", world_model.world_name, "' - Polygon ", poly_index, " verwendet Textur: ", texture_name, " (Index: ", texture_index, ")")
			
			if texture_name == "" and surface.texture_flags != 0:
				push_error("Texturname leer, aber texture_flags=%d (≠0) — vermutlich Lesefehler, nicht 'keine Textur'!" % surface.texture_flags)
				# Fallthrough: Poly wird trotzdem mit Fallback-Textur gerendert, damit der Bug SICHTBAR bleibt
			elif texture_name == "" and surface.texture_flags == 0:
				continue  # legitime texturlose Fläche, überspringen
			
			var tex = dtx_reader.get_cached(texture_path, texture_name)
			var tex_width = 64
			var tex_height = 64

			if tex != null:
				var dims = dtx_reader.get_cached_dims(texture_name)
				tex_width = dims.x
				tex_height = dims.y
			
			var plane
			if model.is_lithtech_1():
				plane = world_model.planes[surface.unknown]
			else:
				plane = world_model.planes[poly.plane_index]
			
			# Lightmap handling
			var lm_image = poly.lightmap_texture as Image
			var depth_uv = lightmap_atlas.place(lm_image)
			
			# OPQ-Vektoren pro Polygon bestimmen
			var O: Vector3
			var P: Vector3  
			var Q: Vector3
			var calculation_method: String
			
			if model.PLATFORM == "PS2":
				O = poly.O
				P = poly.P
				Q = poly.Q
				
				# Packed (Bit 2): OPQ in Surface, direkte UVs in DiskVerts fehlen
				# Nicht packed: direkte UVs in DiskVerts, OPQ wird für LTAWriter zurückgerechnet
				var is_packed = (surface.flags & (1 << 2)) != 0
				calculation_method = "ps2_opq" if is_packed else "ps2_direct"
				
				# Fallback: nie ausgerichtete Flächen (z.B. Invisible.dtx) haben oft
				# entartete P/Q (nahe Null oder nahe parallel) -> Streifenmuster.
				# DEdit löst das manuell per "Reset Texture Coordinates" -> hier nachgebildet.
				if is_packed and UVMath.is_opq_degenerate(P, Q, plane.normal):
					var fallback = UVMath.get_axis_aligned_pq(plane.normal)
					P = fallback[0]
					Q = fallback[1]
					
					# Zurueckschreiben fuer den Export - mit der UNVERAENDERTEN
					# EditPoly.cpp-Formel (kein Godot-Spiegel-Ausgleich noetig,
					# DEdit liest die rohen LithTech-Koordinaten direkt).
					var export_fallback = UVMath.get_axis_aligned_pq_raw(plane.normal)
					poly.O = O
					poly.P = export_fallback[0]
					poly.Q = export_fallback[1]
					# ])
				
				# OPQ debug
				# if not is_packed and poly.disk_verts.size() >= 3:
					# print("POLY_%d [%s] uv0=(%.4f,%.4f) uv1=(%.4f,%.4f) uv2=(%.4f,%.4f)" % [
						# poly_index, texture_name,
						# poly.disk_verts[0].u, poly.disk_verts[0].v,
						# poly.disk_verts[1].u, poly.disk_verts[1].v,
						# poly.disk_verts[2].u, poly.disk_verts[2].v
					# ])
				
			else:
				# PC/DAT: OPQ immer in Surface (LT1/LT2) oder Poly (andere)
				if model.PLATFORM == "PC" and (model.is_lithtech_1() or model.is_lithtech_2()):
					O = surface.O
					P = surface.P
					Q = surface.Q
				else:
					O = poly.O
					P = poly.P
					Q = poly.Q
				calculation_method = "pc_simple"
				
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
				
				# UV-Berechnung basierend auf Polygon-Methode
				match calculation_method:
					"ps2_opq":
						# Packed: OPQ aus Surface, direkte Formel reicht (nur invisible.dtx)
						uvs.append(UVMath.opq_to_uv_pc(vert, O, P, Q, tex_width, tex_height))
					"ps2_direct":
						uvs.append(Vector2(disk_vert.u, disk_vert.v))
					"pc_simple":
						uvs.append(UVMath.opq_to_uv_pc(vert, O, P, Q, tex_width, tex_height))

			# Nach der Vertex-Schleife: OPQ-Speicherung für LTAWriter
			if model.PLATFORM == "PS2" and calculation_method == "ps2_direct":
				# Direkte UVs → OPQ zurückrechnen
				var opq_result = UVMath.convert_uv_to_opq_lithtech_original(poly, world_model, model, tex_width, tex_height)
				poly.O = opq_result.O
				poly.P = opq_result.P
				poly.Q = opq_result.Q
			# ps2_opq: OPQ bereits in poly.O/P/Q aus Surface
			# PC: Keine Aktualisierung nötig
			
			# Lightmap UV2 (LithTech: SetupLMPlaneVectors + GetExtents), ausgelagert nach LightmapAtlas.gd
			var poly_world_verts = []
			for disk_vert_index in range(len(poly.disk_verts)):
				poly_world_verts.append(world_model.points[poly.disk_verts[disk_vert_index].vertex_index])
			var lm_grid = model.world_info.light_map_grid_size
			uvs2 = lightmap_atlas.compute_uv2(plane.normal, poly_world_verts, lm_image, depth_uv, lm_grid)
			
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
		
		# lightmap_atlas.get_image().save_png("./lm_atlas.png")  # disabled: called per world model
		
	var data = build_array_mesh(textured_meshes)
	meshes += data[0]
	mesh_names += data[1]
	texture_references += data[2]

	return [meshes, mesh_names, texture_references, lightmap_atlas.get_image()]
# End Func
