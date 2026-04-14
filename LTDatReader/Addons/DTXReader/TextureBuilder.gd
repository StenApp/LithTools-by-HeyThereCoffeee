extends Node

var last_flags = 0
var _dtx_script = preload("res://Addons/DTXReader/Models/DTX.gd")

func build(source_file, options):
	var file = File.new()
	
	# Versuche zuerst uppercase (.DTX) um Windows-Treiber-Warnungen zu vermeiden,
	# dann original source_file als Fallback.
	var upper_ext = source_file.get_base_dir() + "/" + source_file.get_file().get_basename() + ".DTX"
	var actual_file = upper_ext
	if file.open(actual_file, File.READ) != OK:
		actual_file = source_file
		if file.open(actual_file, File.READ) != OK:
			return null
	var model = _dtx_script.DTX.new()
	var response = model.read(file)
	file.close()
	
	if response.code == model.IMPORT_RETURN.ERROR:
		return null
	self.last_flags = model.flags
		
	var texture = ImageTexture.new()
	if model.image.is_compressed():
		model.image.decompress()
	texture.create_from_image(model.image, ImageTexture.FLAGS_DEFAULT)
	return texture
