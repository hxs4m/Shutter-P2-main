extends Node

# Signals your UI can listen to for playing visual effects
signal time_changed(current_time: float)
signal time_subtracted(amount: float)
signal time_added(amount: float)
signal timer_expired

var time_remaining: float = 300.0 # 5 minutes in seconds
var is_active: bool = true

func _process(delta: float) -> void:
	if is_active and time_remaining > 0:
		time_remaining -= delta
		time_changed.emit(time_remaining)
		
		if time_remaining <= 0.0:
			time_remaining = 0.0
			is_active = false
			timer_expired.emit()

func subtract_time(amount: float) -> void:
	time_remaining = max(0.0, time_remaining - amount)
	time_subtracted.emit(amount) # Triggers red flash / glitch UI effects
	time_changed.emit(time_remaining)
	
	if time_remaining <= 0.0 and is_active:
		is_active = false
		timer_expired.emit()

func add_time(amount: float) -> void:
	time_remaining += amount
	time_added.emit(amount) # Triggers green flash / reward UI effects
	time_changed.emit(time_remaining)

func get_formatted_time() -> String:
	var total_secs = int(ceil(time_remaining))
	var minutes = total_secs / 60
	var seconds = total_secs % 60
	return "%02d:%02d" % [minutes, seconds]
