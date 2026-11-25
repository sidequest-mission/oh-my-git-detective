extends Control

const FileBrowserItemScript = preload("res://scenes/file_browser_item.gd")

enum FileBrowserMode {
	WORKING_DIRECTORY,
	COMMIT,
	INDEX
}

signal saved

@export var title: String: set = _set_title
@export var mode: FileBrowserMode = FileBrowserMode.WORKING_DIRECTORY: set = _set_mode

var shell
var commit : set = _set_commit
var repository

var open_file

@onready var grid = $Panel/Margin/Rows/Scroll/Grid
@onready var text_edit = $Panel/TextEdit
@onready var save_button = $Panel/SaveButton
@onready var title_label = $Panel/Margin/Rows/Title

func _ready():
	text_edit.visibility_changed.connect(_update_editor_buttons)
	update()
	_set_mode(mode)
	_set_title(title)
	$PopupMenu.add_item("New file", 1)

func _input(event):
	if event.is_action_pressed("save"):
		if text_edit.visible:
			save()
	
func clear():
	for item in grid.get_children():
		item.queue_free()
		
func substr2(s):
	return s.substr(2)
		
func update():
	if grid and repository:
		clear()
		
		# Files in the working directory.
		var wd_files = Array(repository.shell.run("find . -type f -not -path '*/\\.git/*'").split("\n"))
		# The last entry is an empty string, remove it.
		wd_files.pop_back()
		wd_files = helpers.map(wd_files, self, "substr2")
		
		var files = wd_files
		
		var head_files
		var index_files
		
		if repository.there_is_a_git_cache:
			# Files in the HEAD commit.
			head_files = Array(repository.shell.run("git ls-tree --name-only -r HEAD 2> /dev/null || true").split("\n"))
			# The last entry is an empty string, remove it.
			head_files.pop_back()
			# Files in the index.
			index_files = Array(repository.shell.run("git ls-files -s | cut -f2 | uniq").split("\n"))
			# The last entry is an empty string, remove it.
			index_files.pop_back()
		
			for f in head_files:
				if not f in files:
					files.push_back(f)
			for f in index_files:
				if not f in files:
					files.push_back(f)
				
		files.sort_custom(Callable(self, "very_best_sort"))
		
		for file_path in files:
			var item = preload("res://scenes/file_browser_item.tscn").instantiate()
			item.label = file_path
			item.repository = repository
			item.connect("clicked", Callable(self, "item_clicked"))
			grid.add_child(item)
		
		if files.size() > 0:
			game.notify("Click on these files to edit them!", self, "file-browser")
						
		if false:
			match mode:
				FileBrowserMode.WORKING_DIRECTORY:
					if shell:
						
						var deleted_files = []
						if shell.run("test -d .git && echo yes || echo no") == "yes\n":
							deleted_files = Array(shell.run("git status -s | grep '^.D' | sed 's/^...//'").split("\n"))
							deleted_files.pop_back()
						
						#var is_visible = false
						for file_path in files:
							if file_path.substr(0, 5) == ".git/":
								continue
							#is_visible = true
							var item = preload("res://scenes/file_browser_item.tscn").instantiate()
							item.label = file_path
							item.connect("clicked", Callable(self, "item_clicked"))
							item.connect("deleted", Callable(self, "item_deleted"))
							item.status = get_file_status(file_path, shell, 1)
								
							grid.add_child(item)
						#visible = is_visible				
						
				FileBrowserMode.COMMIT:
					if commit:
						# The last entry is an empty string, remove it.
						files.pop_back()
						for file_path in files:
							var item = preload("res://scenes/file_browser_item.tscn").instantiate()
							item.label = file_path
							item.connect("clicked", Callable(self, "item_clicked"))
							grid.add_child(item)
				FileBrowserMode.INDEX:
					#var is_visible = false					
					if repository and repository.there_is_a_git_cache:
						
						var deleted_files = Array(repository.shell.run("git status -s | grep '^D' | sed 's/^...//'").split("\n"))
						# The last entries are empty strings, remove them.
						
						for file_path in files:
							var item = preload("res://scenes/file_browser_item.tscn").instantiate()
							item.label = file_path
							item.connect("clicked", Callable(self, "item_clicked"))
							item.status = get_file_status(file_path, repository.shell, 0)
							grid.add_child(item)
							#if item.status != item.IconStatus.NONE:
							#	is_visible = true		
					#visible = is_visible				
						
func get_file_status(file_path, the_shell, idx):
	var file_status = the_shell.run("git status -s '%s'" % file_path)
	if file_status.length()>0:
		match file_status[idx]:
			"D":
				return FileBrowserItemScript.IconStatus.REMOVED
			"M":
				return FileBrowserItemScript.IconStatus.EDIT
			"U":
				return FileBrowserItemScript.IconStatus.CONFLICT
			" ":
				return FileBrowserItemScript.IconStatus.NONE
			"A":
				return FileBrowserItemScript.IconStatus.NEW
			"?":
				return FileBrowserItemScript.IconStatus.UNTRACKED
	else:
		return FileBrowserItemScript.IconStatus.NONE

func item_clicked(item):
	if not item.get_node("VBoxContainer/Control/WD").visible:
		return
		
	match mode:
		FileBrowserMode.WORKING_DIRECTORY:
			text_edit.text = helpers.read_file(repository.shell._cwd + item.label)
		FileBrowserMode.COMMIT:
			text_edit.text = commit.repository.shell.run("git show %s:\"%s\"" % [commit.id, item.label])
		FileBrowserMode.INDEX:
			if item.status == FileBrowserItemScript.IconStatus.CONFLICT:
				return
			text_edit.text = repository.shell.run("git show :\"%s\"" % [item.label])
			
	open_file = item.label
	text_edit.show()
	text_edit.grab_focus()
	
func item_deleted(item):
	helpers.careful_delete(shell._cwd + item.label)
	update()

func close():
	text_edit.hide()
	emit_signal("saved")
	
func save():
	if mode != FileBrowserMode.WORKING_DIRECTORY:
		return
	if repository == null or open_file == null or open_file.is_empty():
		push_error("Cannot save: no working-directory file is open")
		return

	# Add a newline to the end of the file if there is none.
	if text_edit.text.length() > 0 and text_edit.text.substr(text_edit.text.length()-1, 1) != "\n":
		text_edit.text += "\n"

	var file_path = repository.shell._cwd.path_join(open_file)
	if not helpers.write_file(file_path, text_edit.text):
		game.notify("Could not save %s. Check the application log for details." % open_file, self)
		return
	update()
	close()

func _set_commit(new_commit):
	commit = new_commit
	update()
	
func _update_editor_buttons():
	save_button.visible = text_edit.visible and mode == FileBrowserMode.WORKING_DIRECTORY
	$Panel/CloseButton.visible = text_edit.visible

func _set_mode(new_mode):
	mode = new_mode
	
	if save_button:
		_update_editor_buttons()
		text_edit.editable = mode == FileBrowserMode.WORKING_DIRECTORY
		text_edit.selecting_enabled = mode == FileBrowserMode.WORKING_DIRECTORY
		if mode == FileBrowserMode.WORKING_DIRECTORY:
			text_edit.focus_mode = Control.FOCUS_CLICK
		else:
			text_edit.focus_mode = Control.FOCUS_NONE

func _set_title(new_title):
	title = new_title
	if title_label:
		title_label.text = new_title
		
func _gui_input(event):
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_RIGHT:
		$PopupMenu.set_position(get_global_mouse_position())
		$PopupMenu.popup()

func very_best_sort(a,b):
	if a[0] == "." and b[0] != ".":
		return false
	if a[0] != "." and b[0] == ".":
		return true
	return a.casecmp_to(b) == -1
