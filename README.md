# BestFPS

A first person shooter built from scratch in Godot 4, prioritising movement feel,
gunplay and bots — in that order.

**Current state: Milestone 1 — movement only.** No weapons, no enemies, no
sound. That is deliberate; see [ROADMAP.md](ROADMAP.md).

---

## Running it

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

## Tests

```
godot --headless --path . --script scripts/tests/movement_smoke_test.gd
```

18 behavioural checks — top speed, deceleration, jump apex against
`v²/2g`, stair climb and descent, the step-height limit, crouch, and slide.
Exits non-zero on failure, ready to wire into CI.

Feel is not testable and has to be judged by hand. These cover the things that
*are* objective and that break silently when a tuning value is edited.

## Layout

```
scenes/   player and level scenes
scripts/  core/ player/ levels/ ui/ tests/
assets/   config/ (art lands here later)
docs/     engine choice, architecture, tuning guide
```

## Documentation

- **[ROADMAP.md](ROADMAP.md)** — milestones and exit criteria
- **[docs/engine-choice.md](docs/engine-choice.md)** — why Godot + GDScript, what
  we give up by not using Unity, and the risk register
- **[docs/architecture.md](docs/architecture.md)** — the decisions that would be
  expensive to reverse
- **[docs/movement-tuning.md](docs/movement-tuning.md)** — what every dial does
  and how to test it
