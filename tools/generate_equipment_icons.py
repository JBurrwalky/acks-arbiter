#!/usr/bin/env python3
"""
Equipment icon batch generator for ACKS Arbiter.

Generates 179 equipment icons (178 non-magic items + 1 magic placeholder)
using Scenario's GPT Image 2 API.

Prerequisites:
    Python 3.8+  (no extra packages needed — uses stdlib only)

Credentials:
    Set these env vars, OR edit API_KEY / API_SECRET below:
        SCENARIO_SDK_API_KEY=your_key
        SCENARIO_SDK_API_SECRET=your_secret

Usage:
    python tools/generate_equipment_icons.py

The script is resumable: it skips items whose .png already exists in OUTPUT_DIR.
Run it again after a crash to pick up where it left off.

Output: C:/Users/jttau/acks-arbiter/assets/icons/equipment_icons/<key>.png
"""

import os, sys, time, json, base64, urllib.request, urllib.error
from pathlib import Path

# ── CREDENTIALS ────────────────────────────────────────────────────────────
API_KEY    = os.environ.get("SCENARIO_SDK_API_KEY", "")
API_SECRET = os.environ.get("SCENARIO_SDK_API_SECRET", "")

# ── SETTINGS ───────────────────────────────────────────────────────────────
OUTPUT_DIR     = Path(r"C:\Users\jttau\acks-arbiter\assets\icons\equipment_icons")
BATCH_SIZE     = 10    # concurrent jobs per wave
POLL_INTERVAL  = 6     # seconds between status polls
MAX_WAIT       = 300   # seconds before giving up on a job
MODEL_ID       = "model_openai-gpt-image-2"
BASE_URL       = "https://api.cloud.scenario.com/v1"

# ── PROMPT TEMPLATE ────────────────────────────────────────────────────────
PROMPT_TEMPLATE = (
    "In the style of a 1993 hand-painted-on-acetate-film, 3-tone cel shaded "
    "heroic action cartoon reference image: \n\n"
    "{desc}, \n\n"
    "flat orthographic view, aligned 45 degrees along the frontal plane for a "
    "upward-rightward composition, flat white background\n\n"
    "three-tone cel shading with bold hard-edged shadow shapes and crisp "
    "specular highlights on any metal components,\n\n"
    "flat color fills with hand-painted shadow shapes painted directly into the surface,\n\n"
    "vivid saturated NTSC broadcast-safe color palette,\n\n"
    "bold vibrant cel animation paint colors, high-contrast saturated hues,\n\n"
    "deep ink blacks and strong cast shadows, bright crisp white highlights,\n\n"
    "aesthetic of Teenage Mutant Ninja Turtles, Spider-Man: The Animated Series "
    "on Fox Kids, X-Men: The Animated Series, Street Sharks, early 1990s "
    "Saturday morning action cartoon production,\n\n"
    "action hero animation style of the early 1990s,\n\n"
    "hand-drawn animation reference, prop model."
)

# ── ITEM LIST ──────────────────────────────────────────────────────────────
# Format: (item_key, description)
ITEMS = [
    # ── I. WEAPONS — Swords & Daggers ──────────────────────────────────────
    ("sword",             "a single longsword with a cross guard hilt and round pommel"),
    ("short_sword",       "a single short sword with a simple cross guard and tapered double-edged blade"),
    ("two_handed_sword",  "a large two-handed greatsword with a long blade, elongated grip, and wide cross guard"),
    ("dagger",            "a single dagger with a double-edged blade, simple crossguard, and compact grip"),
    ("silver_dagger",     "a single gleaming silver dagger with a bright silver blade, crossguard, and compact grip"),

    # ── I. WEAPONS — Axes ──────────────────────────────────────────────────
    ("battle_axe",        "a single battle axe with a broad single-bit head and wooden haft"),
    ("hand_axe",          "a small hand axe with a compact single-bit head and short wooden handle"),
    ("great_axe",         "a large great axe with a wide double-bit head and long wooden haft"),

    # ── I. WEAPONS — Hafted & Blunt ────────────────────────────────────────
    ("club",              "a simple wooden club, thick at one end and narrowing to a handle"),
    ("mace",              "a flanged steel mace with a spiked metal head and wooden grip"),
    ("warhammer",         "a war hammer with a heavy square metal head and long wooden haft"),
    ("morning_star",      "a morning star with a spiked metal ball head on a wooden haft"),
    ("flail",             "a military flail with a spiked iron ball on a chain attached to a wooden handle"),
    ("quarterstaff",      "a long smooth wooden quarterstaff with tapered ends"),
    ("sap",               "a leather sap or blackjack: a small weighted leather pouch on a short handle"),

    # ── I. WEAPONS — Polearms & Spears ────────────────────────────────────
    ("spear",             "a spear with a leaf-shaped iron tip and long wooden shaft"),
    ("javelin",           "a javelin, a short throwing spear with a slim iron tip and wooden shaft"),
    ("pole_arm",          "a halberd pole arm with a broad axe blade and spike mounted on a long wooden shaft"),
    ("lance",             "a cavalry lance, a long tapered wooden pole with a narrow steel tip and hand guard"),

    # ── I. WEAPONS — Bows ──────────────────────────────────────────────────
    ("shortbow",          "an unstrung shortbow, a curved simple wooden bow with a bowstring"),
    ("longbow",           "a tall longbow, a long straight wooden stave bow with a bowstring"),
    ("composite_bow",     "a composite recurve bow with curved laminated tips"),

    # ── I. WEAPONS — Crossbows ─────────────────────────────────────────────
    ("crossbow",          "a light crossbow with a wooden stock and steel prod and a trigger mechanism"),
    ("arbalest",          "a heavy arbalest crossbow with a massive steel prod, wooden stock, and a cocking lever"),

    # ── I. WEAPONS — Slings, Thrown & Flexible ────────────────────────────
    ("sling",             "a leather sling: a simple strip of leather with a pouch in the middle for hurling stones"),
    ("bola",              "a bola with three weighted stone balls connected by leather cords"),
    ("net",               "a weighted throwing net, circular with lead weights along its edge"),
    ("whip",              "a braided leather whip with a handle and long tapered lash"),

    # ── I. WEAPONS — Improvised ────────────────────────────────────────────
    ("crowbar",           "a steel crowbar: a straight iron bar with a flat prying end and a hooked claw tip"),

    # ── II. AMMUNITION ─────────────────────────────────────────────────────
    ("arrows_20",         "a bundle of twenty wooden arrows with fletched feather vanes and iron tips"),
    ("silver_arrow",      "a single silver-tipped arrow with white fletching and a gleaming silver arrowhead"),
    ("bolts_20",          "a bundle of twenty short crossbow bolts with iron tips and wooden shafts"),
    ("sling_bullets_30",  "a pile of thirty small rounded lead sling bullets"),
    ("sling_stones_20",   "a pile of twenty smooth rounded river stones for slinging"),
    ("dart",              "five slim throwing darts with small stabilizing fins, bundled together"),

    # ── III. ARMOR — Light ─────────────────────────────────────────────────
    ("hide_armor",        "a suit of primitive hide and fur armor with rough-cut leather straps and fur patches"),
    ("leather_armor",     "a suit of hardened leather armor with pauldrons and a cuirass in riveted construction"),

    # ── III. ARMOR — Mail ──────────────────────────────────────────────────
    ("ring_mail",         "a suit of scale mail armor with overlapping metal scales on a leather backing"),
    ("chain_mail",        "a coif and hauberk of interlocked steel chain mail rings"),
    ("banded_armor",      "a suit of banded armor with horizontal metal strips over chain mail"),

    # ── III. ARMOR — Plate ─────────────────────────────────────────────────
    ("plate_armor",       "a full suit of polished steel plate armor with articulated joints"),

    # ── III. ARMOR — Helmets ───────────────────────────────────────────────
    ("light_helmet",      "a simple open-faced iron cap helmet with a brim"),
    ("heavy_helmet",      "a full great helm with a closed visor, cheek guards, and neck protection"),

    # ── IV. SHIELDS ────────────────────────────────────────────────────────
    ("shield",            "a kite shield with a rounded top and tapered bottom, wooden with an iron boss and rim"),

    # ── V. CLOTHING — Torso ────────────────────────────────────────────────
    ("tunic_serf",        "a simple rough-spun serf's tunic and pants in plain undyed linen, laid flat"),
    ("tunic_crafter",     "a sturdy craftsman's belted tunic and pants in dyed wool, laid flat"),
    ("tunic_armiger",     "a fine armiger's belted tunic and pants in quality wool with decorative trim, laid flat"),
    ("tunic_noble",       "an ornate noble's tunic and pants with embroidered trim and silk accents, laid flat"),
    ("robe",              "a long flowing mage's or cleric's robe with wide sleeves and a hood, laid flat"),
    ("cassock",           "a long fitted clerical cassock with buttons down the front, laid flat"),
    ("chiton_wool",       "a draped wool chiton, an ancient Greek rectangular garment with shoulder pin fasteners, laid flat"),
    ("chiton_silk",       "a shimmering draped silk chiton with smooth drape and shoulder pin fasteners, laid flat"),
    ("dress_crafter",     "a practical craftsman's day dress in sturdy dyed linen, laid flat"),
    ("dress_armiger",     "a fine armiger's dress with a tailored bodice and flowing skirt, laid flat"),
    ("gown_noble",        "an elegant noble lady's gown with a fitted bodice and full floor-length skirt, laid flat"),
    ("gown_duchess",      "a magnificent duchess's formal gown with rich embroidery, fur trim, and long train, laid flat"),
    ("breastwrap_wool",   "a simple wool breast wrap chest band, laid flat"),
    ("breastwrap_silk",   "a smooth lustrous silk breast wrap, laid flat"),

    # ── V. CLOTHING — Headwear ─────────────────────────────────────────────
    ("hat_armiger",       "a wide-brimmed felt armiger's hat with a decorative feather plume"),
    ("skullcap_metal",    "a small fitted polished metal skullcap"),
    ("veil_silk",         "a diaphanous silk veil, translucent and softly draped"),

    # ── V. CLOTHING — Cloaks ───────────────────────────────────────────────
    ("cloak_hooded",      "a long hooded wool cloak laid flat, with a decorative clasp at the neck"),
    ("cloak_fur",         "a heavy winter cloak with thick fur lining and a fur-trimmed hood, laid flat"),
    ("cloak_leather",     "a practical hooded leather cloak in dark brown, laid flat"),
    ("cloak_silk",        "a flowing hooded silk cloak with a shimmering smooth surface, laid flat"),
    ("cloak_embroidered", "a rich hooded cloak with elaborate embroidered patterns along the hem and front, laid flat"),

    # ── V. CLOTHING — Footwear ─────────────────────────────────────────────
    ("boots_low",         "a pair of low leather ankle boots with a simple buckle fastening"),
    ("boots_high",        "a pair of tall leather knee-high boots with turned-down cuff tops"),
    ("sandals",           "a pair of simple flat leather sandals with thong straps"),
    ("sandals_high",      "a pair of high-laced leather sandals with straps wrapping up the ankle"),

    # ── V. CLOTHING — Handwear ─────────────────────────────────────────────
    ("gloves",            "a pair of simple short leather gloves"),
    ("gloves_long",       "a pair of long leather gauntlet-style gloves reaching to the elbow"),

    # ── V. CLOTHING — Belts & Sashes ──────────────────────────────────────
    ("belt_leather",      "a plain wide leather belt with a simple iron buckle"),
    ("belt_embossed",     "a wide embossed leather belt with tooled decorative patterns and an ornate buckle"),
    ("belt_silk",         "a long sash-style silk belt with tasseled ends"),

    # ── V. CLOTHING — Legwear ─────────────────────────────────────────────
    ("loincloth",         "a simple wrapped loincloth of rough cloth, laid flat"),

    # ── VI. TEXTILES & RAW MATERIALS ──────────────────────────────────────
    ("linen_cheap",       "a folded bolt of cheap undyed linen fabric"),
    ("linen_fine",        "a folded bolt of fine bleached white linen fabric"),
    ("wool_cheap",        "a folded bolt of coarse undyed natural wool fabric"),
    ("wool_fine",         "a folded bolt of fine dyed quality wool fabric in a rich color"),
    ("silk_yard",         "a folded yard of shimmering colorful silk fabric"),

    # ── VII. GEAR — Containers ─────────────────────────────────────────────
    ("backpack",          "a leather adventurer's backpack with buckled straps and multiple pouches"),
    ("sack_large",        "a large burlap sack with a rope tie at the top"),
    ("sack_small",        "a small burlap sack with a rope tie at the top"),
    ("pouch",             "a small leather drawstring coin pouch"),
    ("barrel",            "a large wooden barrel with iron hoops, approximately twenty gallons"),
    ("chest_ironbound",   "a sturdy wooden chest with iron corner brackets and a padlock hasp"),

    # ── VII. GEAR — Light & Fire ───────────────────────────────────────────
    ("torch",             "a wooden torch wrapped in pitch-soaked cloth at the tip"),
    ("lantern",           "a brass oil lantern with glass panels and a hinged door"),
    ("candle_tallow",     "a single tallow candle in a simple candleholder"),
    ("candle_wax",        "a single smooth white wax candle"),
    ("tinderbox",         "a small metal tinderbox with a flint and steel striker inside"),
    ("oil_flask_common",  "a ceramic oil flask with a cork stopper"),
    ("oil_flask_military","a small sealed clay military burning oil flask"),

    # ── VII. GEAR — Climbing & Exploration ────────────────────────────────
    ("rope_50ft",         "a thick coil of hempen rope"),
    ("grappling_hook",    "a four-pronged iron grappling hook with an attachment ring"),
    ("iron_spikes_12",    "twelve iron climbing spikes with flat heads, bundled together"),
    ("pole_wooden_10ft",  "a long straight wooden pole ten feet in length"),
    ("mallet",            "a wooden mallet with a large cylindrical head and short handle"),

    # ── VII. GEAR — Tools ─────────────────────────────────────────────────
    ("craftsmans_tools",  "a leather tool roll partly unrolled, containing chisels, files, and measuring implements"),
    ("machinists_tools",  "a machinist's precision tool case open, showing calipers, small hammers, and punches"),
    ("thieves_tools",     "a leather lockpick roll partly unrolled, containing lockpicks, tension wrenches, and probes"),
    ("hammer_small",      "a small iron-headed hammer with a wooden handle"),
    ("lock",              "a heavy iron padlock with a keyhole"),
    ("manacles",          "a pair of iron wrist manacles connected by a short chain"),
    ("mirror_small",      "a small hand-held polished steel hand mirror with a handle"),

    # ── VII. GEAR — Camp & Survival ────────────────────────────────────────
    ("tent",              "a canvas A-frame tent with wooden poles and rope guy lines"),
    ("blanket",           "a thick folded wool blanket"),
    ("waterskin",         "a leather waterskin with a cork stopper and a carrying strap"),
    ("rations_standard_week", "a one-week supply of standard travel rations: wrapped cloth packages of dried bread and dried meat"),
    ("rations_iron_week", "a one-week supply of iron rations in waxed cloth packages: dense hardtack and jerky"),
    ("fodder",            "a large bundle of hay and feed for horses, tied with twine"),

    # ── VII. GEAR — Religious & Ritual ─────────────────────────────────────
    ("holy_symbol",       "a holy symbol: a silver sunburst pendant on a chain"),
    ("holy_book",         "a leather-bound holy scripture with a gilded cover and ribbon bookmark"),
    ("holy_water",        "a sealed glass vial of holy water with a wax seal and cork stopper"),
    ("wooden_stakes_4",   "four sharpened wooden stakes tied together in a bundle"),

    # ── VII. GEAR — Herbs & Reagents ───────────────────────────────────────
    ("belladonna",        "a bundle of belladonna nightshade herb with dark berries and purple-black flowers"),
    ("birthwort",         "a bundle of birthwort herb with its distinctive curved pipe-shaped flowers"),
    ("comfrey",           "a bundle of comfrey herb with fuzzy leaves and small bell-shaped purple flowers"),
    ("garlic",            "a whole head of garlic with papery white skin and several cloves"),
    ("goldenrod",         "a bundle of goldenrod herb with bright yellow flower clusters"),
    ("wolfsbane",         "a bundle of wolfsbane aconite herb with deep purple hooded flowers"),
    ("woundwart",         "a bundle of woundwort herb with hairy stems and pale pink flowers"),

    # ── VII. GEAR — Writing & Scholarly ───────────────────────────────────
    ("ink",               "a small glass inkwell with a cork stopper, filled with dark black ink"),
    ("journal",           "a leather-bound journal with a leather cord tie closure"),
    ("spell_book_blank",  "a blank spellbook with a thick leather cover embossed with arcane symbols"),
    ("spell_component_pouch", "a small leather drawstring pouch with visible spell components: feathers, crystals, dried herbs"),

    # ── VII. GEAR — Entertainment & Misc ──────────────────────────────────
    ("dice",              "a pair of polished bone six-sided dice with pip markings"),
    ("musical_instrument_common",    "a simple wooden recorder flute, a common folk instrument"),
    ("musical_instrument_fine",      "a fine quality lute with inlaid wood decoration and carved wooden tuning pegs"),
    ("musical_instrument_masterwork","a masterwork lute with elaborate inlay work, gilded tuning pegs, and exquisite craftsmanship"),

    # ── VIII. PROVISIONS — Staple Foods ───────────────────────────────────
    ("bread_white",       "a round loaf of white bread"),
    ("bread_wheat",       "a round loaf of whole wheat bread"),
    ("bread_coarse",      "a round coarse dark brown bread loaf"),
    ("cheese",            "a wedge of hard yellow cheese"),
    ("meat_1lb",          "a portion of raw red meat on a wooden cutting board"),
    ("eggs_dozen",        "a dozen white eggs in a small wicker basket"),
    ("dried_fruit",       "a pile of assorted dried fruits: raisins, dates, and figs"),

    # ── VIII. PROVISIONS — Drink ───────────────────────────────────────────
    ("ale_cheap",         "a wooden tankard of frothy brown cheap ale"),
    ("ale_good",          "a pewter tankard of good quality golden ale with a foam head"),
    ("wine_cheap",        "a clay jug and cup of cheap red wine"),
    ("wine_good",         "a glass goblet of good quality red wine"),
    ("wine_rare",         "an elegant crystal goblet of rare vintage red wine"),

    # ── VIII. PROVISIONS — Spices & Luxury ────────────────────────────────
    ("spices_common",     "a small clay pot of mixed common spices with a cork lid"),
    ("saffron",           "a small glass vial of precious golden-red saffron threads"),

    # ── IX. TRANSPORT — Riding Mounts ─────────────────────────────────────
    ("light_riding_horse",  "a lean agile bay light riding horse, full side profile"),
    ("medium_riding_horse", "a sturdy chestnut medium riding horse, full side profile"),
    ("light_warhorse",      "a muscular dark light warhorse with basic war tack, full side profile"),
    ("medium_warhorse",     "a powerful dapple grey medium warhorse destrier with full war tack, full side profile"),
    ("heavy_warhorse",      "a massive black heavy warhorse destrier with full barding and war tack, full side profile"),
    ("camel",               "a single-humped dromedary camel with a simple saddle blanket, full side profile"),

    # ── IX. TRANSPORT — Draft Animals ─────────────────────────────────────
    ("medium_draft_horse",  "a stocky roan medium draft horse with a collar harness, full side profile"),
    ("heavy_draft_horse",   "a massive shire heavy draft horse with full collar harness and feathered feet, full side profile"),
    ("ox",                  "a large brown and white ox with a wooden yoke across its shoulders, full side profile"),

    # ── IX. TRANSPORT — Pack Animals ──────────────────────────────────────
    ("donkey",              "a donkey with a simple pack saddle and empty saddlebags, full side profile"),
    ("mule",                "a mule with a pack saddle and loaded canvas bags, full side profile"),

    # ── IX. TRANSPORT — Livestock ──────────────────────────────────────────
    ("cow",                 "a brown and white dairy cow, full side profile"),
    ("goat",                "a white and grey goat with small horns, full side profile"),
    ("sheep",               "a fluffy white woolly sheep, full side profile"),

    # ── IX. TRANSPORT — Companion Animals ─────────────────────────────────
    ("hunting_dog",         "a lean alert greyhound hunting dog in a standing side pose"),
    ("war_dog",             "a large mastiff war dog with a spiked iron collar, standing guard in side pose"),
    ("hawk_trained",        "a trained hawk or falcon perched on a post with a leather jess on its leg"),

    # ── IX. TRANSPORT — Tack & Harness ────────────────────────────────────
    ("saddle_riding",       "a leather riding saddle with stirrups"),
    ("saddle_war",          "a high-cantled war saddle with stirrups and extra leather reinforcing"),
    ("saddle_draft",        "a heavy leather draft horse harness collar and hames set"),
    ("saddle_pack",         "a simple wooden pack saddle frame with leather lashing straps"),
    ("saddlebags",          "a pair of leather saddlebags connected by a center strap"),
    ("panniers",            "a pair of wicker basket panniers connected by a carrying strap"),
    ("caparison",           "a warhorse caparison: a decorative heraldic cloth covering with fringe, laid flat"),

    # ── IX. TRANSPORT — Barding ────────────────────────────────────────────
    ("barding_leather",     "a set of leather horse barding armor pieces for neck and body, laid flat"),
    ("barding_scale",       "a set of scale mail horse barding with overlapping metal scales, laid flat"),
    ("barding_chain",       "a set of chain mail horse barding in interlocked iron rings, laid flat"),
    ("barding_lamellar",    "a set of lamellar horse barding with horizontal plates laced together, laid flat"),
    ("barding_plate",       "a full set of articulated steel plate armor for a warhorse, laid flat"),

    # ── IX. TRANSPORT — Vehicles ──────────────────────────────────────────
    ("cart_small",          "a small two-wheeled wooden cart"),
    ("cart_large",          "a large two-wheeled wooden cart with wooden sideboards"),
    ("wagon",               "a four-wheeled wooden covered wagon with a canvas top"),

    # ── X. TREASURE & CURRENCY ────────────────────────────────────────────
    ("coins_gp",            "a pile of shiny gold coins"),

    # ── XI. MAGIC ITEMS PLACEHOLDER ───────────────────────────────────────
    ("__magic_placeholder", "a glowing four-pointed arcane star sigil with magical energy radiating outward in beams of light"),
]


# ── API HELPERS ────────────────────────────────────────────────────────────

def _auth_header(key, secret):
    token = base64.b64encode(f"{key}:{secret}".encode()).decode()
    return {"Authorization": f"Basic {token}", "Content-Type": "application/json"}

def _request(method, path, body=None, headers=None):
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code} on {method} {path}: {e.read().decode()}")

def submit_job(key, secret, prompt):
    hdrs = _auth_header(key, secret)
    body = {
        "prompt": prompt,
        "width": 1024,
        "height": 1024,
        "quality": "low",
        "numOutputs": 1,
    }
    resp = _request("POST", f"/generate/custom/{MODEL_ID}", body=body, headers=hdrs)
    return resp["job"]["jobId"]

def poll_job(key, secret, job_id):
    """Poll until success/failure. Returns list of asset_ids or raises."""
    hdrs = _auth_header(key, secret)
    deadline = time.time() + MAX_WAIT
    while time.time() < deadline:
        resp = _request("GET", f"/jobs/{job_id}", headers=hdrs)
        job = resp["job"]
        status = job["status"]
        if status == "success":
            return job["metadata"]["assetIds"]
        if status in ("failure", "canceled"):
            raise RuntimeError(f"Job {job_id} ended with status={status}")
        time.sleep(POLL_INTERVAL)
    raise TimeoutError(f"Job {job_id} didn't complete within {MAX_WAIT}s")

def get_asset_url(key, secret, asset_id):
    """Return the CDN download URL for an asset."""
    hdrs = _auth_header(key, secret)
    # Remove Content-Type for GET
    hdrs = {k: v for k, v in hdrs.items() if k != "Content-Type"}
    resp = _request("GET", f"/assets/{asset_id}", headers=hdrs)
    asset = resp.get("asset", resp)  # SDK may unwrap differently
    # Try common URL fields
    url = (
        asset.get("url")
        or asset.get("downloadUrl")
        or (asset.get("metadata") or {}).get("url")
    )
    if not url:
        raise RuntimeError(f"No download URL in asset: {json.dumps(asset)[:300]}")
    return url

def download_file(url, dest_path):
    """Download a URL to a local file."""
    req = urllib.request.Request(url, headers={"User-Agent": "ACKS-Arbiter-IconGen/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp, open(dest_path, "wb") as f:
        f.write(resp.read())


# ── MAIN ───────────────────────────────────────────────────────────────────

def main():
    if not API_KEY or not API_SECRET:
        print(
            "ERROR: Set SCENARIO_SDK_API_KEY and SCENARIO_SDK_API_SECRET env vars.\n"
            "  Find them at: https://app.scenario.com → Project Settings → API Keys"
        )
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Filter out already-done items (resumable)
    todo = [(key, desc) for key, desc in ITEMS
            if not (OUTPUT_DIR / f"{key}.png").exists()]

    if not todo:
        print("All icons already exist. Nothing to do.")
        return

    total   = len(ITEMS)
    done    = total - len(todo)
    print(f"Icons to generate: {len(todo)}/{total}  ({done} already done, skipping)")

    failed = []

    # Process in batches
    for batch_start in range(0, len(todo), BATCH_SIZE):
        batch = todo[batch_start:batch_start + BATCH_SIZE]
        print(f"\n── Batch {batch_start // BATCH_SIZE + 1}  "
              f"(items {batch_start + 1}–{batch_start + len(batch)}) ──────────────")

        # Submit all jobs in the batch
        jobs = {}  # job_id → (key, desc)
        for key, desc in batch:
            prompt = PROMPT_TEMPLATE.format(desc=desc)
            try:
                job_id = submit_job(API_KEY, API_SECRET, prompt)
                jobs[job_id] = key
                print(f"  submitted  {key:40s}  job={job_id}")
            except Exception as e:
                print(f"  FAILED to submit {key}: {e}")
                failed.append(key)

        if not jobs:
            continue

        # Poll all jobs until done
        pending = dict(jobs)  # job_id → key
        while pending:
            time.sleep(POLL_INTERVAL)
            finished = []
            for job_id, key in list(pending.items()):
                try:
                    hdrs = _auth_header(API_KEY, API_SECRET)
                    hdrs = {k: v for k, v in hdrs.items() if k != "Content-Type"}
                    resp = _request("GET", f"/jobs/{job_id}", headers=hdrs)
                    job  = resp["job"]
                    status = job["status"]
                    if status == "success":
                        asset_ids = job["metadata"]["assetIds"]
                        try:
                            url = get_asset_url(API_KEY, API_SECRET, asset_ids[0])
                            dest = OUTPUT_DIR / f"{key}.png"
                            download_file(url, dest)
                            print(f"  ✓  {key}")
                        except Exception as e:
                            print(f"  ✗  {key}  (download failed: {e})")
                            failed.append(key)
                        finished.append(job_id)
                    elif status in ("failure", "canceled"):
                        print(f"  ✗  {key}  (job {status})")
                        failed.append(key)
                        finished.append(job_id)
                    # else still running — leave in pending
                except Exception as e:
                    print(f"  poll error for {key}: {e}")
            for j in finished:
                pending.pop(j, None)

    print("\n══════════════════════════════════════════")
    saved = sum(1 for key, _ in ITEMS if (OUTPUT_DIR / f"{key}.png").exists())
    print(f"Done.  {saved}/{total} icons saved to:\n  {OUTPUT_DIR}")
    if failed:
        print(f"\nFailed ({len(failed)}): {', '.join(failed)}")
        print("Re-run the script to retry failed items.")
    else:
        print("All succeeded!")


if __name__ == "__main__":
    main()
