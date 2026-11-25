extends TextEdit

signal closed

var _server := TCPServer.new()
var _client_connection: StreamPeerTCP
var _request_size := -1
var _editing_commit := false

func _ready():
	text_changed.connect(_update_save_button)
	var error = _server.listen(0, "127.0.0.1")
	if error != OK:
		push_error("Could not start the Git editor: %s" % error_string(error))

func _exit_tree():
	if _client_connection != null:
		_client_connection.disconnect_from_host()
	_server.stop()

func get_editor_port() -> int:
	return _server.get_local_port()

func _process(_delta):
	if _client_connection == null and _server.is_connection_available():
		_client_connection = _server.take_connection()
	if _client_connection == null:
		return
	if _client_connection.poll() != OK or _client_connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		close()
		return
	if visible:
		return
	if _request_size < 0:
		if _client_connection.get_available_bytes() < 5:
			return
		_editing_commit = _client_connection.get_u8() == 1
		_request_size = _client_connection.get_u32()
	if _client_connection.get_available_bytes() < _request_size:
		return
	open(_client_connection.get_utf8_string(_request_size))

func _input(event):
	if visible and event.is_action_pressed("save"):
		get_viewport().set_input_as_handled()
		save()

func open(content):
	text = content
	if _editing_commit and not _has_commit_message():
		text = ""
	placeholder_text = "Write a commit message, then choose Save." if _editing_commit else ""
	set_caret_line(0)
	set_caret_column(0)
	_update_save_button()
	show()
	grab_focus()

func _has_commit_message() -> bool:
	for line in text.split("\n"):
		if not line.begins_with("#") and not line.strip_edges().is_empty():
			return true
	return false

func _update_save_button():
	$SaveButton.disabled = _editing_commit and not _has_commit_message()

func save():
	if not visible or _client_connection == null or $SaveButton.disabled:
		return
	var content = text
	if not content.is_empty() and not content.ends_with("\n"):
		content += "\n"
	# A framed response saves the file. Disconnecting without a response cancels it.
	var payload = content.to_utf8_buffer()
	var response = PackedByteArray()
	response.resize(4)
	response.encode_u32(0, payload.size())
	response.append_array(payload)
	var error = _client_connection.put_data(response)
	if error != OK:
		push_error("Could not send the Git editor contents: %s" % error_string(error))
	close()

func close():
	if _client_connection != null:
		_client_connection.disconnect_from_host()
		_client_connection = null
	_request_size = -1
	_editing_commit = false
	if not visible:
		return
	text = ""
	hide()
	closed.emit()
