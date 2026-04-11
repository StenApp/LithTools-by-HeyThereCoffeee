extends Node

var last_flags = 0
var _dtx_script = preload("res://Addons/DTXReader/Models/DTX.gd")

func build(source_file, options):
	var file = File.new()
	
	# Versuche erst Original, dann lowercase
	var actual_file = source_file
	if not file.file_exists(source_file) and file.file_exists(source_file.to_lower()):
		actual_file = source_file.to_lower()
	
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
