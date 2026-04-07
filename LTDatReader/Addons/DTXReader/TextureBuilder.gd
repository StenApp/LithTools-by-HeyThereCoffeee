extends Node

func build(source_file, options):
	var file = File.new()
	
	# Versuche erst Original, dann lowercase
	var actual_file = source_file
	if not file.file_exists(source_file) and file.file_exists(source_file.to_lower()):
		actual_file = source_file.to_lower()
	
	if file.open(actual_file, File.READ) != OK:
		return null
		
	var path = self.get_script().get_path().get_base_dir() + "/Models/DTX.gd"
	var dtx_file = load(path)
	var model = dtx_file.DTX.new()
	var response = model.read(file)
	file.close()
	
	if response.code == model.IMPORT_RETURN.ERROR:
		return null
		
	var texture = ImageTexture.new()
	if model.image.is_compressed():
		model.image.decompress()
	texture.create_from_image(model.image, ImageTexture.FLAGS_DEFAULT)
	return texture
