# Weapon models

Empty on purpose. Every weapon currently draws a procedural silhouette built
from boxes, which is a placeholder and looks like one.

## Dropping in a real model

1. Put the file here — `.glb` and `.gltf` are the safe bets, and Godot imports
   `.blend`, `.fbx` and `.obj` too.
2. Open the matching `assets/config/weapons/*.tres` and set:
   - **`view_model_scene`** — the first-person model, or
   - **`world_model_scene`** — the model bots and (later) other players hold.
     The same file can go in both.
   - **`model_muzzle`** — the barrel tip in the model's own space. Tracers and
     the muzzle flash come from here.
   - **`model_scale`** and **`model_rotation_degrees`** — exporters disagree
     about which way is forward and how big a metre is. Godot's convention is
     **−Z forward, +Y up, one unit = one metre**.

Nothing else changes. Damage, fire rate, spread, recoil and the shot trace all
read from the `.tres` and from `model_muzzle`, never from the mesh, so art can
never quietly change where bullets go.

If the model has a child node named **`Magazine`**, it drops and reseats on a
magazine reload. One named **`Handguard`** racks on a pump reload. Neither is
required.

## Where to get them

The models have to be licensed for use outside Unreal. In practice that means:

- **Fab** (fab.com) — Epic's store, and the successor to the Unreal Marketplace.
  Since the relaunch the **Standard License is engine-agnostic**: assets under
  it can be used in Godot, commercially. Filter to Free, and check each listing
  says Standard or a Creative Commons licence. Needs an Epic account.
- **Quaternius** (quaternius.com) — CC0, low-poly, and the closest match for
  this game's current look.
- **Kenney** (kenney.nl) — CC0, blockout-friendly.

A realistic rifle against untextured grey boxes tends to look *worse* than a
box that matches, so it is worth deciding whether the whole game keeps the
grey-box look before committing to a style. That decision belongs to M6.
