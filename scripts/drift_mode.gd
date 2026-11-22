extends Node2D
class_name SupraDriftMode

signal exit_to_menu

const TRACK_SIZE := Vector2(3600.0, 2400.0)
const MAX_LIVES := 3
const ROUND_TIME := 120.0

var is_solo_bot: bool = false
var time_left: float = ROUND_TIME
var match_over: bool = false

var cars: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var skidmarks: Array[Dictionary] = []
var smoke_particles: Array[Dictionary] = []
var sparks: Array[Dictionary] = []

var camera: Camera2D
var hud_layer: CanvasLayer
var hud_label: Label
var score_label: Label
var end_panel: PanelContainer
var end_label: Label

var touch_state := {"left": false, "right": false, "gas": false, "drift": false, "shoot": false}

var tex_supra: Texture2D
var tex_heart: Texture2D
var tex_nitro: Texture2D
var tex_rapid: Texture2D
var tex_star: Texture2D

var sfx_shoot: AudioStreamPlayer
var sfx_hit: AudioStreamPlayer
var sfx_pickup: AudioStreamPlayer

func _load_svg(path: String, svg_scale: float = 1.0) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var svg_str: String = f.get_as_text()
	var img := Image.new()
	if img.load_svg_from_string(svg_str, svg_scale) == OK:
		return ImageTexture.create_from_image(img)
	return null

func _ready() -> void:
	tex_supra = _load_svg("res://art/drift/supra_car.svg", 1.1)
	tex_heart = _load_svg("res://art/drift/powerup_heart.svg", 0.85)
	tex_nitro = _load_svg("res://art/drift/powerup_nitro.svg", 0.85)
	tex_rapid = _load_svg("res://art/drift/powerup_rapid.svg", 0.85)
	tex_star = _load_svg("res://art/drift/powerup_points.svg", 0.8)

	camera = Camera2D.new()
	camera.zoom = Vector2(0.85, 0.85)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	add_child(camera)

	_setup_audio()
	_spawn_cars()
	_spawn_initial_pickups()
	_build_hud()

func _setup_audio() -> void:
	sfx_shoot = _make_tone_player(520.0, 0.08, -10.0)
	sfx_hit = _make_tone_player(140.0, 0.22, -6.0)
	sfx_pickup = _make_tone_player(880.0, 0.14, -8.0)

func _make_tone_player(freq: float, dur: float, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	var samples := int(22050 * dur)
	var data := PackedByteArray()
	data.resize(samples)
	for i in range(samples):
		var t: float = float(i) / 22050.0
		var env: float = 1.0 - (float(i) / float(samples))
		var val: float = sin(TAU * freq * t) * env
		data[i] = int(clamp((val * 0.5 + 0.5) * 255.0, 0.0, 255.0))
	wav.data = data
	p.stream = wav
	p.volume_db = db
	add_child(p)
	return p

func _spawn_cars() -> void:
	cars.clear()
	var palette: Array[Color] = [
		Color(1.0, 0.35, 0.15), # Orange Supra (P1)
		Color(0.15, 0.85, 1.0), # Neon Cyan Supra
		Color(0.25, 1.0, 0.45), # Lime Supra
		Color(0.95, 0.25, 0.85) # Magenta Supra
	]
	var names: Array[String] = ["Dig (Supra P1)", "Rival Tokyo", "Drift King", "Night Runner"]
	var total_cars: int = 4 if is_solo_bot else max(2, multiplayer.get_peers().size() + 1)

	for i in range(total_cars):
		var angle_offset: float = (TAU / float(total_cars)) * float(i)
		var spawn_pos: Vector2 = TRACK_SIZE * 0.5 + Vector2(cos(angle_offset) * 950.0, sin(angle_offset) * 580.0)
		cars.append({
			"id": i,
			"name": names[i % names.size()],
			"is_local": (i == 0),
			"is_bot": (i > 0 and is_solo_bot),
			"pos": spawn_pos,
			"vel": Vector2.ZERO,
			"heading": angle_offset + PI * 0.5,
			"drift_angle": 0.0,
			"lives": MAX_LIVES,
			"points": 0,
			"drift_combo": 0.0,
			"color": palette[i % palette.size()],
			"fire_cd": 0.0,
			"rapid_timer": 0.0,
			"nitro_timer": 0.0,
			"invuln_timer": 1.5,
			"respawn_timer": 0.0
		})

func _spawn_initial_pickups() -> void:
	pickups.clear()
	for i in range(28):
		_spawn_single_pickup()

func _spawn_single_pickup() -> void:
	var roll: float = randf()
	var ptype: String = "points"
	if roll < 0.22:
		ptype = "heart"
	elif roll < 0.45:
		ptype = "nitro"
	elif roll < 0.68:
		ptype = "rapid"

	var ang: float = randf() * TAU
	var rad_x: float = randf_range(380.0, 1480.0)
	var rad_y: float = randf_range(260.0, 960.0)
	var pos: Vector2 = TRACK_SIZE * 0.5 + Vector2(cos(ang) * rad_x, sin(ang) * rad_y)
	pickups.append({
		"pos": pos,
		"type": ptype,
		"pulse": randf() * TAU
	})

func _process(delta: float) -> void:
	if match_over:
		queue_redraw()
		return

	time_left = max(0.0, time_left - delta)
	if time_left <= 0.0:
		_finish_match()
		return

	_update_cars(delta)
	_update_bullets(delta)
	_update_pickups(delta)
	_update_fx(delta)
	_update_hud()
	queue_redraw()

func _update_cars(delta: float) -> void:
	var alive_count: int = 0
	for c in cars:
		if int(c["lives"]) > 0:
			alive_count += 1
		if float(c["invuln_timer"]) > 0.0:
			c["invuln_timer"] = max(0.0, float(c["invuln_timer"]) - delta)
		if float(c["rapid_timer"]) > 0.0:
			c["rapid_timer"] = max(0.0, float(c["rapid_timer"]) - delta)
		if float(c["nitro_timer"]) > 0.0:
			c["nitro_timer"] = max(0.0, float(c["nitro_timer"]) - delta)
		if float(c["fire_cd"]) > 0.0:
			c["fire_cd"] = max(0.0, float(c["fire_cd"]) - delta)

		if int(c["lives"]) <= 0:
			continue

		var steer: float = 0.0
		var throttle: float = 0.0
		var drifting: bool = false
		var wants_shoot: bool = false

		if bool(c["is_local"]):
			if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A) or bool(touch_state["left"]):
				steer -= 1.0
			if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D) or bool(touch_state["right"]):
				steer += 1.0
			if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W) or bool(touch_state["gas"]):
				throttle = 1.0
			elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
				throttle = -0.5
			drifting = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SHIFT) or bool(touch_state["drift"])
			wants_shoot = Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_ENTER) or bool(touch_state["shoot"])
		elif bool(c["is_bot"]):
			var bot_out: Dictionary = _compute_bot_ai(c)
			steer = float(bot_out["steer"])
			throttle = float(bot_out["throttle"])
			drifting = bool(bot_out["drift"])
			wants_shoot = bool(bot_out["shoot"])

		# Supra Drift Fysik
		var heading: float = float(c["heading"])
		var vel: Vector2 = c["vel"]
		var forward := Vector2(cos(heading), sin(heading))
		var right := Vector2(-forward.y, forward.x)

		var speed: float = vel.length()
		var turn_rate: float = (3.4 if drifting else 2.5) * clamp(speed / 260.0, 0.35, 1.15)
		heading += steer * turn_rate * delta
		c["heading"] = heading

		forward = Vector2(cos(heading), sin(heading))
		right = Vector2(-forward.y, forward.x)

		var boost_mult: float = 1.42 if float(c["nitro_timer"]) > 0.0 else 1.0
		var accel: float = 780.0 * boost_mult
		vel += forward * (throttle * accel * delta)

		# Lateral friktion (lav ved drift -> brede udskridninger!)
		var forward_speed: float = vel.dot(forward)
		var lateral_speed: float = vel.dot(right)
		var grip: float = 1.65 if drifting else 6.8
		lateral_speed = lerp(lateral_speed, 0.0, clamp(grip * delta, 0.0, 1.0))
		forward_speed *= pow(0.68, delta) # luft/rulle-modstand

		var max_spd: float = 760.0 * boost_mult
		forward_speed = clamp(forward_speed, -260.0, max_spd)
		vel = forward * forward_speed + right * lateral_speed

		var pos: Vector2 = c["pos"] + vel * delta
		# Hold bilen indenfor arenaens autoværn
		if pos.x < 120.0 or pos.x > TRACK_SIZE.x - 120.0:
			vel.x *= -0.55
			pos.x = clamp(pos.x, 120.0, TRACK_SIZE.x - 120.0)
		if pos.y < 120.0 or pos.y > TRACK_SIZE.y - 120.0:
			vel.y *= -0.55
			pos.y = clamp(pos.y, 120.0, TRACK_SIZE.y - 120.0)

		c["pos"] = pos
		c["vel"] = vel

		# Drift-point og dækrøg
		var slip: float = abs(lateral_speed)
		if slip > 125.0 and speed > 210.0:
			c["drift_combo"] = float(c["drift_combo"]) + (slip * delta * 0.14)
			_emit_drift_fx(pos, heading, right, float(c["nitro_timer"]) > 0.0)
		else:
			if float(c["drift_combo"]) >= 10.0:
				c["points"] = int(c["points"]) + int(c["drift_combo"])
			c["drift_combo"] = 0.0

		# Skyd våben
		if wants_shoot and float(c["fire_cd"]) <= 0.0:
			var cd: float = 0.16 if float(c["rapid_timer"]) > 0.0 else 0.42
			c["fire_cd"] = cd
			_fire_bullet(c)

		if bool(c["is_local"]):
			camera.global_position = pos + vel * 0.22

	if alive_count <= 1 and cars.size() > 1:
		_finish_match()

func _compute_bot_ai(c: Dictionary) -> Dictionary:
	var pos: Vector2 = c["pos"]
	var heading: float = float(c["heading"])
	var center: Vector2 = TRACK_SIZE * 0.5
	var to_center: Vector2 = pos - center
	var orbit_angle: float = to_center.angle() + PI * 0.54
	var target_pos: Vector2 = center + Vector2(cos(orbit_angle) * 1050.0, sin(orbit_angle) * 650.0)

	# Jagt hjerte hvis bot har mistet liv
	if int(c["lives"]) < MAX_LIVES:
		for p in pickups:
			if String(p["type"]) == "heart":
				target_pos = p["pos"]
				break

	var desired_angle: float = (target_pos - pos).angle()
	var diff: float = wrapf(desired_angle - heading, -PI, PI)
	var steer: float = clamp(diff * 2.2, -1.0, 1.0)
	var drift: bool = abs(diff) > 0.55

	# Tjek om en anden bil er i sigtekornet
	var shoot: bool = false
	var fwd := Vector2(cos(heading), sin(heading))
	for other in cars:
		if int(other["id"]) == int(c["id"]) or int(other["lives"]) <= 0:
			continue
		var rel: Vector2 = other["pos"] - pos
		if rel.length() < 680.0 and rel.normalized().dot(fwd) > 0.92:
			shoot = true
			break

	return {"steer": steer, "throttle": 0.92, "drift": drift, "shoot": shoot}

func _fire_bullet(car: Dictionary) -> void:
	var heading: float = float(car["heading"])
	var fwd := Vector2(cos(heading), sin(heading))
	var spawn_p: Vector2 = car["pos"] + fwd * 54.0
	bullets.append({
		"owner_id": int(car["id"]),
		"pos": spawn_p,
		"vel": fwd * 1250.0 + car["vel"] * 0.3,
		"life": 1.15,
		"color": car["color"]
	})
	if bool(car["is_local"]) and sfx_shoot:
		sfx_shoot.play()

func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b["pos"] = b["pos"] + b["vel"] * delta
		b["life"] = float(b["life"]) - delta
		if float(b["life"]) <= 0.0:
			bullets.remove_at(i)
			continue

		var bpos: Vector2 = b["pos"]
		var hit_car: bool = false
		for c in cars:
			if int(c["id"]) == int(b["owner_id"]) or int(c["lives"]) <= 0:
				continue
			if bpos.distance_to(c["pos"]) < 42.0:
				hit_car = true
				_damage_car(c, int(b["owner_id"]), b["vel"])
				break
		if hit_car:
			bullets.remove_at(i)

func _damage_car(target: Dictionary, attacker_id: int, impact_vel: Vector2) -> void:
	if float(target["invuln_timer"]) > 0.0:
		return
	target["lives"] = max(0, int(target["lives"]) - 1)
	target["invuln_timer"] = 1.6
	target["vel"] = target["vel"] + impact_vel.normalized() * 340.0
	target["drift_combo"] = 0.0

	for c in cars:
		if int(c["id"]) == attacker_id:
			c["points"] = int(c["points"]) + 250

	for k in range(14):
		var ang: float = randf() * TAU
		sparks.append({
			"pos": target["pos"],
			"vel": Vector2(cos(ang), sin(ang)) * randf_range(120.0, 380.0),
			"life": 0.45,
			"color": Color(1.0, 0.75, 0.1)
		})
	if sfx_hit:
		sfx_hit.play()

func _update_pickups(delta: float) -> void:
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		p["pulse"] = float(p["pulse"]) + delta * 4.0
		var ppos: Vector2 = p["pos"]

		for c in cars:
			if int(c["lives"]) <= 0:
				continue
			if ppos.distance_to(c["pos"]) < 52.0:
				var ptype: String = String(p["type"])
				if ptype == "heart":
					if int(c["lives"]) < MAX_LIVES:
						c["lives"] = int(c["lives"]) + 1
					else:
						c["points"] = int(c["points"]) + 150
				elif ptype == "nitro":
					c["nitro_timer"] = 4.5
					c["points"] = int(c["points"]) + 100
				elif ptype == "rapid":
					c["rapid_timer"] = 6.0
					c["points"] = int(c["points"]) + 100
				else:
					c["points"] = int(c["points"]) + 200

				if bool(c["is_local"]) and sfx_pickup:
					sfx_pickup.play()
				pickups.remove_at(i)
				_spawn_single_pickup()
				break

func _emit_drift_fx(pos: Vector2, heading: float, right: Vector2, is_nitro: bool) -> void:
	var back := Vector2(-cos(heading), -sin(heading)) * 34.0
	var rear_l: Vector2 = pos + back - right * 20.0
	var rear_r: Vector2 = pos + back + right * 20.0
	skidmarks.append({"p1": rear_l, "p2": rear_r, "life": 4.0})
	if skidmarks.size() > 360:
		skidmarks.pop_front()

	if randf() < 0.65:
		smoke_particles.append({
			"pos": rear_l if randf() < 0.5 else rear_r,
			"vel": Vector2(randf_range(-35.0, 35.0), randf_range(-35.0, 35.0)),
			"radius": randf_range(8.0, 15.0),
			"life": 0.55,
			"color": Color(0.2, 0.9, 1.0, 0.55) if is_nitro else Color(0.88, 0.88, 0.92, 0.45)
		})

func _update_fx(delta: float) -> void:
	for i in range(skidmarks.size() - 1, -1, -1):
		skidmarks[i]["life"] = float(skidmarks[i]["life"]) - delta
		if float(skidmarks[i]["life"]) <= 0.0:
			skidmarks.remove_at(i)

	for i in range(smoke_particles.size() - 1, -1, -1):
		var s: Dictionary = smoke_particles[i]
		s["pos"] = s["pos"] + s["vel"] * delta
		s["radius"] = float(s["radius"]) + 18.0 * delta
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			smoke_particles.remove_at(i)

	for i in range(sparks.size() - 1, -1, -1):
		var sp: Dictionary = sparks[i]
		sp["pos"] = sp["pos"] + sp["vel"] * delta
		sp["life"] = float(sp["life"]) - delta
		if float(sp["life"]) <= 0.0:
			sparks.remove_at(i)

func _draw() -> void:
	# 1. Mørk natte-asfalt og neon drift-bane
	draw_rect(Rect2(Vector2.ZERO, TRACK_SIZE), Color(0.08, 0.09, 0.12), true)

	# Asfalt-gitter for tydelig fartfornemmelse
	for gx in range(0, int(TRACK_SIZE.x), 200):
		draw_line(Vector2(gx, 0), Vector2(gx, TRACK_SIZE.y), Color(0.13, 0.14, 0.18), 2.0)
	for gy in range(0, int(TRACK_SIZE.y), 200):
		draw_line(Vector2(0, gy), Vector2(TRACK_SIZE.x, gy), Color(0.13, 0.14, 0.18), 2.0)

	# Oval drift-bane med rød/hvide curbs og neon-striber
	var center: Vector2 = TRACK_SIZE * 0.5
	_draw_track_loop(center, 1520.0, 980.0, Color(0.95, 0.2, 0.35), 14.0)
	_draw_track_loop(center, 1180.0, 740.0, Color(1.0, 1.0, 1.0, 0.35), 6.0)
	_draw_track_loop(center, 840.0, 500.0, Color(0.05, 0.85, 0.95), 12.0)

	# Ydre autoværn
	draw_rect(Rect2(Vector2(100, 100), TRACK_SIZE - Vector2(200, 200)), Color(0.95, 0.25, 0.4), false, 10.0)

	# 2. Dækspor (skidmarks)
	for sm in skidmarks:
		var alpha: float = clamp(float(sm["life"]) / 4.0, 0.0, 0.65)
		var col := Color(0.03, 0.03, 0.04, alpha)
		draw_circle(sm["p1"], 4.5, col)
		draw_circle(sm["p2"], 4.5, col)

	# 3. Power-ups og point-stjerner
	for p in pickups:
		var pos: Vector2 = p["pos"]
		var bob: float = sin(float(p["pulse"])) * 4.0
		var ptype: String = String(p["type"])
		var tex: Texture2D = tex_star
		if ptype == "heart":
			tex = tex_heart
		elif ptype == "nitro":
			tex = tex_nitro
		elif ptype == "rapid":
			tex = tex_rapid
		if tex:
			draw_texture(tex, pos - tex.get_size() * 0.5 + Vector2(0, bob))

	# 4. Dækrøg
	for s in smoke_particles:
		var col: Color = s["color"]
		col.a *= clamp(float(s["life"]) / 0.55, 0.0, 1.0)
		draw_circle(s["pos"], float(s["radius"]), col)

	# 5. Toyota Supra biler
	for c in cars:
		if int(c["lives"]) <= 0:
			continue
		var pos: Vector2 = c["pos"]
		var heading: float = float(c["heading"])
		var blink: bool = float(c["invuln_timer"]) > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0
		if not blink:
			# Underbody neon-glød
			var glow_col: Color = c["color"]
			glow_col.a = 0.28
			draw_circle(pos, 52.0, glow_col)

			draw_set_transform(pos, heading, Vector2.ONE)
			if tex_supra:
				draw_texture(tex_supra, -tex_supra.get_size() * 0.5, c["color"].lerp(Color.WHITE, 0.45))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Navn og hjerter over bilen
		var hearts := ""
		for h in range(int(c["lives"])):
			hearts += "♥"
		draw_string(ThemeDB.fallback_font, pos + Vector2(-42, -52), "%s %s" % [hearts, c["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	# 6. Projektiler og gnister
	for b in bullets:
		draw_circle(b["pos"], 7.0, b["color"])
		draw_circle(b["pos"], 3.5, Color.WHITE)

	for sp in sparks:
		draw_circle(sp["pos"], 4.0, sp["color"])

func _draw_track_loop(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var segs := 64
	for i in range(segs + 1):
		var a: float = (TAU / float(segs)) * float(i)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	hud_label = Label.new()
	hud_label.position = Vector2(24, 18)
	hud_label.add_theme_font_size_override("font_size", 24)
	hud_label.add_theme_color_override("font_color", Color.WHITE)
	hud_layer.add_child(hud_label)

	score_label = Label.new()
	score_label.position = Vector2(960, 18)
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	hud_layer.add_child(score_label)

	var back_btn := Button.new()
	back_btn.text = "← MENU"
	back_btn.position = Vector2(24, 62)
	back_btn.size = Vector2(120, 42)
	back_btn.pressed.connect(func(): exit_to_menu.emit())
	hud_layer.add_child(back_btn)

	# Touch-knapper til Android (Venstre/Højre + Gas/Drift/Skyd)
	_add_touch_btn("◀", Vector2(30, 580), Vector2(105, 105), "left")
	_add_touch_btn("▶", Vector2(150, 580), Vector2(105, 105), "right")
	_add_touch_btn("SKYD", Vector2(910, 580), Vector2(105, 105), "shoot")
	_add_touch_btn("DRIFT", Vector2(1030, 580), Vector2(105, 105), "drift")
	_add_touch_btn("GAS", Vector2(1150, 580), Vector2(105, 105), "gas")

	# Slut-panel
	end_panel = PanelContainer.new()
	end_panel.visible = false
	end_panel.position = Vector2(390, 200)
	end_panel.size = Vector2(500, 280)
	hud_layer.add_child(end_panel)

	var vbox := VBoxContainer.new()
	end_panel.add_child(vbox)
	end_label = Label.new()
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(end_label)

	var menu_btn := Button.new()
	menu_btn.text = "TILBAGE TIL HOVEDMENU"
	menu_btn.custom_minimum_size = Vector2(0, 56)
	menu_btn.pressed.connect(func(): exit_to_menu.emit())
	vbox.add_child(menu_btn)

func _add_touch_btn(txt: String, pos: Vector2, bsize: Vector2, key: String) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.position = pos
	btn.size = bsize
	btn.modulate = Color(1, 1, 1, 0.72)
	btn.button_down.connect(func(): touch_state[key] = true)
	btn.button_up.connect(func(): touch_state[key] = false)
	hud_layer.add_child(btn)

func _update_hud() -> void:
	if cars.is_empty():
		return
	var p1: Dictionary = cars[0]
	var hearts := ""
	for i in range(int(p1["lives"])):
		hearts += "♥ "
	var combo_txt := ""
	if float(p1["drift_combo"]) >= 10.0:
		combo_txt = "  |  DRIFT +%d!" % int(p1["drift_combo"])
	hud_label.text = "LIV: %s  |  POINT: %d%s  |  TID: %ds" % [hearts, int(p1["points"]), combo_txt, int(time_left)]

	var board := "STILLING:
"
	for c in cars:
		board += "%s: %d pt (%d liv)
" % [c["name"], int(c["points"]), int(c["lives"])]
	score_label.text = board

func _finish_match() -> void:
	match_over = true
	var best_car: Dictionary = cars[0]
	for c in cars:
		if int(c["lives"]) > 0 and (int(best_car["lives"]) <= 0 or int(c["points"]) > int(best_car["points"])):
			best_car = c
	end_label.text = "
SUPRA DRIFT BATTLE SLUT!

VINDER: %s
SCORE: %d POINT
" % [best_car["name"], int(best_car["points"])]
	end_panel.visible = true
