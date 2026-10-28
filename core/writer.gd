class_name GcWriter
extends RefCounted
## One background writer serialises updates so filesystem work stays off the UI
## thread. Bursts (window resizing) are coalesced to the latest state, and
## close() flushes the final queued update before the process exits.

var _store: GcStore
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending: Variant = null
var _errors: Array = []
var _closing := false
var _started := false


func _init(store: GcStore) -> void:
	_store = store
	_started = _thread.start(_run) == OK


## `state` must not be modified by the caller afterwards (pass a copy).
func save(state: Dictionary) -> String:
	if not _started:
		return "Settings writer stopped unexpectedly."
	_mutex.lock()
	var closed := _closing
	if not closed:
		_pending = state
	_mutex.unlock()
	if closed:
		return "Settings writer is closed."
	_wake.post()
	return ""


## Next background write error, or null.
func error() -> Variant:
	_mutex.lock()
	var e: Variant = null if _errors.is_empty() else _errors.pop_front()
	_mutex.unlock()
	return e


## Flushes any pending update and stops the worker.
func close() -> void:
	if not _started:
		return
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()
	_started = false


func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var state: Variant = _pending
		_pending = null
		var done := _closing
		_mutex.unlock()
		if state != null:
			var message := _store.save(state)
			if not message.is_empty():
				_mutex.lock()
				_errors.append(message)
				_mutex.unlock()
		if done:
			return
