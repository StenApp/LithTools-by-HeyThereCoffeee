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

	# Modelle der Familie "LTB wrap" (Body 13..17) stecken in einem kleinen "LTBHeader"-Wrapper (siehe LTBWrapper.gd).
	# Das muss VOR dem normalen FileType/Version-Peek unten geprueft werden, weil an Byte 0 ein LTString steht.
	var ltb_wrapper = preload("res://Addons/LTBReader/LTBWrapper.gd")
	if ltb_wrapper.is_ltb_wrap(file):
		var wrapper = ltb_wrapper.read_wrapper(file)
		file.close()

		if not wrapper.ok:
			print("LTB-wrap erkannt, aber Lesen fehlgeschlagen")
			return FAILED

		print("LTB-wrap erkannt - FileType: ", wrapper.file_type, " Container: ", wrapper.container, " Body: ", wrapper.body_version)

		var scene = FAILED
		if wrapper.file_type == ltb_wrapper.LTB_WRAP_ABC_FILE_TYPE:
			print("LTB wrap ABC body - delegiere an ABCReader/ModelBuilder.gd")
			var abc_builder = preload("res://Addons/ABCReader/ModelBuilder.gd").new()
			scene = abc_builder.build(source_file, options, wrapper.offset)
		elif wrapper.file_type == ltb_wrapper.LTB_WRAP_D3D_FILE_TYPE:
			if wrapper.container == 8:
				print("LTB wrap Container 8 (Body-13-Hybrid mit PC-Pieces) wird nicht unterstuetzt")
				return FAILED
			if wrapper.body_version >= 14:
				print("LTB wrap Body ", wrapper.body_version, " - delegiere an LTBModelBuilder_PC.gd (wrapped)")
				var pc_builder = preload("res://Addons/LTBReader/LTBModelBuilder_PC.gd").new()
				scene = pc_builder.build(source_file, options, true)
			else:
				print("LTB wrap D3D Body 13 - delegiere an LTBModelBuilder_Wrap_D3D.gd")
				var d3d_builder = preload("res://Addons/LTBReader/LTBModelBuilder_Wrap_D3D.gd").new()
				scene = d3d_builder.build(source_file, options, wrapper.offset)
		else:
			print("Unbekannter LTB wrap FileType: ", wrapper.file_type)
			return FAILED

		if scene == null or scene == FAILED:
			return FAILED

		var wrap_filename = save_path + "." + get_save_extension()
		print("Saving LTB-wrap as ", wrap_filename)
		ResourceSaver.save(wrap_filename, scene)
		return OK

	var file_type = file.get_32()  # Low-Byte = FileType (uint8), Bytes 2-3 = Container-Version
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