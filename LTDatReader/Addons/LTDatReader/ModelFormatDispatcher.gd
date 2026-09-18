# res://Addons/LTDatReader/ModelFormatDispatcher.gd
tool
extends Reference

# ModelFormatDispatcher.gd -- die EINZIGE Stelle, die anhand der Datei-Bytes
# entscheidet, welcher Builder fuer eine .dat/.ltb-Datei zustaendig ist:
#
#   .dat                                   -> immer ein Level -> WorldBuilder.gd
#   .ltb, erste 4 Bytes == 66 oder 4694     -> Level-LTB (PS2) -> WorldBuilder.gd
#   .ltb, "LTBHeader"-Wrapper am Dateianfang -> Die-Hard:-Nakatomi-Plaza (DHNP):
#       FileType==4 -> ABC-Body   -> ABCReader/ModelBuilder.gd
#       FileType==1 -> D3D-Hybrid -> LTBReader/LTBModelBuilder_DHNP_D3D.gd
#   .ltb, sonst: FileType(32-Bit)+Version(16-Bit) -> Model-LTB:
#       589825/0 -> PC  (v9)  -> LTBReader/LTBModelBuilder_PC.gd
#       2/16     -> PS2 (v16) -> LTBReader/LTBModelBuilder.gd
#
# Diese Unterscheidung stand vorher direkt in WorldBuilder.build() (Level-
# LTB/Model-PC/Model-PS2 wurden dort schon per Byte-Peek erkannt und an den
# jeweils richtigen Builder weitergereicht). WorldBuilder baut jetzt
# ausschliesslich echte Level-Szenen und bekommt von hier aus nie mehr etwas
# anderes vorgesetzt -- die "ist das ueberhaupt ein Level oder ein Modell"-
# Entscheidung lebt nur noch hier.

const DHNP_WRAPPER = preload("res://Addons/LTBReader/DHNPWrapper.gd")

# "level", "model_ps2", "model_pc", "model_dhnp" -- von ModelRendererController
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

	# DHNP-Wrapper hat Vorrang vor allen anderen Checks (siehe DHNPWrapper.gd):
	# sein erstes Feld ist ein LTString, das sonst als kaputtes
	# FileType/Version-Paar fehlinterpretiert wird (genau das war der Bug,
	# der DHNP-Dateien bisher als "Unknown LTB Model format" hat scheitern
	# lassen).
	if DHNP_WRAPPER.is_dhnp(file):
		var wrapper = DHNP_WRAPPER.read_wrapper(file)
		file.close()

		if not wrapper.ok:
			print("DHNP-Wrapper erkannt, aber Lesen fehlgeschlagen: " + source_file)
			return FAILED

		print("DHNP-LTB erkannt - FileType: ", wrapper.file_type, " Version: ", wrapper.version)
		self.last_build_type = "model_dhnp"

		if wrapper.file_type == DHNP_WRAPPER.DHNP_ABC_FILE_TYPE:
			print("DHNP ABC-Body - delegiere an ABCReader/ModelBuilder.gd")
			var abc_builder = preload("res://Addons/ABCReader/ModelBuilder.gd").new()
			return abc_builder.build(source_file, options, wrapper.offset)
		elif wrapper.file_type == DHNP_WRAPPER.DHNP_D3D_FILE_TYPE:
			print("DHNP D3D-Hybrid-Body - delegiere an LTBModelBuilder_DHNP_D3D.gd")
			var d3d_builder = preload("res://Addons/LTBReader/LTBModelBuilder_DHNP_D3D.gd").new()
			return d3d_builder.build(source_file, options, wrapper.offset)
		else:
			print("Unbekannter DHNP FileType: ", wrapper.file_type)
			return FAILED

	# Kein DHNP-Wrapper -- Level-LTB (PS2) vs. Model-LTB (PC/PS2) unterscheiden.
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

	if file_type == 589825 and version == 0:
		print("Loading PC LTB Model (v9)")
		self.last_build_type = "model_pc"
		var ltb_pc_builder = preload("res://Addons/LTBReader/LTBModelBuilder_PC.gd").new()
		return ltb_pc_builder.build(source_file, options)
	elif file_type == 2 and version == 16:
		print("Loading PS2 LTB Model (v16)")
		self.last_build_type = "model_ps2"
		var ltb_ps2_builder = preload("res://Addons/LTBReader/LTBModelBuilder.gd").new()
		return ltb_ps2_builder.build(source_file, options)
	else:
		print("Unknown LTB Model format - FileType: ", file_type, " Version: ", version)
		return FAILED


func _build_level(source_file, options):
	var world_builder = preload("res://Addons/LTDatReader/WorldBuilder.gd").new()
	world_builder.export_to_lta = self.export_to_lta
	return world_builder.build(source_file, options)
