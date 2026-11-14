extends SceneTree
## Reference run of Nexora_godot's nx8 engine (src/game/engine.gd) on the Flutter field geometry (the Godot repo's
## fields are stretched +30%; the Flutter port keeps the RN geometry). Writes test/fixtures/godot_nx8.json.
## Run: godot --headless --path <Nexora_godot> -s <this file> -- <out.json>
const SC := [
	{"name": "pitch_3shots", "field": 0, "forms": [0, 0], "pw": [1.0, 0.7, 0.85, 0.5], "frames": 600},
	{"name": "forest_2v", "field": 1, "forms": [1, 2], "pw": [0.9, 1.0, 0.4], "frames": 540},
]
const FLUT := [ # Flutter kFields[0..1]: W,H,L,R,T,B,cs,g,gs
	{"W": 837.0, "H": 1536.0, "L": 30.0, "R": 805.0, "T": 101.0, "B": 1432.0, "cs": 768.0, "g": 128.0, "gs": "white"},
	{"W": 1216.0, "H": 1622.0, "L": 218.0, "R": 997.0, "T": 142.0, "B": 1468.0, "cs": 786.0, "g": 135.0, "gs": "wood"},
]
const D := preload("res://src/core/data.gd")
## Flutter kForms (RN rows formations); the Godot repo now uses point-list formations, so starting spots are
## re-laid with the Flutter slots() so both engines start from identical positions.
const FLUT_FORMS := [[[0.09, 1], [0.22, 2], [0.36, 2]], [[0.1, 2], [0.24, 2], [0.37, 1]], [[0.1, 3], [0.25, 1], [0.37, 1]],
	[[0.1, 2], [0.24, 1], [0.37, 2]], [[0.09, 1], [0.23, 3], [0.37, 1]], [[0.09, 1], [0.22, 1], [0.36, 3]]]

static func flut_slots(fi: int) -> Array:
	var o := []
	for row in FLUT_FORMS[fi]:
		var c: int = row[1]
		for i in c:
			o.append([0.5 if c == 1 else (0.27 + 0.46 * i if c == 2 else 0.17 + 0.33 * i), float(row[0])])
	return o

func _initialize() -> void:
	var ES = load("res://src/game/engine.gd")
	var out := []
	for s in SC:
		var e = ES.new({"field": s.field, "forms": s.forms, "ai": false, "turn_time": 0, "limit": 99, "first": 0, "seed": 1})
		var f: Dictionary = FLUT[s.field]
		e.f = f
		e.Fl = f.L + 4; e.Fr = f.R - 4; e.Ft = f.T + 4; e.Fb = f.B - 4
		e.CX = (e.Fl + e.Fr) / 2.0; e.CY = (e.Ft + e.Fb) / 2.0; e.KY = f.cs
		var gi: Array = D.GS[f.gs]
		var gw: float = 2.0 * f.g / (gi[3] - gi[2])
		e.DEPTH = maxf(120.0, roundf(gw * gi[1] / gi[0] * 1.28 * 0.98))
		e.goals = [ES.Goal.new(0, e.Ft, e.CX - f.g, e.CX + f.g, -1), NxEngine.Goal.new(1, e.Fb, e.CX - f.g, e.CX + f.g, 1)]
		e.events = []
		e.reset(0)
		e.events = []
		var Fw: float = e.Fr - e.Fl
		var Fh: float = e.Fb - e.Ft
		var ins: float = e.pr + 6.0
		var k := 0
		for cm in 2:
			var sl := flut_slots(s.forms[cm])
			for i in sl.size():
				var b = e.bodies[k]; k += 1
				b.x = e.Fl + ins + sl[i][0] * (Fw - 2 * ins)
				b.y = (e.Ft + sl[i][1] * Fh) if cm else (e.Fb - sl[i][1] * Fh)
				b.px = b.x; b.py = b.y
		var cps := []
		var evs := []
		var si := 0
		for fr in s.frames:
			if e.phase == "aim" and si < s.pw.size():
				# shooter: the current team's disc closest to the ball, aimed at the ball centre
				var best = null
				var bd := 1e18
				for b in e.bodies:
					if b.team == e.turn and b != e.ball:
						var d2: float = (b.x - e.ball.x) * (b.x - e.ball.x) + (b.y - e.ball.y) * (b.y - e.ball.y)
						if d2 < bd: bd = d2; best = b
				var dx: float = e.ball.x - best.x
				var dy: float = e.ball.y - best.y
				var l := sqrt(dx * dx + dy * dy)
				var L: float = s.pw[si] * ES.LMAX
				e.fire(best, dx / l * L, dy / l * L, L)
				si += 1
			e.update(1.0 / 60.0)
			for ev in e.events: evs.append(String(ev.t))
			e.events = []
			if fr % 10 == 9:
				var xs := []
				for b in e.bodies: xs.append([b.x, b.y, b.vx, b.vy])
				cps.append({"f": fr, "b": xs, "turn": e.turn, "phase": e.phase, "score": [e.score[0], e.score[1]]})
		out.append({"name": s.name, "field": s.field, "forms": s.forms, "pw": s.pw, "frames": s.frames, "cps": cps, "evs": evs})
	var args := OS.get_cmdline_user_args()
	var fa := FileAccess.open(args[0], FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, "", false, true))
	fa.close()
	print("wrote ", args[0])
	quit()
