extends CharacterBody2D

const SPEED := 355.0
const JUMP_VELOCITY := -625.0
const GRAVITY := 1520.0
const COYOTE_TIME := 0.11
const JUMP_BUFFER := 0.13

var player_id := 1
var is_local := true
var is_bot := false
var network_position := Vector2.ZERO
var network_velocity := Vector2.ZERO
var network_spinning := false
var network_anim := "idle"
var facing := 1.0
var spinning := false
var spin_left := 0.0
var spin_cooldown := 0.0
var is_out := false

# 8 komplette karakter-animationstilstande: idle, run, jump, fall, land, spin, hit, death
var anim_state := "idle"
var anim_time := 0.0
var land_timer := 0.0
var hit_timer := 0.0
var invuln_timer := 0.0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0

# Spiller-stats til Race & Arena
var fruits := 0
var lives := 3
var has_mask := false
var checkpoint_pos := Vector2(100.0, 540.0)

# Visuelle noder
var visual_root: Node2D
var hero_sprite: Sprite2D
var shadow_poly: Polygon2D
var mask_pivot: Node2D
var mask_sprite: Sprite2D
var dizzy_root: Node2D
var name_label: Label
var dust_particles: CPUParticles2D
var spin_particles: CPUParticles2D
var default_tex: Texture2D

const PLAYER_TINTS := [
	Color(1.0, 1.0, 1.0),
	Color(0.82, 0.98, 1.0),
	Color(0.86, 1.0, 0.84),
	Color(1.0, 0.85, 0.92)
]

func _ready() -> void:
	checkpoint_pos = position
	var main = get_tree().current_scene
	if main and main.has_method("load_svg_tex"):
		default_tex = main.load_svg_tex("res://art/hero.svg")
	if default_tex == null:
		default_tex = load("res://art/hero.svg")

	_draw_character()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(34, 50)
	cs.shape = rect
	cs.position = Vector2(0, -25)
	add_child(cs)

func _draw_character() -> void:
	# Dynamisk jordskygge under spilleren
	shadow_poly = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(12):
		var a := float(i) / 12.0 * TAU
		pts.append(Vector2(cos(a) * 22.0, sin(a) * 5.5))
	shadow_poly.polygon = pts
	shadow_poly.color = Color(0.04, 0.12, 0.09, 0.42)
	shadow_poly.position = Vector2(0, 2)
	add_child(shadow_poly)

	visual_root = Node2D.new()
	visual_root.position = Vector2(0, -28)
	add_child(visual_root)

	hero_sprite = Sprite2D.new()
	hero_sprite.name = "HeroSprite"
	hero_sprite.texture = default_tex
	hero_sprite.scale = Vector2(0.64, 0.64)
	var tint_idx := clampi((player_id - 1) % PLAYER_TINTS.size(), 0, PLAYER_TINTS.size() - 1)
	hero_sprite.modulate = PLAYER_TINTS[tint_idx]
	visual_root.add_child(hero_sprite)

	# Svævende Tiki-beskyttelsesmaske
	mask_pivot = Node2D.new()
	mask_pivot.position = Vector2(0, -34)
	add_child(mask_pivot)
	mask_sprite = Sprite2D.new()
	var main = get_tree().current_scene
	if main and main.has_method("load_svg_tex"):
		mask_sprite.texture = main.load_svg_tex("res://art/tiki_mask.svg")
	mask_sprite.scale = Vector2(0.42, 0.42)
	mask_sprite.position = Vector2(-36, -12)
	mask_sprite.visible = false
	mask_pivot.add_child(mask_sprite)

	# Svimmelheds-stjerner ved hit/death
	dizzy_root = Node2D.new()
	dizzy_root.position = Vector2(0, -68)
	dizzy_root.visible = false
	add_child(dizzy_root)
	for i in range(3):
		var star := Polygon2D.new()
		star.polygon = PackedVector2Array([
			Vector2(0, -7), Vector2(2.5, -2), Vector2(7, -2), Vector2(3, 1.5),
			Vector2(4.5, 6.5), Vector2(0, 3.5), Vector2(-4.5, 6.5), Vector2(-3, 1.5),
			Vector2(-7, -2), Vector2(-2.5, -2)
		])
		star.color = Color("#ffef5c")
		star.position = Vector2(cos(i * TAU / 3.0) * 20.0, sin(i * TAU / 3.0) * 6.0)
		dizzy_root.add_child(star)

	# Løbe-, hop- og landingsstøv
	dust_particles = CPUParticles2D.new()
	dust_particles.position = Vector2(0, 0)
	dust_particles.emitting = false
	dust_particles.amount = 14
	dust_particles.lifetime = 0.38
	dust_particles.one_shot = true
	dust_particles.explosiveness = 0.82
	dust_particles.direction = Vector2(0, -1)
	dust_particles.spread = 68.0
	dust_particles.gravity = Vector2(0, 220)
	dust_particles.initial_velocity_min = 45.0
	dust_particles.initial_velocity_max = 115.0
	dust_particles.scale_amount_min = 4.0
	dust_particles.scale_amount_max = 8.5
	dust_particles.color = Color(0.95, 0.92, 0.80, 0.78)
	add_child(dust_particles)

	# Tornado-spin gnister/blade
	spin_particles = CPUParticles2D.new()
	spin_particles.position = Vector2(0, -26)
	spin_particles.emitting = false
	spin_particles.amount = 18
	spin_particles.lifetime = 0.25
	spin_particles.direction = Vector2(0, -1)
	spin_particles.spread = 180.0
	spin_particles.gravity = Vector2(0, 0)
	spin_particles.initial_velocity_min = 90.0
	spin_particles.initial_velocity_max = 160.0
	spin_particles.scale_amount_min = 3.5
	spin_particles.scale_amount_max = 7.0
	spin_particles.color = Color("#ffe066")
	add_child(spin_particles)

	name_label = Label.new()
	name_label.text = "BOT" if is_bot else ("P%d" % player_id)
	name_label.position = Vector2(-28, -96)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("#fff6b3") if is_local else Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color("#111c15"))
	name_label.add_theme_constant_override("shadow_offset_x", 2)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(name_label)

func _poly(points: Array, c: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array(points)
	p.color = c
	visual_root.add_child(p)

func get_player_id() -> int:
	return player_id

func emit_dust() -> void:
	if is_instance_valid(dust_particles):
		dust_particles.restart()
		dust_particles.emitting = true

func grant_mask() -> void:
	has_mask = true
	if is_instance_valid(mask_sprite):
		mask_sprite.visible = true

func add_fruit(amount: int = 1) -> void:
	fruits += amount

func _physics_process(delta: float) -> void:
	anim_time += delta
	spin_cooldown = maxf(0.0, spin_cooldown - delta)
	hit_timer = maxf(0.0, hit_timer - delta)
	invuln_timer = maxf(0.0, invuln_timer - delta)
	land_timer = maxf(0.0, land_timer - delta)

	if is_instance_valid(mask_sprite):
		mask_sprite.visible = has_mask
		mask_pivot.position.y = -34.0 + sin(anim_time * 5.0) * 5.0
		mask_sprite.position.x = cos(anim_time * 3.8) * 34.0
		mask_sprite.z_index = 2 if sin(anim_time * 3.8) >= 0.0 else -2

	if is_out:
		anim_state = "death"
		_animate(delta)
		return

	if not is_local and not is_bot:
		global_position = global_position.lerp(network_position, minf(delta * 16.0, 1.0))
		velocity = network_velocity
		spinning = network_spinning
		anim_state = network_anim
		_animate(delta)
		return

	var main = get_tree().current_scene
	if main == null or not main.game_started:
		return

	var dir := 0.0
	var want_jump := false
	var want_spin := false

	if is_bot:
		if main.game_mode == "RACE":
			dir = 1.0
			if is_on_wall() or (is_on_floor() and int(position.x) % 270 < 18):
				want_jump = true
		else:
			var target_x := 1100.0 + sin(anim_time * 1.3 + float(player_id)) * 550.0
			if is_instance_valid(main.local_player) and not main.local_player.is_out:
				target_x = main.local_player.global_position.x
				if absf(target_x - global_position.x) < 92.0:
					want_spin = true
			dir = signf(target_x - global_position.x)
			if is_on_wall() or (is_on_floor() and randf() < 0.025):
				want_jump = true
	else:
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
			dir -= 1.0
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
			dir += 1.0
		var analog_x: float = float(main.touch_state.get("analog_x", 0.0))
		if absf(analog_x) > 0.01:
			dir += analog_x
		else:
			if main.touch_state.get("left", false):
				dir -= 1.0
			if main.touch_state.get("right", false):
				dir += 1.0
		dir = clampf(dir, -1.0, 1.0)
		want_jump = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or main.consume_action("jump")
		want_spin = Input.is_key_pressed(KEY_SHIFT) or main.consume_action("spin")

	if dir != 0.0:
		facing = signf(dir)

	var current_speed := SPEED * (1.15 if has_mask else 1.0)
	if hit_timer <= 0.0:
		velocity.x = move_toward(velocity.x, dir * current_speed, 2200.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 750.0 * delta)

	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
		velocity.y += GRAVITY * delta

	if want_jump:
		jump_buffer_timer = JUMP_BUFFER
	else:
		jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and hit_timer <= 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		emit_dust()
		if main.has_method("play_sfx"):
			main.play_sfx("jump")

	if want_spin and spin_cooldown <= 0.0 and hit_timer <= 0.0:
		spinning = true
		spin_left = 0.38
		spin_cooldown = 0.56
		if main.has_method("play_sfx"):
			main.play_sfx("spin")
		_spin_attack()

	if spinning:
		spin_left -= delta
		if spin_left <= 0.0:
			spinning = false

	var pre_floor := is_on_floor()
	move_and_slide()

	if not pre_floor and is_on_floor():
		land_timer = 0.14
		emit_dust()

	var max_x: float = main.get_world_width() - 24.0
	position.x = clampf(position.x, 24.0, max_x)

	if position.y > 790.0:
		_handle_pit_fall(main)

	_update_anim_state(dir)
	_animate(delta)

	if is_local:
		main.submit_local_state(player_id, position, velocity, facing, spinning, anim_state, lives, fruits, has_mask)

func _handle_pit_fall(main) -> void:
	if main.game_mode == "ARENA":
		take_hazard_hit()
		if not is_out:
			position = Vector2(1100.0, 260.0)
			velocity = Vector2.ZERO
	else:
		if main.has_method("play_sfx"):
			main.play_sfx("hit")
		position = checkpoint_pos
		velocity = Vector2.ZERO
		hit_timer = 0.35

func _update_anim_state(dir: float) -> void:
	if is_out:
		anim_state = "death"
	elif hit_timer > 0.0:
		anim_state = "hit"
	elif spinning:
		anim_state = "spin"
	elif not is_on_floor():
		anim_state = "jump" if velocity.y < 0.0 else "fall"
	elif land_timer > 0.0:
		anim_state = "land"
	elif absf(velocity.x) > 22.0 or dir != 0.0:
		anim_state = "run"
	else:
		anim_state = "idle"

func _spin_attack() -> void:
	var main = get_tree().current_scene
	if main and main.has_method("check_spin_interactions"):
		main.check_spin_interactions(self)
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_server_hit(player_id, global_position, facing)
	else:
		_request_spin.rpc_id(1, player_id, global_position, facing)

@rpc("any_peer", "call_remote", "reliable")
func _request_spin(id: int, pos: Vector2, face: float) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == id:
		_server_hit(id, pos, face)

func _server_hit(attacker: int, pos: Vector2, face: float) -> void:
	var main = get_tree().current_scene
	for id in main.players.keys():
		if id == attacker:
			continue
		var other = main.players[id]
		if is_instance_valid(other) and not other.is_out:
			if absf(other.global_position.x - pos.x) < 98.0 and absf(other.global_position.y - pos.y) < 78.0:
				var push_dir: float = signf(float(other.global_position.x) - pos.x)
				if push_dir == 0.0:
					push_dir = face
				other._knockback.rpc(Vector2(push_dir * 680.0, -360.0))

@rpc("authority", "call_local", "reliable")
func _knockback(impulse: Vector2) -> void:
	if has_mask:
		has_mask = false
		invuln_timer = 1.0
		velocity = impulse * 0.45
		return
	velocity = impulse
	hit_timer = 0.42
	invuln_timer = 0.9
	var main = get_tree().current_scene
	if main and main.has_method("play_sfx"):
		main.play_sfx("hit")

func take_hazard_hit() -> void:
	if is_out or invuln_timer > 0.0:
		return
	var main = get_tree().current_scene
	if has_mask:
		has_mask = false
		invuln_timer = 1.25
		velocity = Vector2(-facing * 260.0, -420.0)
		if main and main.has_method("play_sfx"):
			main.play_sfx("crate")
		return
	if main and main.game_mode == "ARENA":
		lives -= 1
		hit_timer = 0.45
		invuln_timer = 1.35
		velocity = Vector2(-facing * 320.0, -480.0)
		if main.has_method("play_sfx"):
			main.play_sfx("hit")
		if lives <= 0:
			knock_out()
	else:
		hit_timer = 0.40
		invuln_timer = 1.1
		position = checkpoint_pos
		velocity = Vector2.ZERO
		if main and main.has_method("play_sfx"):
			main.play_sfx("hit")

func knock_out() -> void:
	if is_out:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_out.rpc_id(1, player_id)
	else:
		_server_out(player_id)

@rpc("any_peer", "call_remote", "reliable")
func _request_out(id: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == id:
		_server_out(id)

func _server_out(id: int) -> void:
	var main = get_tree().current_scene
	if not main.players.has(id):
		return
	main._player_out.rpc(id)
	if main.has_method("check_arena_winner"):
		main.check_arena_winner()

@rpc("authority", "call_local", "reliable")
func _player_out(id: int) -> void:
	var main = get_tree().current_scene
	if main.players.has(id):
		main.players[id].is_out = true

func _animate(delta: float) -> void:
	if not is_instance_valid(visual_root):
		return

	spin_particles.emitting = (anim_state == "spin")
	dizzy_root.visible = (anim_state in ["hit", "death"])
	if dizzy_root.visible:
		for i in range(dizzy_root.get_child_count()):
			var c := dizzy_root.get_child(i) as Node2D
			var ang := anim_time * 6.5 + float(i) * TAU / 3.0
			c.position = Vector2(cos(ang) * 22.0, sin(ang) * 7.0)

	if invuln_timer > 0.0:
		visual_root.modulate.a = 0.45 if int(anim_time * 18.0) % 2 == 0 else 1.0
	else:
		visual_root.modulate.a = 1.0

	hero_sprite.flip_h = (facing < 0.0)

	# Skift sprite-frame ud fra de 25 dedikerede SVG-frames (idle, run, jump, fall, land, spin, hit, death)
	var main = get_tree().current_scene
	if main and main.has_method("get_hero_frame"):
		var frame_tex: Texture2D = main.get_hero_frame(anim_state, anim_time)
		if frame_tex != null:
			hero_sprite.texture = frame_tex

	match anim_state:
		"idle":
			var bob := sin(anim_time * 4.2)
			visual_root.position = Vector2(0, -28.0 + bob * 2.0)
			visual_root.rotation = lerpf(visual_root.rotation, sin(anim_time * 2.1) * 0.03, delta * 12.0)
			visual_root.scale = visual_root.scale.lerp(Vector2(1.0 - bob * 0.02, 1.0 + bob * 0.03), delta * 10.0)
		"run":
			var bounce := absf(cos(anim_time * 15.0))
			visual_root.position = Vector2(0, -28.0 - bounce * 4.0)
			visual_root.rotation = lerpf(visual_root.rotation, facing * 0.08, delta * 15.0)
			visual_root.scale = visual_root.scale.lerp(Vector2(1.04 - bounce * 0.05, 0.96 + bounce * 0.06), delta * 14.0)
		"jump":
			visual_root.position = Vector2(0, -30.0)
			visual_root.rotation = lerpf(visual_root.rotation, -facing * 0.08, delta * 12.0)
			visual_root.scale = visual_root.scale.lerp(Vector2(0.92, 1.12), delta * 14.0)
		"fall":
			visual_root.position = Vector2(0, -26.0)
			visual_root.rotation = lerpf(visual_root.rotation, facing * 0.10, delta * 12.0)
			visual_root.scale = visual_root.scale.lerp(Vector2(0.95, 1.06), delta * 12.0)
		"land":
			visual_root.position = Vector2(0, -22.0)
			visual_root.rotation = lerpf(visual_root.rotation, 0.0, delta * 18.0)
			visual_root.scale = visual_root.scale.lerp(Vector2(1.20, 0.80), delta * 22.0)
		"spin":
			visual_root.position = Vector2(0, -28.0)
			visual_root.rotation = sin(anim_time * 30.0) * 0.10
			visual_root.scale = Vector2(1.14, 0.94)
		"hit":
			visual_root.position = Vector2(0, -28.0)
			visual_root.rotation = lerpf(visual_root.rotation, -facing * 0.28, delta * 16.0)
			visual_root.scale = visual_root.scale.lerp(Vector2(1.08, 0.92), delta * 14.0)
		"death":
			visual_root.position = visual_root.position.lerp(Vector2(0, -14.0), delta * 8.0)
			visual_root.rotation = lerpf(visual_root.rotation, 0.0, delta * 8.0)
			visual_root.scale = visual_root.scale.lerp(Vector2(1.05, 0.95), delta * 8.0)

	if is_instance_valid(name_label):
		var heart_txt := ""
		if main and main.game_mode == "ARENA":
			heart_txt = " " + "♥".repeat(maxi(0, lives))
		name_label.text = ("BOT" if is_bot else ("P%d" % player_id)) + heart_txt
