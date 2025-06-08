extends Node


signal on_file_okay(path)

var file_dialog = FileDialog.new()
var global_controller = null
var loaded_file: LoadedFile


var options = [
	[0, "Open"], 
]

var options_tex = [
	[1, "Export"]
]

var signal_hooks = [
	[0, "id_pressed", "on_file_open"], 
]

var signal_hooks_tex = [
	[1, "id_pressed", "on_file_export"]
]

func _ready():
	global_controller = get_node("/root/Root/UI")
	assert (global_controller)
	
	self.loaded_file = get_node("/root/LoadedFile")
	
	var events = get_node("/root/Events")
	events.connect("on_file_mode_changed", self, "on_file_mode_changed")
	
	
	
	self.file_dialog.access = self.file_dialog.ACCESS_FILESYSTEM
	add_child(file_dialog)


func on_file_open():
	self.file_dialog.connect("file_selected", self, "on_file_selected")
	self.file_dialog.mode = self.file_dialog.MODE_OPEN_FILE
	self.file_dialog.set_filters(PoolStringArray(["*.abc ; Lithtech ABC Mesh File", "*.dtx ; Lithtech DTX Texture File"]))
	self.file_dialog.popup_centered_ratio(0.5)


func on_file_export():
	if self.loaded_file.file_mode != self.loaded_file.FILE_DTX:
		print("Can only export DTX!")
		return
	
	self.file_dialog.connect("file_selected", self, "on_file_selected_for_export_to_png")
	self.file_dialog.mode = self.file_dialog.MODE_SAVE_FILE
	self.file_dialog.set_filters(PoolStringArray(["*.png ; Portable Network Graphics"]))
	self.file_dialog.popup_centered_ratio(0.5)

	
func on_file_selected(path):
	
	emit_signal("on_file_okay", path)
	
	self.file_dialog.disconnect("file_selected", self, "on_file_selected")

	
func on_file_selected_for_export_to_png(path):
	
	var image = self.loaded_file.raw_data as ImageTexture
	
	if image.get_data().save_png(path) == OK:
		print("Exported as png to: " + path)
	else:
		print("Failed to save as png :(")
	
	
	
	self.file_dialog.disconnect("file_selected", self, "on_file_selected_for_export_to_png")


func on_file_mode_changed(args):
	var file_mode = args[0]
	
	
	
	pass
