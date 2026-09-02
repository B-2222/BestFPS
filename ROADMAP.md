# Roadmap

Milestones are ordered by your pillars, with one deliberate exception explained
in M2. Every milestone ends in something you can launch and play — if a
milestone cannot be played, it is too big and needs splitting.

**Current position: M3 in progress, awaiting a verdict on the bots.** Movement
is signed off. All four weapons, the shooting range and the sound pass are in.
Bots spawn, fight, and can be turned up, down or off from the settings menu --
and the duel wing exists so each difficulty can be judged on its own rather
than in whatever scrap the arena is having.

| | Milestone | State |
|---|---|---|
| M0 | Foundations | Done |
| M1 | Movement and feel | Done — signed off |
| M2 | Gunplay + networking spike | Done — four weapons, optic, sound, spike |
| M3 | Bots | **In progress** — senses, states, difficulty, duel wing |
| M4 | The arena | Not started |
| M5 | Multiplayer | Not started |
| M6 | Polish | Not started |

---

## How milestones work

- **Nothing starts until the previous milestone is signed off by you playing it.**
  Feel cannot be reviewed from a diff.
- Each milestone lists **exit criteria** that are demonstrable, not aspirational.
- Anything genuinely risky is called out in the milestone that first touches it,
  not when it explodes.
- Commits stay small and meaningful. Before a large architectural change, the
  working state is committed first so it can be rolled back.

---

## M0 — Foundations *(done)*

Repository structure, Godot 4.4 project, physics layers, `.gitignore`,
`.gitattributes`, engine decision recorded as an ADR.

Also delivered: a **headless smoke test** (`scripts/tests/movement_smoke_test.gd`)
that runs without a display and exits non-zero on failure. It exists this early
because it is the thing GitHub Actions will run later, and because tuning values
are exactly the kind of thing that breaks silently.

CI is now wired up: `.github/workflows/web.yml` runs that test on every push and,
on the default branch, exports a WebAssembly build and publishes it to GitHub
Pages so the current state is playable from a link. The deploy is gated on the
test, so a broken build never reaches the link.

---

## M1 — Movement and feel *(awaiting feedback)*

**Goal:** first-person movement that feels good enough that you would play it
with no weapons, no enemies and no objective.

**Delivered:**
- Quake/Source-style acceleration model with independent ground friction
- Walk, sprint, crouch (with headroom checks), air control with a tunable cap
- Coyote time and jump buffering
- A committed slide that accelerates downhill and can be jumped out of
- Stair stepping, including refusing steps that are too tall
- Camera rig: head bob tied to distance travelled, landing dip on a damped
  spring, strafe lean, speed-linked FOV, stair-step smoothing
- A measured test arena — every obstacle labelled with its dimension
- A tuning HUD with a live speed graph
- 18 headless behavioural checks, all passing

**Exit criteria — all met:**
- [x] Played and accepted: speed, stopping, jump height and camera bob all
      confirmed good as tuned
- [x] Everything runs with no errors and the smoke test passes (22 checks)
- [x] Tuning values settled well enough to build weapons against

**What is deliberately absent:** weapons, health, enemies, sound, menus.

### Decisions made here, that everything downstream inherits

**Slide: kept.** Elevation now has tactical meaning, and the map in M4 has to
be built with slide lines in mind rather than having them retrofitted.

**Bunny hopping: kept** (`auto_bhop = true`). This is the largest single
decision in Milestone 1 and it reaches into three later milestones:

- Strafe jumping accelerates without a natural ceiling in the Quake model.
  Measured at 23 m/s and still climbing after 8 s of clean strafing, against a
  9 m/s sprint. `max_air_speed` now caps it at 16 m/s (~1.8x sprint), which
  ordinary play never touches — a medium-quality turn tops out near 13.
- **M3 (bots)** must contest a player moving at up to 16 m/s. Bots run the same
  movement code so they *can* bhop; whether they should, and at which
  difficulty tiers, is a deliberate choice rather than an accident.
- **M4 (the map)** has to be scaled for 16 m/s traversal, not 9 m/s. Sightlines
  and rotation timings both change.
- **M5 (netcode)** has to lag-compensate a target moving at 16 m/s. Speed
  directly increases how far a target travels per tick, and so how much
  rewind accuracy matters.

Regression tests now pin all three properties: straight-line bhop must not beat
sprinting, strafe jumping must beat it, and sustained strafe jumping must stay
under the cap.

---

## M2 — Gunplay + networking spike

**Goal:** shooting feels good against a static target, with four weapons that
are genuinely distinct.

**Scope:**
- Weapon architecture: a resource-driven definition (fire rate, damage,
  falloff, recoil pattern, spread, reload time, magazine) so a new weapon is
  data plus a model, not a new class
- Hitscan and projectile support behind one interface
- Four weapons chosen for *distinct roles*, not variety: rifle (baseline),
  shotgun (close burst), sniper (commitment), pistol (fast, low damage)
- Recoil as an additive camera layer on top of the existing rig, with a
  learnable pattern rather than random spray
- Reload states, ammo, weapon switching with real switch times
- Damageable targets with hitboxes on their own physics layer, headshot
  multipliers, and a TTK table

**Exit criteria:**
- Shooting a target dummy in the test arena is satisfying without any HUD
- The four weapons feel different from each other in the hand, not on a stat card
- TTK is written down and deliberate, not emergent

### Delivered so far

- Networking decision, written up as [docs/networking-decision.md](docs/networking-decision.md)
- Weapon architecture: weapons are `.tres` data over one runtime, so the
  remaining three are numbers and a model rather than new classes
- Hitscan with deterministic, tick-seeded spread; damage falloff; an authored
  recoil pattern that moves the real aim and then recovers
- Health, hitboxes on their own physics layer, and per-tick hitbox history
- A shooting range with targets at measured distances
- Tracers, impacts, damage numbers, hit markers, and a crosshair that shows
  the true spread cone
- A working optic on the sniper: the weapon is hidden and the screen becomes
  the scope, rather than the receiver being parked in front of the camera
- Sound, synthesised at load rather than shipped as files. Hooking it up
  touched no gameplay code, because the controllers were already announcing
  everything worth hearing
- 50 combat checks in CI, gating the deploy

Rifle baseline: 22 damage, 2.2x on the head, 600 rpm — **5 body shots and
0.40 s to kill**, or 3 headshots. The other three weapons get tuned against
that number rather than in isolation.

### Still to come in M2

- Real weapon models. The placeholders are boxes, one silhouette per weapon.

  **Sourcing, since it came up:** [Quaternius](https://quaternius.com/) and
  [Kenney](https://kenney.nl/) both publish CC0 (public domain, no attribution
  required, commercial use fine) low-poly weapon packs in glTF, which is the
  format Godot imports best. Those are the two to start from. They could not be
  downloaded from this environment -- the network policy blocks them -- and
  they are worth holding until there is a decision about whether the game keeps
  the grey-box look, because a realistic rifle against untextured boxes looks
  worse than a box that matches. The `view_shape` field already keys
  presentation off the weapon, so swapping a box for a mesh is contained.
- **Attachments** *(requested)* — a scope, grip, barrel or stock should change
  how the gun actually behaves: recoil, damage and therefore TTK, handling
  feel, and movement speed. Not cosmetic.

  The architecture already suits this and it should stay a contained addition,
  so writing down the intended shape now: an `AttachmentResource` carries a set
  of modifiers, and equipping a weapon builds an *effective* `WeaponResource`
  by duplicating the base and folding each attachment's modifiers into it.
  Attachments only change in a loadout screen, never mid-burst, so this costs
  one computation per equip and **nothing changes in the per-shot path** —
  `WeaponRuntime` keeps reading a single resource and does not learn that
  attachments exist.

  Movement speed is already wired: `WeaponResource.move_speed_multiplier` feeds
  `PlayerController.speed_multiplier` every tick, so a heavy barrel slowing the
  player needs no new plumbing.

  The real design risk is not code, it is balance — attachments that are
  strictly better are just a tax on players who have not unlocked them. Each
  one should trade something.

### The networking spike *(the deliberate exception to pillar order)*

Also in M2, before weapons are finalised: **a written decision on the
multiplayer model, and a throwaway prototype proving prediction works.**

This is out of pillar order on purpose. Hit registration design depends entirely
on whether the server is authoritative and whether we lag-compensate — and those
decisions are cheap now and extremely expensive once four weapons, bots and a map
are built against the wrong assumption. The prototype gets thrown away; the
decision does not.

**Risk:** this is the highest-risk item in the project. See
`docs/engine-choice.md`.

---

## M3 — Bots

**Goal:** bots that are worth playing against, built so they can be extended.

**Scope:**
- Behaviour tree or hierarchical FSM (the existing `StateMachine` is already
  actor-agnostic and reusable here)
- Navigation with hand-authored links for jumps and drop-downs
- Senses as a real system: line of sight with a view cone, hearing driven by
  gunfire and footsteps, and a memory of last-known-position — so bots lose you
  rather than tracking you through walls
- Tactical behaviour: use cover, flank, retreat at low health, reload in safety
- Difficulty tiers driven by reaction time, accuracy and aggression, **never by
  giving bots information the player cannot have**
- Bots drive the same `PlayerController` through `InputCommand`, so they are
  bound by the same movement rules the player is

**Exit criteria:**
- A 1v1 against a mid-tier bot in the test arena is genuinely fun
- Bots traverse the whole map, including jumps
- Adding a new behaviour is a new file, not an edit to a growing `if` chain

**Risk:** navigation on interesting geometry. Flagged in `docs/engine-choice.md`;
mitigation is to design M4's map for bot traversal from the first blockout.

### Delivered so far

- Navigation baked at runtime from the same static colliders the player
  collides with, so anywhere a bot is told it can walk, you can walk
- `BotSenses`: view cone, line of sight traced against world geometry only,
  hearing seeded by gunfire and footsteps, and a last-known position that
  expires. Every one of those is a thing a human also has
- `BotBrain` fills an `InputCommand` — the same struct your mouse fills — so
  bots are bound by the same acceleration, jump height, fire rate, spread and
  reload times you are. They have no private path to anything
- Four states on the same `StateMachine` the movement uses: idle scans, hunt
  walks to the last *known* position rather than the live one, engage holds
  range and strafes while working the trigger in bursts, retreat gives ground
  and reloads
- Three difficulty tiers as data (`assets/config/bots/*.tres`). Reaction time,
  turn speed, aim error, burst discipline, preferred range and aggression —
  and nothing that lets a bot know something you could not
- `BotDirector` owns the roster: spawns on the navigation mesh away from
  whoever is playing, relocates a bot's respawn on death so its spawn never
  becomes a camping spot, and resizes the match live
- Health regeneration after a delay, so a fight has a cost you can pay back by
  disengaging rather than one that follows you for the rest of the session
- HUD for actually fighting them: health with a delayed damage ghost,
  directional damage indicators, kill feed and score
- A duel wing: three sealed, labelled rooms east of the arena, one bot of one
  tier in each, confined by code as well as by walls. A difficulty is very hard
  to judge in a three-way scrap where you cannot tell whose bullet killed you
- 83 bot checks in CI. Most of them are fairness claims, not behaviour ones

**Still to come in M3:** cover as a real concept rather than an emergent one,
navigation links for the jumps bots currently cannot take, and a 1v1 you sign
off by playing.

---

## M4 — The arena

**Goal:** one map that is genuinely good. Not five that are fine.

**Scope:**
- Blockout iterated against the movement from M1 and bots from M3 — the
  procedural test level is an instrument, this is a designed space
- Deliberate sightlines, cover, elevation, and rotation routes
- Navigation links authored as the map is built, not bolted on
- Art pass only after the layout is proven fun in blockout

**Exit criteria:**
- Ten-minute bot matches on it stay interesting
- No dominant position, no dead space
- Movement tech from M1 has somewhere worth using

---

## M5 — Multiplayer

**Goal:** the model chosen in M2, implemented properly.

**Scope:**
- Server-authoritative simulation with client-side prediction and reconciliation
- Lag compensation with server-side hitbox rewind
- Interest management, snapshot rate, interpolation buffers
- Dedicated server target, headless

**Exit criteria:**
- Two clients on real network conditions (100 ms + jitter + loss) both feel
  responsive
- Hit registration feels honest to the shooter
- Bots and remote players run the same movement code as the local player

**Risk:** highest in the project. This milestone is why M1's input seam exists.

---

## M6 — Polish

**Goal:** the layer that makes it read as a real game.

Hit markers, damage feedback, kill feed, HUD, sound design hooks throughout
(the movement controller already emits `jumped`, `landed` and `stepped` for
exactly this), settings menu with sensitivity, FOV, keybinds and audio, and
performance work.

**Exit criteria:** someone who has never seen the project can pick it up and
play without being told anything.

---

## Standing principles

- One great map beats five mediocre ones. One great weapon beats five variants.
- If the core loop is not fun with three weapons and one map, more content will
  not fix it.
- No feature is "done" until it has been played, not just written.
