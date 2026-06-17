extends Node

## Diagnostic: measure monoculture across SEVERAL seeds at a given Cultural
## Assimilation multiplier, so the bistable single-seed swings average out. Reports
## per-seed top-culture substrate share + present-day polity count, and the averages.
## Env: ASSIM (cultural_assimilation, default 1.0), SIZE (default "medium").
## Run res://tools/assim_sweep.tscn (use an isolated APPDATA so it never touches the
## playtest DB — it is not a test run).

func _ready() -> void:
	var assim: float = float(OS.get_environment("ASSIM")) if OS.get_environment("ASSIM") != "" else 1.0
	var size: String = OS.get_environment("SIZE") if OS.get_environment("SIZE") != "" else "medium"
	var seeds: Array = [1, 42, 777, 12345, 99001, 177621, 500, 31337]
	var shares: Array = []
	var counts: Array = []
	for sd in seeds:
		var params := SettingParameters.new()
		params.map_size = size
		params.cultural_assimilation = assim
		var cid := CampaignRepository.create_campaign("assim_%d" % sd, "w")
		if not SettingGenerator.new().generate(cid, sd, params):
			print("  FAIL seed %d" % sd)
			continue
		var cov := {}
		var land := 0
		for h in SettingRepository.list_hexes(cid):
			if str(h.get("water", "")) != "":
				continue
			land += 1
			var raw = h.get("culture_weights", "{}")
			var d = JSON.parse_string(raw) if raw is String else raw
			if typeof(d) != TYPE_DICTIONARY or d.is_empty():
				continue
			var best := ""
			var bw := -1.0
			for k in d:
				if float(d[k]) > bw:
					bw = float(d[k])
					best = str(k)
			cov[best] = int(cov.get(best, 0)) + 1
		var top := 0
		for c in cov:
			top = maxi(top, int(cov[c]))
		var share := 100.0 * float(top) / maxf(land, 1)
		var npol := SettingRepository.list_polities(cid).size()
		shares.append(share)
		counts.append(npol)
		print("  seed=%-7d top_culture=%2d%%  polities=%-3d cultures=%d" % [
			sd, int(round(share)), npol, cov.size()])
	var sum_share := 0.0
	for s in shares:
		sum_share += float(s)
	var sum_count := 0.0
	for c in counts:
		sum_count += float(c)
	var n := maxf(float(shares.size()), 1.0)
	print("ASSIM_SWEEP assim=%.2f size=%s seeds=%d AVG_top_culture=%d%% AVG_polities=%d" % [
		assim, size, int(n), int(round(sum_share / n)), int(round(sum_count / n))])
	get_tree().quit()
