# Roadmap

Milestones are ordered by your pillars, with one deliberate exception explained
in M2. Every milestone ends in something you can launch and play — if a
milestone cannot be played, it is too big and needs splitting.

**Current position: M1 in review.** Movement is implemented and testable; it is
not signed off until you have played it and said so.

| | Milestone | State |
|---|---|---|
| M0 | Foundations | Done |
| M1 | Movement and feel | **Awaiting your feedback** |
| M2 | Gunplay + networking spike | Not started |
| M3 | Bots | Not started |
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

**Exit criteria:**
- [ ] You have played it and the movement feels good, or told me what to change
- [x] Everything above runs with no errors and the smoke test passes
- [ ] Tuning values settled well enough to build weapons against

**What is deliberately absent:** weapons, health, enemies, sound, menus.

**Open question for you:** slide is implemented and enabled, but whether it
belongs is a question about the game's identity, not tuning. Play with it, then
set `slide_enabled = false` and play without. Same for `auto_bhop`. See
`docs/movement-tuning.md`.

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
