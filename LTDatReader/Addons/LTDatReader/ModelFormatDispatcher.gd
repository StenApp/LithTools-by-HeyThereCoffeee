# res://Addons/LTDatReader/ModelFormatDispatcher.gd
tool
extends Reference

# ModelFormatDispatcher.gd -- die EINZIGE Stelle, die anhand der Datei-Bytes
# entscheidet, welcher Builder fuer eine .dat/.ltb-Datei zustaendig ist:
#
#   .dat                                   -> immer ein Level -> WorldBuilder.gd
#   .ltb, erste 4 Bytes == 66 oder 4694     -> Level-LTB (PS2) -> WorldBuilder.gd
#   .ltb, "LTBHeader"-Wrapper am Dateianfang -> LTB wrap (Body 13..17):
#       FileType==4 -> ABC-Body                 -> ABCReader/ModelBuilder.gd
#       FileType==1, Body 13  -> D3D-Body       -> LTBReader/LTBModelBuilder_Wrap_D3D.gd
#       FileType==1, Body 14..17 -> PC-Pieces   -> LTBReader/LTBModelBuilder_PC.gd (wrapped = true)
#       Container 8 (Body-13-Hybrid mit PC-Pieces) wird nicht unterstuetzt
#   .ltb, sonst: FileType (uint8, Low-Byte) + Container (uint16) -> Model-LTB:
#       Low-Byte 1, Container 9 -> PC raw (Mesh 18..25) -> LTBReader/LTBModelBuilder_PC.gd
#       2/16                     -> PS2 (v16)            -> LTBReader/LTBModelBuilder.gd
#       Low-Byte 5/6/7           -> Render-Style/-Object (kein Modell, wird nicht geladen)
#
# Diese Unterscheidung stand vorher direkt in WorldBuilder.build() (Level-
# LTB/Model-PC/Model-PS2 wurden dort schon per Byte-Peek erkannt und an den
# jeweils richtigen Builder weitergereicht). WorldBuilder baut jetzt
# ausschliesslich echte Level-Szenen und bekommt von hier aus nie mehr etwas
# anderes vorgesetzt -- die "ist das ueberhaupt ein Level oder ein Modell"-
# Entscheidung lebt nur noch hier.

const LTB_WRAPPER = preload("res://Addons/LTBReader/LTBWrapper.gd")

# "level", "model_ps2", "model_pc", "model_ltb_wrap" -- von ModelRendererController
# nach jedem build()-Aufruf ausgelesen, um z.B. die Kamera-Auto-Framing-Logik
# nur fuer Modelle (nicht fuer Level) anzuwenden.
var last_build_type = "level"

# Level-only Feature (Export als .lta beim Laden) -- wird an WorldBuilder
# durchgereicht, siehe build() unten. Bleibt hier statt in WorldBuilder
# gesetzt, weil WorldBuilder jetzt pro Aufruf frisch instanziiert wird.
var export_to_lta = false


func build(source_file, options):
	var lower_path = source_file.to_lower()

	if not (".ltb" in lower_path):
		# .dat ist immer ein Level -- WorldBuilder unveraendert zustaendig.
		self.last_build_type = "level"
		return self._build_level(source_file, options)

	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		print("Failed to open " + source_file)
		return FAILED

	# LTB-wrap hat Vorrang vor allen anderen Checks (siehe LTBWrapper.gd):
	# sein erstes Feld ist ein LTString, das sonst als kaputtes
	# FileType/Version-Paar fehlinterpretiert wird (genau das war der Bug,
	# der LTB-wrap-Dateien bisher als "Unknown LTB Model format" hat scheitern
	# lassen).
	if LTB_WRAPPER.is_ltb_wrap(file):
		var wrapper = LTB_WRAPPER.read_wrapper(file)
		file.close()

		if not wrapper.ok:
			print("LTB-wrap erkannt, aber Lesen fehlgeschlagen: " + source_file)
			return FAILED

		print("LTB-wrap erkannt - FileType: ", wrapper.file_type, " Version: ", wrapper.version)
		self.last_build_type = "model_ltb_wrap"

		if wrapper.file_type == LTB_WRAPPER.LTB_WRAP_ABC_FILE_TYPE:
			print("LTB wrap ABC body - delegiere an ABCReader/ModelBuilder.gd")
			var abc_builder = preload("res://Addons/ABCReader/ModelBuilder.gd").new()
			return abc_builder.build(source_file, options, wrapper.offset)
		elif wrapper.file_type == LTB_WRAPPER.LTB_WRAP_D3D_FILE_TYPE:
			if wrapper.container == 8:
				print("LTB wrap Container 8 (Body-13-Hybrid mit PC-Pieces) wird nicht unterstuetzt: " + source_file)
				return FAILED
			if wrapper.body_version >= 14:
				print("LTB wrap Body ", wrapper.body_version, " - delegiere an LTBModelBuilder_PC.gd (wrapped)")
				var pc_builder = preload("res://Addons/LTBReader/LTBModelBuilder_PC.gd").new()
				return pc_builder.build(source_file, options, true)
			print("LTB wrap D3D Body 13 - delegiere an LTBModelBuilder_Wrap_D3D.gd")
			var d3d_builder = preload("res://Addons/LTBReader/LTBModelBuilder_Wrap_D3D.gd").new()
			return d3d_builder.build(source_file, options, wrapper.offset)
		else:
			print("Unbekannter LTB wrap FileType: ", wrapper.file_type)
			return FAILED

	# Kein LTB-wrap -- Level-LTB (PS2) vs. Model-LTB (PC/PS2) unterscheiden.
	# Level-LTB erkennt man an den ersten 4 Bytes (66 oder 4694).
	var first32 = file.get_32()
	file.seek(0)

	if first32 == 66 or first32 == 4694:
		file.close()
		print("Level-LTB (PS2) erkannt - delegiere an WorldBuilder.gd")
		self.last_build_type = "level"
		return self._build_level(source_file, options)

	# Model-LTB: 32-Bit FileType + 16-Bit Version (funktioniert fuer PC und PS2)
	var file_type = file.get_32()
	var version = file.get_16()
	file.close()

	print("LTB Model - FileType: ", file_type, " Version: ", version)

	# FileType ist ein uint8 (Low-Byte), danach folgt ein Fuellbyte, dann die Container-Version (9 bei PC-Modellen)
	if (file_type & 0xFF) == 1 and (file_type >> 16) == 9 and version == 0:
		print("Loading PC LTB Model (raw, Mesh 18..25)")
		self.last_build_type = "model_pc"
		var ltb_pc_builder = preload("res://Addons/LTBReader/LTBModelBuilder_PC.gd").new()
		return ltb_pc_builder.build(source_file, options)
	elif file_type == 2 and version == 16:
		print("Loading PS2 LTB Model (v16)")
		self.last_build_type = "model_ps2"
		var ltb_ps2_builder = preload("res://Addons/LTBReader/LTBModelBuilder.gd").new()
		return ltb_ps2_builder.build(source_file, options)
	elif (file_type & 0xFF) in [5, 6, 7]:
		print("LTB Render-Style/-Object (FileType ", file_type & 0xFF, ") ist kein Modell - nicht ladbar: " + source_file)
		return FAILED
	else:
		print("Unknown LTB Model format - FileType: ", file_type, " Version: ", version)
		return FAILED


func _build_level(source_file, options):
	var world_builder = preload("res://Addons/LTDatReader/WorldBuilder.gd").new()
	world_builder.export_to_lta = self.export_to_lta
	return world_builder.build(source_file, options)
