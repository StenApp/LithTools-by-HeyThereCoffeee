extends Node




signal on_file_okay(path)

var file_dialog = FileDialog.new()
var global_controller = null
var loaded_file: LoadedFile


var is_alpha_on = false


var options = []

var options_tex = [
	[0, "Toggle Alpha"]
]

var signal_hooks = []

var signal_hooks_tex = [
	[0, "id_pressed", "on_toggle_alpha"], 
]

func _ready():
	self.loaded_file = get_node("/root/LoadedFile")


func on_toggle_alpha():
	var packed_scene = self.loaded_file.scene as PackedScene
	assert (packed_scene)
	
	var scene = packed_scene.instance()
	
	
	var texture_rect = scene.get_child(1) as TextureRect
	var blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	
	if is_alpha_on:
		is_alpha_on = false
		blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	else:
		is_alpha_on = true
	
	texture_rect.material.blend_mode = blend_mode
	
	
	

