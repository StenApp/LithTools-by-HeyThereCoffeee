extends Node

func build(source_file, options):
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		print("Failed to open " + source_file)
		return null
		
	print("Opened " + source_file)
	
	var path = self.get_script().get_path().get_base_dir() + "/Models/DTX.gd"
	var dtx_file = load(path)
	
	# Model as in MVC model, not mesh model!
	var model = dtx_file.DTX.new()
	
	var response = model.read(file)
	
	file.close()
	
	if response.code == model.IMPORT_RETURN.ERROR:
		print("IMPORT ERROR: " + str(response.message))
		return null
		
	var texture = ImageTexture.new()
	texture.create_from_image(model.image)
	
	return texture
