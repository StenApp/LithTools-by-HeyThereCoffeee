extends Spatial

signal animation_command_string

var attached_model = null

func run_command_string(command_string : String):	
	emit_signal("animation_command_string", command_string)
# End Func

func on_attach(model):
	"""Wird aufgerufen wenn ein Model an diesen Helper angehängt wird"""
	self.attached_model = model
	print("Model attached to ABCHelper: ", model)
	
	# Hier können Sie weitere Initialisierung mit dem Model durchführen
	# falls erforderlich
# End Func
