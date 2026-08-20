# Tuning the movement

Everything here lives in `assets/config/player_default.tres`, which you can edit
**while the game is running**. Changes apply on the next physics tick.

1. Run the game (F5)
2. Alt-tab to the editor, open `player_default.tres` in the inspector
3. Change a value, alt-tab back, feel it
4. Keep what works — `Ctrl+S` on the resource pins it

Press **F3** for the HUD. The speed graph is the instrument that matters: a sharp
rise to a plateau means acceleration is right; a slow ramp means `ground_accel`
is too low; a spike that sags means `friction` is fighting it.

---

## Test protocol

Do these in order. They map onto the labelled sections of the arena, and each one
isolates one thing.

**1. The sprint lane (straight ahead from spawn).**
Just run it. At 9 m/s the 30 m mark should arrive in about 3.3 s. Is that fast
enough to feel good, or does the world feel like treacle?

**2. Start and stop, repeatedly, on the open floor.**
Tap forward and release. Watch the speed graph. Does the character feel like it
has weight, or like it is on ice? Does it stop where you expect, or slide past?

**3. Strafe course (northwest pillars).**
Weave through them at speed. Can you keep speed through a turn? Does changing
direction feel crisp or mushy?

**4. Step-up limit (just east of spawn).**
Walk into 0.20, 0.30, 0.35, 0.40. The first three should be walked over without
noticing. The red one should stop you dead. Anything that feels like a
"catch" — you slow but do not climb — is a bug; tell me.

**5. Staircases (northeast).**
Walk up and down all four. Two things to judge: does the camera jolt on each
step (raise `view_step_smooth_time`), and does walking *down* feel glued or
bouncy?

**6. Jump heights (east).**
Jump onto 0.60, 0.90, 1.10, 1.25, 1.40. 1.10 should be comfortable, 1.25 should
be impossible. If 1.10 feels like a coin flip, the jump is under-tuned.

**7. Gap jumps (southeast walkway).**
Predicted from the current numbers, and worth verifying by hand:
2 m and 3 m trivially; 4 m from a walk; 5 m needs a sprint; 6 m needs a sprint
*and* air steering. If 6 m is impossible, `air_speed_cap` is too low for the map
scale — or the gap is a good hard limit. Your call, but tell me which.

**8. Ramps (south).**
Walk up 15°, 30°, 45°. All three should be smooth, with no stutter or speed loss
at the transition from floor to ramp. 55° (red) should refuse you.

**9. Slide slope (west).**
Walk up, turn around, sprint down and crouch. The slide should clearly beat
running. Then try sliding on flat ground — it should feel like a burst that ends,
not a mode you live in.

**10. Crouch tunnel (southwest).**
Crouch through it. Try releasing crouch inside — you should stay crouched. Try
sliding into it at speed.

---

## The dials

### Ground

| Value | Default | What it does | What "wrong" feels like |
|---|---|---|---|
| `walk_speed` | 6.5 | Baseline speed | Too low reads as sluggish and makes sprint mandatory |
| `sprint_speed` | 9.0 | Sprint speed | Too high makes walking feel pointless |
| `ground_accel` | 12.0 | How fast you reach target speed (~80 ms) | Low = wading; very high = twitchy, no weight |
| `friction` | 8.0 | How fast you stop | Low = ice; high = velcro, no momentum |
| `stop_speed` | 2.0 | Minimum friction reference | Too low = a mushy last half-metre right when you are planting to aim |

### Air and jump

| Value | Default | What it does |
|---|---|---|
| `gravity` | 22.0 | Real gravity (9.8) feels floaty; shooters use ~2x |
| `jump_velocity` | 7.0 | Apex = `v²/2g` = **1.11 m**, airtime 0.64 s |
| `air_speed_cap` | 2.0 | **The air-control character dial.** ~0.8 = CS (almost none), ~4 = Quake (strafe jumping) |
| `air_accel` | 22.0 | How hard the cap is pushed against |
| `coyote_time` | 0.10 | Jump grace *after* leaving a ledge |
| `jump_buffer_time` | 0.12 | Jump grace *before* landing |

Coyote time and jump buffering are invisible when present and infuriating when
absent. If you want to feel what they do, set both to 0 and play for a minute.

### Slide

`slide_slope_boost` (1.4) is the interesting one: above 1.0 a downhill slide
accelerates, which is the whole reason slides are fun on a map with elevation.
`slide_steer` (3.0) only redirects existing speed and never adds any, so steering
trades heading for nothing.

### Camera

| Value | Default | Notes |
|---|---|---|
| `view_bob_frequency` | 0.35 | Cycles **per metre**, not per second, so bob stays in step with the stride at every speed and stops dead when you do |
| `view_bob_amount_v` | 0.045 | The single most common thing to overdo |
| `view_land_dip_scale` | 0.0040 | Impulse scales with impact speed. Calibrated so a jump dips ~5.5 cm and a 10 m fall ~17 cm |
| `view_strafe_tilt_deg` | 1.1 | Under ~1.5° reads as weight; above, as a bug |
| `view_step_smooth_time` | 0.10 | Raise if stairs jolt, lower if they feel laggy |
| `mouse_sensitivity` | 0.0022 | Radians per pixel |

Bob is the effect most likely to annoy you. `view_bob_enabled = false` turns it
off entirely — try both.

---

## Presets to try

Change these together, not individually. Each is a coherent identity.

**Arena / Quake** — fast, high skill ceiling, movement is the game:
```
walk_speed 8.0   sprint_speed 8.0   air_speed_cap 4.0   air_accel 30
friction 6.0     auto_bhop true     slide_enabled false
```
(Sprint equal to walk means one speed, which is the arena convention.)

**Tactical / CS** — slow, deliberate, aiming is the game:
```
walk_speed 5.0   sprint_speed 6.5   air_speed_cap 0.8   air_accel 12
friction 10.0    ground_accel 16.0  slide_enabled false
view_bob_amount_v 0.02
```

**Movement shooter / Titanfall** — this is roughly where the defaults sit:
```
walk_speed 6.5   sprint_speed 9.0   air_speed_cap 2.0
slide_enabled true   slide_slope_boost 1.6
```

---

## Two identity questions, not tuning questions

Play both ways before answering.

**Slide.** Implemented and on by default. It rewards reading terrain and gives
elevation meaning. It also pushes toward a faster, more mobile game, which
changes map design and makes bots harder to write. `slide_enabled = false`.

**Bunny hopping.** `auto_bhop = false` today. Setting it true lets a player hold
jump and keep speed indefinitely, which is a huge skill ceiling and a huge
barrier to new players. It is the single biggest fork in this game's identity.

---

## What I need from you

Rough notes are fine — "3 feels floaty", "stairs jolt" is plenty.

1. Which of the ten tests felt wrong, and in which direction?
2. Does the base speed feel right, or should everything be faster/slower?
3. Is the camera bob invisible, pleasant, or annoying?
4. Slide: keep, cut, or change?
5. Auto-bhop: try it on for five minutes. Keep?
6. Anything that felt like the game ignored an input you gave it? Those are bugs,
   not tuning, and I want to hear about them first.
