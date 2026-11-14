class_name InputRouter
extends Node
## The game's single action: HOLD (touch anywhere / LMB / Space) or RELEASE.
## Uses _unhandled_input so presses on UI buttons (which consume their events) never spin the robot;
## touches are additionally checked against `ui_blocker` because ScreenTouch reaches unhandled input
## even when the emulated mouse press was consumed by a Control.

signal hold_changed(holding: bool)
signal tapped

var holding := false
var enabled := true
## Callable(screen_pos: Vector2) -> bool. True = position belongs to UI.
var ui_blocker: Callable

var _touches := {}
var _mouse := false
var _key := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if ui_blocker.is_valid() and ui_blocker.call(t.position):
				return
			_touches[t.index] = true
			_refresh()
			tapped.emit()
			return
		else:
			_touches.erase(t.index)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if ui_blocker.is_valid() and ui_blocker.call(mb.position):
				return
			_mouse = true
			_refresh()
			if not mb.is_echo():
				tapped.emit()
			return
		_mouse = false
	elif event.is_action("spin_ccw") and not event.is_echo():
		_key = event.is_pressed()
		_refresh()
		if _key:
			tapped.emit()
		return
	else:
		return
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset()


func reset() -> void:
	_touches.clear()
	_mouse = false
	_key = false
	_refresh()


## Test / bot hook.
func set_virtual_hold(on: bool) -> void:
	_key = on
	_refresh()


func _refresh() -> void:
	var h := enabled and (not _touches.is_empty() or _mouse or _key)
	if h != holding:
		holding = h
		hold_changed.emit(holding)
