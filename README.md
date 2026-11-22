# Crash Local: Jungle Rumble

Et Crash Bandicoot-inspireret 2D-platformspil udviklet i **Godot 4.7 (GDScript)** til Android med lokal Wi-Fi/Hotspot multiplayer for 2–4 spillere (udviklet og bygget direkte på OnePlus 12R / ARM64).

## Spiltilstande
- **Race Mode (Jungle Sprint):** 6400 px lang junglebane i 4 zoner med kløfter, bevægelige tempelplatforme, patruljerende junglefjender (krabber og Tiki-vagter), pigfælder samt 5 kassetyper (Trækasse, Hoppe-kasse, TNT-kasse, Tiki-beskyttelsesmaske og Checkpoint).
- **Arena Mode (3 Liv Kamp):** Flerlags kamparena med 3 liv pr. spiller, spin-knockback, TNT, hoppe-kasser og 90s kamptimer.
- **Solo-test med AI-Bot:** Indbygget hurtigtest på 1 telefon direkte fra hovedmenuen.

## Lokal Multiplayer (2–4 telefoner)
1. Forbind alle telefoner til samme Wi-Fi eller én telefons **Wi-Fi Hotspot**.
2. **Vært:** Vælg `RACE MODE` eller `ARENA MODE` og tryk **OPRET RUM PÅ DENNE TELEFON** (telefonens lokale IP vises direkte på knappen).
3. **Gæster:** Indtast værtens IP-adresse og tryk **TILSLUT TIL VÆRT**.
4. **Start:** Værten trykker **START MULTIPLAYER SPIL**.

## Projektstruktur
- `project.godot` – Godot 4.7 projektkonfiguration (`gl_compatibility` renderer)
- `scenes/Main.tscn` – Hovedscene
- `scripts/main.gd` – Menu, ENet multiplayer, 4-lags parallax-jungle, banegenerator, HUD, multi-touch & procedurel lyd
- `scripts/player.gd` – Spillerfysik, 8 animationstilstande (`idle`, `run`, `jump`, `fall`, `land`, `spin`, `hit`, `death`), AI-bot & kampmekanik
- `art/` – Vektorgrafik (SVG) samt 25 karakter-animationsframes i `art/hero_frames/`
- `sfx/` – Offline WAV-lydeffekter
