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
	for lesson in ["Moving through time", "Merging timelines", "Friend"]:
		if not await click_to_scene("Menu/Levels", selector):
			return
		var menu = get_tree().current_scene
		for button in menu.level_list.find_children("*", "Button", true, false):
			if button.text == lesson:
				button.pressed.emit()
				break
		await get_tree().process_frame
		await get_tree().process_frame
		var scene = get_tree().current_scene
		if scene == null or scene.scene_file_path != "res://scenes/main.tscn" or scene.level_name.text != lesson:
			fail("could not open " + lesson)
			return
		if not await check_graph(scene, "friend" if lesson == "Friend" else "yours"):
			return
		if not await click_to_scene("Menu/BackButton", title):
			return
	if not await click_to_scene("Menu/Sandbox", "res://scenes/main.tscn"):
		return
	if not await check_graph(get_tree().current_scene, "yours"):
		return
	if not await click_to_scene("Menu/BackButton", title):
		return
	var result = FileAccess.open(OS.get_environment("OMG_MENU_RESULT"), FileAccess.WRITE)
	result.store_line("PASS packaged menu navigation and graph right-clicks")
	result.close()
	get_tree().quit()

func click_to_scene(path: String, destination: String) -> bool:
	var button = get_tree().current_scene.get_node(path)
	var position: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2)
	await click_at(position, MOUSE_BUTTON_LEFT)
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != destination:
		printerr("FAIL ", path, " did not open ", destination)
		get_tree().quit(1)
		return false
	return true

func click_at(position: Vector2, button_index: MouseButton):
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = button_index
		event.pressed = pressed
		get_viewport().push_input(event, true)

func fail(message: String) -> bool:
	printerr("FAIL ", message)
	get_tree().quit(1)
	return false

func check_graph(scene, repo_name: String) -> bool:
	var repo = scene.repositories[repo_name]
	var terminal = scene.terminal
	var input: LineEdit = terminal.input
	var head: String = repo.shell.run("git rev-parse HEAD").strip_edges()
	# Allow the graph to settle into the repository panel.
	await get_tree().create_timer(0.8).timeout
	for node in repo.objects.values():
		if node.type != "commit":
			continue
		# Pick a different local commit for checkout, or the friend's latest commit.
		if repo == terminal.repository and node.id == head:
			continue
		if repo != terminal.repository and node.id != head:
			continue
		input.grab_focus()
		input.insert_text_at_caret("git checkout ")
		await get_tree().process_frame
		await click_at(node.get_global_transform_with_canvas().origin, MOUSE_BUTTON_RIGHT)
		await get_tree().physics_frame
		await get_tree().process_frame
		if input.text != "git checkout " + node.id or not input.has_focus():
			return fail(scene.level_name.text + " right-click left command as '" + input.text + "'")
		# The remote panel inserts into the local terminal, even for objects only the remote has.
		if repo == terminal.repository:
			var enter := InputEventKey.new()
			enter.keycode = KEY_ENTER
			enter.pressed = true
			get_viewport().push_input(enter, true)
			enter.pressed = false
			get_viewport().push_input(enter, true)
			var deadline := Time.get_ticks_msec() + 5000
			while not input.editable and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			if repo.shell.run("git rev-parse HEAD").strip_edges() != node.id:
				return fail(scene.level_name.text + " did not check out the selected commit")
		print("PASS graph right-click in ", scene.level_name.text)
		return true
	return fail(scene.level_name.text + " has no second commit to select")
