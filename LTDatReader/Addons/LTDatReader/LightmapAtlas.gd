tool
extends Reference

# LightmapAtlas.gd - kapselt den Lightmap-Atlas (Bild + Platzierungs-Cursor)
# und die Pro-Polygon-UV2-Berechnung (LithTech: SetupLMPlaneVectors + GetExtents).
# Ausgelagert aus WorldBuilder.gd/fill_array_mesh, da das eigener Zustand mit
# eigenem Lebenszyklus ist (ein Atlas pro Weltmodell-Batch), keine reine
# zustandslose Mathematik wie UVMath.gd.
#
# Nutzung:
#   var atlas = LightmapAtlas.new(enabled, atlas_size)
#   ...
#   var depth_uv = atlas.place(lm_image)                      # beim Poly mit Lightmap
#   var uvs2 = atlas.compute_uv2(plane_normal, poly_world_verts, lm_image, depth_uv, lm_grid)
#   ...
#   var final_image = atlas.get_image()                       # am Ende, fuer den ImageTexture

const LM_PLANES = [
	[Vector3(1,0,0), Vector3(0,0,-1), Vector3(0,1,0)],
	[Vector3(1,0,0), Vector3(0,0,1),  Vector3(0,-1,0)],
	[Vector3(1,0,0), Vector3(0,1,0),  Vector3(0,0,1)],
	[Vector3(1,0,0), Vector3(0,-1,0), Vector3(0,0,-1)],
	[Vector3(0,0,1), Vector3(0,-1,0), Vector3(1,0,0)],
	[Vector3(0,0,-1),Vector3(0,-1,0), Vector3(-1,0,0)]
]

var enabled: bool = false
var atlas_size: float = 2048.0
var image: Image = Image.new()
var cursor: Vector2 = Vector2(0, 0)

func _init(p_enabled: bool, p_atlas_size: float = 2048.0):
	enabled = p_enabled
	atlas_size = p_atlas_size
	if enabled:
		var white_image = Image.new()
		white_image.create(2, 2, false, Image.FORMAT_RGB8)
		white_image.fill(Color(1.0, 1.0, 1.0, 1.0))

		image.create(atlas_size, atlas_size, false, Image.FORMAT_RGB8)
		image.blit_rect(white_image, Rect2(Vector2(0,0), Vector2(2,2)), Vector2(atlas_size - 2, atlas_size - 2))


# Platziert ein einzelnes Lightmap-Bild im Atlas, gibt dessen Offset (depth_uv) zurueck.
# Gibt Vector2(0,0) zurueck, wenn der Atlas deaktiviert oder lm_image null ist.
func place(lm_image: Image) -> Vector2:
	if not enabled or lm_image == null:
		return Vector2(0, 0)

	if cursor.x + lm_image.get_width() > atlas_size:
		cursor.y += 32
		cursor.x = 0

	var lm_size = lm_image.get_size()
	image.blit_rect(lm_image, Rect2(Vector2(0,0), lm_size), cursor)
	var depth_uv = cursor
	cursor.x += lm_image.get_width()
	return depth_uv


# Berechnet die UV2-Koordinaten (Lightmap-UVs) fuer alle Vertices eines Polygons.
# poly_world_verts: Array von Vector3 (Weltposition jedes Disk-Vertex des Polygons).
# Gibt ein Array von Vector2 zurueck, ein Eintrag pro Eingabe-Vertex.
func compute_uv2(poly_normal: Vector3, poly_world_verts: Array, lm_image: Image, depth_uv: Vector2, lm_grid: float) -> Array:
	if not enabled or lm_image == null or lm_image.get_width() <= 0 or lm_image.get_height() <= 0:
		var fallback = []
		for i in range(len(poly_world_verts)):
			fallback.append(Vector2(1, 0))
		return fallback

	var lm_width = float(lm_image.get_width())
	var lm_height = float(lm_image.get_height())
	var vert_offset = depth_uv / Vector2(atlas_size, atlas_size)

	# SelectLMPlaneVector: best plane by dot with poly normal
	var best_plane = 0
	var best_dot = -2.0
	for pi in range(6):
		var d = poly_normal.dot(LM_PLANES[pi][2])
		if d > best_dot:
			best_dot = d
			best_plane = pi

	# SetupLMPlaneVectors
	var lm_P = poly_normal.cross(LM_PLANES[best_plane][1]).normalized()
	var lm_Q = lm_P.cross(poly_normal).normalized()

	# GetExtents: find min projection of all verts onto lm_P and lm_Q
	var min_p = INF
	var min_q = INF
	for vert in poly_world_verts:
		var dp = vert.dot(lm_P)
		var dq = vert.dot(lm_Q)
		if dp < min_p: min_p = dp
		if dq < min_q: min_q = dq

	if lm_grid <= 0.0:
		lm_grid = 20.0

	var result = []
	for vert in poly_world_verts:
		var u = (vert.dot(lm_P) - min_p) / (lm_width * lm_grid)
		var v = (vert.dot(lm_Q) - min_q) / (lm_height * lm_grid)

		var new_vert_uv = Vector2(
			u * (lm_width / atlas_size) + vert_offset.x,
			v * (lm_height / atlas_size) + vert_offset.y
		)

		if is_nan(new_vert_uv.x): new_vert_uv.x = 0.0
		if is_nan(new_vert_uv.y): new_vert_uv.y = 0.0

		result.append(new_vert_uv)
	return result


func get_image() -> Image:
	return image
