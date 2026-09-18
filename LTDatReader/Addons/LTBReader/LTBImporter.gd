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

	# Die-Hard:-Nakatomi-Plaza (DHNP) verpackt sein Modell in einen eigenen,
	# kleinen LTB-Wrapper-Container (siehe DHNPWrapper.gd). Das muss VOR dem
	# normalen FileType/Version-Peek unten geprueft werden, weil der Wrapper
	# an Byte 0 etwas komplett anderes stehen hat (ein LTString "LTBHeader").
	var dhnp_wrapper = preload("res://Addons/LTBReader/DHNPWrapper.gd")
	if dhnp_wrapper.is_dhnp(file):
		var wrapper = dhnp_wrapper.read_wrapper(file)
		file.close()

		if not wrapper.ok:
			print("DHNP-Wrapper erkannt, aber Lesen fehlgeschlagen")
			return FAILED

		print("DHNP-LTB erkannt - FileType: ", wrapper.file_type, " Version: ", wrapper.version)

		var scene = FAILED
		if wrapper.file_type == dhnp_wrapper.DHNP_ABC_FILE_TYPE:
			print("DHNP ABC-Body - delegiere an ABCReader/ModelBuilder.gd")
			var abc_builder = preload("res://Addons/ABCReader/ModelBuilder.gd").new()
			scene = abc_builder.build(source_file, options, wrapper.offset)
		elif wrapper.file_type == dhnp_wrapper.DHNP_D3D_FILE_TYPE:
			print("DHNP D3D-Hybrid-Body - delegiere an LTBModelBuilder_DHNP_D3D.gd")
			var d3d_builder = preload("res://Addons/LTBReader/LTBModelBuilder_DHNP_D3D.gd").new()
			scene = d3d_builder.build(source_file, options, wrapper.offset)
		else:
			print("Unbekannter DHNP FileType: ", wrapper.file_type)
			return FAILED

		if scene == null or scene == FAILED:
			return FAILED

		var dhnp_filename = save_path + "." + get_save_extension()
		print("Saving DHNP-LTB as ", dhnp_filename)
		ResourceSaver.save(dhnp_filename, scene)
		return OK

	var file_type = file.get_32()
	var version = file.get_16()
	file.close()
	
	print("LTB Detection - Type: ", file_type, " Version: ", version)
	
	# Level-LTB? --> An LTDatReader weiterleiten
	if version == 66:  # PS2 Level Format
		print("Level-LTB detected - delegating to LTDatReader")
		# Lade den LTDatReader WorldBuilder
		var world_builder = preload("res://Addons/LTDatReader/WorldBuilder.gd").new()
		var scene = world_builder.build(source_file, options)
		
		var filename = save_path + "." + get_save_extension()
		print("Saving Level-LTB as ", filename)
		ResourceSaver.save(filename, scene)
		return OK
	
	# Model-LTB? --> Unser Plugin
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