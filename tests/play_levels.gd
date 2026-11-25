extends SceneTree

var game
var screen
var failures: Array[String] = []
var level_key: String

func _initialize():
	run.call_deferred()

func check(condition: bool, message: String):
	if not condition:
		failures.append("%s: %s" % [level_key, message])

func goal_feedback() -> Array:
	var flags := []
	for label in screen.goals.get_children():
		if not label.is_queued_for_deletion():
			flags.append(label.get_theme_stylebox("normal").bg_color.g > 0.3)
	return flags

func file_item(filename: String):
	for item in screen.file_browser.grid.get_children():
		if not item.is_queued_for_deletion() and item.label == filename:
			return item
	return null

func append_line(filename: String, line: String):
	var browser = screen.file_browser
	var item = file_item(filename)
	check(item != null, "file missing: " + filename)
	if item == null:
		return
	browser.item_clicked(item)
	var expected: String = browser.text_edit.text + line + "\n"
	browser.text_edit.text = expected
	browser.save_button.pressed.emit()
	await process_frame
	item = file_item(filename)
	check(item != null, "saved file missing: " + filename)
	if item != null:
		browser.item_clicked(item)
		check(browser.text_edit.visible and browser.text_edit.text == expected, "reopened " + filename)
		browser.close()

func mouse_button_at(position: Vector2, pressed: bool):
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func move_mouse(position: Vector2, dragging := false):
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	root.push_input(event, true)

func play_commit(message: String):
	var card = get_first_node_in_group("cards")
	# Let the card finish moving into the hand before aiming at it.
	await create_timer(0.65).timeout
	var pickup: Vector2 = card.get_node("Area2D").get_global_transform_with_canvas().origin
	move_mouse(pickup)
	await physics_frame
	await physics_frame
	mouse_button_at(pickup, true)
	var drop := pickup - Vector2(0, 320)
	move_mouse(drop, true)
	await process_frame
	mouse_button_at(drop, false)

	var editor = screen.terminal.get_node("TextEditor")
	var deadline := Time.get_ticks_msec() + 10000
	while not editor.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	check(editor.visible, "dragging the commit card did not open the editor")
	if not editor.visible:
		return
	check(not screen.file_browser.save_button.visible, "closed file editor shows a second Save button")
	var save_button = editor.get_node("SaveButton")
	check(editor.get_global_rect().is_equal_approx(screen.terminal.get_global_rect()), "message editor must fill the terminal")
	check(editor.get_global_rect().encloses(save_button.get_global_rect()), "Save falls outside the editor")
	check(editor.has_focus() and save_button.disabled, "blank message must have focus and disable Save")
	for character in message:
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = character.to_upper().unicode_at(0)
		key.unicode = character.unicode_at(0)
		root.push_input(key, true)
		key.pressed = false
		root.push_input(key, true)
	await process_frame
	check(editor.text == message and not save_button.disabled, "editor did not accept the typed message")
	var save_at: Vector2 = save_button.get_global_transform_with_canvas() * (save_button.size / 2)
	move_mouse(save_at)
	mouse_button_at(save_at, true)
	mouse_button_at(save_at, false)
	deadline = Time.get_ticks_msec() + 10000
	while not screen.terminal.input.editable and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not editor.visible and screen.terminal.input.editable, "clicking Save did not finish the commit")
	var subject = screen.terminal.repository.shell.run("git log -1 --format=%s", false)
	check(subject.strip_edges() == message, "saved commit message differs")

func act(action):
	if action is String:
		screen.terminal.input.text = action
		screen.terminal.input.text_submitted.emit(action)
		await screen.terminal.command_completed
	elif action.has("append"):
		await append_line(action.append[0], action.append[1])
	else:
		await play_commit(action.commit_card)
	await process_frame

func saved() -> bool:
	var progress = JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
	return level_key in progress.solved_levels

func run_case(sample, chapter, index: int):
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	await process_frame
	screen = current_scene
	await act(sample.wrong)
	if sample.has("verify_wrong"):
		var shell = screen.terminal.repository.shell
		shell.run(sample.verify_wrong, false)
		check(shell.exit_code == 0, "incorrect scenario was not reproduced")
	var flags := goal_feedback()
	check(flags == sample.expected_goals, "wrong move produced goals %s, expected %s" % [flags, sample.expected_goals])
	check(not screen.next_level_button.visible and not screen.level_congrats.visible and not saved(), "wrong move awarded completion")

	var practice: bool = chapter.slug == "sandbox"
	if practice:
		check("fatal:" in screen.terminal.output.get_parsed_text(), "missing Git error")
	elif level_key not in ["intro/cli", "intro/init"]:
		# Destructive mistakes (such as dropping the stash) need a fresh exercise.
		screen.reload_level()
		await process_frame
	for action in sample.solution:
		await act(action)
	if practice:
		var subject = screen.terminal.repository.shell.run("git log -1 --format=%s").strip_edges()
		check(subject == "Practice" and not saved() and not screen.next_level_button.visible, "sandbox recovery")
		return
	flags = goal_feedback()
	check(flags.size() == sample.expected_goals.size() and not flags.has(false), "solution produced goals %s" % [flags])
	check(saved() and screen.next_level_button.visible and screen.level_congrats.visible, "solution did not award completion")
	screen.next_level_button.pressed.emit()
	await process_frame
	await process_frame
	if index + 1 < chapter.levels.size():
		check(current_scene == screen and screen.level_name.text == chapter.levels[index + 1].title, "wrong next lesson")
	else:
		check(current_scene.scene_file_path == "res://scenes/level_select.tscn", "chapter exit")

func run():
	# Refuse to exercise the player's repositories if invoked without the launcher.
	if not OS.get_user_data_dir().get_file().begins_with("omg-tests-"):
		quit(1)
		return
	game = root.get_node("game")
	var chapters = root.get_node("levels").chapters
	var cases = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var count := 0
	for ci in chapters.size():
		var chapter = chapters[ci]
		for li in chapter.levels.size():
			level_key = chapter.slug + "/" + chapter.levels[li].slug
			check(cases.has(level_key), "missing regression case")
			if not cases.has(level_key):
				continue
			game.current_chapter = ci
			game.current_level = li
			var before := failures.size()
			await run_case(cases[level_key], chapter, li)
			if before == failures.size():
				print("PASS ", level_key)
			count += 1
	if failures.is_empty() and count == cases.size() and count > 0:
		print("PASS all level regressions (", count, ")")
		quit()
	else:
		printerr("\n".join(failures))
		quit(1)
