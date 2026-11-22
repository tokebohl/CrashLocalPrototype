extends CharacterBody2D

const MAX_SPEED := 780.0
const ACCEL := 940.0
const BRAKE_FORCE := 1150.0
const TURN_RATE := 2.95
const DRIFT_TURN_BONUS := 1.45
const NORMAL_GRIP := 7.2
const DRIFT_GRIP := 2.15
const BOOST_SPEED := 1040.0

var player_id := 1
var is_local := true
var is_bot := false
var network_position := Vector2.ZERO
var network_velocity := Vector2.ZERO
var network_rotation := 0.0
var network_drifting := false
var network_boosting := false
var network_score := 0
var network_lap := 1

var car_angle := 0.0
var is_drifting := false
var drift_angle := 0.0
var drift_combo_score := 0.0
var total_drift_score := 0
var boost_charge := 0.0
var boost_timer := 0.0
var lap := 1
var passed_halfway := false
var bot_wp_idx := 0
var skid_timer := 0.0
var sfx_cooldown := 0.0
var anim_time := 0.0

var car_sprite: Sprite2D
var smoke_left: CPUParticles2D
var smoke_right: CPUParticles2D
var flame_left: Polygon2D
var flame_right: Polygon2D
var name_label: Label
var drift_popup: Label

const CAR_COLORS := [
	Color("#ff6b1a"), # P1: Iconic Sunset Orange Supra
	Color("#2986ff"), # P2: Midnight Royal Blue
	Color("#24d96b"), # P3: Emerald Racing Green
	Color("#ff3366")  # P4: Crimson Red
]

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	car_angle = rotation
	_build_visuals()

	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 25.0
	cs.shape = circle
	add_child(cs)

func _build_visuals() -> void:
	var main = get_tree().current_scene
	var tex: Texture2D = null
	if main and main.has_method("load_svg_tex"):
		tex = main.load_svg_tex("res://art/supra_car.svg")
	if tex == null and ResourceLoader.exists("res://art/supra_car.svg"):
		tex = load("res://art/supra_car.svg")

	# Udstødningsflammer ved Turbo Boost
	flame_left = Polygon2D.new()
	flame_left.polygon = PackedVector2Array([Vector2(-44, -12), Vector2(-78, -8), Vector2(-44, -4)])
	flame_left.color = Color("#38e8ff")
	flame_left.visible = false
	add_child(flame_left)

	flame_right = Polygon2D.new()
	flame_right.polygon = PackedVector2Array([Vector2(-44, 12), Vector2(-78, 8), Vector2(-44, 4)])
	flame_right.color = Color("#38e8ff")
	flame_right.visible = false
	add_child(flame_right)

	car_sprite = Sprite2D.new()
	car_sprite.name = "SupraSprite"
	car_sprite.texture = tex
	car_sprite.scale = Vector2(0.54, 0.54)
	var c_idx: int = clampi((player_id - 1) % CAR_COLORS.size(), 0, CAR_COLORS.size() - 1)
	car_sprite.modulate = CAR_COLORS[c_idx]
	add_child(car_sprite)

	# Dækrøg ved drift (venstre & højre baghjul)
	smoke_left = _make_tire_smoke(Vector2(-34, -18))
	smoke_right = _make_tire_smoke(Vector2(-34, 18))
	add_child(smoke_left)
	add_child(smoke_right)

	# Spiller-skilt der altid står vandret over bilen
	name_label = Label.new()
	name_label.top_level = true
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("#ffe66d") if is_local else Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 2)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(name_label)

	drift_popup = Label.new()
	drift_popup.top_level = true
	drift_popup.add_theme_font_size_override("font_size", 18)
	drift_popup.add_theme_color_override("font_color", Color("#4dffb8"))
	drift_popup.add_theme_color_override("font_shadow_color", Color.BLACK)
	drift_popup.add_theme_constant_override("shadow_offset_x", 2)
	drift_popup.add_theme_constant_override("shadow_offset_y", 2)
	add_child(drift_popup)

func _make_tire_smoke(offset: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = offset
	p.emitting = false
	p.amount = 22
	p.lifetime = 0.55
	p.spread = 45.0
	p.direction = Vector2(-1, 0)
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 85.0
	p.scale_amount_min = 7.0
	p.scale_amount_max = 16.0
	p.color = Color(0.95, 0.96, 1.0, 0.62)
	return p

func get_player_id() -> int:
	return player_id

func _physics_process(delta: float) -> void:
	anim_time += delta
	sfx_cooldown = maxf(0.0, sfx_cooldown - delta)
	boost_timer = maxf(0.0, boost_timer - delta)

	if not is_local and not is_bot:
		global_position = global_position.lerp(network_position, minf(delta * 16.0, 1.0))
		velocity = network_velocity
		car_angle = lerp_angle(car_angle, network_rotation, minf(delta * 16.0, 1.0))
		rotation = car_angle
		is_drifting = network_drifting
		boost_timer = 0.15 if network_boosting else 0.0
		total_drift_score = network_score
		lap = network_lap
		_update_visual_effects()
		return

	var main = get_tree().current_scene
	if main == null or not main.game_started:
		return

	var steer := 0.0
	var throttle := 0.0
	var want_drift := false
	var want_boost := false

	if is_bot:
		var wps: Array = main.get_drift_waypoints()
		if not wps.is_empty():
			var target: Vector2 = wps[bot_wp_idx % wps.size()]
			if global_position.distance_to(target) < 175.0:
				bot_wp_idx = (bot_wp_idx + 1) % wps.size()
				target = wps[bot_wp_idx]
			var to_target: Vector2 = target - global_position
			var desired_angle: float = to_target.angle()
			var angle_diff: float = wrapf(desired_angle - car_angle, -PI, PI)
			steer = clampf(angle_diff * 2.2, -1.0, 1.0)
			throttle = 0.88 if absf(angle_diff) < 0.7 else 0.68
			want_drift = absf(angle_diff) > 0.38 and velocity.length() > 360.0
			if boost_charge >= 100.0 and absf(angle_diff) < 0.25:
				want_boost = true
	else:
		# Læs styring fra virtuel thumbstick eller tastatur
		var stick_vec: Vector2 = main.get_drift_stick_vector()
		if stick_vec.length() > 0.08:
			steer = clampf(stick_vec.x, -1.0, 1.0)
			throttle = 1.0 if stick_vec.y <= 0.35 else -0.65
		else:
			if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
				steer -= 1.0
			if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
				steer += 1.0
			if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
				throttle = 1.0
			elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
				throttle = -0.65
			elif steer != 0.0:
				throttle = 0.85

		want_drift = Input.is_key_pressed(KEY_SPACE) or bool(main.touch_state.get("drift_held", false))
		want_boost = Input.is_key_pressed(KEY_SHIFT) or main.consume_action("boost")

	if want_boost and boost_charge >= 35.0 and boost_timer <= 0.0:
		boost_timer = 1.15 * (boost_charge / 100.0)
		boost_charge = 0.0
		if main.has_method("play_sfx"):
			main.play_sfx("turbo")
		if is_local and main.has_method("add_camera_shake"):
			main.add_camera_shake(8.0)

	var forward := Vector2.RIGHT.rotated(car_angle)
	var right_vec := forward.orthogonal()
	var forward_speed: float = velocity.dot(forward)
	var lateral_speed: float = velocity.dot(right_vec)

	# Aktiver drift ved håndbremse/drift-knap i fart
	if want_drift and absf(forward_speed) > 250.0:
		is_drifting = true
	else:
		if is_drifting and drift_combo_score >= 25.0:
			total_drift_score += int(drift_combo_score)
			if is_local and main.has_method("play_sfx"):
				main.play_sfx("fruit")
		is_drifting = false
		drift_combo_score = 0.0

	# Drejning (skarpere udskridning under drift)
	var speed_factor: float = clampf(absf(forward_speed) / 260.0, 0.25, 1.0)
	var turn_mult: float = DRIFT_TURN_BONUS if is_drifting else 1.0
	var rev_sign: float = -1.0 if forward_speed < -20.0 else 1.0
	car_angle += steer * TURN_RATE * turn_mult * speed_factor * rev_sign * delta
	rotation = car_angle

	forward = Vector2.RIGHT.rotated(car_angle)
	right_vec = forward.orthogonal()

	# Acceleration & Turbo Boost
	var top_spd: float = BOOST_SPEED if boost_timer > 0.0 else MAX_SPEED
	var accel_rate: float = ACCEL * (1.45 if boost_timer > 0.0 else 1.0)
	if throttle > 0.0:
		forward_speed = move_toward(forward_speed, throttle * top_spd, accel_rate * delta)
	elif throttle < 0.0:
		forward_speed = move_toward(forward_speed, throttle * (MAX_SPEED * 0.45), BRAKE_FORCE * delta)
	else:
		forward_speed = move_toward(forward_speed, 0.0, 290.0 * delta)

	# Sideværts greb (lavt greb under drift giver ægte Supra-udskridning!)
	var grip: float = DRIFT_GRIP if is_drifting else NORMAL_GRIP
	lateral_speed = move_toward(lateral_speed, 0.0, lateral_speed * grip * delta)
	if is_drifting:
		lateral_speed += steer * 195.0 * delta

	velocity = forward * forward_speed + right_vec * lateral_speed
	move_and_slide()

	# Beregn drift-point, turbo-opladning og dækspor på asfalten
	var slip: float = absf(lateral_speed)
	if is_drifting and slip > 70.0 and velocity.length() > 240.0:
		var pts_gain: float = (slip * 0.42) * delta
		drift_combo_score += pts_gain
		boost_charge = minf(100.0, boost_charge + 36.0 * delta)
		skid_timer += delta
		if skid_timer >= 0.045:
			skid_timer = 0.0
			if main.has_method("spawn_skid_mark"):
				main.spawn_skid_mark(global_position - forward * 30.0 - right_vec * 16.0, car_angle)
				main.spawn_skid_mark(global_position - forward * 30.0 + right_vec * 16.0, car_angle)
		if is_local and sfx_cooldown <= 0.0 and main.has_method("play_sfx"):
			main.play_sfx("screech")
			sfx_cooldown = 0.28

	# Tjek checkpoints & omgange på drift-banen
	if main.has_method("check_drift_lap_progress"):
		main.check_drift_lap_progress(self)

	_update_visual_effects()

	if is_local:
		main.submit_drift_state(
			player_id, global_position, velocity, car_angle,
			is_drifting, boost_timer > 0.0, total_drift_score + int(drift_combo_score), lap
		)

func _update_visual_effects() -> void:
	var smoking: bool = is_drifting and velocity.length() > 220.0
	if is_instance_valid(smoke_left):
		smoke_left.emitting = smoking
	if is_instance_valid(smoke_right):
		smoke_right.emitting = smoking

	var boosting: bool = boost_timer > 0.0
	if is_instance_valid(flame_left):
		flame_left.visible = boosting
		flame_left.scale.x = 0.85 + sin(anim_time * 45.0) * 0.25
	if is_instance_valid(flame_right):
		flame_right.visible = boosting
		flame_right.scale.x = 0.85 + cos(anim_time * 45.0) * 0.25

	if is_instance_valid(name_label):
		name_label.global_position = global_position + Vector2(-36, -64)
		var lbl_name: String = "BOT" if is_bot else ("P%d" % player_id)
		name_label.text = "%s • OMG %d • %d PTS" % [lbl_name, lap, total_drift_score + int(drift_combo_score)]

	if is_instance_valid(drift_popup):
		drift_popup.global_position = global_position + Vector2(-42, -88)
		if drift_combo_score >= 15.0:
			drift_popup.visible = true
			drift_popup.text = "DRIFT +%d!" % int(drift_combo_score)
		else:
			drift_popup.visible = false
