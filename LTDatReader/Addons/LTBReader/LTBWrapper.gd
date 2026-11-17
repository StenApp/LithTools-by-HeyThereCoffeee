tool
extends Reference

# LTBWrapper.gd -- Erkennung und Entpacken des "LTBHeader"-Wrapper-Containers.
#
# Dieser Wrapper umhuellt die Modelle der Formatfamilie "LTB wrap" (Body-Versionen 13..17, FileType 1 = D3D-Body,
# FileType 4 = ABC-Body). Er kommt in vielen Spielen vor (nicht nur in einem), nachgewiesen in ueber 2000 Dateien.
# Aufbau (Layout wie in LTB_wrap_*.bt, belegt):
#
#   uint16 len; char text[len];   // "LTBHeader"
#   uint32 NextSection;           // absoluter Offset der ersten Section ("Header"), ueblich 35 (frueher als MeshVersion beschriftet)
#   uint16 FileType;              // NUR das Low-Byte zaehlt (laut ltb.h ein uint8, das Hochbyte ist Fuellbyte):
#                                 // 1 = D3D-Modell, 4 = ABC-Modell; 5/6/7 = Render-Style/-Object (kein Modell)
#   uint16 Version;               // Container-Version (beobachtet: 3, 8, 9)
#   uint32 Reserved1..4;          // immer 0
#
# Danach folgt die Section-Kette Header, Pieces, Nodes, ChildModels, Animation, Sockets, AnimBindings
# (jede Section: LTString Name + uint32 NextSection; die letzte hat 0xFFFFFFFF). Die Body-Version steht als
# erstes uint32 im Body der Section "Header".

const LTB_WRAP_ABC_FILE_TYPE = 4
const LTB_WRAP_D3D_FILE_TYPE = 1


# Prueft, ob die Datei mit dem LTB-Wrapper beginnt. Veraendert die Dateiposition nicht dauerhaft.
static func is_ltb_wrap(f: File) -> bool:
	var pos = f.get_position()
	f.seek(0)
	var len_field = f.get_16()
	var is_match = false
	if len_field == 9:
		var text = f.get_buffer(9).get_string_from_ascii()
		is_match = (text == "LTBHeader")
	f.seek(pos)
	return is_match


# Liest den Wrapper ab Byte 0 und gibt {ok, file_type, container, body_version, offset} zurueck.
# "offset" ist die Byte-Position direkt hinter dem Wrapper (Start der Section "Header"); ABC.gd und
# LTB_Wrap_D3D.gd brauchen ihn als start_offset, weil die gespeicherten NextSection-Werte absolut vom Anfang der
# GESAMTEN Datei gezaehlt werden. "body_version" ist das erste uint32 im Body der Section "Header" (13..17).
static func read_wrapper(f: File) -> Dictionary:
	f.seek(0)
	var text_len = f.get_16()
	if text_len != 9:
		return {"ok": false}
	var text = f.get_buffer(text_len).get_string_from_ascii()
	if text != "LTBHeader":
		return {"ok": false}
	f.get_32()  # NextSection (Offset der Section "Header"), ungenutzt
	var file_type = f.get_16() & 0xFF  # Hochbyte = Fuellbyte
	var container = f.get_16()
	f.seek(f.get_position() + 16)  # Reserved1..4 (4x uint32)
	var offset = f.get_position()

	# Body-Version aus der Section "Header" lesen (Name, NextSection, dann uint32 Version) und Position zuruecksetzen
	var body_version = 0
	var name_len = f.get_16()
	if name_len > 0 and name_len < 32:
		f.seek(f.get_position() + name_len + 4)
		body_version = f.get_32()
	f.seek(offset)

	return {"ok": true, "file_type": file_type, "container": container, "body_version": body_version, "offset": offset}
