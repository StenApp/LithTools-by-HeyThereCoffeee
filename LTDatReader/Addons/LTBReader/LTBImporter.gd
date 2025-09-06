tool
extends EditorImportPlugin

func get_importer_name():
	return "lithtech.ltb.import"

func get_visible_name():
	return "Lithtech LTB Importer"

func get_recognized_extensions():
	return ["ltb"]

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

var _model_builder = null

func _init():
	var path = self.get_script().get_path().get_base_dir() + "/LTBModelBuilder.gd"
	self._model_builder = load(path).new()

func import(source_file, save_path, options, platform_variants, gen_files):
	# Erst checken: Ist es ein Model-LTB oder Level-LTB?
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		return FAILED
	
	var file_type = file.get_32()
	var version = file.get_16()
	file.close()
	
	print("LTB Detection - Type: ", file_type, " Version: ", version)
	
	# Level-LTB? → An LTDatReader weiterleiten
	if version == 66:  # PS2 Level Format
		print("Level-LTB detected - delegating to LTDatReader")
		# Lade den LTDatReader WorldBuilder
		var world_builder = load("res://Addons/LTDatReader/WorldBuilder.gd").new()
		var scene = world_builder.build(source_file, options)
		
		var filename = save_path + "." + get_save_extension()
		print("Saving Level-LTB as ", filename)
		ResourceSaver.save(filename, scene)
		return OK
	
	# Model-LTB? → Unser Plugin
	elif version == 2:  # NOLF1 Model Format
		print("Model-LTB detected - using LTB Model Plugin")
		var scene = self._model_builder.build(source_file, options)
		
		var filename = save_path + "." + get_save_extension()
		print("Saving Model-LTB as ", filename)
		ResourceSaver.save(filename, scene)
		return OK
	
	# Unbekannt
	else:
		print("Unknown LTB version: ", version)
		return FAILED