class_name EncounterTimeline
extends RefCounted

var config: EncounterConfig
var elapsed := 0.0
var next_regular := 10.0
## 0 not due, 1 pending, 2 alive, 3 player kill, 4 environment death.
var elites: Array[int] = [0, 0]
var boss_pending := false
var boss_spawned := false
var running := false
var regular_events := 0

func setup(value: EncounterConfig) -> void:
	config = value
	elapsed = 0
	next_regular = config.interval
	elites = [0, 0]
	boss_pending = false
	boss_spawned = false
	regular_events = 0
	running = true

func advance(delta: float, exploring: bool, control_ready: bool) -> Array[String]:
	var events: Array[String] = []
	if not running or not control_ready or boss_spawned:
		return events
	if exploring:
		elapsed += maxf(0, delta)
		while next_regular <= elapsed + 0.00001:
			events.append("regular")
			regular_events += 1
			next_regular += config.interval
		for i in 2:
			var threshold := config.elite_one_time if i == 0 else config.elite_two_time
			if elapsed + 0.00001 >= threshold and elites[i] == 0:
				elites[i] = 1
	if not boss_spawned and (elapsed >= config.boss_force_time \
			or elapsed >= config.boss_early_time and elites[0] == 3 and elites[1] == 3):
		boss_pending = true
		events.append("boss")
	if exploring:
		for i in 2:
			if elites[i] == 1:
				events.append("elite_%d" % i)
	return events

func elite_spawned(index: int) -> void:
	elites[index] = 2

func elite_died(index: int, cause: String) -> void:
	elites[index] = 3 if cause == "player" else 4
