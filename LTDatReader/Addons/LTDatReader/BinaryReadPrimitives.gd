tool
extends Reference

# BinaryReadPrimitives.gd - gemeinsame Low-Level-Lesefunktionen, die bisher als
# SECHS unabhaengige Kopien existierten: DAT.gd, ABC.gd, ABC6.gd, LTB_PC.gd,
# LTDatReader/Models/LTB_PS2.gd, LTBReader/Models/LTB_PS2.gd.
#
# WICHTIG - NOCH NICHT VERDRAHTET (Stand vor Verifikation gegen echte Formate):
# Diese Datei ist bewusst noch NICHT in den sechs Original-Dateien eingebunden.
#
# UPDATE nach Abgleich mit acht echten 010-Editor-Templates (DAT_V66/V70/V85,
# LTB_PS2 Level+Model, pc_ltb, ABC_V13, pc_abc_v6): Alle acht definieren das
# Quaternion-Struct identisch als "float x, y, z, w" (X,Y,Z,W) - AUSNAHMSLOS.
# read_quat() unten nutzt diese eine, verifizierte Reihenfolge.
#
# DAT.gd und ABC.gd lasen bisher in der Reihenfolge W,X,Y,Z - das war ein echter
# Bug, kein Formatunterschied, und wurde direkt in beiden Dateien gefixt (siehe
# Commit-Kommentar dort). Die read_string-Unterschiede (is_length_a_short-Parameter,
# Sicherheitschecks) bleiben wie unten beschrieben - die sind weiterhin echte,
# gewollte Unterschiede zwischen den Formaten.
#
#   - read_string: DAT.gd und LTDatReader/LTB_PS2.gd lesen die Laenge wahlweise
#     16- oder 32-Bit (Parameter is_length_a_short). ABC.gd/ABC6.gd/LTB_PC.gd/
#     LTBReader-LTB_PS2.gd lesen IMMER 16-Bit.
#
# Vor dem Verdrahten in den sechs Dateien: read_string weiterhin pro Aufrufer
# mit korrektem is_length_a_short-Wert aufrufen, sonst bleibt alles unveraendert.

const EPS = 0.001


static func read_string(file: File, is_length_a_short: bool = true) -> String:
	var length = 0
	if is_length_a_short:
		length = file.get_16()
	else:
		length = file.get_32()  # Sometimes it's 32-bit...
	if length <= 0:
		return ""
	return file.get_buffer(length).get_string_from_ascii()


static func read_vector2(file: File) -> Vector2:
	return Vector2(file.get_float(), file.get_float())


static func read_vector3(file: File) -> Vector3:
	return Vector3(file.get_float(), file.get_float(), file.get_float())


# Byte-Reihenfolge X,Y,Z,W - verifiziert gegen alle acht vom Nutzer bereitgestellten
# 010-Editor-Templates (DAT_V66/V70/V85, LTB_PS2 Level+Model, pc_ltb, ABC_V13, pc_abc_v6):
# ausnahmslos "struct LTQuaternion/LTRotation { float x, y, z, w; }". Das gilt fuer
# ALLE LithTech-Versionen einheitlich - kein Formatunterschied.
static func read_quat(file: File) -> Quat:
	return Quat(file.get_float(), file.get_float(), file.get_float(), file.get_float())


# 4x4-Matrix als 16 Floats, spaltenweise (matcht alle sechs bisherigen Implementierungen
# identisch - dieser Teil war ueberall gleich)
static func read_matrix(file: File) -> Transform:
	var m = []
	for i in range(16):
		m.append(file.get_float())
	return Transform(
		Vector3(m[0], m[4], m[8]),
		Vector3(m[1], m[5], m[9]),
		Vector3(m[2], m[6], m[10]),
		Vector3(m[3], m[7], m[11])
	)


static func make_response(code, message: String = "") -> Dictionary:
	return {"code": code, "message": message}
