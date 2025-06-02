extends MenuButton




var model = preload("res://UI/Src/Models/ViewMenuButton.gd").new()
var model_renderer_controller = null
var loaded_file: LoadedFile


func _ready():
	
	add_child(model)
	
	self.loaded_file = get_node("/root/LoadedFile")
	
	
	for option in model.options:
		get_popup().add_item(option[1], option[0])
		
	get_popup().connect("id_pressed", self, "handle_incoming_pressed_signal")
	
	var events = get_node("/root/Events")
	events.connect("on_file_mode_changed", self, "on_file_mode_changed")
	
	adjust_menus()


	
func handle_incoming_pressed_signal(id):
	var signal_hooks = model.signal_hooks
	
	if self.loaded_file.file_mode == LoadedFile.FILE_DTX:
		signal_hooks += model.signal_hooks_tex
	
	for hook in signal_hooks:
		if hook[0] == id and hook[1] == "id_pressed":
			model.call(hook[2])


func on_file_mode_changed(args):
	var mode = args[0]
	adjust_menus(mode)

func adjust_menus(file_mode = LoadedFile.FILE_NONE):
	var options = model.options
	
	
	get_popup().clear()
	get_popup().disconnect("id_pressed", self, "handle_incoming_pressed_signal")
	
	if (file_mode == LoadedFile.FILE_DTX):
		options += model.options_tex
	
	
	
	for option in options:
		get_popup().add_item(option[1], option[0])
		
	get_popup().connect("id_pressed", self, "handle_incoming_pressed_signal")
