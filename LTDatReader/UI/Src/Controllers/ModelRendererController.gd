extends Node

export  var single_thread_loading = true





var loaded_file: LoadedFile

var _model_builder = preload("res://Addons/ABCReader/ModelBuilder.gd").new()
var _world_builder = preload("res://Addons/LTDatReader/WorldBuilder.gd").new()
var _texture_builder = preload("res://Addons/DTXReader/TextureBuilder.gd").new()
var loading_screen = null
var global_controller = null

var _loaded_file_path = ""
var _loaded_file = null

var default_model_scale = 0.05


var loading = false

var loading_mutex = null
var loading_thread = null


func _ready():
	self.loading = false
	self.loading_screen = get_node("/root/Root/UI/LoadingScreen")
	assert (loading_screen)
	
	self.global_controller = get_node("/root/Root/UI")
	assert (global_controller)
	
	self.loaded_file = get_node("/root/LoadedFile")
	
	loading_mutex = Mutex.new()
	loading_thread = Thread.new()

	
	pass


func on_file_load(path):
	if loading:
		return
		
	if loading_thread.is_active():
		loading_thread.wait_to_finish()
	
	
	loading_mutex.lock()
	
	loading_screen.loading(true)
	
	
	if self._loaded_file != null:
		remove_child(self._loaded_file)
		
		self._loaded_file.free()
		self._loaded_file = null
	
	
	
	self._loaded_file_path = path
	
	
	loading_mutex.unlock()
	
	loading = true
	
	if single_thread_loading:
		_threaded_load(path)
	else:
		var response = loading_thread.start(self, "_threaded_load", path)
		print("Thread returned ", response)


func _threaded_load(path):
	if not loading:
		loading = false
		return
		
	var file_mode = LoadedFile.FILE_NONE
	var raw_file = null
		
	var scene = null
	if ".dat" in path.to_lower() or ".ltb" in path.to_lower():
		scene = self._world_builder.build(path, [])
		raw_file = scene
	elif ".abc" in path.to_lower():
		scene = self._model_builder.build(path, [])
		raw_file = scene
		file_mode = LoadedFile.FILE_ABC
	elif ".dtx" in path.to_lower():
		
		
		
		var texture = self._texture_builder.build(path, [])
		
		if texture == null:
			loading_mutex.lock()
			print("Failed to load texture...")
			self.loaded_file.clear()
			loading_screen.loading(false)
			loading_mutex.unlock()
			
			loading = false
			return
			
		var tex_rect = TextureRect.new()
		tex_rect.texture = texture
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.anchor_right = 1
		tex_rect.anchor_bottom = 1
		
		
		var material = CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		tex_rect.material = material
		
		var control = Control.new()
		control.anchor_right = 1
		control.anchor_bottom = 1
		
		var bg = ColorRect.new()
		bg.color = Color(0.0, 0.0, 0.0, 1.0)
		bg.anchor_right = 1
		bg.anchor_bottom = 1
		
		control.add_child(bg)
		control.add_child(tex_rect)
		bg.owner = control
		tex_rect.owner = control
		
		scene = PackedScene.new()
		scene.pack(control)
		
		
		control.queue_free()
	
		file_mode = LoadedFile.FILE_DTX
		raw_file = texture
	
		
	

	
	if (scene == null):
		
		loading_mutex.lock()
		
		if self._loaded_file != null:
			self._loaded_file.queue_free()
			self._loaded_file = null
		
		self.loaded_file.clear()
		loading_screen.loading(false)
		loading_mutex.unlock()
		
		loading = false
		return
	
	
	
	
	loading_mutex.lock()
	
	self.loaded_file.raw_data = raw_file
	self.loaded_file.scene = scene
	
	self._loaded_file = scene.instance()
	
	
	
	
	if file_mode != LoadedFile.FILE_DTX:
		self._loaded_file.scale = Vector3(self.default_model_scale, self.default_model_scale, self.default_model_scale)
	
	
	call_deferred("add_child", self._loaded_file)
	
	
	
	
	if file_mode == LoadedFile.FILE_ABC:
		self._loaded_file.on_attach(self._model_builder.model)
		
		
		var anim_player: AnimationPlayer = self._loaded_file.get_child(1)
		var anim_list = anim_player.get_animation_list()
		anim_player.play(anim_list[0])
	
	loading_screen.loading(false)
	
	
	self.loaded_file.set_opened_file(path)
	self.loaded_file.set_file_mode(file_mode)
	
	
	loading_mutex.unlock()
	
	loading = false
	

func _exit_tree():
	loading_thread.wait_to_finish()
