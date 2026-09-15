extends Node

var model_renderer_controller = null


func _ready():
	
	model_renderer_controller = get_node("/root/Root/UI/ModelRenderer")
	assert (model_renderer_controller)
	
	# Center window on screen
	var screen_size = OS.get_screen_size()
	var window_size = OS.get_window_size()
	OS.set_window_position((screen_size - window_size) / 2)
	
	get_tree().connect("files_dropped", self, "on_file_dropped")
	pass

func on_file_dropped(files: PoolStringArray, screen: int):
	print("Files!", files, screen)
	
	
	if len(files) > 1:
		return
		
	model_renderer_controller.on_file_load(files[0])
	
	pass




