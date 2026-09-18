tool
extends Reference

# DHNPWrapper.gd -- Erkennung und Entpacken des Die-Hard:-Nakatomi-Plaza
# (DHNP) LTB-Wrapper-Containers.
#
# DHNP verpackt seine Modelldaten in einen aeusseren LTB-Container, der bei
# keinem anderen von diesem Projekt unterstuetzten Spiel vorkommt (normales
# ABC, normales LTB-PC, LTB-PS2). Der Container ist winzig:
#
#   uint16 len; char text[len];   // "LTBHeader"
#   uint32 MeshVersion;
#   uint16 FileType;              // 4 = ABC-Body, 1 = D3D-Hybrid-Body
#   uint16 Version;                // LTB-Container-Version (beobachtet: 3)
#   uint32 Reserved1..4;           // in allen Beispielen immer 0
#
# Byte-fuer-Byte identisch zur bereits gegen 9 echte DHNP-Dateien validierten
# Python-Implementierung in reader_ltb_dhnp.py (Blender-Addon io_scene_lithtech,
# selbe Code-Basis/Recherche).

const DHNP_ABC_FILE_TYPE = 4
const DHNP_D3D_FILE_TYPE = 1


# Prueft, ob die Datei an der aktuellen (bzw. wiederhergestellten) Position
# mit dem DHNP-Wrapper beginnt. Veraendert die Dateiposition nicht dauerhaft.
static func is_dhnp(f: File) -> bool:
	var pos = f.get_position()
	f.seek(0)
	var len_field = f.get_16()
	var is_match = false
	if len_field == 9:
		var text = f.get_buffer(9).get_string_from_ascii()
		is_match = (text == "LTBHeader")
	f.seek(pos)
	return is_match


# Liest den Wrapper ab Byte 0 und gibt {ok, file_type, version, offset} zurueck.
# "offset" ist die Byte-Position direkt hinter dem Wrapper -- das ist der
# start_offset, den ABC.gd/LTB_DHNP_D3D.gd fuer ihre Section-Scan-Schleife
# brauchen, weil die im File gespeicherten "NextSectionLocation"-Werte absolut
# vom Anfang der GESAMTEN (Wrapper inklusive) Datei aus gezaehlt werden.
static func read_wrapper(f: File) -> Dictionary:
	f.seek(0)
	var text_len = f.get_16()
	if text_len != 9:
		return {"ok": false}
	var text = f.get_buffer(text_len).get_string_from_ascii()
	if text != "LTBHeader":
		return {"ok": false}
	f.get_32()  # MeshVersion, ungenutzt
	var file_type = f.get_16()
	var version = f.get_16()
	f.seek(f.get_position() + 16)  # Reserved1..4 (4x uint32)
	return {"ok": true, "file_type": file_type, "version": version, "offset": f.get_position()}
