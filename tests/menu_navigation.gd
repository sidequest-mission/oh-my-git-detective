extends Node

func _ready():
	await get_tree().process_frame
	if not OS.get_user_data_dir().get_file().begins_with("omg-tests-"):
		get_tree().quit(1)
		return
	var title := "res://scenes/title.tscn"
	var selector := "res://scenes/level_select.tscn"
	await get_tree().process_frame
	for attempt in range(2):
		if not await click_to_scene("Menu/Levels", selector):
			return
		# Back must also work while the list is scrolled.
		get_tree().current_scene.get_node("ScrollContainer").scroll_vertical = 400 * attempt
		await get_tree().process_frame
		if not await click_to_scene("Button", title):
			return
	if not await click_to_scene("Menu/Sandbox", "res://scenes/main.tscn"):
		return
	if not await click_to_scene("Menu/BackButton", title):
		return
	var result = FileAccess.open(OS.get_environment("OMG_MENU_RESULT"), FileAccess.WRITE)
	result.store_line("PASS packaged menu navigation")
	result.close()
	get_tree().quit()

func click_to_scene(path: String, destination: String) -> bool:
	var button = get_tree().current_scene.get_node(path)
	var position: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != destination:
		printerr("FAIL ", path, " did not open ", destination)
		get_tree().quit(1)
		return false
	return true
