# PROJECT HANDOVER – CRASH LOCAL (JUNGLE RUMBLE)
**Android Multiplayer 2D Platformer – Godot 4.7 (ARM64 / OnePlus 12R)**

---

## 1. Præcise Filstier og Termux-Kommandoer (VIGTIGT TIL NÆSTE AI)

Al udvikling og test foregår direkte på Android via **Termux** og **Godot 4 (Android)** på en **OnePlus 12R (16 GB RAM, ARM64 / aarch64)**.

### Nøglestier på telefonen
* **Download-mappe på telefonen:** `~/storage/shared/Download/`
* **Aktiv projektmappe:** `~/storage/shared/Download/CrashLocalPrototype`
* **Godot-projektfil:** `~/storage/shared/Download/CrashLocalPrototype/project.godot`
* **Hovedscene:** `~/storage/shared/Download/CrashLocalPrototype/scenes/Main.tscn`
* **Hovedscript:** `~/storage/shared/Download/CrashLocalPrototype/scripts/main.gd`
* **Spillerscript:** `~/storage/shared/Download/CrashLocalPrototype/scripts/player.gd`
* **Grafikfiler (SVG):** `~/storage/shared/Download/CrashLocalPrototype/art/`
* **Karakter-animationsframes (25 SVG-frames):** `~/storage/shared/Download/CrashLocalPrototype/art/hero_frames/`
* **Lydfiler (WAV):** `~/storage/shared/Download/CrashLocalPrototype/sfx/`
* **Backupfiler:**
  * `scripts/main.gd.before_visual_assets`
  * `scripts/player.gd.before_visual_assets`
  * `scripts/main.gd.before_v2_upgrade`
  * `scripts/player.gd.before_v2_upgrade`
  * `scripts/main.gd.before_jungle_art`
  * `scripts/main.gd.before_cinematic_jungle`
  * `scripts/main.gd.before_indent_fix`
  * `scripts/main.gd.before_missing_functions_fix`
  * `scripts/main.gd.backup`

### Standard Termux-kommandoer

**1. Åbn projektmappen i Termux:**
```bash
cd ~/storage/shared/Download/CrashLocalPrototype
```

**2. Se alle projektfiler (uden `.godot` og `.git` støj):**
```bash
find . -type f \
  -not -path './.godot/*' \
  -not -path './.git/*' | sort
```

**3. Udpak en ny `CrashLocal_COMPLETE.zip` direkte i `Download` (uden copy-paste af kode):**
```bash
cd ~/storage/shared/Download
unzip -o CrashLocal_COMPLETE.zip
rm -rf ~/storage/shared/Download/CrashLocalPrototype/.godot/imported
```

**4. Lav en komplet ZIP-backup i `Download`:**
```bash
cd ~/storage/shared/Download
zip -r CrashLocal_COMPLETE.zip CrashLocalPrototype \
  -x "*/.godot/*" "*/.git/*"
```

---

## 2. Projektets Arkitektur & Nuværende Status (v2.0 – Grafisk & Gameplay Opgradering)

### Grafik & Miljø (`art/` + `scripts/main.gd`)
* **4-lags Parallax Jungle (`ParallaxBackground` + `ParallaxLayer`):**
  * `art/jungle_back.svg` (Himmel, sol-korona, skyer, fjerne vulkanbjerge – scroll `0.10`).
  * `art/jungle_ruins.svg` (Aztekiske/Tiki tempelpyramider, klipper – scroll `0.28`).
  * `art/jungle_mid.svg` (Palmetræer, lianer, eksotiske blomster, tæt underskov – scroll `0.55`).
  * `art/jungle_fg.svg` (Forgrunds-bladhang øverst i billedet – scroll `0.82`).
* **Dynamiske miljøeffekter:**
  * 3-frames animerede vandfald (`art/waterfall_1..3.svg`) med bundskum-partikler (`CPUParticles2D`).
  * Solstråler (God Rays) og svajende jungleplanter (`art/jungle_plant.svg`).
  * Runtime SVG-loader (`load_svg_tex()` i `main.gd`), der rasteriserer SVG direkte via `Image.load_svg_from_string()`, så ændringer i `art/*.svg` vises øjeblikkeligt på Android uden at hænge i gammel `.godot/imported/`-cache.

### Karakteranimationer (`art/hero_frames/` + `scripts/player.gd`)
* **25 dedikerede SVG-frames fordelt på alle 8 tilstande:**
  * `idle` (`hero_idle_1..4.svg` – vejrtrækning og blink).
  * `run` (`hero_run_1..6.svg` – fuld 6-frames løbecyklus).
  * `jump` (`hero_jump_1..2.svg` – afsæt og stræk).
  * `fall` (`hero_fall_1..2.svg` – luftfald).
  * `land` (`hero_land_1..2.svg` – squash-and-stretch landing).
  * `spin` (`hero_spin_1..4.svg` – Crash-inspireret cyklon/tornado spin-angreb).
  * `hit` (`hero_hit_1..2.svg` – knockback reaktion med stjerner).
  * `death` (`hero_death_1..3.svg` – kollaps med roterende svimmelheds-stjerner).
* **Partikler og følelse:**
  * Fodstøv ved afsæt og landing (`dust_particles`), gnister ved spin (`spin_particles`), dynamisk jordskygge (`shadow_poly`), Coyote Time (`0.11s`) og Jump Buffering (`0.13s`).

### Banedesign & Spiltilstande (`RACE` & `ARENA`)
* **RACE MODE (6400 px lang junglebane i 4 zoner):**
  * Kløfter, bevægelige gyldne tempelplatforme (`art/moving_platform.svg`), svævende stenplatforme med græs (`art/platform.svg`) og pigfælder (`art/spikes.svg`).
  * **5 kassetyper:** Almindelig trækasse (`crate.svg`, giver 3 Wumpa-frugter), Hoppe-kasse (`bounce_crate.svg`, katapulterer spilleren højt op), TNT-kasse (`tnt_crate.svg`, 3-sekunders nedtælling + eksplosion eller øjeblikkelig eksplosion ved spin), Aku/Tiki-kasse (`aku_crate.svg`, giver svævende Tiki-beskyttelsesmaske `tiki_mask.svg`) og Checkpoint-kasse (`checkpoint_crate.svg` -> `checkpoint_open.svg`).
  * **Fjender:** Patruljerende animerede junglekrabber (`enemy_crab_1..2.svg`) og Tiki-vagter (`enemy_tiki_1..2.svg`), der kan besejres med spin eller hop ovenfra.
  * **Målportal:** Tiki-målportal (`goal_portal.svg`), der registrerer første spiller i mål og viser vinder-skærmen.
* **ARENA MODE (2200 px flerlags kamparena):**
  * Hver spiller starter med **3 liv (`♥♥♥`)**.
  * Spin-angreb giver kraftigt knockback mod andre spillere; TNT-kasser, hoppe-kasser og Tiki-skjold er placeret strategisk i arenaen.
  * Sidste overlevende spiller (eller højeste score når 90s udløber) vinder automatisk.
* **Solo/Bot-test:** Knappen `"HURTIG TEST PÅ 1 TELEFON (MED BOT)"` gør det muligt at teste både Race og Arena med det samme på én telefon.

### Multiplayer & Android Optimering
* **ENet UDP Port `24567` (2–4 telefoner på lokalt Wi-Fi eller telefon-hotspot):**
  * Værtens lokale LAN-IP vises automatisk på Host-knappen i menuen.
  * Serveren broadcaster spillerpositioner, hastighed, retning, spin, animationstilstand, liv, frugter og Tiki-maske med stabil **30 Hz tickrate** (`unreliable_ordered`), mens kassesmadring, frugt-opsamling, fjende-eliminering og vinderkåring sendes `reliable`.
* **Ægte Android Multi-Touch (`_input` med `InputEventScreenTouch` & `InputEventScreenDrag`):**
  * Understøtter at spilleren glider venstre tommelfinger mellem `◀` og `▶` og samtidig trykker `JUMP` og `SPIN` med højre tommelfinger.

---

## 3. Regler for videre udvikling (til næste AI)
1. Arbejd altid videre direkte i `~/storage/shared/Download/CrashLocalPrototype`.
2. Slet aldrig fungerende funktioner eller eksisterende backupfiler.
3. Lever altid ændringer som en komplet, køreklar ZIP-fil (`CrashLocal_COMPLETE.zip`), så brugeren kan udpakke direkte i Termux uden at skulle copy-paste lange koder.
