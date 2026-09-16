extends Reference

var last_flags = 0
var last_effective_width = 0
var last_effective_height = 0
var last_raw_width = 0
var last_raw_height = 0
var last_mipmap_offset = 0
var last_version = 0
var _dtx_script = preload("res://Addons/DTXReader/Models/DTX.gd")

var cached_textures = {}
var missing_textures = []
var cached_texture_dims = {}

func build(source_file, options):
	var file = File.new()
	
	# Immer lowercase verwenden damit Godot keinen Case-Mismatch meldet
	var actual_file = source_file.get_base_dir() + "/" + source_file.get_file().get_basename().to_lower() + ".dtx"
	if file.open(actual_file, File.READ) != OK:
		return null
	var model = _dtx_script.DTX.new()
	var response = model.read(file)
	file.close()
	
	if response.code == model.IMPORT_RETURN.ERROR:
		return null
	self.last_flags = model.flags
	self.last_effective_width = model.get_effective_width()
	self.last_effective_height = model.get_effective_height()
	self.last_raw_width = model.width
	self.last_raw_height = model.height
	self.last_mipmap_offset = model.mipmap_offset
	self.last_version = model.version
		
	var texture = ImageTexture.new()
	if model.image.is_compressed():
		model.image.decompress()
		
	texture.create_from_image(model.image, ImageTexture.FLAGS_DEFAULT)
	#texture.create_from_image(model.image, 0)
	return texture

# Textur-Cache, ausgelagert aus WorldBuilder.gd - gehoert inhaltlich hierher,
# da es nur ein Cache-Wrapper um build() ist, kein Godot-Szenen-Wissen braucht.
func get_cached(texture_path: String, tex_name: String):
	if tex_name in cached_textures:
		return cached_textures[tex_name]
	var tex = build(texture_path + tex_name, [])
	if tex == null:
		print("Texture not found under: ", texture_path + tex_name)
		if not missing_textures.has(texture_path + tex_name):
			missing_textures.append(texture_path + tex_name)
	cached_textures[tex_name] = tex
	if tex != null:
		cached_texture_dims[tex_name] = Vector2(last_effective_width, last_effective_height)
	return tex

func get_cached_dims(tex_name: String) -> Vector2:
	return cached_texture_dims.get(tex_name, Vector2(64, 64))

func clear_cache():
	cached_textures.clear()
	missing_textures.clear()
