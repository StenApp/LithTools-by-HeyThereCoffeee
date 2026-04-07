extends Node


signal on_file_okay(path)
signal on_options_changed()

var file_dialog = FileDialog.new()
var global_controller = null
var loaded_file: LoadedFile

const SETTINGS_PATH = "./settings.cfg"
const SETTINGS_SECTION = "Worlds"
const SETTINGS_KEY = "export_to_lta_on_load"

var export_to_lta_on_load: bool = false

var options = [
	[0, "Open"],
	[2, ""],   # placeholder – label set dynamically in _ready / _build_lta_label()
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
	return ("[x] Export LTA on Load" if export_to_lta_on_load else "[ ] Export LTA on Load")

func _load_export_to_lta_setting():
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		export_to_lta_on_load = config.get_value(SETTINGS_SECTION, SETTINGS_KEY, false)
	else:
		export_to_lta_on_load = false
	# Refresh label in options array
	options[1][1] = _build_lta_label()

func _save_export_to_lta_setting():
	# ConfigFile.save() strips all comments, so we do an in-place text replacement instead.
	var f = File.new()
	if f.open(SETTINGS_PATH, File.READ) != OK:
		push_error("FileMenuButton: Cannot read settings.cfg")
		return
	var content = f.get_as_text()
	f.close()

	var new_val = "true" if export_to_lta_on_load else "false"
	# Replace the value on the export_to_lta_on_load line, keeping everything else intact.
	var regex = RegEx.new()
	regex.compile("(export_to_lta_on_load\\s*=\\s*)(true|false)")
	var result = regex.search(content)
	if result:
		content = content.substr(0, result.get_start(2)) + new_val + content.substr(result.get_end(2))
	else:
		# Key not found - append it under [Worlds] as fallback
		push_warning("FileMenuButton: export_to_lta_on_load not found in settings.cfg, appending")
		content += "\nexport_to_lta_on_load = " + new_val + "\n"

	if f.open(SETTINGS_PATH, File.WRITE) != OK:
		push_error("FileMenuButton: Cannot write settings.cfg")
		return
	f.store_string(content)
	f.close()

func on_toggle_export_to_lta():
	export_to_lta_on_load = not export_to_lta_on_load
	_save_export_to_lta_setting()
	options[1][1] = _build_lta_label()
	emit_signal("on_options_changed")

func _ready():
	global_controller = get_node("/root/Root/UI")
	assert (global_controller)
	
	self.loaded_file = get_node("/root/LoadedFile")
	
	var events = get_node("/root/Events")
	events.connect("on_file_mode_changed", self, "on_file_mode_changed")
	
	_load_export_to_lta_setting()
	
	self.file_dialog.access = self.file_dialog.ACCESS_FILESYSTEM
	add_child(file_dialog)

func on_file_open():
	self.file_dialog.connect("file_selected", self, "on_file_selected")
	self.file_dialog.mode = self.file_dialog.MODE_OPEN_FILE
	
	# Filter für unterstützte Dateitypen
	self.file_dialog.set_filters(PoolStringArray([
		"*.ltb ; Lithtech Binary File (Model/Level)",
		"*.dat ; Lithtech DAT File (Level)",
		"*.abc ; Lithtech ABC File (Model)", 
		"*.dtx ; Lithtech DTX File (Texture)"
		#"* ; All Files"
	]))
	
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
