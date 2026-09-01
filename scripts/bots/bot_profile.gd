class_name BotProfile
extends Resource
## A difficulty tier, as data.
##
## Every dial here is something a *human* also has: how far they can see, how
## fast they swing, how steady they hold, how long they take to react. None of
## them give the bot information the player could not have.
##
## That constraint is deliberate. The cheap way to make hard bots is to let
## them see through walls and hit perfectly, and it produces opponents that
## feel like cheats rather than players. Making difficulty out of reaction time
## and precision means a hard bot is doing something you could learn to do.

@export var display_name: String = "Normal"

@export_group("Senses")
@export var vision_range: float = 55.0
## Total cone width. Humans notice movement well past this, but a bot with a
## 360 degree view is impossible to flank, which removes the main thing
## positioning is for.
@export var view_cone_degrees: float = 140.0
@export var hearing_range: float = 45.0
## How long a lost target stays hunted before the bot gives up and idles.
@export var memory_seconds: float = 6.0

@export_group("Aim")
## Delay between a target appearing and the bot reacting. The single most
## important difficulty dial -- it is what makes an easy bot beatable by
## someone with a slower hand, and a hard bot punishing to peek.
@export var reaction_time: float = 0.34
## Radians per second the view can swing. Caps how fast a bot can turn onto
## someone behind it.
@export var aim_speed: float = 5.0
## Steady-state aim wobble. Resampled each burst, so a bot's shots cluster
## slightly off rather than tracking perfectly.
@export var aim_error_degrees: float = 2.6
## Extra error against a target moving across the bot's view, so strafing
## actually helps you.
@export var aim_error_moving: float = 2.4

@export_group("Engagement")
@export var burst_min: int = 3
@export var burst_max: int = 6
@export var burst_pause_min: float = 0.30
@export var burst_pause_max: float = 0.75
## Distance the bot tries to hold. Closer and it pushes, further and it closes.
@export var preferred_range: float = 16.0
@export var range_tolerance: float = 6.0
## 0 holds position and trades, 1 pushes relentlessly.
@export_range(0.0, 1.0, 0.05) var aggression: float = 0.5
## Falls back below this fraction of health.
@export_range(0.0, 1.0, 0.05) var retreat_health: float = 0.3
@export var weapon_slot: int = 1
