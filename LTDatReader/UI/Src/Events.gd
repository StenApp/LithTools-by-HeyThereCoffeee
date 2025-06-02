extends Node







signal on_file_mode_changed

func dispatch(event: String, args):
	emit_signal(event, args)
