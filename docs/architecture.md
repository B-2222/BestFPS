# Architecture

Only the decisions that would be expensive to reverse. Everything else is just
code and can be changed when it annoys you.

## Layout

```
scenes/     player.tscn, test_arena.tscn
scripts/
  core/     engine-agnostic building blocks (state machine, settings)
  player/   controller, config, input, camera, movement states
  weapons/  weapon data, runtime, controller, ballistics
  combat/   health, hitboxes, damage, noise
  bots/     profile, senses, brain, director, bot states
  audio/    synthesised sound bank and the director that plays it
  levels/   the procedural test blockout
  ui/       debug HUD, combat HUD, settings menu
  tests/    headless behavioural checks
assets/     config/  player, weapons/*.tres, bots/*.tres
docs/       this, engine-choice.md, movement-tuning.md,
            networking-decision.md
```

---

## 1. Input is data, not a global read

`InputCommand` is one tick of intent as a value. The movement code reads only
that struct and never touches the `Input` singleton.

```
PlayerInput  ─┐
BotBrain     ─┼─→ InputCommand ─→ PlayerController ─→ motion
NetReceiver  ─┘      (M3)              (M5)
```

Three things depend on this and all three are expensive to retrofit:

- **Bots (M3)** drive the same movement code, so they move like players by
  construction rather than via a second implementation that drifts.
- **Remote players (M5)** are simulated by replaying received commands.
- **Client-side prediction (M5)** must re-simulate a *range* of past ticks after
  a server correction. That is only possible if a tick's input is a value you can
  store and replay.

It also pays off immediately: the smoke test drives the controller by writing
commands directly. That test could not exist otherwise.

Look is carried as **absolute yaw/pitch, not mouse deltas** — deltas are
frame-rate dependent and unreplayable.

## 2. Movement uses acceleration + friction, not lerp-to-target

Most Godot controllers do `velocity = velocity.lerp(target, weight)`. That ties
stopping distance to current speed: the character floats when fast and feels
sticky when slow, and you cannot fix one without breaking the other.

Quake's model splits them. `accelerate()` only ever adds speed *along* the wish
direction and only up to the target, while friction is applied separately. So
"leaves the ground instantly" (`ground_accel`) and "stops on a dime"
(`friction`, `stop_speed`) are independent dials. That separation is most of why
Quake and CS feel tight.

Air control is the same function with the target clamped to `air_speed_cap`
while the *rate* still scales with full speed. That asymmetry is what makes air
strafing work: push sideways while turning and the cap keeps resetting.

## 3. A state machine, not a pile of flags

Movement states (`grounded`, `air`, `slide`) are separate classes. Adding a
wall-run or a mantle is a new file, not an edit to a growing conditional.

Two details that are load-bearing:

- **States are `RefCounted`, not `Node`.** Cheap per actor, no scene-tree
  overhead, and re-runnable — which is what prediction needs in M5.
- **`check_transitions()` decides whether to leave; `physics_update()` does the
  work.** Splitting them prevents the classic FSM bug where a state mutates the
  world and then exits in the same tick, leaving its successor to clean up.

The `machine` back-pointer on `State` is a `WeakRef`. GDScript reference
counting has no cycle collector, so a strong back-pointer would leak the machine
and every state for each actor ever freed. This was caught by Godot's
leak report at exit, not by inspection.

`StateMachine` deliberately knows nothing about players or nodes, so M3's bot AI
reuses it.

## 4. Tuning lives in a Resource

`PlayerConfig` is a `Resource`, not a set of constants, so values can be changed
in the inspector **while the game is running** and saved as named presets to A/B
without touching code. Feel is found by tweaking, not by reasoning.

The defaults live in `player_config.gd` and `player_default.tres` is empty of
overrides, so there is exactly one source of truth and a diff shows precisely
which dial moved.

## 5. The rendered camera is not the aim origin

```
Player ─ Head ─┬─ AimPoint    ← authoritative; weapons fire from here
               └─ CameraArm   ← bob, dip, lean, FOV, and later recoil
                    └─ Camera3D
```

View effects compose additively onto the camera and never touch `AimPoint`. If
weapons fired from the rendered camera, tuning head bob would silently change
where bullets land — and that class of bug is miserable to find months later.
`get_aim_transform()` is the only thing weapon code should ever use.

The rig runs in `_process`, not `_physics_process`: view effects should be
smooth at display refresh, not quantised to the 120 Hz simulation. Mouse look is
applied the instant the event arrives for the same reason.

## 6. The player hull is a cylinder

This one was discovered empirically and cost real debugging time.

Godot's `CharacterBody3D` has no built-in stair handling, so `_step_up()` does
the standard up / forward / probe-down test. With a **capsule** it never worked:
a rounded bottom contacts a step *below its hemisphere equator*, so the
down-probe returns the step's vertical face (78° from vertical — a wall, not a
floor) and the body would need roughly its own radius of forward travel before
it was ever supported.

Flat-bottomed hulls are why Quake and Source step cleanly. Switching to
`CylinderShape3D` fixed it immediately: the contact point and the bottom face's
leading edge coincide, so the body is supported the moment it moves forward at
all.

Second trap in the same function: **every probe passes an explicit 0.001
collision margin.** `test_move()` defaults to 0.08 m, which is enormous next to a
stair — clearing a 0.35 m step by exactly 0 m reads as a collision and the step
is silently rejected. `can_stand_up()` has the same fix for the same reason.

`floor_snap_length` must stay `>= max_step_height`, or walking *down* stairs
turns into a rattle. There is a test for this.

## 7. Physics at 120 Hz

The camera is a child of the physics body, so at 60 Hz the world visibly steps on
a high-refresh monitor. 120 Hz halves that without needing physics interpolation.

**Known coupling, flagged now:** Quake-style air acceleration gains speed per
*tick*, so air-strafe acceleration scales with tick rate. The current values are
tuned at 120 Hz. If the tick rate changes, air control changes with it — and in
M5 this becomes a correctness issue, because client and server must simulate at
the same rate.

## 8. The browser build has three hard constraints

`.github/workflows/web.yml` exports a WebAssembly build on every push and
publishes it to GitHub Pages, gated on the smoke test. Three constraints shaped
how it is configured, and each one fails at *runtime* rather than at export,
which is exactly the kind of thing to write down.

**No threads.** A threaded Godot web build needs `SharedArrayBuffer`, which
needs the page to be cross-origin isolated, which needs `Cross-Origin-Opener-Policy`
and `Cross-Origin-Embedder-Policy` response headers. **GitHub Pages cannot send
custom headers.** So the preset sets `variant/thread_support=false` and Godot
links the `web_nothreads` template instead. Verified in a real browser over
plain HTTP: `crossOriginIsolated === false` and the engine boots anyway. The
workflow fails the build if `index.worker.js` ever appears, because that file
means a threaded build slipped through and it would only break for players.

**No Vulkan.** Forward+ is desktop-only, so `rendering_method.web` is
`gl_compatibility`. Anything Forward+ exclusive has to be guarded rather than
merely configured — SSAO is switched on only when
`RenderingServer.get_rendering_device()` is non-null, or the Compatibility
renderer logs a warning on every launch.

**Pointer lock needs a user gesture.** The browser refuses the mouse capture
that `PlayerInput._ready()` requests, and `fill_command()` deliberately returns
empty input while the mouse is free — so without an explanation the game looks
frozen. That is what `CapturePrompt` is for, and why it polls mouse mode rather
than listening to our own input code: the browser also drops pointer lock on
tab switch and focus loss, and none of that routes through us.

The desktop build remains the reference for feel. WebGL and pointer lock both
add latency, and Milestone 1 is being judged on latency.

## 9. The test level is an instrument

`arena_builder.gd` builds the blockout procedurally from a table of dimensions
rather than from hand-placed nodes. The level exists to *measure* the controller
— "is a 0.35 m ledge a step or a wall", "can I clear a 4 m gap" — and numbers in
a table are easier to trust and change than nodes dragged in a viewport. Every
obstacle is labelled in-world with its dimension.

M4 replaces it with a handcrafted map. This one is a tool, not a level.

---

## 10. Bots press buttons; they do not have powers

A bot is a `PlayerController` with a `BotBrain` where the player has a
`PlayerInput`. Both answer the same call:

```gdscript
func fill_command(cmd: InputCommand, delta: float) -> void
```

That is the whole integration. A bot has no private movement path, no direct
call into `WeaponController`, and no way to make a shot happen that is not
"set `fire_held` and wait for the weapon to be ready". The consequences are
structural rather than a matter of discipline:

- A bot accelerates, jumps, slides and bunny-hops on exactly the movement code
  you do, because there is only one copy of it.
- A bot cannot fire faster than the weapon's rate, skip a reload, or ignore
  spread, because the weapon controller does not know or care who filled the
  command.
- Any weapon tuning change applies to bots on the same commit, with no second
  place to update.
- In M5 the same brain runs on a server that never renders it, and a replayed
  network command and a bot's command are the same kind of thing.

One consequence bites, and it is worth knowing about: the command is a value
that lives on the controller between ticks, so a brain that only writes the
fields it cares about leaves the rest set from last tick. `BotBrain` clears the
command every tick before its states touch it. Without that, one shot fired
leaves `fire_held` true forever and the bot shoots through walls in every fight
afterwards — which is exactly what happened, and what the bot suite now
watches for.

### Fairness is the design, not a setting

Everything a bot knows comes through `BotSenses`, and every channel into it is
one a human also has: a view cone, a line-of-sight trace against world geometry
only, hearing scaled by how loud the thing was, and a last-known position that
expires. Difficulty is made out of reaction time, turn speed, aim error and
burst discipline — never out of extra information.

This is a deliberate rejection of the cheap way to make hard bots. Giving them
perfect tracking and knowledge through walls is much less work and produces
opponents that feel like cheats: you cannot learn to beat them, only to avoid
them. Making difficulty out of human quantities means a hard bot is doing
something you could learn to do too, and the counterplay — break line of sight,
flank the cone, be quiet, strafe — is real counterplay rather than a trick.

Those claims are testable, which is the point of stating them so precisely.
`scripts/tests/bot_smoke_test.gd` asserts that a bot cannot see through a
pillar and does not shoot at one, cannot see a target standing behind it,
spends its reaction time before firing, hears gunfire but not from across the
map, forgets a target it has lost, and fires no faster than its weapon allows.
Fairness bugs are invisible by feel — losing to a bot that cheats feels exactly
like losing to a good one — so they have to be caught by assertion.

### Hunting a memory, not a position

`BotHuntState` paths to `senses.last_known_position`, never to the target's
live one. The distinction is the single clearest tell in AI: a bot that walks
straight to where you actually are, through geometry it cannot see through, is
visibly cheating. It also matters mechanically — breaking line of sight is
most of what positioning is *for*, and it only means something if the bot can
actually be lost.

### Difficulty as data

`BotProfile` is a `Resource`, so a tier is a `.tres` file and a new one is not
a code change. `BotDirector` holds a reference rather than copying values out,
which is why difficulty can be changed mid-match from the settings menu and
takes effect on the next tick without respawning anyone.
