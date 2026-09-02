# Networking model

**Decision: server-authoritative simulation, client-side prediction for the
local player, and server-side lag compensation for hit registration.**
Status: accepted. This is the M2 spike from `ROADMAP.md`.

It is written now, before weapons exist, because **hit registration design is
downstream of it** and retrofitting is expensive. None of the netcode is
implemented yet — M5 does that. What this document buys is the right seams in
Milestone 2's weapon code.

---

## The model

1. **The server simulates and is authoritative.** Clients send `InputCommand`s;
   the server runs the same movement and weapon code and owns the result.
2. **The local client predicts.** It applies its own input immediately and keeps
   unacknowledged commands. When the server's state for tick *N* disagrees, the
   client snaps to it and replays every command after *N*. Without this, moving
   costs a round trip and the movement we just spent a milestone tuning is gone.
3. **The server lag-compensates.** When it processes a shot fired on tick *N*,
   it rewinds every hitbox to where it was on tick *N* — where the shooter
   actually saw them — resolves the trace, then restores. Without it, hitting a
   moving target means leading by your ping.

Rejected alternatives: **client-authoritative hits** (trivially cheatable — the
client just claims kills) and **no prediction** (correct, unplayable above about
30 ms).

## What that forces on Milestone 2

Everything here is cheap now and expensive later, so it is all built in from the
first weapon even though nothing is networked yet.

**Firing is a field on `InputCommand`, not a signal from `Input`.** Same seam as
movement. The server replays a command and gets the same shot; a bot fills the
same struct.

**Timing is counted in ticks, never in wall-clock seconds.** Fire rate, reload,
and equip are tick counters. `Time.get_ticks_msec()` cannot be replayed, so a
replayed shot must not consult it.

**Spread and recoil are deterministic, seeded per shot.** A shot's RNG seed is
derived from the command tick and the shot index, so the client and the server
independently compute the *same* pellet directions. If spread used a free-running
RNG, the server would disagree with the client on every shot and either reject
legitimate hits or have to trust the client.

**Traces originate from `AimPoint`, never the camera.** Established in
Milestone 1 — view bob, landing dip and now recoil kick all move the camera, and
if shots came from there the feel layer would silently change where bullets go.

**Hitboxes are separate nodes on their own physics layer, with per-tick
transform history.** Two consequences: traces mask against hitboxes only (layer
4) and pass straight through character bodies (layer 2), so a hitbox can be
smaller or larger than the collision hull without affecting movement; and the
history is what M5's rewind reads. `HitboxRecorder` already records it —
recording is cheap, and adding it after weapons are tuned would mean re-tuning
against changed hit behaviour.

**Damage is applied through one function.** `Health.apply_damage()` is the only
mutation path, so the server can later be the only caller without touching
weapon code.

## Known risk

Hand-written prediction and lag compensation is the largest technical risk in
the project (`docs/engine-choice.md`). Godot gives us replication, not these.
The mitigation is that every seam above is load-bearing and already in place, so
M5 is *implementation* rather than *rearchitecture*.

The honest fallback, if M5 proves too hard: ship single-player and bots, which
is a complete game on its own, and revisit multiplayer separately.

---

## Transport, decided in M5

**ENet over UDP, and multiplayer is a desktop-build feature.** This is the part
that had to be found out by trying rather than by planning, so it is written
down here before anyone builds on the wrong assumption.

The goal was the one that was asked for: two people on the same network, one
reads out a join code, the other types it in, no accounts and no servers. ENet
is Godot's default high-level peer and does exactly that — the host opens a UDP
port, the code *is* its LAN address and port, and nothing else has to exist.

**It does not work from the browser build, and neither does the alternative.**

- Browsers cannot open raw UDP sockets, so ENet is out.
- `WebSocketMultiplayerPeer` would work in principle, but a browser cannot
  accept incoming connections, so the host must be a desktop build. Worse, the
  page on GitHub Pages is served over HTTPS, and a page served over HTTPS may
  not open an insecure `ws://` connection. A LAN address cannot have a
  certificate, so `wss://` is not available either.
- WebRTC would work, but needs a signalling server somebody has to run and pay
  for, which is the opposite of the "no infrastructure" property that made LAN
  attractive in the first place.

So: **the Pages build stays single-player against bots, and LAN multiplayer
ships in the desktop build.** Browser multiplayer, if it is ever wanted, is an
internet-hosted relay and a different milestone — not a variation on this one.

### What the join code is

Four bytes of IPv4 and two of port, 48 bits, base32 into ten characters over an
alphabet with no `0`, `O`, `1` or `I` in it, because codes get read out loud
across a room. Nothing is looked up; the code *is* the address. A mistyped
character is refused rather than corrected, since every plausible correction
maps one valid code onto a different valid one — and silently connecting
somebody to the wrong machine looks like a network fault, not a typo.
