#!/usr/bin/env python3
from pathlib import Path
import shutil, sys

project = Path.cwd()
if not (project / "project.godot").exists() or not (project / "scripts/main.gd").exists():
    sys.exit("Kør dette script fra CrashLocalPrototype-mappen.")
pack = Path(__file__).resolve().parent / "art"
(project / "art").mkdir(exist_ok=True)
for f in pack.glob("*.svg"):
    destination = project / "art" / f.name
    if f.resolve() != destination.resolve():
        shutil.copy2(f, destination)

mp = project / "scripts/main.gd"
pp = project / "scripts/player.gd"
shutil.copy2(mp, project / "scripts/main.gd.before_visual_assets")
shutil.copy2(pp, project / "scripts/player.gd.before_visual_assets")

def replace_func(src, name, replacement):
    start = src.find("func " + name + "(")
    if start < 0:
        raise RuntimeError("Function not found: " + name)
    # Find next function, including any decorator directly before it.
    nxt = src.find("\nfunc ", start + 1)
    dec = src.find("\n@rpc", start + 1)
    candidates = [i for i in (nxt, dec) if i >= 0]
    end = min(candidates) if candidates else len(src)
    return src[:start] + replacement.rstrip() + "\n\n" + src[end+1 if src[end:end+1] == "\n" else end:]

world = r'''func _create_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
	world = Node2D.new()
	world.name = "GameWorld"
	add_child(world)

	var bg := Sprite2D.new()
	bg.name = "DistantJungle"
	bg.texture = load("res://art/jungle_back.svg")
	bg.position = Vector2(WORLD_WIDTH / 2.0, 360)
	bg.z_index = -30
	world.add_child(bg)

	var mid := Sprite2D.new()
	mid.name = "JungleForeground"
	mid.texture = load("res://art/jungle_mid.svg")
	mid.position = Vector2(WORLD_WIDTH / 2.0, 360)
	mid.z_index = -20
	world.add_child(mid)

	_platform(Vector2(0, FLOOR_Y), Vector2(WORLD_WIDTH, 110), Color("#795039"), Color("#83d35a"))
	if game_mode == "RACE":
		var places := [Vector2(270, 505), Vector2(540, 455), Vector2(800, 390), Vector2(1080, 485), Vector2(1335, 425), Vector2(1600, 360), Vector2(1870, 455), Vector2(2110, 390)]
		for i in range(places.size()):
			_platform(places[i], Vector2(145, 30), Color("#93603b"), Color("#a8df67"))
			if i in [1, 4, 6]:
				_add_art_sprite("res://art/crate.svg", places[i] + Vector2(55, -53), Vector2(44, 44), 3)
			if i in [0, 2, 3, 5, 7]:
				_add_art_sprite("res://art/fruit.svg", places[i] + Vector2(105, -66), Vector2(30, 35), 4)
		_add_art_sprite("res://art/sign.svg", Vector2(WORLD_WIDTH - 105, 425), Vector2(78, 84), 5)
		_goal(Vector2(WORLD_WIDTH - 85, 480))
	else:
		for item in [[300.0, 500.0], [800.0, 445.0], [1300.0, 500.0], [1750.0, 460.0]]:
			_platform(Vector2(item[0], item[1]), Vector2(170, 30), Color("#93603b"), Color("#a8df67"))
		for x in [520.0, 1000.0, 1500.0, 1950.0]:
			_hazard(Vector2(x, FLOOR_Y - 20))
		_add_art_sprite("res://art/crate.svg", Vector2(670, 555), Vector2(48, 48), 3)
		_add_art_sprite("res://art/crate.svg", Vector2(1450, 555), Vector2(48, 48), 3)

	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24, 16)
	hud.add_theme_font_size_override("font_size", 27)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_shadow_color", Color("#15221b"))
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 3)
	layer.add_child(hud)
	_touch_button(layer, "◀", Vector2(24, 610), "left")
	_touch_button(layer, "▶", Vector2(112, 610), "right")
	_touch_button(layer, "JUMP", Vector2(1010, 590), "jump")
	_touch_button(layer, "SPIN", Vector2(1110, 590), "spin")

	camera = Camera2D.new()
	camera.position = Vector2(640, 360)
	camera.limit_left = 0
	camera.limit_right = int(WORLD_WIDTH)
	camera.make_current()
	world.add_child(camera)

func _add_art_sprite(path: String, at: Vector2, target_size: Vector2, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.position = at
	sprite.z_index = z
	if sprite.texture:
		sprite.scale = Vector2(target_size.x / sprite.texture.get_width(), target_size.y / sprite.texture.get_height())
	world.add_child(sprite)
	return sprite

func _platform(pos: Vector2, size: Vector2, body_color: Color, top_color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = pos + size / 2.0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)
	var visual := Sprite2D.new()
	visual.texture = load("res://art/platform.svg")
	visual.scale = Vector2(size.x / 320.0, maxf(size.y / 90.0, 0.5))
	body.add_child(visual)
	world.add_child(body)
'''
# Replace _create_world and _platform together by starting at _create_world and ending before _goal.
start = mp.read_text().find("func _create_world()")
end = mp.read_text().find("\nfunc _goal(", start)
if start < 0 or end < 0:
    sys.exit("Could not locate world drawing functions; no script changes made.")
main = mp.read_text()[:start] + world + "\n" + mp.read_text()[end+1:]
mp.write_text(main)

hero = r'''func _draw_character() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "HeroSprite"
	sprite.texture = load("res://art/hero.svg")
	sprite.position = Vector2(0, -28)
	sprite.scale = Vector2(0.62, 0.62)
	add_child(sprite)
	visual_root = sprite
	var label := Label.new()
	label.text = "P%d" % player_id
	label.position = Vector2(-18, -92)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color("#17231b"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
'''
player = replace_func(pp.read_text(), "_draw_character", hero)
pp.write_text(player)
print("Installeret: SVG-jungle, separate baggrundslag, platforme, frugt, kasser og ny spillerfigur.")
print("Backup oprettet for main.gd og player.gd.")
print("Genindlæs projektet i Godot og vent på at SVG-filerne importeres.")
