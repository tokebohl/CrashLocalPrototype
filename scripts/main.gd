extends Node2D

const PORT := 27015
const MAX_CLIENTS := 3
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const DRIFT_CAR_SCRIPT := preload("res://scripts/drift_car.gd")
const RACE_WORLD_WIDTH := 6400.0
const ARENA_WORLD_WIDTH := 2200.0
const FLOOR_Y := 610.0
const NET_TICK_INTERVAL := 0.033 # 30 Hz ENet multiplayer synkronisering
const DRIFT_TARGET_LAPS := 3

var peer: ENetMultiplayerPeer
var players: Dictionary = {}
var game_mode := "RACE"
var game_started := false
var menu: Control
var menu_bg: Control
var status_label: Label
var ip_input: LineEdit
var world: Node2D
var hud_layer: CanvasLayer
var hud: Label
var sub_hud: Label
var touch_state := {"left": false, "right": false, "analog_x": 0.0, "analog_y": 0.0, "drift_held": false}
var touch_rects: Dictionary = {}
var active_touches: Dictionary = {}
var jump_queued := false
var spin_queued := false
var boost_queued := false
var local_player
var camera: Camera2D
var finishers: Array[int] = []
var arena_timer := 90.0
var result_panel: Control

# Virtuel analog thumbstick til både platform- og drift-styring
var stick_center := Vector2(138.0, 618.0)
var stick_radius := 68.0
var stick_touch_id := -1
var stick_base: Control
var stick_knob: Control

# Grafik-, animations-, objekt- og lyd-containere
var tex_cache: Dictionary = {}
var hero_anim_frames: Dictionary = {}
var sfx_streams: Dictionary = {}
var crates: Dictionary = {}
var fruits_map: Dictionary = {}
var enemies: Dictionary = {}
var moving_platforms: Array[Dictionary] = []
var waterfalls: Array[Sprite2D] = []
var swaying_plants: Array[Node2D] = []
var waterfall_frames: Array[Texture2D] = []
var crab_frames: Array[Texture2D] = []
var tiki_frames: Array[Texture2D] = []
var env_time := 0.0
var net_tick_accum := 0.0
var camera_shake := 0.0

# Supra Drift-bane data
var drift_waypoints: Array[Vector2] = []
var skid_marks: Array[Polygon2D] = []
var drift_start_line := Rect2(1480.0, 210.0, 140.0, 290.0)
var drift_halfway_zone := Rect2(1480.0, 1420.0, 140.0, 290.0)

func _ready() -> void:
	print("CrashLocal: Main._ready")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_procedural_sfx()
	_preload_animation_textures()
	_build_menu()

func get_world_width() -> float:
	if game_mode == "DRIFT":
		return 3200.0
	return RACE_WORLD_WIDTH if game_mode == "RACE" else ARENA_WORLD_WIDTH

func load_svg_tex(path: String, svg_scale: float = 1.0) -> Texture2D:
	var key: String = "%s@%.2f" % [path, svg_scale]
	if tex_cache.has(key):
		return tex_cache[key]
	if FileAccess.file_exists(path) and path.ends_with(".svg"):
		var svg_str := FileAccess.get_file_as_string(path)
		if not svg_str.is_empty():
			var img := Image.new()
			if img.load_svg_from_string(svg_str, svg_scale) == OK and not img.is_empty():
				var tex := ImageTexture.create_from_image(img)
				tex_cache[key] = tex
				return tex
	if ResourceLoader.exists(path):
		var loaded: Texture2D = load(path)
		if loaded != null:
			tex_cache[key] = loaded
			return loaded
	return null

func _preload_animation_textures() -> void:
	waterfall_frames = [
		load_svg_tex("res://art/waterfall_1.svg"),
		load_svg_tex("res://art/waterfall_2.svg"),
		load_svg_tex("res://art/waterfall_3.svg")
	]
	crab_frames = [
		load_svg_tex("res://art/enemy_crab_1.svg"),
		load_svg_tex("res://art/enemy_crab_2.svg")
	]
	tiki_frames = [
		load_svg_tex("res://art/enemy_tiki_1.svg"),
		load_svg_tex("res://art/enemy_tiki_2.svg")
	]
	var counts := {"idle": 4, "run": 6, "jump": 2, "fall": 2, "land": 2, "spin": 4, "hit": 2, "death": 3}
	for st in counts.keys():
		var arr: Array[Texture2D] = []
		for i in range(counts[st]):
			var t := load_svg_tex("res://art/hero_frames/hero_%s_%d.svg" % [st, i + 1])
			if t != null:
				arr.append(t)
		hero_anim_frames[st] = arr

func get_hero_frame(state: String, anim_time: float) -> Texture2D:
	if not hero_anim_frames.has(state):
		state = "idle"
	var arr: Array = hero_anim_frames.get(state, [])
	if arr.is_empty():
		return load_svg_tex("res://art/hero.svg")
	var fps := 8.0
	match state:
		"idle": fps = 5.0
		"run": fps = 14.0
		"spin": fps = 22.0
		"jump", "fall", "land", "hit": fps = 8.0
		"death": fps = 4.0
	var idx := int(anim_time * fps) % arr.size()
	if state == "death":
		idx = mini(arr.size() - 1, int(anim_time * fps))
	return arr[idx]

func _init_procedural_sfx() -> void:
	sfx_streams["jump"] = _make_tone_sfx(240.0, 680.0, 0.16, 0.55, false)
	sfx_streams["spin"] = _make_tone_sfx(180.0, 320.0, 0.28, 0.55, true)
	sfx_streams["crate"] = _make_tone_sfx(210.0, 95.0, 0.18, 0.65, true)
	sfx_streams["fruit"] = _make_tone_sfx(587.0, 880.0, 0.14, 0.55, false)
	sfx_streams["bounce"] = _make_tone_sfx(300.0, 920.0, 0.24, 0.60, false)
	sfx_streams["beep"] = _make_tone_sfx(980.0, 980.0, 0.09, 0.50, false)
	sfx_streams["explosion"] = _make_tone_sfx(110.0, 42.0, 0.42, 0.80, true)
	sfx_streams["checkpoint"] = _make_tone_sfx(523.0, 1046.0, 0.30, 0.60, false)
	sfx_streams["hit"] = _make_tone_sfx(420.0, 140.0, 0.24, 0.65, true)
	sfx_streams["win"] = _make_tone_sfx(523.0, 1174.0, 0.45, 0.65, false)
	sfx_streams["turbo"] = _make_tone_sfx(2200.0, 780.0, 0.30, 0.65, true)
	sfx_streams["screech"] = _make_tone_sfx(1280.0, 1490.0, 0.22, 0.42, true)

func _make_tone_sfx(f0: float, f1: float, dur: float, vol: float, noisy: bool) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	for i in range(count):
		var t := float(i) / float(count)
		var freq := lerpf(f0, f1, t)
		phase += TAU * freq / float(rate)
		var env := (1.0 - t) * sin(minf(1.0, t * 12.0) * PI * 0.5)
		var sig := sin(phase) * 0.75 + sin(phase * 2.0) * 0.25
		if noisy:
			sig = sig * 0.55 + (randf() * 2.0 - 1.0) * 0.45
		var sample := clampi(int(sig * env * vol * 32000.0), -32767, 32767)
		bytes.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func play_sfx(name_key: String) -> void:
	if not sfx_streams.has(name_key):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sfx_streams[name_key]
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func add_camera_shake(amount: float) -> void:
	camera_shake = maxf(camera_shake, amount)

func _get_local_lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "192.168.1.10"

func _build_menu() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0f2830")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.custom_minimum_size = Vector2(1280, 720)
	add_child(bg)
	menu_bg = bg

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.custom_minimum_size = Vector2(1280, 720)
	add_child(center)
	menu = center

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(680, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "CRASH LOCAL: JUNGLE & SUPRA DRIFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#ffe66d"))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "RACE MODE  •  ARENA MODE  •  TOYOTA SUPRA DRIFT  •  2–4 TELEFONER"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("#9be8d8"))
	box.add_child(subtitle)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	box.add_child(mode_row)

	var race := Button.new()
	race.text = "RACE MODE"
	race.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race.custom_minimum_size.y = 52
	mode_row.add_child(race)

	var arena := Button.new()
	arena.text = "ARENA MODE"
	arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena.custom_minimum_size.y = 52
	mode_row.add_child(arena)

	var drift := Button.new()
	drift.text = "SUPRA DRIFT"
	drift.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drift.custom_minimum_size.y = 52
	mode_row.add_child(drift)

	var mode_btns: Array[Button] = [race, arena, drift]
	race.pressed.connect(func() -> void: _select_mode("RACE", race, mode_btns))
	arena.pressed.connect(func() -> void: _select_mode("ARENA", arena, mode_btns))
	drift.pressed.connect(func() -> void: _select_mode("DRIFT", drift, mode_btns))

	var host := Button.new()
	host.text = "OPRET RUM PÅ DENNE TELEFON (DIN IP: %s)" % _get_local_lan_ip()
	host.custom_minimum_size.y = 48
	host.pressed.connect(_host_game)
	box.add_child(host)

	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Indtast værtens lokale IP-adresse (fx 192.168.43.1)"
	ip_input.text = _get_local_lan_ip()
	ip_input.custom_minimum_size.y = 42
	box.add_child(ip_input)

	var join := Button.new()
	join.text = "TILSLUT TIL VÆRT"
	join.custom_minimum_size.y = 48
	join.pressed.connect(_join_game)
	box.add_child(join)

	var start := Button.new()
	start.text = "START MULTIPLAYER SPIL (VÆRT)"
	start.custom_minimum_size.y = 52
	start.modulate = Color("#ffe66d")
	start.pressed.connect(_start_game)
	box.add_child(start)

	var solo := Button.new()
	solo.text = "HURTIG TEST PÅ 1 TELEFON (MED BOT)"
	solo.custom_minimum_size.y = 46
	solo.pressed.connect(_start_solo_with_bot)
	box.add_child(solo)

	status_label = Label.new()
	status_label.text = "Vælg Race, Arena eller Supra Drift. Alle telefoner skal være på samme Wi-Fi/hotspot."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)

	_select_mode("RACE", race, mode_btns)

func _select_mode(mode: String, selected: Button, all_buttons: Array[Button]) -> void:
	game_mode = mode
	for b in all_buttons:
		b.modulate = Color.WHITE
	selected.modulate = Color("#8cff9b")
	_status("Valgt %s. Opret rum på værten (IP: %s) eller tilslut." % [mode, _get_local_lan_ip()])

func _host_game() -> void:
	_close_network()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		err = peer.create_server(0, MAX_CLIENTS)
	if err != OK:
		_status("Kunne ikke oprette rum. Godot-fejlkode: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	_status("RUM OPRETTET! Værtens IP: %s (Port %d). Indtast denne IP på de andre telefoner." % [_get_local_lan_ip(), PORT])

func _join_game() -> void:
	_close_network()
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		_status("Skriv værtens lokale IP-adresse.")
		return
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		_status("Kunne ikke forbinde. Godot-fejlkode: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	_status("Forbinder til %s:%d ..." % [address, PORT])

func _start_game() -> void:
	if not multiplayer.has_multiplayer_peer():
		_host_game()
	if not multiplayer.is_server():
		_status("Kun værten kan starte spillet. Vent på værten.")
		return
	_begin_match.rpc(game_mode, false)

func _start_solo_with_bot() -> void:
	_host_game()
	_begin_match(game_mode, true)

@rpc("authority", "call_local", "reliable")
func _begin_match(mode: String, include_bot: bool = false) -> void:
	game_mode = mode
	game_started = true
	finishers.clear()
	arena_timer = 90.0
	if is_instance_valid(menu):
		menu.hide()
	if is_instance_valid(menu_bg):
		menu_bg.hide()
	if is_instance_valid(result_panel):
		result_panel.queue_free()

	_create_world()
	var spawn_base := Vector2(1380.0, 315.0) if game_mode == "DRIFT" else Vector2(110.0, FLOOR_Y - 70.0)
	_spawn_player(multiplayer.get_unique_id(), spawn_base, false)
	if multiplayer.is_server():
		var idx := 1
		for id in multiplayer.get_peers():
			var offset := Vector2(-idx * 95.0, (idx % 2) * 70.0) if game_mode == "DRIFT" else Vector2(idx * 65.0, 0.0)
			_spawn_player(id, spawn_base + offset, false)
			idx += 1
		if include_bot:
			var bot_offset := Vector2(-110.0, 75.0) if game_mode == "DRIFT" else Vector2(75.0, 0.0)
			_spawn_player(99, spawn_base + bot_offset, true)
	else:
		_request_spawn.rpc_id(1, multiplayer.get_unique_id())
	play_sfx("checkpoint")

@rpc("any_peer", "call_remote", "reliable")
func _request_spawn(id: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == id:
		var pos := Vector2(1290.0, 385.0) if game_mode == "DRIFT" else Vector2(160.0 + (id % 3) * 65.0, FLOOR_Y - 70.0)
		_spawn_player.rpc(id, pos, false)

func _create_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(hud_layer):
		hud_layer.queue_free()

	crates.clear()
	fruits_map.clear()
	enemies.clear()
	moving_platforms.clear()
	waterfalls.clear()
	swaying_plants.clear()
	active_touches.clear()
	skid_marks.clear()
	stick_touch_id = -1
	touch_state = {"left": false, "right": false, "analog_x": 0.0, "analog_y": 0.0, "drift_held": false}

	world = Node2D.new()
	world.name = "GameWorld"
	add_child(world)

	if game_mode == "DRIFT":
		_build_drift_track()
		_build_hud_and_touch()
		camera = Camera2D.new()
		camera.position = Vector2(1380, 340)
		camera.limit_left = 0
		camera.limit_right = 3200
		camera.limit_top = 0
		camera.limit_bottom = 1900
		camera.zoom = Vector2(0.85, 0.85)
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 8.0
		camera.make_current()
		world.add_child(camera)
		return

	var w_width := get_world_width()
	_build_parallax_jungle(w_width)

	if game_mode == "RACE":
		_build_race_level()
	else:
		_build_arena_level()

	_build_hud_and_touch()

	camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	camera.limit_left = 0
	camera.limit_right = int(w_width)
	camera.limit_top = 0
	camera.limit_bottom = 720
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	camera.make_current()
	world.add_child(camera)

func _build_drift_track() -> void:
	# Tropisk kyst- og jungle-driftbane (3200 x 1900 top-down)
	var grass_bg := ColorRect.new()
	grass_bg.position = Vector2.ZERO
	grass_bg.size = Vector2(3200, 1900)
	grass_bg.color = Color("#1e6b3b")
	grass_bg.z_index = -30
	world.add_child(grass_bg)

	# Indre sø / lagune midt på banen
	var lake_border := Polygon2D.new()
	lake_border.polygon = PackedVector2Array([
		Vector2(660, 560), Vector2(2540, 560), Vector2(2540, 1340), Vector2(660, 1340)
	])
	lake_border.color = Color("#e8c87d")
	lake_border.z_index = -25
	world.add_child(lake_border)

	var lake := Polygon2D.new()
	lake.polygon = PackedVector2Array([
		Vector2(700, 600), Vector2(2500, 600), Vector2(2500, 1300), Vector2(700, 1300)
	])
	lake.color = Color("#1ea8d6")
	lake.z_index = -24
	world.add_child(lake)

	# Asfalt-driftbane med chikane og hårnålesving
	var track_outer := Polygon2D.new()
	track_outer.polygon = PackedVector2Array([
		Vector2(220, 200), Vector2(2980, 200), Vector2(2980, 1700), Vector2(220, 1700)
	])
	track_outer.color = Color("#2d323a")
	track_outer.z_index = -20
	world.add_child(track_outer)

	var track_inner := Polygon2D.new()
	track_inner.polygon = PackedVector2Array([
		Vector2(540, 500), Vector2(2660, 500), Vector2(2660, 1400), Vector2(540, 1400)
	])
	track_inner.color = Color("#237a43")
	track_inner.z_index = -19
	world.add_child(track_inner)

	# Rød/hvide racing-curbs langs svingene
	var curb_rects := [
		[Vector2(200, 180), Vector2(2800, 20), Color("#ff3b3b")],
		[Vector2(200, 1700), Vector2(2800, 20), Color("#ff3b3b")],
		[Vector2(200, 200), Vector2(20, 1500), Color("#ffffff")],
		[Vector2(2980, 200), Vector2(20, 1500), Color("#ffffff")],
		[Vector2(520, 480), Vector2(2160, 20), Color("#ffd43b")],
		[Vector2(520, 1400), Vector2(2160, 20), Color("#ffd43b")],
		[Vector2(520, 500), Vector2(20, 900), Color("#ff3b3b")],
		[Vector2(2660, 500), Vector2(20, 900), Color("#ff3b3b")]
	]
	for cr in curb_rects:
		var cpoly := ColorRect.new()
		cpoly.position = cr[0]
		cpoly.size = cr[1]
		cpoly.color = cr[2]
		cpoly.z_index = -18
		world.add_child(cpoly)

	# Fysiske yder- og indervægge så bilerne bliver på banen
	_add_drift_wall(Vector2(1600, 165), Vector2(3000, 45))
	_add_drift_wall(Vector2(1600, 1735), Vector2(3000, 45))
	_add_drift_wall(Vector2(185, 950), Vector2(45, 1600))
	_add_drift_wall(Vector2(3015, 950), Vector2(45, 1600))
	_add_drift_wall(Vector2(1600, 950), Vector2(2090, 870))

	# Start/Mål-linje (skakternet)
	for row in range(10):
		for col in range(3):
			var sq := ColorRect.new()
			sq.position = Vector2(1500 + col * 24, 205 + row * 29)
			sq.size = Vector2(24, 29)
			sq.color = Color.WHITE if (row + col) % 2 == 0 else Color("#12151a")
			sq.z_index = -16
			world.add_child(sq)

	# Halfway checkpoint-linje nederst på banen
	var cp_line := ColorRect.new()
	cp_line.position = Vector2(1520, 1420)
	cp_line.size = Vector2(24, 280)
	cp_line.color = Color("#38f2ff", 0.55)
	cp_line.z_index = -16
	world.add_child(cp_line)

	# Drift-zoner (gyldne markeringer i svingene)
	for dz_pos in [Vector2(2680, 260), Vector2(2680, 1460), Vector2(280, 1460), Vector2(280, 260)]:
		var dz := ColorRect.new()
		dz.position = dz_pos
		dz.size = Vector2(240, 180)
		dz.color = Color("#ffae2b", 0.16)
		dz.z_index = -17
		world.add_child(dz)

	# Waypoints til AI-Bot Supra
	drift_waypoints = [
		Vector2(2150, 340),
		Vector2(2820, 360),
		Vector2(2820, 950),
		Vector2(2820, 1550),
		Vector2(2100, 1550),
		Vector2(1100, 1550),
		Vector2(380, 1550),
		Vector2(380, 950),
		Vector2(380, 350),
		Vector2(1100, 340)
	]

func _add_drift_wall(center_pos: Vector2, wall_size: Vector2) -> void:
	var sb := StaticBody2D.new()
	sb.position = center_pos
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = wall_size
	cs.shape = rect
	sb.add_child(cs)
	world.add_child(sb)

func get_drift_waypoints() -> Array[Vector2]:
	return drift_waypoints

func get_drift_stick_vector() -> Vector2:
	return Vector2(float(touch_state.get("analog_x", 0.0)), float(touch_state.get("analog_y", 0.0)))

func spawn_skid_mark(pos: Vector2, ang: float) -> void:
	if not is_instance_valid(world):
		return
	var mark := Polygon2D.new()
	mark.polygon = PackedVector2Array([
		Vector2(-10, -3), Vector2(10, -3), Vector2(10, 3), Vector2(-10, 3)
	])
	mark.position = pos
	mark.rotation = ang
	mark.color = Color(0.06, 0.07, 0.09, 0.55)
	mark.z_index = -15
	world.add_child(mark)
	skid_marks.append(mark)
	if skid_marks.size() > 260:
		var oldest = skid_marks.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

func check_drift_lap_progress(car) -> void:
	if not is_instance_valid(car):
		return
	var p: Vector2 = car.global_position
	if drift_halfway_zone.has_point(p):
		car.passed_halfway = true
	elif drift_start_line.has_point(p) and car.passed_halfway:
		car.passed_halfway = false
		car.lap += 1
		if car.is_local:
			play_sfx("checkpoint")
		if car.lap > DRIFT_TARGET_LAPS and multiplayer.is_server():
			var final_pts: int = int(car.total_drift_score) + int(car.drift_combo_score) + 500
			var wname: String = "BOT SUPRA" if car.is_bot else ("SPILLER %d SUPRA" % int(car.player_id))
			_show_result.rpc("%s VANDT SUPRA DRIFT! (%d Drift-Point)" % [wname, final_pts])

func _build_parallax_jungle(w_width: float) -> void:
	var pbg := ParallaxBackground.new()
	world.add_child(pbg)

	var layers_cfg := [
		["res://art/jungle_back.svg", Vector2(0.10, 0.0)],
		["res://art/jungle_ruins.svg", Vector2(0.28, 0.0)],
		["res://art/jungle_mid.svg", Vector2(0.55, 0.0)],
		["res://art/jungle_fg.svg", Vector2(0.82, 0.0)]
	]
	for cfg in layers_cfg:
		var pl := ParallaxLayer.new()
		pl.motion_scale = cfg[1]
		pl.motion_mirroring = Vector2(2400, 0)
		var sp := Sprite2D.new()
		sp.texture = load_svg_tex(cfg[0])
		sp.centered = false
		sp.position = Vector2.ZERO
		if game_mode == "ARENA" and cfg[0].ends_with("jungle_back.svg"):
			sp.modulate = Color(0.82, 0.78, 1.0)
		pl.add_child(sp)
		pbg.add_child(pl)

	var wf_x_list := [520.0, 1840.0, 3420.0, 5120.0] if game_mode == "RACE" else [460.0, 1740.0]
	for wx in wf_x_list:
		var wf := Sprite2D.new()
		if waterfall_frames.size() > 0:
			wf.texture = waterfall_frames[0]
		wf.position = Vector2(wx, 445)
		wf.z_index = -12
		world.add_child(wf)
		waterfalls.append(wf)

		var mist := CPUParticles2D.new()
		mist.position = Vector2(wx, 585)
		mist.z_index = -11
		mist.amount = 16
		mist.lifetime = 0.9
		mist.direction = Vector2(0, -1)
		mist.spread = 75.0
		mist.gravity = Vector2(0, 60)
		mist.initial_velocity_min = 25.0
		mist.initial_velocity_max = 60.0
		mist.scale_amount_min = 6.0
		mist.scale_amount_max = 13.0
		mist.color = Color(0.88, 0.99, 1.0, 0.55)
		world.add_child(mist)

	var rays_count := int(w_width / 650.0)
	for i in range(rays_count):
		var rx := 280.0 + float(i) * 650.0
		var ray := Polygon2D.new()
		ray.polygon = PackedVector2Array([
			Vector2(rx, -20), Vector2(rx + 120, -20),
			Vector2(rx + 310, 640), Vector2(rx + 130, 640)
		])
		ray.color = Color(1.0, 0.98, 0.78, 0.08)
		ray.z_index = -8
		world.add_child(ray)

func _build_race_level() -> void:
	var ground_segments := [
		[0.0, 1420.0],
		[1580.0, 2980.0],
		[3160.0, 4680.0],
		[4860.0, 6400.0]
	]
	for seg in ground_segments:
		var x0: float = seg[0]
		var x1: float = seg[1]
		_platform(Vector2(x0, FLOOR_Y), Vector2(x1 - x0, 120))
		var px := x0 + 95.0
		while px < x1 - 95.0:
			_add_swaying_plant(Vector2(px, FLOOR_Y - 18))
			px += 260.0

	_add_moving_platform(Vector2(1425, 535), Vector2(1555, 535), 1.6)
	_add_moving_platform(Vector2(3000, 520), Vector2(3140, 430), 1.8)
	_add_moving_platform(Vector2(4700, 525), Vector2(4840, 440), 1.9)

	var plats := [
		[280.0, 495.0, 165.0], [540.0, 425.0, 165.0], [820.0, 365.0, 175.0], [1120.0, 465.0, 165.0],
		[1740.0, 485.0, 170.0], [2020.0, 410.0, 170.0], [2310.0, 345.0, 180.0], [2620.0, 445.0, 170.0],
		[3320.0, 480.0, 165.0], [3590.0, 395.0, 165.0], [3860.0, 320.0, 185.0], [4160.0, 415.0, 170.0], [4430.0, 360.0, 165.0],
		[5040.0, 475.0, 175.0], [5340.0, 395.0, 175.0], [5640.0, 330.0, 180.0], [5930.0, 435.0, 175.0]
	]
	for i in range(plats.size()):
		var p: Array = plats[i]
		_platform(Vector2(p[0], p[1]), Vector2(p[2], 34))
		_spawn_fruit(i * 10 + 1, Vector2(p[0] + 45.0, p[1] - 42.0))
		_spawn_fruit(i * 10 + 2, Vector2(p[0] + 85.0, p[1] - 62.0))
		_spawn_fruit(i * 10 + 3, Vector2(p[0] + 125.0, p[1] - 42.0))

	var crate_defs := [
		[1, Vector2(360, 465), "NORMAL"],
		[2, Vector2(680, FLOOR_Y - 26), "BOUNCE"],
		[3, Vector2(905, 335), "AKU"],
		[4, Vector2(1240, FLOOR_Y - 26), "TNT"],
		[5, Vector2(1640, FLOOR_Y - 26), "CHECKPOINT"],
		[6, Vector2(1820, 455), "NORMAL"],
		[7, Vector2(2100, 380), "TNT"],
		[8, Vector2(2395, 315), "NORMAL"],
		[9, Vector2(2520, FLOOR_Y - 26), "BOUNCE"],
		[10, Vector2(3220, FLOOR_Y - 26), "CHECKPOINT"],
		[11, Vector2(3400, 450), "AKU"],
		[12, Vector2(3945, 290), "NORMAL"],
		[13, Vector2(4000, 290), "TNT"],
		[14, Vector2(4320, FLOOR_Y - 26), "BOUNCE"],
		[15, Vector2(4920, FLOOR_Y - 26), "CHECKPOINT"],
		[16, Vector2(5125, 445), "NORMAL"],
		[17, Vector2(5425, 365), "TNT"],
		[18, Vector2(5725, 300), "AKU"]
	]
	for cd in crate_defs:
		_spawn_crate(cd[0], cd[1], cd[2])

	for hx in [980.0, 2180.0, 2790.0, 3720.0, 4520.0, 5520.0, 5820.0]:
		_hazard(Vector2(hx, FLOOR_Y - 18))

	var enemy_defs := [
		[1, Vector2(460, FLOOR_Y - 26), 110.0, "CRAB"],
		[2, Vector2(1290, FLOOR_Y - 26), 95.0, "CRAB"],
		[3, Vector2(1920, FLOOR_Y - 32), 130.0, "TIKI"],
		[4, Vector2(2460, FLOOR_Y - 26), 110.0, "CRAB"],
		[5, Vector2(3480, FLOOR_Y - 32), 140.0, "TIKI"],
		[6, Vector2(4080, FLOOR_Y - 26), 120.0, "CRAB"],
		[7, Vector2(5240, FLOOR_Y - 32), 135.0, "TIKI"],
		[8, Vector2(6040, FLOOR_Y - 26), 110.0, "CRAB"]
	]
	for ed in enemy_defs:
		_spawn_enemy(ed[0], ed[1], ed[2], ed[3])

	_add_art_sprite("res://art/sign.svg", Vector2(RACE_WORLD_WIDTH - 230, FLOOR_Y - 56), Vector2(82, 88), 2)
	_goal(Vector2(RACE_WORLD_WIDTH - 115, FLOOR_Y - 110))

func _build_arena_level() -> void:
	_platform(Vector2(120, FLOOR_Y), Vector2(1960, 115))
	var arena_plats := [
		[280.0, 475.0, 240.0], [1680.0, 475.0, 240.0],
		[640.0, 380.0, 260.0], [1300.0, 380.0, 260.0],
		[940.0, 275.0, 320.0]
	]
	for ap in arena_plats:
		_platform(Vector2(ap[0], ap[1]), Vector2(ap[2], 34))

	_add_moving_platform(Vector2(480, 290), Vector2(780, 290), 1.5)
	_add_moving_platform(Vector2(1420, 290), Vector2(1720, 290), 1.5)

	for hx in [560.0, 1100.0, 1640.0]:
		_hazard(Vector2(hx, FLOOR_Y - 18))

	var arena_crates := [
		[101, Vector2(220, FLOOR_Y - 26), "BOUNCE"],
		[102, Vector2(1980, FLOOR_Y - 26), "BOUNCE"],
		[103, Vector2(400, 445), "TNT"],
		[104, Vector2(1800, 445), "TNT"],
		[105, Vector2(770, 350), "NORMAL"],
		[106, Vector2(1430, 350), "NORMAL"],
		[107, Vector2(1100, 245), "AKU"],
		[108, Vector2(860, FLOOR_Y - 26), "TNT"],
		[109, Vector2(1340, FLOOR_Y - 26), "TNT"]
	]
	for cd in arena_crates:
		_spawn_crate(cd[0], cd[1], cd[2])

	for i in range(10):
		_spawn_fruit(200 + i, Vector2(340.0 + i * 165.0, 215.0 + float(i % 2) * 95.0))

func _add_swaying_plant(pos: Vector2) -> void:
	var sp := Sprite2D.new()
	sp.texture = load_svg_tex("res://art/jungle_plant.svg")
	sp.position = pos
	sp.scale = Vector2(0.45, 0.45)
	sp.z_index = 4
	world.add_child(sp)
	swaying_plants.append(sp)

func _add_moving_platform(p_from: Vector2, p_to: Vector2, speed: float) -> void:
	var body := AnimatableBody2D.new()
	body.position = p_from
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(150, 28)
	cs.shape = rect
	body.add_child(cs)
	var sp := Sprite2D.new()
	sp.texture = load_svg_tex("res://art/moving_platform.svg")
	sp.scale = Vector2(150.0 / 240.0, 32.0 / 56.0)
	body.add_child(sp)
	world.add_child(body)
	moving_platforms.append({"node": body, "from": p_from, "to": p_to, "speed": speed, "phase": randf() * TAU})

func _spawn_crate(cid: int, pos: Vector2, ctype: String) -> void:
	var area := Area2D.new()
	area.position = pos
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 48)
	cs.shape = rect
	area.add_child(cs)

	var tex_path := "res://art/crate.svg"
	match ctype:
		"BOUNCE": tex_path = "res://art/bounce_crate.svg"
		"TNT": tex_path = "res://art/tnt_crate.svg"
		"AKU": tex_path = "res://art/aku_crate.svg"
		"CHECKPOINT": tex_path = "res://art/checkpoint_crate.svg"

	var sp := Sprite2D.new()
	sp.name = "Sprite"
	sp.texture = load_svg_tex(tex_path)
	sp.scale = Vector2(46.0 / 128.0, 46.0 / 128.0)
	area.add_child(sp)

	var lbl := Label.new()
	lbl.name = "TimerLabel"
	lbl.position = Vector2(-12, -52)
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color("#ffea47"))
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	area.add_child(lbl)

	area.body_entered.connect(func(body: Node2D): _on_crate_touched(cid, body))
	world.add_child(area)
	crates[cid] = {"node": area, "sprite": sp, "label": lbl, "type": ctype, "active": true, "tnt_timer": -1.0}

func _on_crate_touched(cid: int, body) -> void:
	if not crates.has(cid) or not crates[cid]["active"]:
		return
	if not body.has_method("get_player_id"):
		return
	var cdata: Dictionary = crates[cid]
	var ctype: String = cdata["type"]
	var cnode: Area2D = cdata["node"]

	if ctype == "CHECKPOINT":
		body.checkpoint_pos = cnode.global_position + Vector2(0, -20)
		_activate_crate_effect.rpc(cid, body.get_player_id(), false)
		return

	if ctype == "BOUNCE":
		body.velocity.y = -840.0
		body.emit_dust()
		play_sfx("bounce")
		cnode.scale = Vector2(1.25, 0.75)
		return

	if ctype == "TNT":
		if body.spinning:
			_activate_crate_effect.rpc(cid, body.get_player_id(), true)
		elif cdata["tnt_timer"] < 0.0:
			cdata["tnt_timer"] = 3.0
			if body.global_position.y < cnode.global_position.y:
				body.velocity.y = -480.0
			play_sfx("beep")
		return

	if body.global_position.y < cnode.global_position.y:
		body.velocity.y = -520.0
	_activate_crate_effect.rpc(cid, body.get_player_id(), false)

@rpc("any_peer", "call_local", "reliable")
func _activate_crate_effect(cid: int, pid: int, immediate_explode: bool) -> void:
	if not crates.has(cid) or not crates[cid]["active"]:
		return
	var cdata: Dictionary = crates[cid]
	var ctype: String = cdata["type"]
	var cnode: Area2D = cdata["node"]
	var pos := cnode.global_position

	if ctype == "CHECKPOINT":
		cdata["active"] = false
		var sp: Sprite2D = cdata["sprite"]
		sp.texture = load_svg_tex("res://art/checkpoint_open.svg")
		play_sfx("checkpoint")
		_spawn_burst_particles(pos, Color("#4cff88"), 18)
		return

	cdata["active"] = false
	cnode.hide()

	if ctype == "TNT" or immediate_explode:
		play_sfx("explosion")
		add_camera_shake(14.0)
		_spawn_burst_particles(pos, Color("#ff4d29"), 28)
		for id in players.keys():
			var p = players[id]
			if is_instance_valid(p) and p.global_position.distance_to(pos) < 115.0:
				p.take_hazard_hit()
	else:
		play_sfx("crate")
		add_camera_shake(5.0)
		_spawn_burst_particles(pos, Color("#e89a3c"), 16)
		if players.has(pid) and is_instance_valid(players[pid]):
			if ctype == "AKU":
				players[pid].grant_mask()
				play_sfx("checkpoint")
			else:
				players[pid].add_fruit(3)
				play_sfx("fruit")

func _spawn_fruit(fid: int, pos: Vector2) -> void:
	var area := Area2D.new()
	area.position = pos
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	cs.shape = circle
	area.add_child(cs)
	var sp := Sprite2D.new()
	sp.texture = load_svg_tex("res://art/fruit.svg")
	sp.scale = Vector2(32.0 / 96.0, 36.0 / 112.0)
	area.add_child(sp)
	area.body_entered.connect(func(body: Node2D):
		if body.has_method("get_player_id") and fruits_map.has(fid) and fruits_map[fid]["active"]:
			_collect_fruit.rpc(fid, body.get_player_id())
	)
	world.add_child(area)
	fruits_map[fid] = {"node": area, "base_y": pos.y, "active": true}

@rpc("any_peer", "call_local", "reliable")
func _collect_fruit(fid: int, pid: int) -> void:
	if not fruits_map.has(fid) or not fruits_map[fid]["active"]:
		return
	fruits_map[fid]["active"] = false
	var node: Area2D = fruits_map[fid]["node"]
	_spawn_burst_particles(node.global_position, Color("#ffd426"), 10)
	node.hide()
	play_sfx("fruit")
	if players.has(pid) and is_instance_valid(players[pid]):
		players[pid].add_fruit(1)

func _spawn_enemy(eid: int, pos: Vector2, patrol_dist: float, etype: String) -> void:
	var area := Area2D.new()
	area.position = pos
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(46, 44) if etype == "CRAB" else Vector2(44, 68)
	cs.shape = rect
	area.add_child(cs)

	var sp := Sprite2D.new()
	sp.texture = crab_frames[0] if etype == "CRAB" else tiki_frames[0]
	sp.scale = Vector2(0.46, 0.46) if etype == "CRAB" else Vector2(0.54, 0.54)
	area.add_child(sp)
	area.body_entered.connect(func(body: Node2D): _on_enemy_contact(eid, body))
	world.add_child(area)
	enemies[eid] = {
		"node": area, "sprite": sp, "type": etype,
		"start_x": pos.x, "dist": patrol_dist, "dir": 1.0, "active": true
	}

func _on_enemy_contact(eid: int, body) -> void:
	if not enemies.has(eid) or not enemies[eid]["active"]:
		return
	if not body.has_method("get_player_id"):
		return
	var enode: Area2D = enemies[eid]["node"]
	if body.spinning or (body.velocity.y > 0.0 and body.global_position.y < enode.global_position.y - 10.0):
		body.velocity.y = -520.0
		_defeat_enemy.rpc(eid)
	else:
		body.take_hazard_hit()

@rpc("any_peer", "call_local", "reliable")
func _defeat_enemy(eid: int) -> void:
	if not enemies.has(eid) or not enemies[eid]["active"]:
		return
	enemies[eid]["active"] = false
	var enode: Area2D = enemies[eid]["node"]
	_spawn_burst_particles(enode.global_position, Color("#ff6b4a"), 18)
	enode.hide()
	play_sfx("crate")
	add_camera_shake(6.0)

func check_spin_interactions(player) -> void:
	var ppos: Vector2 = player.global_position
	for cid in crates.keys():
		if crates[cid]["active"]:
			var cnode: Area2D = crates[cid]["node"]
			if cnode.global_position.distance_to(ppos) < 84.0:
				_activate_crate_effect.rpc(cid, player.get_player_id(), crates[cid]["type"] == "TNT")
	for eid in enemies.keys():
		if enemies[eid]["active"]:
			var enode: Area2D = enemies[eid]["node"]
			if enode.global_position.distance_to(ppos) < 88.0:
				_defeat_enemy.rpc(eid)

func _spawn_burst_particles(pos: Vector2, col: Color, count: int) -> void:
	if not is_instance_valid(world):
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = count
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 0.92
	p.spread = 180.0
	p.gravity = Vector2(0, 480)
	p.initial_velocity_min = 95.0
	p.initial_velocity_max = 240.0
	p.scale_amount_min = 5.0
	p.scale_amount_max = 10.0
	p.color = col
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)

func _add_art_sprite(path: String, at: Vector2, target_size: Vector2, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load_svg_tex(path)
	sprite.position = at
	sprite.z_index = z
	if sprite.texture:
		sprite.scale = Vector2(target_size.x / sprite.texture.get_width(), target_size.y / sprite.texture.get_height())
	world.add_child(sprite)
	return sprite

func _platform(pos: Vector2, size: Vector2, _body_color: Color = Color.WHITE, _top_color: Color = Color.WHITE) -> void:
	var body := StaticBody2D.new()
	body.position = pos + size / 2.0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)

	var tex := load_svg_tex("res://art/platform.svg")
	var tiles := maxi(1, int(ceil(size.x / 320.0)))
	var tile_w := size.x / float(tiles)
	for i in range(tiles):
		var visual := Sprite2D.new()
		visual.texture = tex
		visual.position = Vector2(-size.x * 0.5 + tile_w * (float(i) + 0.5), 0.0)
		visual.scale = Vector2(tile_w / 320.0, maxf(size.y / 90.0, 0.48))
		body.add_child(visual)
	world.add_child(body)

func _goal(pos: Vector2) -> void:
	var goal := Area2D.new()
	goal.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(75, 190)
	shape.shape = rect
	goal.add_child(shape)

	var portal := Sprite2D.new()
	portal.texture = load_svg_tex("res://art/goal_portal.svg")
	portal.scale = Vector2(0.85, 0.85)
	goal.add_child(portal)

	goal.body_entered.connect(_on_goal)
	world.add_child(goal)

func _hazard(pos: Vector2) -> void:
	var h := Area2D.new()
	h.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(74, 34)
	shape.shape = rect
	h.add_child(shape)

	var sp := Sprite2D.new()
	sp.texture = load_svg_tex("res://art/spikes.svg")
	sp.scale = Vector2(82.0 / 240.0, 42.0 / 110.0)
	h.add_child(sp)

	h.body_entered.connect(_on_hazard)
	world.add_child(h)

func _build_hud_and_touch() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)

	var hud_bg := ColorRect.new()
	hud_bg.position = Vector2(16, 12)
	hud_bg.size = Vector2(730, 74)
	hud_bg.color = Color(0.05, 0.14, 0.11, 0.65)
	hud_layer.add_child(hud_bg)

	hud = Label.new()
	hud.position = Vector2(28, 16)
	hud.add_theme_font_size_override("font_size", 24)
	hud.add_theme_color_override("font_color", Color("#ffe66d"))
	hud.add_theme_color_override("font_shadow_color", Color("#111c15"))
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	hud_layer.add_child(hud)

	sub_hud = Label.new()
	sub_hud.position = Vector2(28, 48)
	sub_hud.add_theme_font_size_override("font_size", 18)
	sub_hud.add_theme_color_override("font_color", Color.WHITE)
	hud_layer.add_child(sub_hud)

	# Analog Controller Thumbstick nederst til venstre
	_build_virtual_thumbstick(hud_layer)

	# Action-knapper nederst til højre (tilpasset Race/Arena eller Supra Drift)
	if game_mode == "DRIFT":
		_touch_button(hud_layer, "DRIFT", Vector2(990, 588), Vector2(125, 102), "drift", Color("#e85d24"))
		_touch_button(hud_layer, "TURBO", Vector2(1130, 588), Vector2(125, 102), "boost", Color("#1b9cfc"))
	else:
		_touch_button(hud_layer, "JUMP", Vector2(995, 590), Vector2(120, 100), "jump", Color("#2678d9"))
		_touch_button(hud_layer, "SPIN", Vector2(1130, 590), Vector2(120, 100), "spin", Color("#e85d24"))

func _build_virtual_thumbstick(layer: CanvasLayer) -> void:
	stick_base = Control.new()
	stick_base.position = stick_center - Vector2(stick_radius, stick_radius)
	stick_base.size = Vector2(stick_radius * 2.0, stick_radius * 2.0)
	stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(stick_base)

	var outer_ring := Polygon2D.new()
	var pts_outer := PackedVector2Array()
	for i in range(32):
		var a: float = float(i) / 32.0 * TAU
		pts_outer.append(Vector2(stick_radius + cos(a) * stick_radius, stick_radius + sin(a) * stick_radius))
	outer_ring.polygon = pts_outer
	outer_ring.color = Color(0.10, 0.28, 0.22, 0.56)
	stick_base.add_child(outer_ring)

	var inner_ring := Polygon2D.new()
	var pts_inner := PackedVector2Array()
	for i in range(32):
		var a: float = float(i) / 32.0 * TAU
		pts_inner.append(Vector2(stick_radius + cos(a) * (stick_radius - 5.0), stick_radius + sin(a) * (stick_radius - 5.0)))
	inner_ring.polygon = pts_inner
	inner_ring.color = Color(0.55, 0.92, 0.76, 0.24)
	stick_base.add_child(inner_ring)

	stick_knob = Control.new()
	stick_knob.position = Vector2(stick_radius, stick_radius)
	stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick_base.add_child(stick_knob)

	var knob_poly := Polygon2D.new()
	var pts_knob := PackedVector2Array()
	for i in range(24):
		var a: float = float(i) / 24.0 * TAU
		pts_knob.append(Vector2(cos(a) * 28.0, sin(a) * 28.0))
	knob_poly.polygon = pts_knob
	knob_poly.color = Color(0.95, 0.98, 0.90, 0.88)
	stick_knob.add_child(knob_poly)

func _touch_button(layer: CanvasLayer, text: String, pos: Vector2, bsize: Vector2, action: String, col: Color) -> void:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = bsize
	b.modulate = col.lightened(0.25)
	b.add_theme_font_size_override("font_size", 24)
	layer.add_child(b)
	touch_rects[action] = Rect2(pos - Vector2(10, 10), bsize + Vector2(20, 20))
	b.button_down.connect(func():
		b.scale = Vector2(0.92, 0.92)
		_set_touch(action, true)
	)
	b.button_up.connect(func():
		b.scale = Vector2.ONE
		_set_touch(action, false)
	)

func _input(event: InputEvent) -> void:
	if not game_started:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			active_touches[st.index] = st.position
			if touch_rects.has("jump") and touch_rects["jump"].has_point(st.position):
				jump_queued = true
			elif touch_rects.has("spin") and touch_rects["spin"].has_point(st.position):
				spin_queued = true
			elif touch_rects.has("boost") and touch_rects["boost"].has_point(st.position):
				boost_queued = true
			elif touch_rects.has("drift") and touch_rects["drift"].has_point(st.position):
				touch_state["drift_held"] = true
			elif stick_touch_id == -1 and st.position.x < 560.0 and st.position.y > 300.0:
				stick_touch_id = st.index
				_update_thumbstick(st.position)
		else:
			active_touches.erase(st.index)
			if st.index == stick_touch_id:
				stick_touch_id = -1
				_reset_thumbstick()
			if touch_rects.has("drift") and touch_rects["drift"].has_point(st.position):
				touch_state["drift_held"] = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		active_touches[sd.index] = sd.position
		if sd.index == stick_touch_id:
			_update_thumbstick(sd.position)

func _update_thumbstick(touch_pos: Vector2) -> void:
	var delta_vec: Vector2 = touch_pos - stick_center
	var clamped: Vector2 = delta_vec.limit_length(stick_radius)
	if is_instance_valid(stick_knob):
		stick_knob.position = Vector2(stick_radius, stick_radius) + clamped
	var norm: Vector2 = clamped / stick_radius
	if absf(norm.x) < 0.14:
		norm.x = 0.0
	if absf(norm.y) < 0.14:
		norm.y = 0.0
	touch_state["analog_x"] = norm.x
	touch_state["analog_y"] = norm.y
	touch_state["left"] = norm.x < -0.14
	touch_state["right"] = norm.x > 0.14

func _reset_thumbstick() -> void:
	if is_instance_valid(stick_knob):
		stick_knob.position = Vector2(stick_radius, stick_radius)
	touch_state["analog_x"] = 0.0
	touch_state["analog_y"] = 0.0
	touch_state["left"] = false
	touch_state["right"] = false

@rpc("authority", "call_local", "reliable")
func _spawn_player(id: int, pos: Vector2, is_bot: bool = false) -> void:
	if players.has(id) or not is_instance_valid(world):
		return
	var p = CharacterBody2D.new()
	p.name = "Player_%d" % id
	if game_mode == "DRIFT":
		p.set_script(DRIFT_CAR_SCRIPT)
	else:
		p.set_script(PLAYER_SCRIPT)
	p.player_id = id
	p.is_bot = is_bot
	p.is_local = (id == multiplayer.get_unique_id()) and not is_bot
	p.position = pos
	world.add_child(p)
	players[id] = p
	if p.is_local:
		local_player = p
		camera.make_current()

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
	_status("Spiller %d forlod rummet." % id)

func _on_connected() -> void:
	_status("Forbundet til værten! Vent på at værten trykker START.")

func _on_connection_failed() -> void:
	_status("Forbindelse fejlede. Kontrollér værtens IP og Wi-Fi/hotspot.")

func _on_server_disconnected() -> void:
	_status("Værtsforbindelsen blev afbrudt.")

func _close_network() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	game_started = false
	players.clear()
	local_player = null

func _status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
	print("CrashLocal: ", message)

func _on_peer_connected(id: int) -> void:
	_status("Telefon #%d tilsluttet! (%d spillere klar)" % [id, multiplayer.get_peers().size() + 1])
	if game_started and multiplayer.is_server():
		var spawn_p := Vector2(1290.0, 385.0) if game_mode == "DRIFT" else Vector2(140.0 + (id % 3) * 60.0, FLOOR_Y - 70.0)
		_spawn_player.rpc(id, spawn_p, false)

func _set_touch(action: String, pressed: bool) -> void:
	if action == "jump":
		if pressed:
			jump_queued = true
	elif action == "spin":
		if pressed:
			spin_queued = true
	elif action == "boost":
		if pressed:
			boost_queued = true
	elif action == "drift":
		touch_state["drift_held"] = pressed
	else:
		touch_state[action] = pressed

func consume_action(action: String) -> bool:
	if action == "jump":
		var result := jump_queued
		jump_queued = false
		return result
	if action == "spin":
		var result := spin_queued
		spin_queued = false
		return result
	if action == "boost":
		var result := boost_queued
		boost_queued = false
		return result
	return false

# Netværkssynkronisering til Race & Arena
func submit_local_state(id: int, pos: Vector2, vel: Vector2, face: float, spin: bool, anim: String = "idle", lvs: int = 3, frt: int = 0, msk: bool = false) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_apply_state(id, pos, vel, face, spin, anim, lvs, frt, msk)
	else:
		_submit_state.rpc_id(1, id, pos, vel, face, spin, anim, lvs, frt, msk)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_state(id: int, pos: Vector2, vel: Vector2, face: float, spin: bool, anim: String, lvs: int, frt: int, msk: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == id:
		_apply_state(id, pos, vel, face, spin, anim, lvs, frt, msk)

func _apply_state(id: int, pos: Vector2, vel: Vector2, face: float, spin: bool, anim: String, lvs: int, frt: int, msk: bool) -> void:
	if not players.has(id) or game_mode == "DRIFT":
		return
	var p = players[id]
	if not is_instance_valid(p):
		return
	p.network_position = pos
	p.network_velocity = vel
	p.facing = face
	p.network_spinning = spin
	p.network_anim = anim
	p.lives = lvs
	p.fruits = frt
	p.has_mask = msk

@rpc("authority", "call_remote", "unreliable_ordered")
func _broadcast_state(id: int, pos: Vector2, vel: Vector2, face: float, spin: bool, anim: String, lvs: int, frt: int, msk: bool) -> void:
	if players.has(id) and id != multiplayer.get_unique_id() and game_mode != "DRIFT":
		var p = players[id]
		if is_instance_valid(p):
			p.network_position = pos
			p.network_velocity = vel
			p.facing = face
			p.network_spinning = spin
			p.network_anim = anim
			p.lives = lvs
			p.fruits = frt
			p.has_mask = msk

# Netværkssynkronisering til Toyota Supra Drift Mode
func submit_drift_state(id: int, pos: Vector2, vel: Vector2, rot: float, drifting: bool, boosting: bool, score: int, lp: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_apply_drift_state(id, pos, vel, rot, drifting, boosting, score, lp)
	else:
		_submit_drift_state.rpc_id(1, id, pos, vel, rot, drifting, boosting, score, lp)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_drift_state(id: int, pos: Vector2, vel: Vector2, rot: float, drifting: bool, boosting: bool, score: int, lp: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == id:
		_apply_drift_state(id, pos, vel, rot, drifting, boosting, score, lp)

func _apply_drift_state(id: int, pos: Vector2, vel: Vector2, rot: float, drifting: bool, boosting: bool, score: int, lp: int) -> void:
	if not players.has(id) or game_mode != "DRIFT":
		return
	var p = players[id]
	if not is_instance_valid(p):
		return
	p.network_position = pos
	p.network_velocity = vel
	p.network_rotation = rot
	p.network_drifting = drifting
	p.network_boosting = boosting
	p.network_score = score
	p.network_lap = lp

@rpc("authority", "call_remote", "unreliable_ordered")
func _broadcast_drift_state(id: int, pos: Vector2, vel: Vector2, rot: float, drifting: bool, boosting: bool, score: int, lp: int) -> void:
	if players.has(id) and id != multiplayer.get_unique_id() and game_mode == "DRIFT":
		var p = players[id]
		if is_instance_valid(p):
			p.network_position = pos
			p.network_velocity = vel
			p.network_rotation = rot
			p.network_drifting = drifting
			p.network_boosting = boosting
			p.network_score = score
			p.network_lap = lp

func _process(delta: float) -> void:
	if not game_started:
		return

	env_time += delta
	if game_mode != "DRIFT":
		_update_world_animations(delta)

	if is_instance_valid(local_player) and is_instance_valid(camera):
		var shake_offset := Vector2.ZERO
		if camera_shake > 0.1:
			shake_offset = Vector2(randf_range(-camera_shake, camera_shake), randf_range(-camera_shake, camera_shake))
			camera_shake = lerpf(camera_shake, 0.0, delta * 10.0)
		if game_mode == "DRIFT":
			var look_vec: Vector2 = (local_player.velocity as Vector2) * 0.25
			var cam_x: float = clampf(float(local_player.position.x) + look_vec.x, 740.0, 2460.0)
			var cam_y: float = clampf(float(local_player.position.y) + look_vec.y, 420.0, 1480.0)
			camera.position = Vector2(cam_x, cam_y) + shake_offset
		else:
			var w_width := get_world_width()
			var look_ahead: float = float(local_player.facing) * 95.0
			var target_x: float = clampf(float(local_player.position.x) + look_ahead, 640.0, w_width - 640.0)
			camera.position = Vector2(target_x, 360.0) + shake_offset

	net_tick_accum += delta
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if net_tick_accum >= NET_TICK_INTERVAL:
			net_tick_accum = 0.0
			for id in players.keys():
				var p = players[id]
				if is_instance_valid(p):
					if game_mode == "DRIFT":
						var d_pos: Vector2 = p.global_position if (p.is_local or p.is_bot) else p.network_position
						var d_vel: Vector2 = p.velocity if (p.is_local or p.is_bot) else p.network_velocity
						var d_rot: float = p.car_angle if (p.is_local or p.is_bot) else p.network_rotation
						var d_drf: bool = p.is_drifting if (p.is_local or p.is_bot) else p.network_drifting
						var d_bst: bool = (p.boost_timer > 0.0) if (p.is_local or p.is_bot) else p.network_boosting
						var d_scr: int = (int(p.total_drift_score) + int(p.drift_combo_score)) if (p.is_local or p.is_bot) else int(p.network_score)
						var d_lap: int = int(p.lap) if (p.is_local or p.is_bot) else int(p.network_lap)
						_broadcast_drift_state.rpc(id, d_pos, d_vel, d_rot, d_drf, d_bst, d_scr, d_lap)
					else:
						var sync_pos: Vector2 = p.position if (p.is_local or p.is_bot) else p.network_position
						var sync_vel: Vector2 = p.velocity if (p.is_local or p.is_bot) else p.network_velocity
						var sync_spin: bool = p.spinning if (p.is_local or p.is_bot) else p.network_spinning
						var sync_anim: String = p.anim_state if (p.is_local or p.is_bot) else p.network_anim
						_broadcast_state.rpc(id, sync_pos, sync_vel, p.facing, sync_spin, sync_anim, p.lives, p.fruits, p.has_mask)

		if game_mode == "ARENA":
			arena_timer -= delta
			if arena_timer <= 0.0:
				_finish_arena_by_time()

	_update_hud_text()

func _update_world_animations(delta: float) -> void:
	if waterfall_frames.size() >= 3:
		var wf_idx := int(env_time * 9.0) % 3
		for wf in waterfalls:
			if is_instance_valid(wf):
				wf.texture = waterfall_frames[wf_idx]

	for i in range(swaying_plants.size()):
		var pl: Node2D = swaying_plants[i]
		if is_instance_valid(pl):
			pl.rotation = sin(env_time * 3.2 + float(i)) * 0.11

	for mp in moving_platforms:
		var body: AnimatableBody2D = mp["node"]
		if is_instance_valid(body):
			var w: float = (sin(env_time * float(mp["speed"]) + float(mp["phase"])) + 1.0) * 0.5
			body.position = (mp["from"] as Vector2).lerp(mp["to"] as Vector2, w)

	for fid in fruits_map.keys():
		var fdata: Dictionary = fruits_map[fid]
		if fdata["active"] and is_instance_valid(fdata["node"]):
			fdata["node"].position.y = fdata["base_y"] + sin(env_time * 4.5 + float(fid)) * 6.0

	for cid in crates.keys():
		var cdata: Dictionary = crates[cid]
		if not cdata["active"]:
			continue
		var cnode: Area2D = cdata["node"]
		cnode.scale = cnode.scale.lerp(Vector2.ONE, delta * 10.0)
		if cdata["tnt_timer"] > 0.0:
			var prev_sec: int = int(ceil(float(cdata["tnt_timer"])))
			cdata["tnt_timer"] -= delta
			var now_sec: int = int(ceil(float(cdata["tnt_timer"])))
			if now_sec != prev_sec and now_sec > 0:
				play_sfx("beep")
			cdata["label"].text = str(maxi(1, now_sec))
			cnode.modulate = Color(1.0, 0.45, 0.45) if int(env_time * 14.0) % 2 == 0 else Color.WHITE
			if cdata["tnt_timer"] <= 0.0 and multiplayer.is_server():
				_activate_crate_effect.rpc(cid, 1, true)

	var frame_idx := int(env_time * 6.5) % 2
	for eid in enemies.keys():
		var edata: Dictionary = enemies[eid]
		if not edata["active"]:
			continue
		var enode: Area2D = edata["node"]
		var esp: Sprite2D = edata["sprite"]
		if is_instance_valid(enode):
			enode.position.x += edata["dir"] * 95.0 * delta
			if absf(enode.position.x - edata["start_x"]) > edata["dist"]:
				edata["dir"] = -edata["dir"]
			esp.flip_h = (edata["dir"] > 0.0)
			if edata["type"] == "CRAB" and crab_frames.size() >= 2:
				esp.texture = crab_frames[frame_idx]
			elif edata["type"] == "TIKI" and tiki_frames.size() >= 2:
				esp.texture = tiki_frames[frame_idx]

func _update_hud_text() -> void:
	if not is_instance_valid(hud) or not is_instance_valid(local_player):
		return
	if game_mode == "DRIFT":
		var pts: int = int(local_player.total_drift_score) + int(local_player.drift_combo_score)
		var turbo_pct: int = int(local_player.boost_charge)
		hud.text = "TOYOTA SUPRA DRIFT  •  OMGANG %d/%d  •  DRIFT POINT: %d" % [int(local_player.lap), DRIFT_TARGET_LAPS, pts]
		sub_hud.text = "Biler: %d  •  TURBO: %d%% (Hold DRIFT i svingene, tryk TURBO!)" % [players.size(), turbo_pct]
		return

	var mask_txt: String = "  •  TIKI-SKJOLD AKTIVT!" if local_player.has_mask else ""
	if game_mode == "RACE":
		var pct: int = clampi(int((float(local_player.position.x) / (RACE_WORLD_WIDTH - 150.0)) * 100.0), 0, 100)
		hud.text = "JUNGLE RACE  •  WUMPA: %d  •  FREMSKRIDT: %d%%" % [local_player.fruits, pct]
		sub_hud.text = "Spillere: %d  •  Smadr kasser med SPIN eller HOP!%s" % [players.size(), mask_txt]
	else:
		var hearts: String = "♥".repeat(maxi(0, int(local_player.lives)))
		hud.text = "ARENA KAMP  •  LIV: %s  •  TID: %ds" % [hearts, maxi(0, int(ceil(arena_timer)))]
		sub_hud.text = "Wumpa: %d  •  Slå modstandere ud med SPIN!%s" % [local_player.fruits, mask_txt]

func _on_goal(body) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or game_mode != "RACE":
		return
	if body.has_method("get_player_id"):
		var id: int = body.get_player_id()
		if not finishers.has(id):
			finishers.append(id)
			if finishers.size() == 1:
				var winner_name: String = "BOT" if body.is_bot else ("SPILLER %d" % id)
				_show_result.rpc("%s VANDT JUNGLE RACE! (%d Wumpa-frugter)" % [winner_name, body.fruits])

func _on_hazard(body) -> void:
	if body.has_method("take_hazard_hit"):
		body.take_hazard_hit()
	elif body.has_method("knock_out"):
		body.knock_out()

@rpc("authority", "call_local", "reliable")
func _player_out(id: int) -> void:
	if players.has(id) and is_instance_valid(players[id]):
		players[id].is_out = true

func check_arena_winner() -> void:
	if game_mode != "ARENA" or not multiplayer.is_server() or not game_started:
		return
	var alive: Array = []
	for id in players.keys():
		var p = players[id]
		if is_instance_valid(p) and not p.is_out:
			alive.append(p)
	if players.size() > 1 and alive.size() == 1:
		var w = alive[0]
		var wname: String = "BOT" if w.is_bot else ("SPILLER %d" % int(w.player_id))
		_show_result.rpc("%s VINDER ARENA KAMPEN!" % wname)
	elif alive.is_empty():
		_show_result.rpc("UAFGJORT I ARENAEN!")

func _finish_arena_by_time() -> void:
	var best_p = null
	var best_score := -1
	for id in players.keys():
		var p = players[id]
		if is_instance_valid(p) and not p.is_out:
			var sc: int = p.lives * 100 + p.fruits
			if sc > best_score:
				best_score = sc
				best_p = p
	if best_p != null:
		var wname: String = "BOT" if best_p.is_bot else ("SPILLER %d" % int(best_p.player_id))
		_show_result.rpc("TIDEN ER UDE! %s VINDER PÅ POINT!" % wname)
	else:
		_show_result.rpc("TIDEN ER UDE!")

@rpc("authority", "call_local", "reliable")
func _show_result(message: String) -> void:
	if is_instance_valid(result_panel):
		return
	game_started = false
	play_sfx("win")
	result_panel = PanelContainer.new()
	result_panel.position = Vector2(310, 230)
	result_panel.custom_minimum_size = Vector2(660, 190)
	if is_instance_valid(hud_layer):
		hud_layer.add_child(result_panel)
	else:
		add_child(result_panel)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	result_panel.add_child(v)

	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("#ffe66d"))
	v.add_child(label)

	var button := Button.new()
	button.text = "TILBAGE TIL HOVEDMENU"
	button.custom_minimum_size = Vector2(320, 56)
	button.pressed.connect(func(): get_tree().reload_current_scene())
	v.add_child(button)
