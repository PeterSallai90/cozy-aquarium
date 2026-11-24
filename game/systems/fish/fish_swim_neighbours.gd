class_name FishSwimNeighbours
extends RefCounted
## The neighbour search of FishSwimSim (ADR 0015 rule 4): from the positions, headings and speeds
## of all fish it builds, per fish, the forces and limits the steering reads: the personal-space
## push (separation), the soft spacing push and the cohesion and alignment sums of the school-mates
## in view, the nearest school-mate, the predicted-collision push (a fish steers away from a fish
## whose path crosses its own, before it has to brake) and the speed limit set by a fish ahead.
## Pure arrays and numbers, no Node; all pairs are tested with a cheap distance check first.

## Personal-space push (before its weight), by fish index.
var sep: PackedVector3Array = PackedVector3Array()
## Soft spacing push of school-mates that are closer than the style spacing.
var spc: PackedVector3Array = PackedVector3Array()
## Push away from a fish that is about to cross the path of this one.
var avd: PackedVector3Array = PackedVector3Array()
## Sum of the positions and headings of the school-mates in view, and their number.
var coh: PackedVector3Array = PackedVector3Array()
var ali: PackedVector3Array = PackedVector3Array()
var count: PackedInt32Array = PackedInt32Array()
## Index and squared distance of the nearest school-mate (any distance), -1 and INF when alone.
var near: PackedInt32Array = PackedInt32Array()
var near_sq: PackedFloat64Array = PackedFloat64Array()
## Speed limit from the fish ahead (INF when none): its own speed along the heading plus what the
## braking distance allows.
var clear: PackedFloat64Array = PackedFloat64Array()
## 1 when the fish ahead is already at the stopping distance or closer: the limit is then absolute.
var touching: PackedByteArray = PackedByteArray()
## The pairs (by index) that are close enough to touch before the next search.
var contact_a: PackedInt32Array = PackedInt32Array()
var contact_b: PackedInt32Array = PackedInt32Array()
## Positions of the fish at the last search.
var pos: PackedVector3Array = PackedVector3Array()
var _fwd: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _half: PackedFloat64Array = PackedFloat64Array()
var _spacing: PackedFloat64Array = PackedFloat64Array()
var _view_sq: PackedFloat64Array = PackedFloat64Array()
var _amax: PackedFloat64Array = PackedFloat64Array()
var _key: PackedInt32Array = PackedInt32Array()
var _style: PackedInt32Array = PackedInt32Array()
var _pinned: PackedByteArray = PackedByteArray()


## Searches every pair of `members` (fish index = array index) and fills the results; `keys` maps
## the group key of a fish to a small integer.
func rebuild(
	members: Array[FishSwimMember], keys: Dictionary[StringName, int], t: FishSwimTuning
) -> void:
	var n: int = members.size()
	for array: PackedVector3Array in [pos, _fwd, _vel, sep, spc, avd, coh, ali]:
		array.resize(n)
	for array: PackedFloat64Array in [_half, _spacing, _view_sq, _amax, near_sq, clear]:
		array.resize(n)
	for array: PackedInt32Array in [_key, _style, count, near]:
		array.resize(n)
	_pinned.resize(n)
	touching.resize(n)
	touching.fill(0)
	sep.fill(Vector3.ZERO)
	spc.fill(Vector3.ZERO)
	avd.fill(Vector3.ZERO)
	coh.fill(Vector3.ZERO)
	ali.fill(Vector3.ZERO)
	count.fill(0)
	near.fill(-1)
	near_sq.fill(INF)
	clear.fill(INF)
	contact_a.clear()
	contact_b.clear()
	for i: int in n:
		_load(members[i], i, keys)
	var grouped_from: int = FishSpecies.GroupStyle.TIGHT_SCHOOL
	var space_factor: float = t.separation_factor
	var ramp: float = t.separation_ramp_fraction
	var safety: float = t.brake_safety
	var horizon: float = t.avoid_horizon_s
	var avoid_factor: float = t.avoid_radius_factor
	var stop_factor: float = t.clear_stop_factor
	var contact_scale: float = t.contact_reach_factor
	var contact_slack: float = t.contact_reach_m
	for i: int in range(n - 1):
		var at: Vector3 = pos[i]
		var grouped_style: bool = _style[i] >= grouped_from
		for j: int in range(i + 1, n):
			var off: Vector3 = at - pos[j]
			var d2: float = off.length_squared()
			var hs: float = _half[i] + _half[j]
			var grouped: bool = grouped_style and _key[i] == _key[j]
			if grouped:
				if d2 < near_sq[i]:
					near_sq[i] = d2
					near[i] = j
				if d2 < near_sq[j]:
					near_sq[j] = d2
					near[j] = i
				if d2 < _view_sq[i]:
					coh[i] += pos[j]
					coh[j] += at
					ali[i] += _fwd[j]
					ali[j] += _fwd[i]
					count[i] += 1
					count[j] += 1
			if d2 < (contact_scale * hs + contact_slack) * (contact_scale * hs + contact_slack):
				contact_a.append(i)
				contact_b.append(j)
			var space: float = space_factor * hs
			var spacing: float = _spacing[i] if grouped else 0.0
			var rel: Vector3 = _vel[j] - _vel[i]
			var rel_sq: float = rel.length_squared()
			var near_reach: float = maxf(maxf(space, spacing), 3.0 * hs)
			var cross_reach: float = near_reach + sqrt(rel_sq) * horizon
			if d2 >= cross_reach * cross_reach:
				continue
			var d: float = sqrt(d2)
			var away: Vector3 = off / d if d > 1.0e-9 else Vector3.RIGHT
			var yields_i: bool = _pinned[i] == 0
			var yields_j: bool = _pinned[j] == 0
			if d < space:
				var push: Vector3 = away * minf((space - d) / (hs * ramp), t.separation_max)
				if yields_i:
					sep[i] += push
				if yields_j:
					sep[j] -= push
			if d < spacing:
				var soft: Vector3 = away * ((spacing - d) / spacing)
				if yields_i:
					spc[i] += soft
				if yields_j:
					spc[j] -= soft
			# A path that crosses within the avoid radius soon: both steer away from the crossing.
			if rel_sq > 1.0e-8:
				var t_cross: float = off.dot(rel) / rel_sq
				if t_cross > 0.0 and t_cross < horizon:
					var gap: Vector3 = rel * t_cross - off
					var gap_len: float = gap.length()
					var radius: float = avoid_factor * hs
					if gap_len < radius:
						var side: Vector3 = (
							-gap / gap_len
							if gap_len > 1.0e-9
							else off.cross(Vector3.UP).normalized()
						)
						var strength: float = (1.0 - t_cross / horizon) * (1.0 - gap_len / radius)
						if yields_i:
							avd[i] += side * strength
						if yields_j:
							avd[j] -= side * strength
			if d2 >= near_reach * near_reach:
				continue
			var ahead_i: float = -off.dot(_fwd[i])
			if ahead_i > 0.0 and d2 - ahead_i * ahead_i < hs * hs:
				var follow_i: float = maxf(_vel[j].dot(_fwd[i]), 0.0)
				var room_i: float = maxf(ahead_i - hs * stop_factor, 0.0)
				clear[i] = minf(clear[i], follow_i + sqrt(2.0 * _amax[i] * room_i) * safety)
				if room_i <= 0.0:
					touching[i] = 1
			var ahead_j: float = off.dot(_fwd[j])
			if ahead_j > 0.0 and d2 - ahead_j * ahead_j < hs * hs:
				var follow_j: float = maxf(_vel[i].dot(_fwd[j]), 0.0)
				var room_j: float = maxf(ahead_j - hs * stop_factor, 0.0)
				clear[j] = minf(clear[j], follow_j + sqrt(2.0 * _amax[j] * room_j) * safety)
				if room_j <= 0.0:
					touching[j] = 1


func _load(f: FishSwimMember, i: int, keys: Dictionary[StringName, int]) -> void:
	var p: FishSwimParams = f.params
	f.idx = i
	pos[i] = f.position
	var cos_pitch: float = cos(f.travel_pitch)
	var heading: Vector3 = Vector3(
		sin(f.yaw) * cos_pitch, sin(f.travel_pitch), cos(f.yaw) * cos_pitch
	)
	_fwd[i] = heading
	_vel[i] = heading * f.speed
	_half[i] = p.half_length_m
	_spacing[i] = p.spacing_m
	_view_sq[i] = p.view_radius_m * p.view_radius_m
	_amax[i] = p.accel_max
	_key[i] = keys[p.species_key]
	_style[i] = p.group_style
	_pinned[i] = 1 if f.vert.pinned else 0
