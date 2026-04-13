tool
extends EditorImportPlugin

func get_importer_name():
	return "lithtech.dat.import"

func get_visible_name():
	return "Lithtech DAT/LTB Importer"

func get_recognized_extensions():
	return ["dat", "ltb"]  # Beide weiterhin erkennen

func get_save_extension():
	return "tscn"

func get_resource_type():
	return "PackedScene"

func get_preset_count():
	return 1

func get_preset_name(i):
	return "Default"

func get_import_options(i):
	return []
	
func get_option_visibility(option, options):
	return true

var _world_builder = null

func _init():
	var script = load("res://Addons/LTDatReader/WorldBuilder.gd")
	self._world_builder = script.new()

func import(source_file, save_path, options, platform_variants, gen_files):
	# Smart Detection: DAT vs LTB
	if source_file.get_extension().to_lower() == "ltb":
		# LTB-Datei --> An LTBReader delegieren
		print("LTB file detected - delegating to LTBReader")
		
		# Lade den LTBReader Importer
		var ltb_importer = load("res://addons/LTBReader/LTBImporter.gd").new()
		return ltb_importer.import(source_file, save_path, options, platform_variants, gen_files)
	
	else:
		# DAT-Datei --> Normale LTDatReader Verarbeitung
		print("DAT file detected - using LTDatReader")
		var scene = self._world_builder.build(source_file, options)
		
		var filename = save_path + "." + get_save_extension()
		print("Saving as ", filename)
		ResourceSaver.save(filename, scene)
		return OK
