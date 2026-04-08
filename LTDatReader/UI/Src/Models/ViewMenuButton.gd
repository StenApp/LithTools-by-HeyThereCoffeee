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
	# Alpha-Modus: bg ausblenden + BLEND_MODE_PREMULT_ALPHA zeigt Alphakanal
	var model_renderer = get_node_or_null("/root/Root/UI/ModelRenderer")
	if model_renderer == null:
		return
	var displayed = model_renderer._loaded_file
	if displayed == null:
		return
	var bg = displayed.get_child(0) as ColorRect
	var tex_rect = displayed.get_child(1) as TextureRect
	if bg == null or tex_rect == null or tex_rect.material == null:
		return
	if self.loaded_file.is_fullbrite:
		print("[Toggle Alpha] Texture has DTX_FULLBRITE - no real alpha channel.")
		return
	is_alpha_on = not is_alpha_on
	if is_alpha_on:
		bg.visible = false
		tex_rect.material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	else:
		bg.visible = true
		tex_rect.material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	
	
	

