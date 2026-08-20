# Engine choice

**Decision: Godot 4.4, GDScript.**
Status: accepted, 2026-08-20. Revisit triggers are listed at the bottom.

This confirms your default rather than overriding it, but the reasoning matters
more than the conclusion, because two of the reasons come with real costs that
land in Milestone 5.

---

## Why Godot over Unity

Unity is a genuinely better engine in a few areas that matter to this project.
It is worth being honest about that before explaining why it still loses.

**Where Unity is actually better for an FPS:**

| | Unity | Godot 4 |
|---|---|---|
| Netcode ecosystem | NGO, Fish-Net, Mirror, Photon — several with **client-side prediction and lag compensation built in** | High-level multiplayer replicates state; prediction and lag comp are yours to write |
| Navigation | NavMesh with off-mesh links, agent avoidance, area costs | NavigationServer3D is solid but links and avoidance are thinner |
| Profiling | Deep, mature, frame-accurate | Improved in 4.x, still shallower |
| Asset ecosystem | Enormous; FPS kits, animation sets | Small; you will build or source most things |
| Console porting | First-party | Third-party porting houses only |

**Why Godot still wins here:**

1. **Iteration speed is the deciding factor for the thing you care most about.**
   Your top pillar is movement feel, and feel is found by changing a number and
   feeling it again — hundreds of times. Godot launches the game in under a
   second, has no domain reload, and hot-reloads scripts. Unity's enter-play-mode
   delay is small per iteration and enormous per week. This is not a small
   ergonomic preference; it directly determines how many tuning passes the
   movement actually gets.

2. **The engine is not a business risk.** MIT licensed, no per-install fees, no
   runtime terms that can change. For a serious long-term project by one person,
   "nobody can change the deal" has real value, and Unity spent 2023 proving the
   inverse is possible.

3. **The whole engine is readable.** When stair stepping misbehaves — as it did
   during this very session — you can read `character_body_3d.cpp` and know the
   answer instead of inferring it from a black box. On a project whose hardest
   problems are all "the physics did something I did not expect", that is worth
   a lot.

4. **Scope fit.** The Unity advantages above are concentrated in areas we either
   do not need (console ports, asset store) or will be hand-writing regardless.
   Which brings us to the honest cost.

**The honest cost:** for a *competitive* shooter, Unity's netcode ecosystem is a
real advantage and we are giving it up. See the risk register below — it is the
single largest technical risk in this project and it is why input is already
structured as replayable data in Milestone 1.

## Why not Unreal

Agreed, and for the reason you gave plus one more. Unreal ships the best
out-of-the-box FPS foundation in the industry — its networking model is
battle-tested, and `CharacterMovementComponent` already solves prediction and
reconciliation. If the goal were "ship a competent shooter fastest", Unreal
would be the answer.

But its defaults are also its trap: you would inherit a movement system tuned by
someone else, and "tight, responsive, distinctive movement" means fighting or
replacing that component — which is C++ work in the most complex codebase of the
three. Add build times, editor weight, and Blueprint/C++ split, and the learning
curve costs more than it saves at this scale.

## Why GDScript over C#

Both are first-class in Godot 4. GDScript for now:

- **No build step.** Same argument as above, applied per-edit rather than
  per-session. For a tuning-heavy project this compounds.
- **Fewer moving parts at the engine boundary.** C# in Godot marshals across a
  binding layer; a physics-tick-heavy controller calling engine APIs constantly
  is exactly where that cost shows up.
- **Every Godot example, answer and doc snippet is in GDScript.** When you are
  learning the engine, matching the documentation's language is worth more than
  language features.
- **C# export support is narrower**, particularly for web.

**Where this could bite:** GDScript is meaningfully slower than C# for heavy
non-engine computation. The realistic candidate is bot AI at scale in Milestone
3 — 20+ agents running behaviour trees and pathfinding queries per tick.

**Why that is survivable:** the escape hatch is designed in. The state machine
(`scripts/core/`) is deliberately independent of players, nodes, and the scene
tree. If profiling shows bot decision-making is the bottleneck, that subsystem
can move to C# or a GDExtension module without touching anything else. We do not
have to pick now, and we do not have to rewrite to change our minds later.

---

## Risk register

Flagged now, as requested, rather than three weeks in.

### 1. Netcode — HIGH, and the largest risk in the project

Godot's high-level multiplayer gives you replication. A competitive shooter
needs three more things it does not give you:

- **Client-side prediction** — the local player must move on their own input
  immediately, not after a server round trip.
- **Server reconciliation** — when the server disagrees, the client rewinds and
  replays its unacknowledged inputs.
- **Lag compensation** — the server rewinds hitboxes to where the shooter saw
  them, or nobody can hit a moving target.

All three are ours to write. This is weeks of work and it is the hardest code in
the project.

**Mitigations already in place in Milestone 1:**
- Input is a replayable value (`InputCommand`), not a global read. Re-simulating
  a range of past ticks is impossible otherwise.
- Movement states are `RefCounted` and re-runnable, not scene-tree nodes.
- Commands already carry a tick counter, which is the acknowledgement key.
- Look is carried as absolute yaw/pitch, not mouse deltas, because deltas are
  frame-rate dependent and unreplayable.

None of that is speculative architecture — it is the minimum needed to keep
Milestone 5 from being a rewrite. **Decisions about hit registration must be
made before gunplay is finalised in Milestone 2**, which is why the roadmap
places a networking design spike there rather than at the start of Milestone 5.

### 2. Hit registration — HIGH

Follows directly from the above. Server-side hitbox rewind needs per-tick
transform history for every hitbox on every character. Retrofitting this into
finished weapon code is painful, so hitboxes get their own physics layer and
their own nodes from the start — never the character's collision hull.

Related, and already handled: view effects never move the aim origin. If weapons
fired from the rendered camera, tuning head bob would silently change where
bullets land, and that class of bug is miserable to find months later.

### 3. Bot navigation on real geometry — MEDIUM, arrives in Milestone 3

Navigation meshes are fine on flat, connected floors. They struggle with exactly
what makes an arena good: jump gaps, drop-downs, vaultable cover, one-way routes.
Godot supports links but they are less mature than Unity's, and bots that cannot
use the movement tech players use will read as stupid.

**Mitigation:** design the Milestone 4 arena with bot traversal in mind from the
first blockout, and accept hand-authored navigation links. Do not discover this
after the map is finished.

### 4. Cylinder collision shapes — LOW, but note it

The player hull is a `CylinderShape3D`, not a capsule — a rounded bottom cannot
step cleanly (see `docs/architecture.md`). Cylinder support in GodotPhysics3D is
less battle-tested than box or capsule. Cylinder-vs-static-box is well exercised
and is all we use today, but character-vs-character contact arrives with bots.

**Fallbacks if it misbehaves:** switch the physics backend to Jolt (available in
4.4), or move to a box hull. Both are contained changes.

### 5. Content and animation pipeline — MEDIUM, deferred

First-person arms, weapon models and animations are the largest non-code cost.
Godot's import pipeline handles glTF well; retargeting humanoid animation is
workable but not Unity-grade. Not urgent, but do not assume it is free.

---

## Revisit triggers

This decision should be reopened — not defended — if any of these happen:

- The Milestone 2 networking spike concludes that hand-written prediction and lag
  compensation is more than we can carry. Unity's netcode ecosystem is the single
  strongest argument for switching, and it is best acted on *before* there is a
  lot of gameplay code.
- Profiling shows GDScript is the bottleneck in a way that moving one subsystem
  to C# or GDExtension does not fix.
- Console release becomes a real goal.
- Godot's 3D physics proves unstable for character movement in a way Jolt does
  not resolve.

Switching engines after Milestone 3 would be very expensive. Switching after
Milestone 1 would cost about a week. That asymmetry is why the networking spike
is scheduled early.
