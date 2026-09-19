extends CharacterBody3D
## Roamer enemy (level 2).
##
## ROAM     -> wanders the navmesh, slowed run animation + slow footsteps
## CHASE    -> instantly runs at the player on sight, fast footsteps
## LUNGE    -> attack animation. Parry window opens parry_window_start seconds in and
##             stays open for parry_window_duration seconds.
## REPELLED -> parried by the camera's REPEL flash: shockwave, knocked back, chases again
## KILLING  -> missed parry: stepped fade to black, teleport, stepped fade back in
##
## Every tunable value is an @export, so change things in the Inspector, not here.

# ------------------------------------------------------------------
# REFERENCES
# ------------------------------------------------------------------
@export_group("References")
@export var lock_on_target: Node3D ## Drag the Head (or any Node3D) here
@export var player_group: StringName = &"Player" ## Group your player is in (case-sensitive!)

# ------------------------------------------------------------------
# MOVEMENT
# ------------------------------------------------------------------
@export_group("Movement")
@export var roam_speed: float = 1.5
@export var chase_speed: float = 5.5
@export var gravity: float = 9.8

@export_group("Facing")
@export var face_camera: bool = true ## Face the player camera while chasing / lunging / repelled
@export var roam_face_camera: bool = false ## While roaming: stare at the camera instead of facing where he walks
@export var face_camera_speed: float = 12.0
@export var flip_facing: bool = false ## Tick this if your model's front points the wrong way

# ------------------------------------------------------------------
# ROAMING
# ------------------------------------------------------------------
@export_group("Roaming")
@export var roam_point_range: float = 10.0 ## How far from himself he picks a new wander point
@export var roam_point_tolerance: float = 1.0 ## Reject wander points further than this from the navmesh
@export var roam_pick_attempts: int = 8
@export var roam_animation_scale: float = 0.4 ## Run animation speed while roaming (slowed run)
@export var roam_area_center: Vector3 = Vector3.ZERO ## Centre of the area he's allowed to wander in
@export var roam_area_radius: float = 0.0 ## Wander points are pulled inside this radius (0 = no limit). Set this to keep him off the map edge

# ------------------------------------------------------------------
# SIGHT & CHASE
# ------------------------------------------------------------------
@export_group("Sight & Chase")
@export var sight_range: float = 15.0
@export var sight_height: float = 1.0 ## Height of the sight ray above his origin
@export var require_line_of_sight: bool = true
@export var chase_directly_if_unreachable: bool = true ## If the navmesh path doesn't end near the player, walk straight at them
@export var chase_path_tolerance: float = 3.0 ## How far (metres) the path end may be from the player before we stop trusting it
@export var chase_animation_scale: float = 1.0 ## Run animation speed while chasing

# ------------------------------------------------------------------
# LUNGE & PARRY
# ------------------------------------------------------------------
@export_group("Lunge & Parry")
@export var lunge_distance: float = 2.5 ## Distance that switches chase -> lunge
@export var lunge_forward_speed: float = 3.0 ## Set to 0 if the attack animation already moves him
@export var lunge_forward_time: float = 0.4 ## How long he steps forward during the lunge
@export var lunge_min_distance: float = 1.2 ## He stops stepping forward once this close
@export var parry_window_start: float = 0.2 ## Seconds into the attack when the window opens
@export var parry_window_duration: float = 0.3 ## Length of the window (0.3 = 300ms)
@export var kill_delay_after_window: float = 0.0 ## Extra time after the window closes before the kill

@export_group("Knockback (after a parry)")
@export var knockback_force: float = 12.0
@export var knockback_upward_force: float = 4.0
@export var knockback_decay: float = 3.0
@export var repelled_duration: float = 1.2 ## Seconds before he chases again

@export_group("Repel Effect")
@export var sound_repel: AudioStream
@export var repel_effect_scene: PackedScene ## Your explosion / shockwave scene (optional)
@export var repel_effect_offset: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var repel_effect_lifetime: float = 2.0 ## Seconds before the effect is freed (0 = never)

# ------------------------------------------------------------------
# KILL FADE & TELEPORT
# ------------------------------------------------------------------
@export_group("Kill Fade")
@export var kill_fade_color: Color = Color.BLACK
@export var fade_steps: int = 6
@export var fade_step_time: float = 0.15
@export var black_screen_hold_time: float = 1.5

@export_group("Teleport")
@export var teleport_radius: float = 30.0
@export var teleport_center: Vector3 = Vector3.ZERO
@export var teleport_min_distance_from_player: float = 15.0
@export var teleport_attempts: int = 10
@export var teleport_use_navmesh_height: bool = false ## Use the navmesh floor height instead of his current Y
@export var teleport_height_offset: float = 0.0 ## Added to the height

# ------------------------------------------------------------------
# STUCK RECOVERY
# ------------------------------------------------------------------
@export_group("Stuck Recovery")
@export var stuck_check_time: float = 1.0 ## Check every this many seconds while roaming (0 = off)
@export var stuck_min_distance: float = 0.4 ## Moved less than this in that time = stuck, pick a new wander point

# ------------------------------------------------------------------
# STARTUP
# ------------------------------------------------------------------
@export_group("Startup")
@export var startup_wait_frames: int = 2 ## Physics frames to wait so the navmesh can sync

# ------------------------------------------------------------------
# AUDIO
# ------------------------------------------------------------------
@export_group("Audio")
@export var sound_footstep_roam: AudioStream
@export var sound_footstep_chase: AudioStream
@export var sound_lunge: AudioStream
@export var footstep_interval_roam: float = 0.6
@export var footstep_interval_chase: float = 0.28
@export var footstep_pitch_min: float = 0.9
@export var footstep_pitch_max: float = 1.1

# ------------------------------------------------------------------
# ANIMATION
# ------------------------------------------------------------------
@export_group("Animation")
@export var run_state_name: StringName = &"run" ## State that plays the run anim (use "BlendTree" if the TimeScale lives there)
@export var attack_state_name: StringName = &"attack"
@export var run_scale_node_name: StringName = &"RunScale" ## Name of the TimeScale node in your blend tree
@export var run_scale_parameter: String = "" ## Leave empty to auto-detect, or paste the full path e.g. parameters/BlendTree/RunScale/scale

# ------------------------------------------------------------------
# DEBUG
# ------------------------------------------------------------------
@export_group("Debug")
@export var debug_prints: bool = false ## Prints every state change + a status line every interval
@export var debug_print_interval: float = 1.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
@onready var sfx_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()

enum State { ROAM, CHASE, LUNGE, REPELLED, KILLING }
var current_state: State = State.ROAM
var player: CharacterBody3D

var parry_window_open: bool = false
var time_in_attack: float = 0.0
var repelled_time_left: float = 0.0
var footstep_timer: float = 0.0
var _nav_ready: bool = false
var _run_scale_param: String = ""
var _warned_no_fade_rect: bool = false
var _stuck_timer: float = 0.0
var _stuck_anchor: Vector3 = Vector3.ZERO
var _debug_timer: float = 0.0


func _ready() -> void:
	add_child(sfx_player)
	add_to_group("roamers")
	player = get_tree().get_first_node_in_group(player_group) as CharacterBody3D

	# Wait for the NavigationServer to sync. Until then _physics_process does NOT move him,
	# otherwise the agent's default target of (0,0,0) sends him toward the map origin/edge.
	for _i in maxi(1, startup_wait_frames):
		await get_tree().physics_frame

	_resolve_run_scale_param()

	if _get_player() == null:
		push_warning("Roamer: no node found in group '%s'. Check the group name (case-sensitive)." % player_group)

	_pick_random_roam_point()
	_stuck_anchor = global_position
	_nav_ready = true


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if not _nav_ready:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_update_facing(delta)

	match current_state:
		State.ROAM:
			_process_roam(delta)
		State.CHASE:
			_process_chase(delta)
		State.LUNGE:
			_process_lunge(delta)
		State.REPELLED:
			_process_repelled(delta)
		State.KILLING:
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()
	_check_stuck(delta)
	_debug_tick(delta)


# ------------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------------
func _set_state(new_state: State) -> void:
	if new_state == current_state:
		return
	if debug_prints:
		var p := _get_player()
		var dist: float = global_position.distance_to(p.global_position) if p else -1.0
		print("[Roamer] %s -> %s | distance to player: %.1f" % [State.keys()[current_state], State.keys()[new_state], dist])
	current_state = new_state


func _get_player() -> CharacterBody3D:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(player_group) as CharacterBody3D
	return player


func _move_toward(target_pos: Vector3, speed: float) -> void:
	var dir: Vector3 = global_position.direction_to(target_pos)
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	else:
		dir = Vector3.ZERO
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed


func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	sfx_player.stream = stream
	sfx_player.pitch_scale = 1.0
	sfx_player.play()


# ------------------------------------------------------------------
# ANIMATION SPEED (TimeScale inside your blend tree)
# ------------------------------------------------------------------
func _resolve_run_scale_param() -> void:
	if run_scale_parameter != "":
		_run_scale_param = run_scale_parameter
		return

	# The path depends on where the TimeScale sits in the tree (e.g. parameters/BlendTree/RunScale/scale),
	# so search the AnimationTree for it instead of hardcoding it.
	var suffix: String = "/%s/scale" % run_scale_node_name
	for prop in anim_tree.get_property_list():
		var prop_name: String = prop["name"]
		if prop_name.begins_with("parameters/") and prop_name.ends_with(suffix):
			_run_scale_param = prop_name
			if debug_prints:
				print("[Roamer] Using run scale parameter: ", _run_scale_param)
			return

	push_warning("Roamer: couldn't find a TimeScale node named '%s' in the AnimationTree, so run-speed scaling won't work. Check Inspector > Animation > Run Scale Node Name." % run_scale_node_name)


func _set_run_scale(value: float) -> void:
	if _run_scale_param != "":
		anim_tree.set(_run_scale_param, value)


# ------------------------------------------------------------------
# FACING
# ------------------------------------------------------------------
func _update_facing(delta: float) -> void:
	var facing_camera: bool = roam_face_camera if current_state == State.ROAM else face_camera

	if facing_camera:
		var camera := get_viewport().get_camera_3d()
		if camera:
			_turn_toward(camera.global_position, delta)
	elif current_state == State.ROAM:
		# Face where he's walking
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		if flat.length() > 0.1:
			_turn_toward(global_position + flat, delta)


func _turn_toward(target_pos: Vector3, delta: float) -> void:
	target_pos.y = global_position.y
	if global_position.distance_to(target_pos) < 0.05:
		return

	var target_basis: Basis = Transform3D(Basis.IDENTITY, global_position).looking_at(target_pos, Vector3.UP).basis
	if flip_facing:
		target_basis = target_basis.rotated(Vector3.UP, PI)

	var current_basis: Basis = global_transform.basis.orthonormalized()
	global_transform.basis = current_basis.slerp(target_basis, clampf(delta * face_camera_speed, 0.0, 1.0))


# ------------------------------------------------------------------
# ROAM
# ------------------------------------------------------------------
func _process_roam(delta: float) -> void:
	if _can_see_player():
		_set_state(State.CHASE)
		return

	if nav_agent.is_navigation_finished():
		_pick_random_roam_point()

	_move_toward(nav_agent.get_next_path_position(), roam_speed)

	playback.travel(run_state_name)
	_set_run_scale(roam_animation_scale)
	_handle_footsteps(delta, footstep_interval_roam, sound_footstep_roam)


func _pick_random_roam_point(retreat_dir: Vector3 = Vector3.ZERO) -> void:
	# Only accept wander points that are actually on the navmesh. Points off the mesh make the
	# agent run to the nearest mesh edge.
	var map: RID = nav_agent.get_navigation_map()
	for _i in maxi(1, roam_pick_attempts):
		var offset := Vector3(
			randf_range(-roam_point_range, roam_point_range),
			0.0,
			randf_range(-roam_point_range, roam_point_range)
		)
		# When stuck, lean the new point back the way he came
		if retreat_dir != Vector3.ZERO:
			offset = retreat_dir * roam_point_range * 0.6 + offset * 0.4
		var candidate: Vector3 = global_position + offset

		# Keep wander points inside the allowed area (pull them back to its edge)
		if roam_area_radius > 0.0:
			var from_center := Vector2(candidate.x - roam_area_center.x, candidate.z - roam_area_center.z)
			if from_center.length() > roam_area_radius:
				from_center = from_center.normalized() * roam_area_radius
				candidate.x = roam_area_center.x + from_center.x
				candidate.z = roam_area_center.z + from_center.y

		var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, candidate)
		var gap := Vector2(candidate.x - on_mesh.x, candidate.z - on_mesh.z).length()
		if gap <= roam_point_tolerance:
			nav_agent.target_position = on_mesh
			return

	# No valid point found: stand still this frame and try again next frame.
	nav_agent.target_position = global_position


# ------------------------------------------------------------------
# STUCK RECOVERY + DEBUG
# ------------------------------------------------------------------
func _check_stuck(delta: float) -> void:
	if stuck_check_time <= 0.0 or current_state != State.ROAM:
		_stuck_timer = 0.0
		_stuck_anchor = global_position
		return

	_stuck_timer += delta
	if _stuck_timer < stuck_check_time:
		return

	var moved: float = Vector2(global_position.x - _stuck_anchor.x, global_position.z - _stuck_anchor.z).length()
	if moved < stuck_min_distance:
		var heading: Vector3 = global_position.direction_to(nav_agent.get_next_path_position())
		heading.y = 0.0
		var retreat: Vector3 = -heading.normalized() if heading.length() > 0.01 else Vector3.ZERO
		if debug_prints:
			print("[Roamer] Stuck while roaming (moved %.2fm) - picking a new wander point" % moved)
		_pick_random_roam_point(retreat)

	_stuck_anchor = global_position
	_stuck_timer = 0.0


func _debug_tick(delta: float) -> void:
	if not debug_prints:
		return
	_debug_timer += delta
	if _debug_timer < debug_print_interval:
		return
	_debug_timer = 0.0

	var p := _get_player()
	var dist: float = global_position.distance_to(p.global_position) if p else -1.0
	var step := Vector3.ONE * 0.1
	print("[Roamer] state=%s | speed=%.1f | dist_to_player=%.1f | pos=%s | nav_target=%s | path_end=%s" % [
		State.keys()[current_state],
		Vector2(velocity.x, velocity.z).length(),
		dist,
		global_position.snapped(step),
		nav_agent.target_position.snapped(step),
		nav_agent.get_final_position().snapped(step)
	])


# ------------------------------------------------------------------
# CHASE
# ------------------------------------------------------------------
func _process_chase(delta: float) -> void:
	var p := _get_player()
	if p == null:
		_set_state(State.ROAM)
		return

	if global_position.distance_to(p.global_position) <= lunge_distance:
		_start_lunge()
		return

	nav_agent.target_position = p.global_position
	var next_pos: Vector3 = nav_agent.get_next_path_position()

	# If the navmesh path doesn't actually end near the player (player off the mesh, or on a
	# disconnected island), don't follow it - it would lead to the nearest mesh edge instead.
	if chase_directly_if_unreachable:
		var path_end: Vector3 = nav_agent.get_final_position()
		var gap: float = Vector2(path_end.x - p.global_position.x, path_end.z - p.global_position.z).length()
		if gap > chase_path_tolerance:
			next_pos = p.global_position

	_move_toward(next_pos, chase_speed)

	playback.travel(run_state_name)
	_set_run_scale(chase_animation_scale)
	_handle_footsteps(delta, footstep_interval_chase, sound_footstep_chase)


# ------------------------------------------------------------------
# LUNGE
# ------------------------------------------------------------------
func _start_lunge() -> void:
	_set_state(State.LUNGE)
	velocity.x = 0.0
	velocity.z = 0.0
	time_in_attack = 0.0
	parry_window_open = false
	playback.travel(attack_state_name)
	_play_sfx(sound_lunge)

	# Tells the player to lock the camera on to lock_on_target
	var p := _get_player()
	if p and p.has_method("_on_roamer_lunge_started"):
		p._on_roamer_lunge_started(self, lock_on_target)


func _process_lunge(delta: float) -> void:
	time_in_attack += delta

	var window_end: float = parry_window_start + parry_window_duration
	parry_window_open = time_in_attack >= parry_window_start and time_in_attack <= window_end

	# Short step forward at the start of the lunge
	var stepping_forward: bool = false
	var p := _get_player()
	if p and lunge_forward_speed > 0.0 and time_in_attack <= lunge_forward_time:
		if global_position.distance_to(p.global_position) > lunge_min_distance:
			stepping_forward = true
			_move_toward(p.global_position, lunge_forward_speed)
	if not stepping_forward:
		velocity.x = 0.0
		velocity.z = 0.0

	# Window closed without a parry -> kill
	if time_in_attack > window_end + kill_delay_after_window and not parry_window_open:
		_execute_player_kill()


# ------------------------------------------------------------------
# REPEL (PARRY) - called by your camera script's REPEL mode
# ------------------------------------------------------------------
func apply_repel(from_pos: Vector3) -> bool:
	if current_state == State.LUNGE and parry_window_open:
		_set_state(State.REPELLED)
		parry_window_open = false
		repelled_time_left = repelled_duration

		# Releases the player's lock-on (the camera script handles the player's boost)
		var p := _get_player()
		if p and p.has_method("_on_roamer_parry_window_closed"):
			p._on_roamer_parry_window_closed(true)

		var knock_dir: Vector3 = global_position - from_pos
		knock_dir.y = 0.0
		knock_dir = knock_dir.normalized()
		velocity = knock_dir * knockback_force
		velocity.y = knockback_upward_force

		_play_sfx(sound_repel)
		_spawn_repel_effect()
		return true
	return false


func _process_repelled(delta: float) -> void:
	var t: float = clampf(delta * knockback_decay, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, 0.0, t)
	velocity.z = lerpf(velocity.z, 0.0, t)

	repelled_time_left -= delta
	if repelled_time_left <= 0.0:
		_set_state(State.CHASE)


func _spawn_repel_effect() -> void:
	if repel_effect_scene == null:
		return
	var fx: Node = repel_effect_scene.instantiate()
	get_tree().current_scene.add_child(fx)
	if fx is Node3D:
		fx.global_position = global_position + repel_effect_offset
	if repel_effect_lifetime > 0.0:
		get_tree().create_timer(repel_effect_lifetime).timeout.connect(func():
			if is_instance_valid(fx):
				fx.queue_free()
		)


# ------------------------------------------------------------------
# KILL + TELEPORT
# ------------------------------------------------------------------
func _execute_player_kill() -> void:
	_set_state(State.KILLING)
	velocity.x = 0.0
	velocity.z = 0.0
	parry_window_open = false
	_set_run_scale(0.0) # freeze the run cycle so he isn't jogging on the spot while the screen fades

	var p := _get_player()
	if p and p.has_method("_on_roamer_parry_window_closed"):
		p._on_roamer_parry_window_closed(false)

	var flash_rect: ColorRect = null
	if p:
		flash_rect = p.get("flash_color_rect") as ColorRect

	if flash_rect == null:
		if not _warned_no_fade_rect:
			_warned_no_fade_rect = true
			push_warning("Roamer: the player's flash_color_rect isn't assigned, so there is no fade to black. Assign it in the player's Inspector.")
		_teleport_to_random_spot()
		_set_state(State.ROAM)
		return

	_set_fade_alpha(flash_rect, 0.0)
	var tween := create_tween()
	var steps: int = maxi(1, fade_steps)

	# Stepped fade to black
	for i in range(1, steps + 1):
		tween.tween_callback(_set_fade_alpha.bind(flash_rect, float(i) / steps))
		tween.tween_interval(fade_step_time)

	# Teleport while the screen is black so the player never sees him move
	tween.tween_callback(_teleport_to_random_spot)
	tween.tween_interval(black_screen_hold_time)

	# Stepped fade back to transparent
	for i in range(steps - 1, -1, -1):
		tween.tween_callback(_set_fade_alpha.bind(flash_rect, float(i) / steps))
		tween.tween_interval(fade_step_time)

	tween.tween_callback(_finish_kill)


func _set_fade_alpha(rect: ColorRect, alpha: float) -> void:
	if is_instance_valid(rect):
		# Set the full colour every step so a camera flash can't leave the fade tinted white
		rect.color = Color(kill_fade_color.r, kill_fade_color.g, kill_fade_color.b, alpha)


func _finish_kill() -> void:
	if current_state == State.KILLING:
		_set_state(State.ROAM)


func _teleport_to_random_spot() -> void:
	var map: RID = nav_agent.get_navigation_map()
	var p := _get_player()

	var best_pos: Vector3 = global_position
	var best_dist: float = -1.0

	# Try a few random spots, snap each to the navmesh, and prefer one far from the player.
	for _i in maxi(1, teleport_attempts):
		var candidate: Vector3 = teleport_center + Vector3(
			randf_range(-teleport_radius, teleport_radius),
			0.0,
			randf_range(-teleport_radius, teleport_radius)
		)
		candidate.y = global_position.y
		candidate = NavigationServer3D.map_get_closest_point(map, candidate)

		var dist: float = candidate.distance_to(p.global_position) if p else INF
		if dist > best_dist:
			best_dist = dist
			best_pos = candidate
		if dist >= teleport_min_distance_from_player:
			break

	if teleport_use_navmesh_height:
		global_position = Vector3(best_pos.x, best_pos.y + teleport_height_offset, best_pos.z)
	else:
		global_position = Vector3(best_pos.x, global_position.y + teleport_height_offset, best_pos.z)

	velocity = Vector3.ZERO
	_pick_random_roam_point()


# ------------------------------------------------------------------
# SIGHT
# ------------------------------------------------------------------
func _can_see_player() -> bool:
	var p := _get_player()
	if p == null:
		return false

	if global_position.distance_to(p.global_position) > sight_range:
		return false

	if not require_line_of_sight:
		return true

	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * sight_height
	var to: Vector3 = p.global_position + Vector3.UP * sight_height
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()] # never let the ray hit himself
	var result := space_state.intersect_ray(query)

	return not result.is_empty() and result.collider == p


# ------------------------------------------------------------------
# AUDIO
# ------------------------------------------------------------------
func _handle_footsteps(delta: float, interval: float, stream: AudioStream) -> void:
	footstep_timer += delta
	if footstep_timer >= interval:
		footstep_timer = 0.0
		if stream:
			sfx_player.stream = stream
			sfx_player.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
			sfx_player.play()
