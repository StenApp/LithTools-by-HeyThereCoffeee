extends Node

var model_renderer_controller = null


func _ready():
	
	model_renderer_controller = get_node("/root/Root/UI/ModelRenderer")
	assert (model_renderer_controller)
	
	get_tree().connect("files_dropped", self, "on_file_dropped")
	pass

func on_file_dropped(files: PoolStringArray, screen: int):
	print("Files!", files, screen)
	
	
	if len(files) > 1:
		return
		
	model_renderer_controller.on_file_load(files[0])
	
	pass




