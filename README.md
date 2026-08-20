# BestFPS

A first person shooter built from scratch in Godot 4, prioritising movement feel,
gunplay and bots — in that order.

**[▶ Play it in your browser](https://b-2222.github.io/BestFPS/)**

[![Web build](https://github.com/B-2222/BestFPS/actions/workflows/web.yml/badge.svg)](https://github.com/B-2222/BestFPS/actions/workflows/web.yml)

**Current state: Milestone 1 — movement only.** No weapons, no enemies, no
sound. That is deliberate; see [ROADMAP.md](ROADMAP.md).

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

## Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D` | Move |
| Mouse | Look |
| `Space` | Jump |
| `Shift` | Sprint |
| `Ctrl` / `C` | Crouch (hold) |
| `Shift` + `Ctrl` while moving | Slide |
| `R` | Respawn at spawn point |
| `F3` | Toggle the tuning HUD |
| `F1` | Slide on/off (try both — see below) |
| `F2` | Auto bunny-hop on/off (try both — see below) |
| `Esc` | Release the mouse (click to recapture) |

## The test level

A measured blockout, not a map. Every obstacle is labelled in-world with its
dimension so feedback can be specific. Sections bracket the controller's limits
on purpose — 0.35 m and 0.40 m ledges either side of the step limit, 45° and 55°
ramps either side of the walkable angle, gaps from 2 m to 6 m.

**If you only do one thing:** press F3 and work through the ten tests in
[docs/movement-tuning.md](docs/movement-tuning.md).

## Tuning it yourself

Open `assets/config/player_default.tres` in the inspector and edit values **while
the game is running**. Every number that decides how the player feels is in that
one resource. Full guide: [docs/movement-tuning.md](docs/movement-tuning.md).

## Tests and CI

```
godot --headless --path . --script scripts/tests/movement_smoke_test.gd
```

18 behavioural checks — top speed, deceleration, jump apex against
`v²/2g`, stair climb and descent, the step-height limit, crouch, and slide.
Exits non-zero on failure, ready to wire into CI.

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
