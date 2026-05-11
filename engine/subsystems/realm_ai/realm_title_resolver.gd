class_name RealmTitleResolver
extends RefCounted

## Per acore_axioms_strongholds_and_domains.xml §titles_of_nobility L273-285
## + §muster_delay L373-382.
##
## A ruler's title is determined by personal-domain families × number of
## domains ruled × overall-realm families. Each title also dictates the
## muster cadence for Call to Arms duties (Baron-Count = Week, Prince-Duke
## = Month, King-Emperor = Season).
##
## The RAW table is the BAND that the ruler qualifies for; the actual title
## is the highest band whose three thresholds are ALL met. (A ruler with
## small personal domain but large overall realm cannot be Emperor unless
## their personal domain hits the Emperor floor.)
##
## Public API:
##   resolve_title(personal_families, domains_ruled, realm_families) -> String
##     Returns one of: "Baron" | "Marquis" | "Count" | "Duke" | "Prince" |
##                     "King" | "Emperor"
##
##   muster_period(title) -> String
##     Returns "Week" | "Month" | "Season".
##
##   describe(personal_families, domains_ruled, realm_families) -> Dictionary
##     {title, muster_period, qualifying_band: String, ...}

# Bands ordered highest → lowest. A ruler qualifies for the highest band
# where all three thresholds are met; the personal_families and realm_families
# are *minimums* (lower bounds), and domains_ruled is also a minimum.
# Source: acore_axioms §titles_of_nobility table at L277-283.
const _TITLE_BANDS := [
	{
		"title": "Emperor",
		"personal_min": 12500, "domains_min": 5461,
		"realm_min": 2_000_000,
	},
	{
		"title": "King",
		"personal_min": 12500, "domains_min": 1365,
		"realm_min": 364000,
	},
	{
		"title": "Prince",
		"personal_min": 7500, "domains_min": 341,
		"realm_min": 87000,
	},
	{
		"title": "Duke",
		"personal_min": 1500, "domains_min": 85,
		"realm_min": 20000,
	},
	{
		"title": "Count",
		"personal_min": 780, "domains_min": 21,
		"realm_min": 4600,
	},
	{
		"title": "Marquis",
		"personal_min": 320, "domains_min": 5,
		"realm_min": 960,
	},
	{
		"title": "Baron",
		"personal_min": 160, "domains_min": 1,
		"realm_min": 160,
	},
]

const _MUSTER_PERIOD := {
	"Emperor": "Season",
	"King":    "Season",
	"Duke":    "Month",
	"Prince":  "Month",
	"Count":   "Week",
	"Marquis": "Week",
	"Baron":   "Week",
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func resolve_title(
	personal_families: int,
	domains_ruled: int,
	realm_families: int
) -> String:
	for band in _TITLE_BANDS:
		var pf_ok: bool = personal_families >= int(band["personal_min"])
		var dr_ok: bool = domains_ruled >= int(band["domains_min"])
		var rf_ok: bool = realm_families >= int(band["realm_min"])
		if pf_ok and dr_ok and rf_ok:
			return String(band["title"])
	# Below Baron threshold: still classified as Baron per Phase 0 default.
	# A ruler with sub-160 personal-domain families won't have a stronghold
	# fit for the Baron title in RAW, but the Phase 0 schema initializes
	# realm_title to 'Baron', so we preserve that default.
	return "Baron"


static func muster_period(title: String) -> String:
	return String(_MUSTER_PERIOD.get(title, "Week"))


static func describe(
	personal_families: int,
	domains_ruled: int,
	realm_families: int
) -> Dictionary:
	var title: String = resolve_title(personal_families, domains_ruled, realm_families)
	return {
		"title": title,
		"muster_period": muster_period(title),
		"personal_families": personal_families,
		"domains_ruled": domains_ruled,
		"realm_families": realm_families,
	}
