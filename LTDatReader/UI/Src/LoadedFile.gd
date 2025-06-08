extends Node

const FILE_NONE = "none"
const FILE_ABC = "abc"
const FILE_DTX = "dtx"
const FILE_DAT = "dat"

var opened_file = ""
var file_mode = self.FILE_NONE

var scene: PackedScene
var raw_data = null


func _ready():
	self.clear()

	
func clear():
	self.set_opened_file("")
	self.file_mode = self.FILE_NONE
	self.scene = null
	self.raw_data = null


func set_opened_file(value):
	self.opened_file = value
	
	if value == "":
		OS.set_window_title("LithTools")
	else:
		# Change this line:
		OS.set_window_title("LithTools - " + self.opened_file)


func set_file_mode(value):
	self.file_mode = value
	
	var event = get_node("/root/Events")
	event.dispatch("on_file_mode_changed", [value])
	

func is_image():
	return [FILE_DTX].has(self.file_mode)

func is_model():
	return [FILE_ABC].has(self.file_mode)

func is_world():
	return [FILE_DAT].has(self.file_mode)
