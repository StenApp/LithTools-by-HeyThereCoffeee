extends MenuButton

var model = preload("res://UI/Src/Models/FileMenuButton.gd").new()
var model_renderer_controller = null
var loaded_file: LoadedFile
var popup_connected = false  # Track connection state manually

func _ready():
	add_child(model)
	
	var events = get_node("/root/Events")
	events.connect("on_file_mode_changed", self, "on_file_mode_changed")
	
	self.loaded_file = get_node("/root/LoadedFile")
	
	adjust_menus()
	
	model_renderer_controller = get_node("/root/Root/UI/ModelRenderer")
	assert (model_renderer_controller)
	
	# Debug: Print the node type to make sure we have the right one
	print("Model renderer controller type: ", model_renderer_controller.get_class())
	print("Model renderer controller script: ", model_renderer_controller.get_script())
	
	# Check if the method exists before connecting
	if model_renderer_controller.has_method("on_file_load"):
		model.connect("on_file_okay", model_renderer_controller, "on_file_load")
		print("Connected on_file_okay signal successfully")
	else:
		print("ERROR: on_file_load method not found in model_renderer_controller")

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
	
	# FIX: Only disconnect if we know it's connected
	if popup_connected:
		get_popup().disconnect("id_pressed", self, "handle_incoming_pressed_signal")
		popup_connected = false
	
	if (file_mode == LoadedFile.FILE_DTX):
		options += model.options_tex
	
	for option in options:
		get_popup().add_item(option[1], option[0])
		
	get_popup().connect("id_pressed", self, "handle_incoming_pressed_signal")
	popup_connected = true
