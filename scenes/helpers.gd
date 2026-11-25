extends Node

var debug_file_io = false

# Crash the game and display the error message.
func crash(message):
	push_error(message)
	print("FATAL ERROR: " + message)
	get_tree().quit()

func map(array, object, f):
	var new_array = []
	for i in range(array.size()):
		new_array.push_back(object.call(f, array[i]))
	return new_array

# Run a simple command with arguments, blocking, using OS.execute.
func exec(command, args=[], crash_on_fail=true):
	var debug = false
	
	if debug:
		print("exec: %s [%s]" % [command, ", ".join(PackedStringArray(args))])
		
	var output = []
	var exit_code = OS.execute(command, args, output, true, true)
	output = output[0] if output.size() > 0 else ""
		
	if exit_code != 0 and crash_on_fail:
		helpers.crash("OS.execute failed: %s [%s] Output: %s \nExit Code %d" % [command, ", ".join(PackedStringArray(args)), output, exit_code])
	elif debug:
		print("Output: %s" %output)

	return {"output": output, "exit_code": exit_code}

func exec_async(command, args=[]):
	OS.execute(command, args, [], false, true)

# Return the contents of a file. If no fallback_string is provided, crash when
# the file doesn't exist.
func read_file(path, fallback_string=null):
	if debug_file_io:
		print("reading " + path)
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		return file.get_as_text()
	else:
		if fallback_string != null:
			return fallback_string
		else:
			helpers.crash("File %s could not be read, and has no fallback" % path)

func write_file(path, content):
	if debug_file_io:
		print("writing " + path)
	
	# Create the base directory of the file, if it doesn't exist.
	var dirname = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dirname):
		var directory_error = DirAccess.make_dir_recursive_absolute(dirname)
		if directory_error != OK:
			push_error("Could not create directory %s (error %d)" % [dirname, directory_error])
			return false

	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open file for writing: %s" % path)
		return false
	file.store_string(content)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Could not finish writing file %s (error %d)" % [path, write_error])
		return false
	return true

func parse_args():
	var arguments = {}
	for argument in OS.get_cmdline_args():
		if argument.substr(0, 2) == "--":
			# Parse valid command-line arguments into a dictionary
			if argument.find("=") > -1:
				var key_value = argument.split("=")
				arguments[key_value[0].lstrip("--")] = key_value[1]
			else:
				arguments[argument.lstrip("--")] = true
	return arguments
	
func careful_delete(path_inside):
	var expected_prefix = "%s/tmp/" % OS.get_user_data_dir()
	
	var os = OS.get_name()
	if os == "Windows":
		# In the game, we use forward slashes:
		expected_prefix = expected_prefix.replace("\\", "/")
		# Windows treats paths case-insensitively:
		expected_prefix = expected_prefix.to_lower()
		path_inside = path_inside.to_lower()
	
	if path_inside.substr(0,expected_prefix.length()) != expected_prefix:
		helpers.crash("Refusing to delete directory %s that does not start with %s" % [path_inside, expected_prefix])
	else:
		game.global_shell.cd(game.tmp_prefix)
		game.global_shell.run("rm -rf '%s'" % path_inside)

func parse(file):
	var text = read_file(file)
	var result = {}
	var current_section
	
	var section_regex = RegEx.new()
	section_regex.compile("^\\[(.*)\\]$")
	
	var assignment_regex = RegEx.new()
	assignment_regex.compile("^([a-z ]+)=(.*)$")
	
	for line in text.split("\n"):
		# Skip comments.
		if line.substr(0, 1) == ";":
			continue
		
		# Parse a [section name].
		var m = section_regex.search(line)
		if m:
			current_section = m.get_string(1)
			result[current_section] = ""
			continue
		
		# Parse a direct=assignment.
		m = assignment_regex.search(line)
		if m:
			var key = m.get_string(1).strip_edges()
			var value = m.get_string(2).strip_edges()
			result[key] = value
			continue
			
		# At this point, the line is just content belonging to the current section.
		if current_section:
			result[current_section] += line + "\n"
	
	for key in result:
		result[key] = result[key].strip_edges()
	
	return result

func abbreviate(text, max_length):
	if text.length() > max_length-3:
		text = text.substr(0, max_length-3) + "..."
	
	return text
