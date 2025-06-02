extends Node

func _init():
	VisualServer.set_debug_generate_wireframes(true)

func _input(event):
	if event is InputEventKey and Input.is_key_pressed(KEY_F1):
		var viewport = get_viewport()
		
		viewport.debug_draw = (viewport.debug_draw + 3) %6
	if event is InputEventKey and Input.is_key_pressed(KEY_F2):
		var gltf_exporter = load("res://Src/gltf_exporter.gd").GLTFExporter.new()
		gltf_exporter.process(get_tree().current_scene)
