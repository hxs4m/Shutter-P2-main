extends Node

var saved_time: float = -1.0
var total_overall_score: int = 0
var level_score: int = 0

# --- Frequencies ---
var cones_collected: int = 0
var cubes_collected: int = 0
var spheres_collected: int = 0
var enemies_stunned: int = 0
var times_caught: int = 0
var time_left: int = 0

# --- Point Values ---
const CONE_VAL = 50
const CUBE_VAL = 40
const SPHERE_VAL = 20
const STUN_VAL = 30
const CAUGHT_VAL = -20 # Penalty

func reset_level_stats() -> void:
	cones_collected = 0
	cubes_collected = 0
	spheres_collected = 0
	enemies_stunned = 0
	times_caught = 0
	time_left = 0
	level_score = 0

func calculate_final_score(remaining_seconds: float) -> void:
	time_left = int(remaining_seconds)
	level_score = 0
	
	level_score += cones_collected * CONE_VAL
	level_score += cubes_collected * CUBE_VAL
	level_score += spheres_collected * SPHERE_VAL
	level_score += enemies_stunned * STUN_VAL
	level_score += times_caught * CAUGHT_VAL
	level_score += time_left # 1 point per second
	
	# Prevent the player from getting a negative score for the level
	level_score = max(0, level_score)
	
	total_overall_score += level_score
