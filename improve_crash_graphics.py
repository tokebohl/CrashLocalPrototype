from pathlib import Path
import sys

project = Path.cwd()
main_file = project / "scripts" / "main.gd"
if not (project / "project.godot").is_file() or not main_file.is_file():
    print("FEJL: Kør scriptet fra CrashLocalPrototype-projektmappen.")
    sys.exit(1)

s = main_file.read_text(encoding="utf-8")
start = s.find("func _create_world() -> void:")
end = s.find("func _goal(", start)
if start < 0 or end < 0:
    print("FEJL: Kunne ikke finde _create_world() og _goal(). Ingen ændringer foretaget.")
    sys.exit(1)

backup = project / "scripts" / "main.gd.before_jungle_art"
if not backup.exists():
    backup.write_text(s, encoding="utf-8")

new_code = r'''
func _create_world() -> void:
    if is_instance_valid(world):
        world.queue_free()
    world = Node2D.new()
    world.name = "GameWorld"
    add_child(world)

    var sky := ColorRect.new()
    sky.position = Vector2(-100, -100)
    sky.size = Vector2(WORLD_WIDTH + 200, 900)
    sky.color = Color("#54b9df") if game_mode == "RACE" else Color("#514b82")
    world.add_child(sky)

    for layer_index in range(3):
        var mountain_color: Color
        if layer_index == 0:
            mountain_color = Color("#79aeb5")
        elif layer_index == 1:
            mountain_color = Color("#438d83")
        else:
            mountain_color = Color("#286d61")
        var step := 155.0 + float(layer_index) * 32.0
        var base_y := 485.0 + float(layer_index) * 43.0
        for i in range(18):
            var x := float(i) * step - 100.0
            var peak := base_y - float((i * 47 + layer_index * 31) % 115)
            _art_poly(world, Vector2.ZERO, [
                Vector2(x, 720), Vector2(x, base_y),
                Vector2(x + step * 0.45, peak),
                Vector2(x + step, base_y + 15), Vector2(x + step, 720)
            ], mountain_color)

    for i in range(12):
        _art_cloud(world, Vector2(100 + i * 205, 115 + (i % 3) * 43),
            0.7 + float(i % 3) * 0.17)
    for x in [365.0, 1080.0, 1830.0]:
        _art_waterfall(world, Vector2(x, 385), 80.0, 235.0)
    for i in range(6):
        _art_temple(world, Vector2(170 + i * 420, 390 - (i % 2) * 40),
            0.65 + float(i % 3) * 0.15)
    for i in range(13):
        _art_palm(world, Vector2(70 + i * 195, 590),
            0.65 + float(i % 4) * 0.12)

    _platform(Vector2(0, FLOOR_Y), Vector2(WORLD_WIDTH, 110),
        Color("#795039"), Color("#83d35a"))
    if game_mode == "RACE":
        for i in range(11):
            var px := 250.0 + i * 175.0
            var py := 500.0 - float((i % 3) * 45)
            _platform(Vector2(px, py), Vector2(100, 22),
                Color("#93603b"), Color("#a8df67"))
            if i % 3 == 1:
                _art_crate(world, Vector2(px + 30, py - 43), 38.0, false)
            if i % 4 == 2:
                _art_fruit(world, Vector2(px + 65, py - 65), 13.0)
        _goal(Vector2(WORLD_WIDTH - 100, 480))
    else:
        for item in [[300.0, 500.0], [800.0, 445.0],
                     [1300.0, 500.0], [1750.0, 460.0]]:
            _platform(Vector2(item[0], item[1]), Vector2(170, 22),
                Color("#93603b"), Color("#a8df67"))
        for x in [520.0, 1000.0, 1500.0, 1950.0]:
            _hazard(Vector2(x, FLOOR_Y - 20))
        _art_crate(world, Vector2(670, 555), 46.0, true)
        _art_crate(world, Vector2(1450, 555), 46.0, false)

    for i in range(65):
        var x := float(i) * 37.0
        var height := 10.0 + float((i * 19) % 24)
        var leaf_color := Color("#37844a") if i % 2 == 0 else Color("#54a94e")
        _art_poly(world, Vector2.ZERO, [
            Vector2(x, FLOOR_Y + 2), Vector2(x + 7, FLOOR_Y - height),
            Vector2(x + 12, FLOOR_Y + 2)
        ], leaf_color)

    var layer := CanvasLayer.new()
    layer.name = "HUD"
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(22, 15)
    hud.add_theme_font_size_override("font_size", 24)
    hud.add_theme_color_override("font_color", Color.WHITE)
    layer.add_child(hud)
    _touch_button(layer, "◀", Vector2(24, 610), "left")
    _touch_button(layer, "▶", Vector2(112, 610), "right")
    _touch_button(layer, "JUMP", Vector2(1010, 590), "jump")
    _touch_button(layer, "SPIN", Vector2(1110, 590), "spin")

    camera = Camera2D.new()
    camera.position = Vector2(640, 360)
    camera.limit_left = 0
    camera.limit_right = int(WORLD_WIDTH)
    world.add_child(camera)
    camera.make_current()


func _art_poly(parent: Node2D, at: Vector2, points: Array, color: Color) -> void:
    var shape := Polygon2D.new()
    shape.position = at
    shape.polygon = PackedVector2Array(points)
    shape.color = color
    parent.add_child(shape)


func _art_disc(parent: Node2D, at: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array()
    for i in range(20):
        var angle := TAU * float(i) / 20.0
        points.append(Vector2(cos(angle), sin(angle)) * radius)
    _art_poly(parent, at, points, color)


func _art_cloud(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var cloud := Node2D.new()
    cloud.position = at
    cloud.scale = Vector2.ONE * scale_factor
    parent.add_child(cloud)
    _art_disc(cloud, Vector2(-24, 3), 20.0, Color("#e0f3f4", 0.78))
    _art_disc(cloud, Vector2(0, -8), 27.0, Color("#f6ffff", 0.88))
    _art_disc(cloud, Vector2(25, 2), 19.0, Color("#e0f3f4", 0.78))
    _art_disc(cloud, Vector2(3, 9), 23.0, Color("#f6ffff", 0.88))


func _art_waterfall(parent: Node2D, at: Vector2, width: float, height: float) -> void:
    _art_poly(parent, at, [
        Vector2(0, 0), Vector2(width, 0),
        Vector2(width - 10, height), Vector2(12, height)
    ], Color("#a4ecf4", 0.68))
    for i in range(5):
        var x := 8.0 + float(i) * width / 5.0
        _art_poly(parent, at, [
            Vector2(x, 0), Vector2(x + 4, 0),
            Vector2(x + 8, height), Vector2(x + 3, height)
        ], Color("#e2ffff", 0.38))


func _art_palm(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var tree := Node2D.new()
    tree.position = at
    tree.scale = Vector2.ONE * scale_factor
    parent.add_child(tree)
    _art_poly(tree, Vector2.ZERO, [
        Vector2(-9, 0), Vector2(-4, -75), Vector2(5, -112),
        Vector2(13, -108), Vector2(6, -65), Vector2(10, 0)
    ], Color("#765039"))
    var crown := Vector2(5, -108)
    for i in range(7):
        var a := -PI + float(i) * PI / 6.0
        var finish := crown + Vector2(cos(a) * 82, sin(a) * 40 - 10)
        _art_poly(tree, Vector2.ZERO, [
            crown, crown + Vector2(cos(a - 0.18) * 32, -18),
            finish, crown + Vector2(cos(a + 0.15) * 30, 5)
        ], Color("#25884e") if i % 2 == 0 else Color("#45b957"))
    _art_disc(tree, crown, 10.0, Color("#8a633a"))


func _art_temple(parent: Node2D, at: Vector2, scale_factor: float) -> void:
    var temple := Node2D.new()
    temple.position = at
    temple.scale = Vector2.ONE * scale_factor
    parent.add_child(temple)
    _art_poly(temple, Vector2.ZERO, [
        Vector2(-55, 0), Vector2(-55, -65),
        Vector2(55, -65), Vector2(55, 0)
    ], Color("#8a755b"))
    _art_poly(temple, Vector2.ZERO, [
        Vector2(-68, -65), Vector2(0, -112), Vector2(68, -65)
    ], Color("#5d493b"))
    _art_poly(temple, Vector2.ZERO, [
        Vector2(-43, -7), Vector2(-43, -47),
        Vector2(-19, -47), Vector2(-19, -7)
    ], Color("#443b36"))
    _art_poly(temple, Vector2.ZERO, [
        Vector2(18, -7), Vector2(18, -47),
        Vector2(42, -47), Vector2(42, -7)
    ], Color("#443b36"))
    _art_poly(temple, Vector2.ZERO, [
        Vector2(-55, -55), Vector2(55, -55),
        Vector2(55, -49), Vector2(-55, -49)
    ], Color("#b49a70"))


func _art_crate(parent: Node2D, at: Vector2, size: float, explosive: bool) -> void:
    var box := Node2D.new()
    box.position = at
    parent.add_child(box)
    var base := Color("#a94b36") if explosive else Color("#c78943")
    _art_poly(box, Vector2.ZERO, [
        Vector2.ZERO, Vector2(size, 0),
        Vector2(size, size), Vector2(0, size)
    ], Color("#633d2a"))
    _art_poly(box, Vector2(3, 3), [
        Vector2.ZERO, Vector2(size - 6, 0),
        Vector2(size - 6, size - 6), Vector2(0, size - 6)
    ], base)
    _art_poly(box, Vector2.ZERO, [
        Vector2(5, 5), Vector2(size - 5, size - 5),
        Vector2(size - 10, size - 5), Vector2(5, 10)
    ], Color("#e2b66b"))
    _art_poly(box, Vector2.ZERO, [
        Vector2(size - 5, 5), Vector2(5, size - 5),
        Vector2(10, size - 5), Vector2(size - 5, 10)
    ], Color("#e2b66b"))
    if explosive:
        var label := Label.new()
        label.text = "TNT"
        label.position = Vector2(1, size * 0.24)
        label.size = Vector2(size - 2, size * 0.5)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", int(size * 0.34))
        label.add_theme_color_override("font_color", Color.WHITE)
        box.add_child(label)


func _art_fruit(parent: Node2D, at: Vector2, radius: float) -> void:
    _art_disc(parent, at + Vector2(0, 3), radius + 2, Color("#e69c24"))
    _art_disc(parent, at, radius, Color("#ffcf24"))
    _art_disc(parent, at + Vector2(-3, -3), radius * 0.62, Color("#ffec64"))
    _art_poly(parent, at, [
        Vector2(0, -radius), Vector2(3, -radius - 8),
        Vector2(7, -radius - 9), Vector2(5, -radius - 3)
    ], Color("#477d35"))


func _platform(pos: Vector2, size: Vector2, body_color: Color, top_color: Color) -> void:
    var body := StaticBody2D.new()
    body.position = pos + size / 2.0
    var collision := CollisionShape2D.new()
    var rectangle := RectangleShape2D.new()
    rectangle.size = size
    collision.shape = rectangle
    body.add_child(collision)

    var stone := ColorRect.new()
    stone.position = -size / 2.0
    stone.size = size
    stone.color = body_color
    body.add_child(stone)

    var moss_shadow := ColorRect.new()
    moss_shadow.position = Vector2(-size.x / 2.0, -size.y / 2.0)
    moss_shadow.size = Vector2(size.x, minf(12.0, size.y))
    moss_shadow.color = Color("#477f3c")
    body.add_child(moss_shadow)

    var grass := ColorRect.new()
    grass.position = Vector2(-size.x / 2.0, -size.y / 2.0)
    grass.size = Vector2(size.x, minf(7.0, size.y))
    grass.color = top_color
    body.add_child(grass)

    if size.x < 500:
        for x in range(25, int(size.x), 36):
            var seam := ColorRect.new()
            seam.position = Vector2(-size.x / 2.0 + x, -size.y / 2.0 + 13)
            seam.size = Vector2(2, maxf(2, size.y - 14))
            seam.color = Color("#5b3d31", 0.45)
            body.add_child(seam)
    world.add_child(body)

'''

s = s[:start] + new_code + "\n" + s[end:]
main_file.write_text(s, encoding="utf-8")
print("Jungle-grafikken er installeret i scripts/main.gd.")
print(f"Backup: {backup}")
print("Genindlæs Godot og test. Gendan backup, hvis parserfejl opstår.")
