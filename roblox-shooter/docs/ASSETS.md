# ASSETS.md: built-in Roblox assets usable without uploading

> **Kurzfassung (Deutsch):** Roblox liefert nur **11 eingebaute Sounds** mit, und keiner davon ist ein Schuss.
> Schüsse, Hitmarker usw. bauen wir deshalb aus diesen 11 Dateien. Dafür nutzen wir Tonhöhe
> (`PlaybackSpeed`), Ausschnitt (`PlaybackRegion`) und Effekte (`DistortionSoundEffect` usw.).
> Zusätzlich gibt es in `Config` Felder für Sound-IDs (`0` = eingebauter Ersatz).
> Für Partikel/Tracer gibt es gute eingebaute Texturen (Glow, Funken-Quadrat, Rauch, Stern, Cartoon-Puff, Beam-Verlauf).
> Achtung: Zwei Sounds aus Meteor Heist (`swordslash.wav`, `electronicpingshort.wav`) gibt es im Client
> gar nicht mehr. Sie sind sehr wahrscheinlich stumm (siehe Abschnitt 9).

Status words used below:

- **VERIFIED**: the file exists in the current Roblox client package (manifest checked, see Section 1).
- **VERIFIED + VIEWED**: also decoded and looked at. Its MD5 matched the shipped file byte for byte.
- **UNVERIFIED**: could not be proven. Do not rely on it without testing in Studio.
- **NOT SHIPPED**: the file is not in the client. Using it gives silence or a missing texture.

---

## 1. How this was verified

- **Source:** GitHub `MaximumADHD/Roblox-Client-Tracker`, branch `roblox`, commit `41ab074bc` (2026-10-07),
  client version **0.742.0.7421053** (`version-9b554450a0fc4e65`).
- This branch has **no `content/` folder**, so the GitHub API path `contents/content/sounds` does not exist.
  The authoritative list is **`rbxManifest.csv` / `rbxManifest.txt`**. Roblox's CDN publishes this list of
  (almost) every file extracted from the client zips, each with its MD5.
  It has 9393 `content/...` entries, including `content/sounds/*`, `content/textures/**` and `content/sky/*`.
- The repo also mirrors the actual texture files in `textures/`.
  58 candidate textures were decoded (PNG + DDS) and inspected visually.
  **All 58 MD5s match the manifest**, so they are exactly the shipped files.
- **Audio could not be downloaded:** the Roblox CDN (`setup.rbxcdn.com`) is blocked by this environment's egress policy (HTTP 403).
  The repo does not mirror audio. Sound descriptions therefore come from file names and Roblox's own usage. They are **not auditioned**.
- **Cross-check:** grepped Roblox's own CoreScripts/PlayerScripts (in the repo) and `Full-API-Dump.json`
  (engine defaults) for `rbxasset://` paths.
  If Roblox's player scripts or an engine default use a path, that file ships on **all platforms**, mobile included.
- **History:** 655 manifest revisions back to 2018-09 were checked to see what was removed or renamed.
- **Limitation:** the manifest describes the Windows Studio package.
  The player uses the same `content-*` zips, but files used only by Studio plugins may not exist in live games.
  Use only the paths listed here.

### Path rules (important)

- `rbxasset://X` maps to the client folder `content/X`. Example: `rbxasset://sounds/oof.ogg` maps to `content/sounds/oof.ogg`.
  `rbxasset://textures/...` is also overlaid by `PlatformContent/<platform>/textures/...` (that is where the skybox lives).
- Paths are **case-sensitive** on mobile/Mac: write `SquareParticle.png`, not `squareparticle.png`.
  Always use forward slashes. No current built-in file has a space in its name.
  Old tutorial names such as `Rocket shot.wav` are gone.
- **Extensions changed over time:** `action_falling.mp3` became `action_falling.ogg` in Nov 2024, so the old `.mp3` path is dead.
  Copy paths exactly from this file.
- Do **not** use `StudioContent/...`, `content/studio_svg_textures/...` or the Studio-plugin folders inside `content/textures/`
  (AnimationEditor, PivotEditor, StudioSharedUI, ...). They are Studio-only.

---

## 2. Sounds: the complete built-in list (all 11 files)

Total `content-sounds.zip` is ~499 KB uncompressed. There is no other audio anywhere in the client package.

| Path (exact) | Status | What it is (not auditioned) | Recommended use in the shooter |
|---|---|---|---|
| `rbxasset://sounds/impact_explosion_03.mp3` | VERIFIED | Explosion impact "boom" (name; no Lua reference, so presumably used by the C++ engine) | **Base for all gunshots** (pitched up + short region + distortion), rocket/grenade explosion at normal pitch |
| `rbxasset://sounds/action_jump_land.mp3` | VERIFIED, used by RbxCharacterSounds and Meteor Heist | Short dull landing thud | Mag in/out clacks (pitched up 2.5-3.5), UI deny/error (pitched down), "bonk" hits |
| `rbxasset://sounds/volume_slider.ogg` | VERIFIED (added 2022-08) | Short UI tick/blip from the settings volume slider (by name) | **Hitmarker, headshot ding, kill confirm, UI clicks, countdown beeps, win/lose jingles** (pitched to musical notes) |
| `rbxasset://sounds/action_jump.mp3` | VERIFIED, RbxCharacterSounds | Default jump whoosh | Played automatically on jump. Pitched up: melee swing / weapon swap whoosh |
| `rbxasset://sounds/action_get_up.mp3` | VERIFIED, RbxCharacterSounds | Default "get up" sound | Slide/bolt rack, pump (short region, pitched up). UNTESTED by ear |
| `rbxasset://sounds/action_falling.ogg` | VERIFIED, RbxCharacterSounds (loop) | Falling wind loop | Rocket launch whoosh / rocket flight loop, dash/slide wind |
| `rbxasset://sounds/action_footsteps_plastic.mp3` | VERIFIED, RbxCharacterSounds (loop) | Default footsteps loop | **Footsteps are automatic** (RbxCharacterSounds). No extra code needed |
| `rbxasset://sounds/action_swim.mp3` | VERIFIED, RbxCharacterSounds (loop) | Swimming loop | Only if a map has water |
| `rbxasset://sounds/impact_water.mp3` | VERIFIED, RbxCharacterSounds | Water splash | Bullet hits water, falling into water |
| `rbxasset://sounds/ouch.ogg` | VERIFIED (added 0.536, 2022-07, replacing `uuhhh.mp3`) | Current Roblox death sound (replacement of the old "oof") | Local "you were eliminated" sting (optional) |
| `rbxasset://sounds/oof.ogg` | VERIFIED (re-added 0.684, 2025-07) | By name: the classic "oof" | Optional fun lose/elimination sound. Keep it optional and quiet |

### 2.1 NOT SHIPPED / do not use

| Path | Status | Notes |
|---|---|---|
| `rbxasset://sounds/swordslash.wav` | **NOT SHIPPED** | Not in any manifest since 2018-09. **Used by Meteor Heist `Bat.luau:27`, so it is very likely silent** |
| `rbxasset://sounds/electronicpingshort.wav` | **NOT SHIPPED** | Not in any manifest since 2018-09. **Used by Meteor Heist `MeteorRun.luau:31`, so it is very likely silent** |
| `rbxasset://sounds/uuhhh.mp3` | **UNVERIFIED** | Removed from the package in 0.536 (2022-07), but Roblox's own `RbxCharacterSounds.lua` and settings scripts still reference it. The engine probably remaps it internally. Do not use; use `ouch.ogg` |
| `rbxasset://sounds/action_falling.mp3` | NOT SHIPPED | Renamed to `.ogg` in 0.650 (2024-11) |
| `rbxasset://sounds/bass.wav`, `rbxasset://sounds/snap.mp3` | NOT SHIPPED | Present in 2018, removed later |
| Any other legacy name (`swordlunge.wav`, `unsheath.wav`, `button.wav`, `hit.wav`, `splat.wav`, `Rocket shot.wav`, `Launching rocket.wav`, `collide.wav`, ...) | NOT SHIPPED | Only the 11 files above exist |

### 2.2 Sound recipes for shooter roles (built-ins only)

Engine members used here are all VERIFIED in the 0.742 API dump:
`Sound.PlaybackRegion` (NumberRange, seconds of the **source file**, default 0-60000) together with `Sound.PlaybackRegionsEnabled`
(default false), plus `PlaybackSpeed`, `DistortionSoundEffect.Level`, `EqualizerSoundEffect.LowGain/MidGain/HighGain`,
`EchoSoundEffect.Delay/Feedback/DryLevel/WetLevel`, `PitchShiftSoundEffect.Octave`, `ReverbSoundEffect`, `SoundService:PlayLocalSound`.

**All numbers are UNTESTED starting values.** Tune them by ear in Studio.
Add ±4 % random `PlaybackSpeed` per shot so repeated shots do not sound robotic.

Musical pitch ratios for jingles: major third = 1.26, fifth = 1.498, octave = 2.0, minor third down = 0.841, fifth down = 0.667.

| Role | Base file | PlaybackSpeed | PlaybackRegion (source s) | Effects | Vol | Notes |
|---|---|---|---|---|---|---|
| Pistol shot | `impact_explosion_03.mp3` | 2.4 | 0-0.30 | Distortion 0.5; EQ Low -6, High +4 | 0.6 | Layer `action_jump_land.mp3` @3.0, vol 0.35 as mechanical click |
| Rifle / SMG (auto) | `impact_explosion_03.mp3` | 3.0 | 0-0.20 | Distortion 0.6; EQ High +6 | 0.45 | Pool 3-4 Sounds round-robin, because `Play()` restarts a single Sound |
| Shotgun | `impact_explosion_03.mp3` | 1.7 | 0-0.50 | Distortion 0.75; EQ Low +4 | 0.8 | Pump: `action_get_up.mp3` @1.8 |
| Sniper | `impact_explosion_03.mp3` | 1.3 | full | Distortion 0.4; Echo Delay 0.15, Feedback 0.25, Wet -8 | 0.9 | "Crack + echo", large `RollOffMaxDistance` (~600) |
| Rocket launch | `action_falling.ogg` | 2.2 | 0-0.60 | EQ High +6 | 0.6 | Flight loop: same file `Looped`, @1.5 |
| Rocket / grenade explosion | `impact_explosion_03.mp3` | 1.0 ±0.1 | full | (Distortion 0.2) | 1.0 | Native boom |
| Dry fire (empty) | `volume_slider.ogg` | 0.8 | n/a | none | 0.5 | |
| Reload: mag out / mag in | `action_jump_land.mp3` | 3.2 / 2.6 | n/a | EQ High +4 / Distortion 0.2 | 0.5 | Time them with the procedural reload tween |
| Reload: slide/bolt | `action_get_up.mp3` | 2.0 | 0-0.25 | none | 0.5 | |
| Hitmarker | `volume_slider.ogg` | 1.6 | n/a | none | 0.5 | Client-only via `SoundService:PlayLocalSound` |
| Headshot ding | `volume_slider.ogg` | 2.2, then 2.8 after 0.05 s | n/a | Echo Delay 0.08 | 0.7 | Pair with sparkle-star VFX |
| Kill confirm | `volume_slider.ogg` | 1.0, 1.26, 1.5 (0.06 s apart) | n/a | none | 0.7 | Quick up-arpeggio |
| Eliminated (self) | `ouch.ogg` (or `oof.ogg`) | 1.0 | n/a | none | 0.6 | |
| Melee swing / weapon swap | `action_jump.mp3` | 1.8 | n/a | none | 0.5 | |
| Footsteps / jump / land | built in | n/a | n/a | n/a | n/a | RbxCharacterSounds plays them automatically |
| UI click / hover | `volume_slider.ogg` | 1.0 / 1.5 | n/a | none | 0.5 / 0.2 | `PlayLocalSound` |
| UI error / deny | `action_jump_land.mp3` | 0.7 | n/a | none | 0.5 | |
| Countdown 3-2-1 / GO | `volume_slider.ogg` | 1.0 per tick / 2.0 (+1.5 layered) | n/a | none | 0.7 | |
| Round win jingle | `volume_slider.ogg` | 1.0, 1.26, 1.5, 2.0 (0.09 s apart) | n/a | Echo on last note | 0.8 | |
| Round lose jingle | `volume_slider.ogg` | 1.0, 0.841, 0.667 (0.16 s apart) | n/a | EQ High -6 | 0.7 | Optional `oof.ogg` at the end |
| Low ammo warning | `volume_slider.ogg` | 1.2 twice | n/a | none | 0.4 | |
| Bullet hits water | `impact_water.mp3` | 1.3 | n/a | none | 0.5 | |

```lua
-- Baut einen Schuss-Sound nur aus eingebauten Dateien (kein Upload nötig).
-- Startwerte aus docs/ASSETS.md, bitte im Studio nach Gehör anpassen.
local function makeShotSound(parent: Instance, speed: number, regionEnd: number, distortion: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/impact_explosion_03.mp3"
	sound.PlaybackSpeed = speed
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(0, regionEnd) -- Sekunden in der Original-Datei
	sound.Volume = 0.6
	sound.RollOffMaxDistance = 300
	local dist = Instance.new("DistortionSoundEffect")
	dist.Level = distortion
	dist.Parent = sound
	sound.Parent = parent -- z. B. Attachment an der Mündung (3D-Sound)
	return sound
end
```

### 2.3 Configurable real sounds (owner adds later)

- Put an ID per role in `Config.Sounds` (`PistolShot = 0`, `RifleShot = 0`, `ShotgunShot = 0`, `SniperShot = 0`, `RocketLaunch = 0`,
  `Explosion = 0`, `Reload = 0`, `Hitmarker = 0`, `Headshot = 0`, `Kill = 0`, `UIClick = 0`, `Countdown = 0`, `Win = 0`, `Lose = 0`,
  `LobbyMusic = 0`).
  `0` means use the recipe above. Otherwise use `"rbxassetid://" .. id`.
- The owner can take **Roblox-made audio from the Creator Store** (Toolbox, Audio, creator "Roblox"). These are public for every experience, so **no upload is needed**.
  **No such IDs are listed here.** They could not be verified (`create.roblox.com` is blocked in this environment).
- Optional: `AudioTextToSpeech` exists in the 0.742 API dump (`Text`, `VoiceId`, `Pitch`, `Speed`, `Volume`).
  It could announce "3, 2, 1, GO!" or "HEADSHOT!" without assets. **Availability and behaviour are UNVERIFIED** (it may be beta / rollout-gated).
  If used, keep it behind a Config flag with a beep fallback.
- No tone generator exists in the API (`AudioWindSynthesizer` is NotBrowsable). Beeps must come from `volume_slider.ogg`.

---

## 3. Particle textures: `rbxasset://textures/particles/` (all 28 files)

"Tintable" means the RGB is white or light, so `ParticleEmitter.Color` / `ImageColor3` / `Beam.Color` can colour it
(colour multiplies). Dark textures can only stay dark.

| Path (exact) | Status | Looks like | Tintable | Recommended use |
|---|---|---|---|---|
| `rbxasset://textures/particles/sparkles_main.dds` | VERIFIED + VIEWED; **engine default of `ParticleEmitter.Texture`**; used by Meteor Heist | 128x128 soft **8-point star sparkle** | yes (RGB≈206) | Headshot/crit star, kill pop, pickup sparkle, cartoon muzzle star |
| `rbxasset://textures/particles/explosion01_implosion_main.dds` | VERIFIED + VIEWED | 256x256 **soft white radial glow blob** | yes (RGB≈250) | **Muzzle flash core**, hit flash, plasma glow, tracer head |
| `rbxasset://textures/particles/SquareParticle.png` | VERIFIED + VIEWED | 256x256 **solid white square** (slight bevel at the bottom edge) | yes (pure white) | **Chunky cartoon sparks**, debris, confetti (win screen), pixel bits |
| `rbxasset://textures/particles/smoke_main.dds` | VERIFIED + VIEWED | 128x128 **soft light-grey puff** | yes (RGB≈244) | **Muzzle smoke**, impact dust, smoke grenade, landing dust |
| `rbxasset://textures/particles/explosion01_core_main.dds` | VERIFIED + VIEWED | 256x256 **orange fiery cloud** | coloured already | Explosion fireball, rocket blast, incendiary hit |
| `rbxasset://textures/particles/explosion01_shockwave_main.dds` | VERIFIED + VIEWED | 256x256 **soft ring** | grey-ish | Explosion shockwave, headshot ring, landing/stomp ring, spawn ring |
| `rbxasset://textures/particles/explosion01_smoke_main.dds` | VERIFIED + VIEWED | 256x256 **dark cloudy smoke** | **no** (RGB≈25, dark only) | Dark explosion smoke / burnt smoke |
| `rbxasset://textures/particles/fire_main.dds` | VERIFIED + VIEWED | 256x256 **wispy flame / smoke strands**, brownish | partly | Fire, flamethrower, burn areas |
| `rbxasset://textures/particles/forcefield_vortex_main.dds` | VERIFIED + VIEWED | 128x128 **ring with sparkle dots** | grey-ish | Spawn-protection effect, pickup/objective ring |
| `rbxasset://textures/particles/forcefield_glow_main.dds` | VERIFIED + VIEWED | 256x256 very faint big circle | weak | Rarely useful (too faint) |
| `rbxasset://textures/particles/fire_sparks_main.dds` | VERIFIED + VIEWED | 64x64, a few **nearly black specks** | **no** (RGB≈13) | **Avoid for sparks**: it relies on an engine colour ramp. Use `SquareParticle.png` / `sparkles_main.dds` |
| `common_alpha.dds`, `explosion_alpha.dds`, `explosion_color.dds`, `explosion01_core_alpha.png`, `explosion01_implosion_color.png`, `explosion01_smoke_alpha.dds`, `explosion01_smoke_color_new.dds`, `fire_alpha.dds`, `fire_color.dds`, `fire_sparks_color.dds`, `forcefield_alpha.dds`, `forcefield_glow_alpha.dds`, `forcefield_glow_color.dds`, `forcefield_vortex_color.dds`, `legacy_fire_alpha_color.dds`, `smoke_color.dds`, `sparkles_color.dds` (all in `rbxasset://textures/particles/`) | VERIFIED + VIEWED | **128x32 colour/alpha ramps** (lookup gradients for the engine's Fire/Smoke/Explosion shaders) | n/a | **Do not use as sprites.** They render as a gradient strip |

---

## 4. Other useful textures

| Path (exact) | Status | Looks like | Recommended use |
|---|---|---|---|
| `rbxasset://textures/explosion.png` | VERIFIED + VIEWED | 128x128 **cartoon white/cream puff cloud** (RGB≈255,246,238, tintable) | **Cartoon hit "poof" instead of blood**, impact puff, kill pop (tint with team colour) |
| `rbxasset://textures/glow.png` | VERIFIED + VIEWED | 256x256 **white starburst rays** on a dark-grey soft halo (grey+alpha) | **Muzzle-flash star** (`LightEmission = 1` so the dark halo vanishes), lens flash |
| `rbxasset://textures/gradient.png` | VERIFIED + VIEWED | 512x512 pure white; alpha is a **bright horizontal band in the middle fading to transparent at top/bottom** | **Beam/Trail tracer texture**: bright core with soft edges, tint via `Beam.Color`. The orientation (band across the width) is by reasoning; UNVERIFIED in Studio |
| `rbxasset://textures/ui/traildot.png` | VERIFIED + VIEWED; used by Roblox ClickToMove (all platforms) | 246x246 **soft light-grey disc with glowing edge** | Glowing bullet head / energy round particle, soft dot particles |
| `rbxasset://textures/sparkle.png` | VERIFIED + VIEWED | 32x32 small white 4-point star | Tiny sparkles, UI shine |
| `rbxasset://textures/whiteCircle.png` | VERIFIED + VIEWED | 512x512 white filled disc | Round UI (tintable), scope lens base, big dots |
| `rbxasset://textures/smallWhiteCircle.png` | VERIFIED + VIEWED | 64x64 white filled disc | Particle dots, crosshair centre dot, minimap dots |
| `rbxasset://textures/triangle.png` | VERIFIED + VIEWED | 48x64 white triangle | **Damage direction indicator**, arrows, "you are here" markers |
| `rbxasset://textures/Blank.png` | VERIFIED + VIEWED | 16x16 fully transparent | Placeholder image |
| `rbxasset://textures/Cursors/CrossMouseIcon.png` | VERIFIED + VIEWED; used by Roblox PlayerModule (shift-lock cursor) | 64x64 transparent with a tiny thin "+" | Fallback `UserInputService.MouseIcon` crosshair. The real crosshair should be built from Frames (dynamic spread) |
| `rbxasset://textures/ui/Input/AimStrafeButtonRegular.png` (+ `AimStrafeButtonPressed.png`, `@2x`) | VERIFIED + VIEWED (Pressed: exists) | 44x44 **reticle-in-circle** icon | **Mobile AIM button icon** |
| `rbxasset://textures/ui/Input/Disk_padded.png` | VERIFIED + VIEWED | 256x256 white filled disc | **Tintable round touch buttons** (Fire/Reload/Aim) |
| `rbxasset://textures/ui/Input/Ring_padded.png` | VERIFIED + VIEWED | 118x118 white ring | Touch-button outline, cooldown ring |
| `rbxasset://textures/ui/Input/JumpButtonRegular.png` / `JumpButtonPressed.png` | VERIFIED + VIEWED / VERIFIED; used by Roblox touch controls | 120x120 jump arrow in a circle | Mobile jump (default Roblox look) |
| `rbxasset://textures/ui/Input/CrouchButtonRegular.png`, `CrouchButtonPressed.png`, `SprintButtonRegular.png`, `SprintButtonPressed.png`, `StrafeButtonRegular.png`, `StrafeButtonPressed.png` (+ `@2x`) | VERIFIED (not viewed) | Roblox touch-button icons | Mobile crouch/sprint/slide buttons |
| `rbxasset://textures/ui/Input/TouchControlsSheetV2.png` | VERIFIED + VIEWED; used by Roblox touch controls | 512x512 sprite sheet (thumbstick, jump) | Only if copying the default thumbstick look |
| `rbxasset://textures/ui/Controls/RadialFill.png` | VERIFIED + VIEWED; used by ProximityPrompt | 58x58 white ring | Reload / ability progress ring (with a UIGradient rotation trick) |
| `rbxasset://textures/ui/Controls/XboxController/ButtonX.png` (also `ButtonA/B/Y/LB/RB/LT/RT/LS/RS/Select/Start/DPad*/Thumbstick1/2.png`), `.../PlayStationController/ButtonSquare.png` (also `ButtonCross/Circle/Triangle/L1/L2/R1/R2...`), `.../DefaultController/...` | VERIFIED (not viewed) | Controller glyphs | Button prompts. Prefer **`UserInputService:GetImageForKeyCode(keyCode)`** (VERIFIED in API), which returns the right glyph per controller |
| `rbxasset://textures/ui/Controls/key_single.png`, `shift.png`, `spacebar.png`, `tab.png`, `return.png`, `backspace.png` (+ `@2x/@3x`) | VERIFIED (not viewed); used by CoreScripts | Keyboard key caps | PC key prompts ("[R] Reload") |
| `rbxasset://textures/ui/common/robux_color.png` (+ `@2x`, `@3x`) | VERIFIED + VIEWED | Current **gold Robux hexagon** | Shop prices |
| `rbxasset://textures/ui/common/robux.png`, `robux_small.png` (+ `@2x`, `@3x`) | VERIFIED (not viewed) | White Robux icon (tintable) | Shop prices on coloured buttons |
| `rbxasset://textures/ui/RobuxIcon.png`, `rbxasset://textures/icon_ROBUX.png` | VERIFIED + VIEWED | **Old** green/grey "R$" | Avoid (outdated look) |
| `rbxasset://textures/loading/loadingvignette.png` | VERIFIED + VIEWED | 256x144, **RGB pure black**, alpha opaque at the edges / clear in the centre | Darkening vignette only (low HP, scope). It **cannot be tinted red**. For a red damage flash use a Frame + `UIGradient` |
| `rbxasset://textures/ui/waypoint.png` | VERIFIED + VIEWED; used by ClickToMove | Map pin | Objective / teammate marker |
| `rbxasset://textures/face.png` | VERIFIED + VIEWED | Default smiley face | Bot/dummy faces |
| `rbxasset://textures/ui/TopBar/HealthBar.png`, `HealthBarBase.png` | VERIFIED (not viewed) | Roblox health-bar pieces | Optional; a Frame health bar is easier |

---

## 5. Effect recipes (Parts + built-in textures, no upload)

- **Muzzle flash (first and third person):** an Attachment at the barrel holds
  (a) a ParticleEmitter with `explosion01_implosion_main.dds` (yellow-orange, `LightEmission = 1`, Size 0.6 to 0, Lifetime 0.04-0.07,
  `Rate = 0`, `:Emit(1)`, `LockedToPart = true`) and
  (b) a second emitter with `glow.png` or `sparkles_main.dds` (random Rotation, Size ~0.8) for the cartoon star.
  Add a `PointLight` enabled for ~0.05 s. Optionally a tiny Neon Ball Part for 1 frame.
- **Sparks (bullet hits hard surface):** `SquareParticle.png` at Size 0.06-0.12, yellow, `LightEmission = 1`, Speed 15-25, SpreadAngle 40,
  Acceleration (0,-40,0), Drag 3, Lifetime 0.2-0.35, `:Emit(6-10)`.
- **Impact dust:** `smoke_main.dds`, tinted to the surface colour (`RaycastResult.Instance.Color`), Size 0.4 to 1.2, Transparency 0.4 to 1, Lifetime 0.4.
- **Player hit (no blood, cartoon):** `explosion.png` puff (white or the victim's team colour) + 2-3 `sparkles_main.dds` stars.
  Headshot: bigger, yellow stars + `explosion01_shockwave_main.dds` ring + ding.
- **Explosion (rocket / grenade):** `explosion01_core_main.dds` (fireball) + `explosion01_shockwave_main.dds` (ring) +
  `explosion01_smoke_main.dds` (dark smoke) + `SquareParticle.png` debris.
  Or use the engine `Explosion` instance as **visual only**: set `BlastPressure = 0` (default is 500000!), `DestroyJointRadiusPercent = 0`
  (default is 1, which would kill players!) and `ExplosionType = NoCraters`. The server computes damage itself.
- **Tracers:** a Beam between two Attachments: `Texture = "rbxasset://textures/gradient.png"`, `FaceCamera = true`, `LightEmission = 1`,
  `Width0 = 0.12`, `Width1 = 0.05`, Color = weapon or team colour, fade out over 0.05-0.08 s.
  Fallback with zero texture risk: `Texture = ""` (solid beam) or a thin Neon Part.
  Bullet trails can use a `Trail` with the same texture.
- **Hitmarker / crosshair / damage numbers:** build them from Frames (4 bars + X), TextLabels (FredokaOne/LuckiestGuy + thick `UIStroke`)
  and BillboardGuis. No textures are needed.
- **Kill feed icons:** emoji in TextLabels render with the built-in emoji fonts (`content/fonts/RobloxEmoji.ttf`, `TwemojiMozilla.ttf`, both VERIFIED).
  Example: U+1F3AF "direct hit" for a headshot. Keep the icons cartoon-style.

---

## 6. Sky

| Path (exact) | Status | Notes |
|---|---|---|
| `rbxasset://sky/sun.jpg` | VERIFIED; **engine default of `Sky.SunTextureId`** | Lives in `content/sky/` |
| `rbxasset://sky/moon.jpg` | VERIFIED; **engine default of `Sky.MoonTextureId`** | |
| `rbxasset://textures/sky/sky512_bk.tex`, `sky512_dn.tex`, `sky512_ft.tex`, `sky512_lf.tex`, `sky512_rt.tex`, `sky512_up.tex` | VERIFIED (PC: `PlatformContent/pc/textures/sky/`); **engine defaults of `Sky.Skybox*`** | The default blue Roblox sky. Other platforms have their own PlatformContent (presumably the same files, since they are engine defaults) |
| `rbxasset://textures/sky/indoor512_bk.tex`, `indoor512_dn.tex`, `indoor512_ft.tex`, `indoor512_lf.tex`, `indoor512_rt.tex`, `indoor512_up.tex` | VERIFIED on PC only (not viewed) | Indoor skybox. Not needed |
| `content/sky/clouds.dds`, `cloudDetail*.dds`, `noise*.dds`, `bn.dds`, `cloudAdvection.dds`, `cloudsfb.dds` | VERIFIED | Engine-internal (Clouds/Atmosphere shaders). Do not reference directly |

Recommendation for the bright Roblox look: keep the default `Sky`, then add `Atmosphere`, a `Clouds` instance (in Terrain),
`Lighting.ClockTime ≈ 14`, plus `ColorCorrectionEffect` (Saturation +0.15) and `BloomEffect`. All of these are instances, so no assets are needed.

---

## 7. Fonts: `Enum.Font` (VERIFIED from the 0.742 API dump)

Full list: Legacy, Arial, ArialBold, SourceSans, SourceSansBold, SourceSansLight, SourceSansItalic, Bodoni, Garamond, Cartoon,
Code, Highway, SciFi, Arcade, Fantasy, Antique, SourceSansSemibold, Gotham, GothamMedium, GothamBold, GothamBlack, AmaticSC,
Bangers, Creepster, DenkOne, Fondamento, FredokaOne, GrenzeGotisch, IndieFlower, JosefinSans, Jura, Kalam, LuckiestGuy,
Merriweather, Michroma, Nunito, Oswald, PatrickHand, PermanentMarker, Roboto, RobotoCondensed, RobotoMono, Sarpanch,
SpecialElite, TitilliumWeb, Ubuntu, BuilderSans, BuilderSansMedium, BuilderSansBold, BuilderSansExtraBold, Arimo, ArimoBold, Unknown.

Each local font file and family JSON is VERIFIED in `content/fonts/`. Example: `FredokaOne-Regular.ttf` and
`rbxasset://fonts/families/FredokaOne.json`, usable with `Font.new("rbxasset://fonts/families/LuckiestGuy.json")`.
Glyphs ÄÖÜäöüß€ were checked with fontTools on the **upstream Google Fonts** files, not Roblox's exact copies.

| Use | Enum.Font | Local file | Umlauts | Why |
|---|---|---|---|---|
| Main UI (matches the Meteor Heist UI kit) | `FredokaOne` | yes | already used in German by Meteor Heist | Rounded, chunky, the Roblox look |
| Big banners: "VICTORY", "ROUND 3", killstreak | `LuckiestGuy` | yes | ok | Very bold cartoon caps |
| Pop text: "HEADSHOT!", damage numbers | `Bangers` | yes | ok | Comic-book punch |
| Alternative readable bold | `DenkOne` | yes | ok | |
| Techy HUD: ammo, timer | `Sarpanch` (Bold file), `TitilliumWeb` (Bold file), `Michroma`, `Oswald` (Bold file) | yes | ok (Sarpanch-Bold, TitilliumWeb-Bold, Michroma checked) | Shooter-HUD feel |
| Retro digits | `Arcade` | `PressStart2P-Regular.ttf` is shipped. The Arcade-to-PressStart2P mapping is UNVERIFIED | ok (PressStart2P) | Use sparingly |
| Jitter-free numbers (timers, ammo) | `RobotoMono` / `Code` | `RobotoMono-Regular.ttf` / `Inconsolata-Regular.ttf` | n/a | Monospaced |
| Small body text | `BuilderSans`, `BuilderSansBold`, `BuilderSansExtraBold` | yes | n/a | Roblox's own system UI font |
| **Avoid** | `Gotham*` | **no local file** (GothamSSm is not shipped; Meteor Heist auto-replaces it with FredokaOne) | n/a | Cloud-loaded, old look |
| **Avoid** | `Creepster`, `GrenzeGotisch`, `Antique`, `Legacy` | n/a | n/a | Horror/gothic/legacy, wrong tone |

---

## 8. Mobile / controller UI helpers (all VERIFIED)

- Touch buttons: tint `Disk_padded.png` + `Ring_padded.png`, with icons drawn by `AimStrafeButtonRegular.png` (aim),
  TextLabels "R" / bullet glyphs, or Frames.
- Controller prompts: `UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonR2)` and similar.
- Keyboard prompts: `ui/Controls/key_single.png` + a TextLabel.

---

## 9. Audit: Meteor Heist's existing rbxasset usage

| File:line | Path | Result |
|---|---|---|
| `src/client/Modules/MeteorRun.luau:31` | `rbxasset://sounds/electronicpingshort.wav` | **NOT SHIPPED.** Very likely silent (absent from every manifest since 2018-09). Suggested replacement: `rbxasset://sounds/volume_slider.ogg` with the same pitch logic |
| `src/client/Modules/Bat.luau:27` | `rbxasset://sounds/swordslash.wav` | **NOT SHIPPED.** Very likely silent. Suggested replacement: `rbxasset://sounds/action_jump.mp3` @ ~1.8 (whoosh) or a Config ID |
| `src/client/Modules/Effects.luau:1587` | `rbxasset://sounds/action_jump_land.mp3` | VERIFIED |
| `src/server/Services/CarryService.luau:695` | `rbxasset://sounds/action_jump_land.mp3` | VERIFIED |
| `NestField.luau:784`, `Night.luau:173`, `MeteorFactory.luau:477`, `AlienFactory.luau:1196`, `AlienFactory.luau:1222` | `rbxasset://textures/particles/sparkles_main.dds` | VERIFIED (it is also the engine default) |

The "known to work" assumption only holds for `action_jump_land.mp3` and `sparkles_main.dds`.
To confirm the two broken ones in Studio, play the place and look in Output for a sound-load warning on those paths.

---

## 10. UNVERIFIED summary (test in Studio before relying on these)

1. How the 11 sounds actually sound. They could not be auditioned because the CDN is blocked. All sound recipe numbers are starting values.
2. `rbxasset://sounds/uuhhh.mp3`: referenced by Roblox scripts but not shipped.
3. `gradient.png` orientation on a Beam (expected: bright band along the beam's centre line).
4. The `Enum.Font` to family-file mapping for Arcade / SciFi / Cartoon / Highway / Fantasy / Antique.
5. Mobile/console presence of textures that are **not** used by Roblox's own player scripts or engine defaults
   (`explosion.png`, `glow.png`, `gradient.png`, `sparkle.png`, `whiteCircle.png`, `smallWhiteCircle.png`, `triangle.png`, `SquareParticle.png`, `AimStrafeButton*`, `Disk_padded`, `Ring_padded`).
   They are verified in the desktop package. Always give critical effects a texture-free fallback (Neon Parts, solid Beams, Frames).
6. `AudioTextToSpeech` availability.
7. Any `rbxassetid://` Creator Store IDs. None are listed on purpose.

## 11. Re-verify after a Roblox update

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout --branch roblox \
  https://github.com/MaximumADHD/roblox-client-tracker /tmp/rct
git -C /tmp/rct show HEAD:rbxManifest.csv | tr '\\' '/' | grep -E ',content/(sounds|sky|textures/particles)/'
git -C /tmp/rct show HEAD:version.txt
```
