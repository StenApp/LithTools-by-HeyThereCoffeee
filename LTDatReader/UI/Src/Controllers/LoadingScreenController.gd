extends Node




var background = null
var loading_label = null

var target_alpha = 0.0
var current_alpha = 0.0

var current_load_time = 0
export  var max_alpha_fade_in_time = 2

export  var on_alpha = 0.45
export  var off_alpha = 0.0



func _ready():
	
	background = get_node("./Background") as ColorRect
	assert (background)
	
	loading_label = get_node("./LoadingLabel") as Label
	assert (loading_label)
	loading_label.visible = false
	
	background.color = Color(0.0, 0.0, 0.0, off_alpha)
	
	current_alpha = off_alpha
	target_alpha = current_alpha
	
	pass
	
func loading(on):
	if on:
		target_alpha = on_alpha
		loading_label.visible = true
	else:
		target_alpha = off_alpha
		loading_label.visible = false
		
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

