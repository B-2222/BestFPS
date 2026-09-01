# BestFPS

A first person shooter built from scratch in Godot 4, prioritising movement feel,
gunplay and bots — in that order.

**[▶ Play it in your browser](https://b-2222.github.io/BestFPS/)**

[![Web build](https://github.com/B-2222/BestFPS/actions/workflows/web.yml/badge.svg)](https://github.com/B-2222/BestFPS/actions/workflows/web.yml)

**Current state: Milestone 2 — movement and four weapons.** A shooting range
with targets at measured distances, and no enemies that shoot back yet. See
[ROADMAP.md](ROADMAP.md).

![The movement test arena](docs/images/test-arena.png)

*The test blockout. Every obstacle is labelled with its dimension — here the
0.25 m and 0.35 m staircases are climbable and the 0.45 m one is deliberately
not.*

---

## Running it

### In a browser

<https://b-2222.github.io/BestFPS/> — click the page to capture the mouse, then
play. Needs WebGL 2, which every current desktop browser has. First load pulls
about 11 MB (a 44 MB WebAssembly runtime, served compressed) and takes a few
seconds.

Every push rebuilds and redeploys it automatically, and the build only ships if
the movement smoke test passes.

Expect it to feel slightly worse than the desktop build: browsers run the
Compatibility (WebGL) renderer rather than Forward+, and mouse input goes
through pointer lock. **Judge the movement feel on desktop**, not here.

> Already live — the first deploy succeeded, so nothing needs configuring. If
> the link ever 404s, check **Settings → Pages → Build and deployment** is still
> set to source **"GitHub Actions"**; that is the one setting a workflow cannot
> set for itself.

### On desktop

1. Install **Godot 4.4** or newer (standard build, not .NET) — <https://godotengine.org/download>
2. Open the project: `Import` → select `project.godot`
3. Press **F5**

First launch takes a moment while Godot imports and builds its class cache.

### If Godot crashes

Godot 4 defaults to the **Forward+** renderer, which hard-requires a working
Vulkan driver and dies rather than falling back when there isn't one. That is
the most common reason it crashes on laptops, integrated GPUs and managed
school machines.

**This project is already set to the Compatibility (OpenGL) renderer** for
exactly that reason, so pull the latest code before trying again — the fix is
in `project.godot` and only applies once you have it.

If it still crashes:

1. **Launch Godot itself in OpenGL mode.** The Project Manager runs before it
   reads any project setting, so a Vulkan crash there needs a command-line
   flag. Windows: `Godot_v4.4.1-stable_win64.exe --rendering-driver opengl3`
   (or add ` --rendering-driver opengl3` to the end of a shortcut's *Target*).
   macOS/Linux: same flag from a terminal.
2. **Update your graphics drivers**, then try Forward+ again.
3. **Check where it dies** — on the Project Manager, on import, on opening the
   3D scene, or on pressing F5. That distinction says which of the above is
   the culprit.

You do not need the editor to make progress. Every change is built and
verified in CI, and the browser build above is always current.

## Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D` | Move |
| Mouse | Look |
| `Space` | Jump |
| `Shift` | Sprint |
| `Ctrl` / `C` | Crouch (hold) |
| `Shift` + `Ctrl` while moving | Slide |
| Left mouse | Fire |
| Right mouse | Aim down sights |
| `R` | Reload |
| `1`–`4` / wheel | Switch weapon |
| `Backspace` | Respawn at spawn point |

Every binding in that table can be changed in the settings menu (`Esc`), and
your choices persist between sessions. Master volume and mouse sensitivity are
there too — both worth turning down on a laptop.

### Sound

All of it is **synthesised at load**, not loaded from files: gunshots are
filtered noise plus a pitch-swept body, footfalls and impacts are damped low
noise, and interface blips are swept sines. Each weapon gets its own character
from four numbers. There are no audio files in this repo and no licence
attached to any of it — see `scripts/audio/sound_bank.gd`. Real recordings
replace the streams later without touching anything that plays them.
| `F3` | Toggle the tuning HUD |
| `F1` | Slide on/off (try both — see below) |
| `F2` | Auto bunny-hop on/off (try both — see below) |
| `Esc` | Settings — rebind any key, adjust volume and mouse sensitivity |

## The test level

A measured blockout, not a map. Every obstacle is labelled in-world with its
dimension so feedback can be specific. Sections bracket the controller's limits
on purpose — 0.35 m and 0.40 m ledges either side of the step limit, 45° and 55°
ramps either side of the walkable angle, gaps from 2 m to 6 m.

**If you only do one thing:** press F3 and work through the ten tests in
[docs/movement-tuning.md](docs/movement-tuning.md).

### The weapons

Four roles, balanced against each other rather than in isolation. Every number
lives in `assets/config/weapons/*.tres` and can be edited without touching code.

| | Damage | Head | Rate | Mag | Body shots to kill | Notes |
|---|---|---|---|---|---|---|
| **Rifle** `1` | 22 | 2.2x | 600 rpm, auto | 30 | 5 (0.40 s) | The baseline everything else is tuned against |
| **Shotgun** `2` | 13 x 9 pellets | 1.5x | 75 rpm | 6 | 1 up close | Useless past ~18 m; falls to 28% damage |
| **Sniper** `3` | 88 | 2.6x | 45 rpm | 5 | 2 — **1 headshot** | Sights through a real scope: the weapon is hidden and the screen becomes the optic. Pinpoint aimed, wild from the hip; slowest to carry |
| **Pistol** `4` | 18 | 2.4x | 420 rpm | 15 | 6 | Fastest to draw (0.25 s) and the only one that does not slow you down |

They differ in more than damage: movement speed, aim-down-sights zoom, reload
and equip times, spread while moving, and recoil are all per-weapon. Recoil is
deliberately mild on all four — sustained climb stays under 2.1 deg/s, which a
trackpad can still counter, and a test enforces that ceiling.

### The shooting range

Along the north wall. Targets at 10, 20, 30 and 45 m, fanned sideways so the
near one does not block the far ones, plus a strafing target at 55 m. Each
dummy shows its own health, has an orange head worth 2.2x damage, and revives
three seconds after it goes down.

Shots leave bullet holes on walls and floors that fade after about nine
seconds, tracers are drawn from the barrel rather than the camera, and the
crosshair gap is the **real spread cone** converted to pixels, so it shows
exactly where a bullet can land — it grows while you move and while you hold
the trigger, and shrinks when you aim.

## Tuning it yourself

Open `assets/config/player_default.tres` in the inspector and edit values **while
the game is running**. Every number that decides how the player feels is in that
one resource. Full guide: [docs/movement-tuning.md](docs/movement-tuning.md).

## Tests and CI

```
godot --headless --path . --script scripts/tests/movement_smoke_test.gd
```

```
godot --headless --path . --script scripts/tests/combat_smoke_test.gd
```

42 behavioural checks across the two suites. Movement: top speed,
deceleration, jump apex against `v²/2g`, stair climb and descent, the
step-height limit, crouch, slide, and the bunny-hop speed bounds. Combat: fire
rate, damage, falloff, headshot reward, time-to-kill, reload, recoil recovery,
and that spread is reproducible from the command tick. Both exit non-zero on
failure.

Feel is not testable and has to be judged by hand. These cover the things that
*are* objective and that break silently when a tuning value is edited.

`.github/workflows/web.yml` runs the same test on every push and gates the web
deploy on it, so a broken build never reaches the play link.

## Layout

```
scenes/   player and level scenes
scripts/  core/ player/ levels/ ui/ tests/
assets/   config/ (art lands here later)
docs/     engine choice, architecture, tuning guide
.github/  web build + Pages deploy workflow
```

## Documentation

- **[ROADMAP.md](ROADMAP.md)** — milestones and exit criteria
- **[docs/engine-choice.md](docs/engine-choice.md)** — why Godot + GDScript, what
  we give up by not using Unity, and the risk register
- **[docs/architecture.md](docs/architecture.md)** — the decisions that would be
  expensive to reverse
- **[docs/movement-tuning.md](docs/movement-tuning.md)** — what every dial does
  and how to test it
- **[docs/networking-decision.md](docs/networking-decision.md)** — the
  multiplayer model, and what it forces on the weapon code today
