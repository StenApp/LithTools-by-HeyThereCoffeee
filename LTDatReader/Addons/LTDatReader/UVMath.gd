tool

# UVMath.gd - reine UV/OPQ-Mathematik fuer LithTech-Level-Texturkoordinaten.
# Ausgelagert aus WorldBuilder.gd, da dieser Teil kein Godot-Szenen-Wissen
# braucht (keine Node/MeshInstance/Material-Abhaengigkeit) - gehoert damit
# inhaltlich zum Level-Format-Wissen von LTDatReader, nicht zur reinen
# Godot-Orchestrierung.
#
# Alle Funktionen sind "static func" und damit ohne .new() direkt aufrufbar:
#   const UVMath = preload("res://Addons/LTDatReader/UVMath.gd")
#   UVMath.opq_to_uv_pc(...)

extends Reference


# Fallback fuer degenerierte OPQ (z.B. nie ausgerichtete Invisible.dtx-Flaechen):
# klassische achsparallele Projektion, abhaengig von der dominanten Normalen-Achse
static func get_axis_aligned_pq(normal: Vector3) -> Array:
	# Echte LithTech-Tabelle aus EditPoly.cpp (SetupBaseTextureSpace),
	# 6 einzelne Faelle - Ost/West bzw. Nord/Sued NICHT per abs()
	# zusammengefasst (das war der Fehler: gegenueberliegende Waende
	# bekamen dieselbe Ausrichtung und eine davon war dadurch immer
	# spiegelverkehrt - bestaetigt an echten Godot-Screenshots).
	var planes = [
		Vector3(0, 1, 0),   # Bottom
		Vector3(0, -1, 0),  # Top
		Vector3(1, 0, 0),   # East
		Vector3(-1, 0, 0),  # West
		Vector3(0, 0, 1),   # North
		Vector3(0, 0, -1),  # South
	]
	var right_vectors = [
		Vector3(1, 0, 0),   # Bottom
		Vector3(-1, 0, 0),  # Top
		Vector3(0, 0, 1),   # East
		Vector3(0, 0, -1),  # West
		Vector3(-1, 0, 0),  # North
		Vector3(1, 0, 0),   # South
	]

	var best_dot = -INF
	var best_i = 0
	for i in range(6):
		var d = normal.dot(planes[i])
		if d > best_dot:
			best_dot = d
			best_i = i

	var P = right_vectors[best_i]
	var Q = planes[best_i].cross(P)
	return [P, Q]

# Gleiche Achsen-Auswahl wie oben, aber mit der Original-EditPoly.cpp-
# Kreuzprodukt-Reihenfolge (P.cross(plane), NICHT gedreht). Der Godot-Viewer
# braucht die gedrehte Version oben (kompensiert Godots eigenen "-1 X-Scale"-
# Spiegel, der nur fuer die Darstellung draufkommt) - fuer den LTA-Export
# (von DEdit nativ gelesen, ohne jeden Godot-Spiegel) ist dagegen die
# unveraenderte Original-Formel richtig.
static func get_axis_aligned_pq_raw(normal: Vector3) -> Array:
	var planes = [
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var right_vectors = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
		Vector3(-1, 0, 0), Vector3(1, 0, 0),
	]
	var best_dot = -INF
	var best_i = 0
	for i in range(6):
		var d = normal.dot(planes[i])
		if d > best_dot:
			best_dot = d
			best_i = i
	var P = right_vectors[best_i]
	var Q = -P.cross(planes[best_i])  # Export: Flip Y, empirisch bestaetigt (DEdit-Screenshot)
	return [P, Q]


static func is_opq_degenerate(p: Vector3, q: Vector3, real_normal: Vector3) -> bool:
	var eps = 0.001
	if p.length() < eps or q.length() < eps:
		return true
	if p.normalized().cross(q.normalized()).length() < eps:
		return true
	# Passt die aus P/Q abgeleitete Normale zur echten Flaechennormale?
	var derived_normal = p.normalized().cross(q.normalized()).normalized()
	if abs(derived_normal.dot(real_normal.normalized())) < 0.9:
		return true
	return false


# OPQ to UV - standard LithTech formula, used for both PC and PS2 packed surfaces
static func opq_to_uv_pc(vertex: Vector3, o: Vector3, p: Vector3, q: Vector3, tex_width = 128.0, tex_height = 128.0) -> Vector2:
	var point = vertex - o
	var u = point.dot(p) / tex_width
	var v = point.dot(q) / tex_height
	return Vector2(u, v)


static func get_vert_uv(vert: Vector3, poly_u: Vector3, poly_v: Vector3, lm_width, lm_height) -> Vector2:
	return Vector2(vert.dot(poly_u) / (lm_width), vert.dot(poly_v) / (lm_height))


# UV to OPQ conversion based on LithTech's original uvtoopq.cpp
# Reference: uvtoopq.cpp - ConvertUVToOPQ function
static func convert_uv_to_opq_lithtech_original(poly, world_model, model, tex_width: int, tex_height: int) -> Dictionary:
	"""
	Converts UV coordinates to OPQ vectors using LithTech's original algorithm.
	Based on uvtoopq.cpp - uses first 3 vertices only, regardless of polygon complexity.
	"""
	if poly.disk_verts.size() < 3:
		push_error("Polygon has fewer than 3 vertices")
		return {"O": Vector3.ZERO, "P": Vector3.RIGHT, "Q": Vector3.UP}

	# Following uvtoopq.cpp approach: use first 3 vertices only
	var positions = []
	var uv_coords = []

	for i in range(3):  # Hardcoded to 3 as in original uvtoopq.cpp
		var disk_vert = poly.disk_verts[i]
		var world_pos = world_model.points[disk_vert.vertex_index]
		var uv = Vector2(disk_vert.u, disk_vert.v)

		positions.append(world_pos)
		uv_coords.append(uv)

	return convert_uv_to_opq(positions, uv_coords, tex_width, tex_height)


# UV to OPQ Converter - Godot port of LithTech's original algorithm
# Based on uvtoopq.cpp
static func bary_coords_area(p0: Vector3, p1: Vector3, p2: Vector3) -> float:
	var e0 = p1 - p0
	var e1 = p2 - p0
	return (e0.x * e1.y - e1.x * e0.y)


static func bary_coords(p0: Vector3, p1: Vector3, p2: Vector3, p: Vector3) -> Vector3:
	var n = bary_coords_area(p0, p1, p2)
	if abs(n) < 0.001:
		return Vector3(1.0, 0.0, 0.0)
	var u = bary_coords_area(p1, p2, p) / n
	var v = bary_coords_area(p2, p0, p) / n
	var w = 1.0 - u - v
	return Vector3(u, v, w)


static func convert_uv_to_opq(positions: Array, uv_coords: Array, tex_width: int, tex_height: int) -> Dictionary:
	"""
	Sets up OPQs based on UV coordinates for each vertex
	Based on uvtoopq.cpp - ConvertUVToOPQ function
	"""
	if positions.size() != 3 or uv_coords.size() != 3:
		push_error("convert_uv_to_opq: Benoetigt genau 3 Positionen und 3 UV-Koordinaten")
		return {"O": Vector3.ZERO, "P": Vector3.RIGHT, "Q": Vector3.UP}

	# vertex positions in texture space (OHNE Y-flip wie in uvtoopq.cpp)
	var tv0 = Vector3(uv_coords[0].x, uv_coords[0].y, 0.0)
	var tv1 = Vector3(uv_coords[1].x, uv_coords[1].y, 0.0)
	var tv2 = Vector3(uv_coords[2].x, uv_coords[2].y, 0.0)

	# vertex positions in world space
	var v0 = positions[0]
	var v1 = positions[1]
	var v2 = positions[2]

	# determine barycentric coordinates of OPQ in texture space
	var bc_o = bary_coords(tv0, tv1, tv2, Vector3(0.0, 0.0, 0.0))
	var bc_p = bary_coords(tv0, tv1, tv2, Vector3(1.0, 0.0, 0.0))
	var bc_q = bary_coords(tv0, tv1, tv2, Vector3(0.0, 1.0, 0.0))

	# calculate OPQ in world space
	var O = bc_o.x * v0 + bc_o.y * v1 + bc_o.z * v2
	var P = bc_p.x * v0 + bc_p.y * v1 + bc_p.z * v2
	var Q = bc_q.x * v0 + bc_q.y * v1 + bc_q.z * v2

	P = P - O
	Q = Q - O

	# Scale factors (wie in uvtoopq.cpp)
	var tp = P.length()
	tp *= 1.0 / float(tex_width)
	tp = 1.0 / tp if tp > 0.001 else 1.0

	var tq = Q.length()
	tq *= 1.0 / float(tex_height)
	tq = 1.0 / tq if tq > 0.001 else 1.0

	P = P.normalized()
	Q = Q.normalized()

	# Fix up P and Q to be what DEdit really wants (orthogonalization)
	var R = Q.cross(P)
	var P_new = R.cross(Q)
	var Q_new = P.cross(R)

	# Fix up scale factors for new P and Q
	P_new = P_new.normalized()
	Q_new = Q_new.normalized()

	var p_scale = 1.0 / P.dot(P_new) if abs(P.dot(P_new)) > 0.001 else 1.0
	var q_scale = 1.0 / Q.dot(Q_new) if abs(Q.dot(Q_new)) > 0.001 else 1.0

	P_new *= tp * p_scale
	Q_new *= tq * q_scale

	return {
		"O": O,
		"P": P_new,
		"Q": Q_new
	}
