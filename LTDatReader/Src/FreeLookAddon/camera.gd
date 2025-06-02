extends Camera

export (float, 0.0, 1.0) var sensitivity = 0.25


var _mouse_position = Vector2(0.0, 0.0)
var _total_pitch = 0.0


var _direction = Vector3(0.0, 0.0, 0.0)
var _velocity = Vector3(0.0, 0.0, 0.0)
var _acceleration = 30
var _deceleration = - 10
var _vel_multiplier = 4


var _w = false
var _s = false
var _a = false
var _d = false
var _q = false
var _e = false


var bindings = {






}

func read_keys_from_config():
	var config = ConfigFile.new()
	var err = config.load("./settings.cfg")

	if err != OK:
		return
		
	
	var code = config.get_value("Bindings", "move_forwards", KEY_W)
	bindings[code] = "move_forwards"
	code = config.get_value("Bindings", "move_backwards", KEY_S)
	bindings[code] = "move_backwards"
	code = config.get_value("Bindings", "move_left", KEY_A)
	bindings[code] = "move_left"
	code = config.get_value("Bindings", "move_right", KEY_D)
	bindings[code] = "move_right"
	code = config.get_value("Bindings", "move_up", KEY_Q)
	bindings[code] = "move_up"
	code = config.get_value("Bindings", "move_down", KEY_E)
	bindings[code] = "move_down"



func _init():
	self.read_keys_from_config()

func _input(event):
	
	if event is InputEventMouseMotion:
		_mouse_position = event.relative
	
	
	if event is InputEventMouseButton:
		match event.button_index:
			BUTTON_RIGHT:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE)
			BUTTON_WHEEL_UP:
				_vel_multiplier = clamp(_vel_multiplier * 1.1, 0.2, 256)
			BUTTON_WHEEL_DOWN:
				_vel_multiplier = clamp(_vel_multiplier / 1.1, 0.2, 256)

	
	if event is InputEventKey:
		
		
		if event.scancode in bindings:
			var action = bindings[event.scancode]
			
			if action == "move_forwards":
				_w = event.pressed
			if action == "move_backwards":
				_s = event.pressed
			if action == "move_left":
				_a = event.pressed
			if action == "move_right":
				_d = event.pressed
			if action == "move_up":
				_q = event.pressed
			if action == "move_down":
				_e = event.pressed















func _process(delta):
	_update_mouselook()
	_update_movement(delta)


func _update_movement(delta):
	
	_direction = Vector3(_d as float - _a as float, 
							_e as float - _q as float, 
							_s as float - _w as float)
	
	
	
	var offset = _direction.normalized() * _acceleration * _vel_multiplier * delta\
	+ _velocity.normalized() * _deceleration * _vel_multiplier * delta
	
	
	if _direction == Vector3.ZERO and offset.length_squared() > _velocity.length_squared():
		
		_velocity = Vector3.ZERO
	else:
		
		_velocity.x = clamp(_velocity.x + offset.x, - _vel_multiplier, _vel_multiplier)
		_velocity.y = clamp(_velocity.y + offset.y, - _vel_multiplier, _vel_multiplier)
		_velocity.z = clamp(_velocity.z + offset.z, - _vel_multiplier, _vel_multiplier)
	
		translate(_velocity * delta)


func _update_mouselook():
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_mouse_position *= sensitivity
		var yaw = _mouse_position.x
		var pitch = _mouse_position.y
		_mouse_position = Vector2(0, 0)
		
		
		pitch = clamp(pitch, - 90 - _total_pitch, 90 - _total_pitch)
		_total_pitch += pitch
	
		rotate_y(deg2rad( - yaw))
		rotate_object_local(Vector3(1, 0, 0), deg2rad( - pitch))
