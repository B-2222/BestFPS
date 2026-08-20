class_name PlayerConfig
extends Resource
## Every number that decides how the player feels, in one editable resource.
##
## Why a [Resource] and not constants: feel is found by tweaking, not by
## reasoning. This can be edited in the inspector *while the game is running*,
## and saved as named presets (arena-fast vs tactical-slow) that we can A/B
## without touching code. Milestone 1 is entirely about turning these dials.
##
## Units are metres and seconds throughout. A player is 1.8 m tall, so a
## "waist-high crate" is ~1.0 m and a doorway is ~2.2 m.

# ---------------------------------------------------------------------------
@export_group("Ground Movement")

## Baseline speed. Deliberately high enough to feel good on its own -- the
## common mistake is making the walk sluggish to justify a sprint button.
@export var walk_speed: float = 6.5

## Sprint is a modest boost, not a different game. Keep the ratio near 1.4x.
@export var sprint_speed: float = 9.0

## Multiplier applied to [member walk_speed] while crouched.
@export var crouch_speed_mult: float = 0.45

## Only sprint when the stick/keys are pushed forward. Stops the "sprint
## sideways at full speed" look that reads as a bug to players.
@export var sprint_forward_only: bool = true

## Quake-style acceleration coefficient. Speed gained per tick is
## [code]ground_accel * target_speed * delta[/code], capped so you never
## overshoot the target. 12 reaches full speed in ~80 ms: instant to the hand,
## but still a curve rather than a step.
@export_range(1.0, 40.0, 0.5) var ground_accel: float = 12.0

## Deceleration coefficient when not pushing toward your velocity.
@export_range(0.0, 30.0, 0.5) var friction: float = 8.0

## Below this speed, friction is applied as if you were moving this fast.
## Without it, the last fraction of a m/s takes forever and the stop feels
## mushy at exactly the moment the player is trying to plant and aim.
@export var stop_speed: float = 2.0

# ---------------------------------------------------------------------------
@export_group("Air Movement")

@export var gravity: float = 22.0

## Terminal velocity, so a long fall cannot tunnel through geometry.
@export var terminal_velocity: float = 60.0

## Air acceleration coefficient. Higher than ground on purpose -- it is heavily
## limited by [member air_speed_cap] below.
@export_range(1.0, 60.0, 0.5) var air_accel: float = 22.0

## The Quake air-control trick: while airborne you may only accelerate up to
## this speed *along the direction you are pushing*. Push sideways while
## turning and the cap keeps resetting, which is what lets a skilled player
## gain speed in the air. Low values (~0.8) give CS-style near-zero air
## control; high values (~4) give Quake-style strafe jumping.
@export_range(0.0, 6.0, 0.05) var air_speed_cap: float = 2.0

# ---------------------------------------------------------------------------
@export_group("Jump")

## Vertical launch speed. Apex height = jump_velocity^2 / (2 * gravity).
## 7.0 with gravity 22 gives a 1.11 m jump and 0.64 s of airtime.
@export var jump_velocity: float = 7.0

## Grace period after walking off a ledge during which a jump still works.
## Players mash jump slightly late; without this the game feels like it is
## ignoring inputs. Invisible when present, infuriating when absent.
@export_range(0.0, 0.4, 0.005) var coyote_time: float = 0.10

## Grace period *before* landing during which a jump press is remembered.
## The other half of the same problem: players mash jump slightly early.
@export_range(0.0, 0.4, 0.005) var jump_buffer_time: float = 0.12

## Hold jump to keep hopping instead of re-pressing. A game identity decision
## rather than a tuning value; kept on after playtesting.
@export var auto_bhop: bool = true

## Hard ceiling on horizontal speed while airborne. 0 removes it.
##
## Quake-style strafe jumping accelerates without bound: measured at 23 m/s and
## still climbing after 8 s of clean strafing, against a 9 m/s sprint. That is
## authentic, and it breaks everything downstream -- an 80 m arena stops
## containing the player, bots cannot contest someone moving at 5x walk speed,
## and hit registration gets much harder the further a target moves per tick.
##
## 16 is about 1.8x sprint: high enough that good strafing is still clearly
## rewarded (a medium turn tops out near 12.7 and never touches this), low
## enough that the game stays bounded. Raise it for a faster, more
## movement-driven game; set 0 for pure Quake.
@export var max_air_speed: float = 16.0

# ---------------------------------------------------------------------------
@export_group("Crouch")

@export var standing_height: float = 1.8
@export var crouch_height: float = 1.0
@export var standing_eye_height: float = 1.62
@export var crouch_eye_height: float = 0.85

## Time constant for the height blend. Fast enough to be responsive, slow
## enough that the camera does not teleport.
@export_range(0.01, 0.5, 0.005) var crouch_transition_time: float = 0.10

# ---------------------------------------------------------------------------
@export_group("Slide")

## Slide is behind a flag because whether it belongs is a question about the
## game's identity, not about tuning. Turn it off and the rest still works.
@export var slide_enabled: bool = true

## Minimum ground speed required to start a slide.
@export var slide_min_speed: float = 6.0

## Speed added on entry. The reward for timing the slide correctly.
@export var slide_boost: float = 3.5

@export var slide_max_speed: float = 15.0

## Friction while sliding. Much lower than [member friction]; this is what
## makes a slide carry.
@export_range(0.0, 10.0, 0.1) var slide_friction: float = 2.2

## How fast the slide direction can be steered, in radians-ish per second.
## Steering redirects speed, it never adds any.
@export_range(0.0, 12.0, 0.1) var slide_steer: float = 3.0

## Multiplier on gravity-along-the-slope while sliding. Above 1.0, downhill
## slides accelerate -- which is the entire reason slides are fun on a map
## with elevation.
@export_range(0.0, 4.0, 0.05) var slide_slope_boost: float = 1.4

## Drop below this speed and the slide ends.
@export var slide_min_exit_speed: float = 3.5

## Hard cap so a flat-ground slide cannot be held forever.
@export var slide_max_time: float = 1.6

## Delay before another slide can start. Prevents slide-spam as a movement tech.
@export var slide_cooldown: float = 0.35

# ---------------------------------------------------------------------------
@export_group("Collision")

## Tallest ledge the player walks up without jumping. Godot's CharacterBody3D
## has no built-in stair handling; see PlayerController._step_up().
@export_range(0.0, 1.0, 0.01) var max_step_height: float = 0.35

## Slopes steeper than this are walls. 46 deg keeps a 45 deg ramp walkable
## with margin for floating-point noise on rotated collision boxes.
@export_range(0.0, 89.0, 0.5) var floor_max_angle_deg: float = 46.0

## How far the body reaches down to stay glued to the ground. Must be >=
## [member max_step_height] or walking *down* stairs turns into bouncing.
@export var floor_snap_length: float = 0.4

# ---------------------------------------------------------------------------
@export_group("Look")

## Radians of rotation per pixel of mouse movement.
@export_range(0.0002, 0.02, 0.0001) var mouse_sensitivity: float = 0.0022

@export var pitch_min_deg: float = -89.0
@export var pitch_max_deg: float = 89.0

# ---------------------------------------------------------------------------
@export_group("View Effects", "view_")

@export var view_fov_base: float = 90.0

## Extra FOV blended in as speed rises from [member walk_speed] toward
## [member view_fov_speed_ref]. Speed you can see is speed you can feel.
@export var view_fov_speed_add: float = 8.0
@export var view_fov_speed_ref: float = 13.0
@export var view_fov_slide_add: float = 12.0
@export_range(1.0, 30.0, 0.5) var view_fov_blend: float = 8.0

@export var view_bob_enabled: bool = true

## Bob cycles per metre travelled -- not per second. Tying bob to distance
## means it stays in step with the legs at every speed, and stops dead when
## the player does, instead of swaying on the spot.
@export_range(0.0, 2.0, 0.01) var view_bob_frequency: float = 0.35
@export var view_bob_amount_v: float = 0.045
@export var view_bob_amount_h: float = 0.030
@export var view_bob_roll_deg: float = 0.35

## Landing dip, as an underdamped spring. Impulse scales with impact speed so a
## small hop barely registers and a long fall lands hard.
##
## Calibrated, not guessed: at these values an ordinary jump (7 m/s impact)
## dips about 5.5 cm, a 2 m drop about 7 cm, and a 10 m fall about 17 cm --
## which leaves the clamp as a genuine safety net rather than something every
## landing hits. Raising the scale much past 0.006 makes routine jumping feel
## like the camera is slamming into the floor.
@export var view_land_dip_scale: float = 0.0040
@export var view_land_dip_stiffness: float = 170.0
@export var view_land_dip_damping: float = 18.0
@export var view_land_dip_max: float = 0.18

## Camera roll when strafing. Under ~1.5 deg it reads as weight; above that it
## reads as a bug.
@export var view_strafe_tilt_deg: float = 1.1
@export var view_strafe_tilt_speed: float = 8.0
@export var view_slide_tilt_deg: float = 4.0

## Decay time for step-up smoothing. Walking up stairs teleports the body
## upward by up to [member max_step_height]; without this the camera jolts on
## every single step. Source engine does exactly this.
@export_range(0.01, 0.4, 0.005) var view_step_smooth_time: float = 0.10
