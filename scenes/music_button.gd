extends Button


func _ready():
	toggle_mode = true
	_update_music_state()


func toggle_music():
	game.toggle_music()
	_update_music_state()


func _update_music_state():
	button_pressed = game.music_muted
	text = "Unmute music" if game.music_muted else "Mute music"
