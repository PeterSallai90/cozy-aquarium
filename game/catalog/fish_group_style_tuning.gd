class_name FishGroupStyleTuning
extends Resource
## The strengths of one FishSpecies.GroupStyle in the steering model (ADR 0015 rule 3); one entry
## per enum value in FishSwimTuning.group_styles, indexed by the enum value. All (tuning).

## Pull of a fish to the centre of the school-mates it sees (times the sociability of the fish).
@export var cohesion: float = 0.0
## How much a fish copies the heading of the school-mates it sees.
@export var alignment: float = 0.0
## Distance in body lengths below which school-mates push each other apart softly.
@export var spacing_bl: float = 0.0
## How far, in body lengths, a fish sees its school-mates.
@export var view_radius_bl: float = 0.0
