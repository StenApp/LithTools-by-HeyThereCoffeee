extends Node


signal on_file_okay(path)
signal on_options_changed()

var file_dialog = FileDialog.new()
var global_controller = null
var loaded_file: LoadedFile

var export_to_lta_on_load: bool = false

var options = [
	[0, "Open"],
	[2, ""],   # placeholder – label set dynamically
]

var options_tex = [
	[1, "Export"]
]

var signal_hooks = [
	[0, "id_pressed", "on_file_open"],
	[2, "id_pressed", "on_toggle_export_to_lta"],
]

var signal_hooks_tex = [
	[1, "id_pressed", "on_file_export"]
]

func _build_lta_label() -> String:
	return ("[x] Export Level as LTA on Load" if export_to_lta_on_load else "[ ] Export Level as LTA on Load")

func on_toggle_export_to_lta():
	export_to_lta_on_load = not export_to_lta_on_load
	options[1][1] = _build_lta_label()
	emit_signal("on_options_changed")

func _ready():
	global_controller = get_node("/root/Root/UI")
	assert (global_controller)
	
	self.loaded_file = get_node("/root/LoadedFile")
	
	var events = get_node("/root/Events")
	events.connect("on_file_mode_changed", self, "on_file_mode_changed")
	
	options[1][1] = _build_lta_label()
	
	self.file_dialog.access = self.file_dialog.ACCESS_FILESYSTEM
	add_child(file_dialog)

func on_file_open():
	if not self.file_dialog.is_connected("file_selected", self, "on_file_selected"):
		self.file_dialog.connect("file_selected", self, "on_file_selected")
	self.file_dialog.mode = self.file_dialog.MODE_OPEN_FILE
	
	self.file_dialog.set_filters(PoolStringArray([
		"*.ltb ; Lithtech Binary File (Model/Level)",
		"*.dat ; Lithtech DAT File (Level)",
		"*.abc ; Lithtech ABC File (Model)", 
		"*.dtx ; Lithtech DTX File (Texture)"
	]))
	
	self.file_dialog.rect_position = Vector2(0, 0)
	self.file_dialog.popup_centered_ratio(0.5)

func on_file_export():
	if self.loaded_file.file_mode != self.loaded_file.FILE_DTX:
		print("Can only export DTX!")
		return
	
	if not self.file_dialog.is_connected("file_selected", self, "on_file_selected_for_export_to_png"):
		self.file_dialog.connect("file_selected", self, "on_file_selected_for_export_to_png")
	if not self.file_dialog.is_connected("popup_hide", self, "on_export_png_cancelled"):
		self.file_dialog.connect("popup_hide", self, "on_export_png_cancelled")
	self.file_dialog.mode = self.file_dialog.MODE_SAVE_FILE
	self.file_dialog.set_filters(PoolStringArray(["*.png ; Portable Network Graphics"]))
	self.file_dialog.rect_position = Vector2(0, 0)
	self.file_dialog.popup_centered_ratio(0.5)

func on_file_selected(path):
	emit_signal("on_file_okay", path)
	self.file_dialog.disconnect("file_selected", self, "on_file_selected")

func on_file_selected_for_export_to_png(path):
	var image = self.loaded_file.raw_data as ImageTexture
	if image == null:
		print("Export failed: no image loaded or not a DTX file.")
		return
	if image.get_data().save_png(path) == OK:
		print("Exported as png to: " + path)
	else:
		print("Failed to save as png :(")
	self.file_dialog.disconnect("file_selected", self, "on_file_selected_for_export_to_png")

func on_export_png_cancelled():
	if self.file_dialog.is_connected("file_selected", self, "on_file_selected_for_export_to_png"):
		self.file_dialog.disconnect("file_selected", self, "on_file_selected_for_export_to_png")
	if self.file_dialog.is_connected("popup_hide", self, "on_export_png_cancelled"):
		self.file_dialog.disconnect("popup_hide", self, "on_export_png_cancelled")

func on_file_mode_changed(args):
	var file_mode = args[0]
	pass
