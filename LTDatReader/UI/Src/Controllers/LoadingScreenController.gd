extends Node




var background = null

var target_alpha = 0.0
var current_alpha = 0.0

var current_load_time = 0
export  var max_alpha_fade_in_time = 2

export  var on_alpha = 0.45
export  var off_alpha = 0.0



func _ready():
	
	background = get_node("./Background") as ColorRect
	assert (background)
	
	background.color = Color(0.0, 0.0, 0.0, off_alpha)
	
	current_alpha = off_alpha
	target_alpha = current_alpha
	
	pass
	
func loading(on):
	if on:
		target_alpha = on_alpha
	else:
		target_alpha = off_alpha
		
	current_load_time = 0



func _process(delta):
	current_load_time += delta
	
	if current_load_time > max_alpha_fade_in_time:
		return
	
	if current_alpha == target_alpha:
		return
	
	
	current_alpha = current_alpha + (target_alpha - current_alpha) * (current_load_time / max_alpha_fade_in_time)
	background.color = Color(0.0, 0.0, 0.0, current_alpha)
	pass

