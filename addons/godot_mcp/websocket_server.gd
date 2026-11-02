@tool
extends Node
class_name MCPWebSocketServer

signal command_received(id: String, command: String, params: Dictionary)
signal client_connected()
signal client_disconnected()

const DEFAULT_PORT := 6550
const STALE_CONNECTION_TIMEOUT_MSEC := 45000
const HANDSHAKE_TIMEOUT_MSEC := 5000
const CLOSE_CODE_STALE := 4002
const CLOSE_REASON_STALE := "Connection timed out (no activity)"

var _server: TCPServer
var _clients: Dictionary = {}
var _requests: Dictionary = {}
var _next_client_id: int = 0
var _next_request_id: int = 0


func _process(_delta: float) -> void:
	if not _server:
		return

	while _server.is_connection_available():
		_accept_connection()

	for client_id in _clients.keys():
		_poll_client(client_id)


func start_server(port: int = DEFAULT_PORT, bind_address: String = "127.0.0.1") -> Error:
	_server = TCPServer.new()
	var err := _server.listen(port, bind_address)
	if err != OK:
		_server = null
		MCPLog.error("Failed to start server on %s:%d: %s" % [bind_address, port, error_string(err)])
	return err


func stop_server() -> void:
	for client_id in _clients.keys():
		_remove_client(client_id)
	_requests.clear()
	if _server:
		_server.stop()
		_server = null


func get_connected_client_count() -> int:
	var count := 0
	for client in _clients.values():
		if client["connected"]:
			count += 1
	return count


func get_connected_host() -> String:
	for client in _clients.values():
		if client["connected"]:
			var tcp: StreamPeerTCP = client["tcp"]
			return tcp.get_connected_host()
	return ""


func get_connected_port() -> int:
	for client in _clients.values():
		if client["connected"]:
			var tcp: StreamPeerTCP = client["tcp"]
			return tcp.get_connected_port()
	return 0


func send_response(response: Dictionary) -> void:
	var request_id := str(response.get("id", ""))
	if not _requests.has(request_id):
		return

	var request: Dictionary = _requests[request_id]
	_requests.erase(request_id)
	if not _clients.has(request["client_id"]):
		return

	var ws: WebSocketPeer = _clients[request["client_id"]]["ws"]
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	# Give the reply back to its sender, even if another session uses the same ID.
	var outgoing := response.duplicate()
	outgoing["id"] = request["id"]
	ws.send_text(JSON.stringify(outgoing))


func _accept_connection() -> void:
	var tcp := _server.take_connection()
	if not tcp:
		return

	var ws := WebSocketPeer.new()
	ws.outbound_buffer_size = 16 * 1024 * 1024
	var err := ws.accept_stream(tcp)
	if err != OK:
		tcp.disconnect_from_host()
		MCPLog.error("Failed to accept WebSocket stream: %s" % error_string(err))
		return

	# Idle sessions can stay connected without locking other sessions out.
	_clients[_next_client_id] = {
		"tcp": tcp,
		"ws": ws,
		"connected": false,
		"last_activity_msec": Time.get_ticks_msec(),
	}
	_next_client_id += 1


func _poll_client(client_id: int) -> void:
	var client: Dictionary = _clients[client_id]
	var ws: WebSocketPeer = client["ws"]
	ws.poll()

	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not client["connected"]:
				client["connected"] = true
				client["last_activity_msec"] = Time.get_ticks_msec()
				client_connected.emit()

			while ws.get_available_packet_count() > 0:
				client["last_activity_msec"] = Time.get_ticks_msec()
				_handle_packet(client_id, ws.get_packet())

			if Time.get_ticks_msec() - int(client["last_activity_msec"]) > STALE_CONNECTION_TIMEOUT_MSEC:
				_remove_client(client_id, CLOSE_CODE_STALE, CLOSE_REASON_STALE)
		WebSocketPeer.STATE_CLOSED:
			_remove_client(client_id)
		_:
			if Time.get_ticks_msec() - int(client["last_activity_msec"]) > HANDSHAKE_TIMEOUT_MSEC:
				_remove_client(client_id)


func _remove_client(client_id: int, close_code: int = 1000, close_reason: String = "") -> void:
	var client: Dictionary = _clients[client_id]
	var ws: WebSocketPeer = client["ws"]
	var tcp: StreamPeerTCP = client["tcp"]
	ws.close(close_code, close_reason)
	tcp.disconnect_from_host()
	_clients.erase(client_id)

	# A disconnected sender should not leave unfinished reply routes behind.
	for request_id in _requests.keys():
		if _requests[request_id]["client_id"] == client_id:
			_requests.erase(request_id)
	if client["connected"]:
		client_disconnected.emit()


func _handle_packet(client_id: int, packet: PackedByteArray) -> void:
	var request_id := "%d:%d" % [client_id, _next_request_id]
	_next_request_id += 1
	_requests[request_id] = {"client_id": client_id, "id": ""}

	var json := JSON.new()
	var err := json.parse(packet.get_string_from_utf8())
	if err != OK:
		_send_error_response(request_id, "PARSE_ERROR", "Invalid JSON: %s" % json.get_error_message())
		return
	if not json.data is Dictionary:
		_send_error_response(request_id, "INVALID_FORMAT", "Expected JSON object")
		return

	var data: Dictionary = json.data
	_requests[request_id]["id"] = str(data.get("id", ""))
	if not data.has("id") or not data.has("command"):
		_send_error_response(request_id, "INVALID_FORMAT", "Missing 'id' or 'command' field")
		return
	if not data.get("params", {}) is Dictionary:
		_send_error_response(request_id, "INVALID_FORMAT", "Expected params to be an object")
		return

	command_received.emit(request_id, str(data["command"]), data.get("params", {}))


func _send_error_response(id: String, code: String, message: String) -> void:
	send_response({
		"id": id,
		"status": "error",
		"error": {"code": code, "message": message},
	})
