#!/usr/bin/env python3
"""Send equipment icons to Scenario's AI background remover -> transparent PNGs.

Per image, against the Scenario REST API (https://docs.scenario.com):
  1. upload : POST /v1/assets  { image: <base64>, name }              -> assetId
  2. remove : POST /v1/generate/remove-background { image: assetId }  -> inferenceId
  3. poll   : GET  /v1/generate/remove-background/{inferenceId}        until succeeded
  4. fetch the result image, ensure RGBA + 256x256, save back over the file.

Auth: Basic base64("<API_KEY>:<API_SECRET>"). Set both as env vars (never hard-code):
    SCENARIO_API_KEY, SCENARIO_API_SECRET   (Organization settings -> API keys)

Confirmed against the API: base URL, Basic auth, the /v1/assets upload, and the
/v1/generate/remove-background endpoint. The inference request/poll FIELD NAMES
follow Scenario's standard inference pattern; the response parsing below is
defensive (tries the common shapes). If your account returns something different,
run `--dry-run` (one image, prints raw JSON) and adjust _find_asset_id /
_find_inference_id / _find_result in one place.

Only stdlib + Pillow. Non-destructive by default (writes to <dir>_nobg/); pass
--inplace to overwrite the icons.

Usage:
    export SCENARIO_API_KEY=...   SCENARIO_API_SECRET=...
    python tools/scenario_remove_backgrounds.py --dry-run     # validate on 1 image
    python tools/scenario_remove_backgrounds.py               # all -> <dir>_nobg/
    python tools/scenario_remove_backgrounds.py --inplace     # overwrite in place
"""
from __future__ import annotations
import argparse
import base64
import glob
import io
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request

from PIL import Image

BASE_URL = "https://api.cloud.scenario.com/v1"
# Resolve relative to this file (tools/ -> project root) so it works from any CWD.
_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(_PROJECT_ROOT, "assets", "icons", "equipment_icons")


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def _auth_header() -> str:
    key = os.environ.get("SCENARIO_API_KEY")
    secret = os.environ.get("SCENARIO_API_SECRET")
    if not key or not secret:
        sys.exit("error: set SCENARIO_API_KEY and SCENARIO_API_SECRET environment variables.")
    token = base64.b64encode(f"{key}:{secret}".encode()).decode()
    return "Basic " + token


def _request(method: str, path: str, body=None, raw: bool = False, verbose: bool = False):
    url = path if path.startswith("http") else BASE_URL + path
    headers = {"Authorization": _auth_header(), "Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            payload = resp.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} on {method} {url}\n{e.read().decode(errors='replace')}")
    if raw:
        return payload
    out = json.loads(payload) if payload else {}
    if verbose:
        print(json.dumps(out, indent=2)[:2500])
    return out


# ---------------------------------------------------------------------------
# Defensive response parsing (adjust here if your account's shapes differ)
# ---------------------------------------------------------------------------

def _find_asset_id(resp: dict):
    a = resp.get("asset", resp)
    return a.get("id") or resp.get("assetId") or resp.get("id")


def _download(url: str) -> bytes:
    """Plain GET (no API auth header) — the result CDN url is already signed."""
    with urllib.request.urlopen(urllib.request.Request(url, method="GET"), timeout=180) as resp:
        return resp.read()


# ---------------------------------------------------------------------------
# Pipeline steps
# ---------------------------------------------------------------------------

def upload(path: str, verbose: bool) -> str:
    img_b64 = base64.b64encode(open(path, "rb").read()).decode()
    resp = _request("POST", "/assets",
                    {"image": img_b64, "name": os.path.basename(path)}, verbose=verbose)
    aid = _find_asset_id(resp)
    if not aid:
        sys.exit("could not find asset id in upload response:\n" + json.dumps(resp, indent=2))
    return aid


_DONE = ("success", "succeeded", "complete", "completed", "done")


def remove_background(asset_id: str, verbose: bool) -> str:
    """POST the removal and return the result image URL. The endpoint is
    SYNCHRONOUS: it returns the de-backgrounded asset directly (resp.asset.url),
    with resp.job carrying status + produced assetIds. If a job ever comes back
    not-yet-done, fall back to polling it."""
    resp = _request("POST", "/generate/remove-background",
                    {"image": asset_id, "format": "png"}, verbose=verbose)
    asset = resp.get("asset", {})
    job = resp.get("job", {})
    status = str(job.get("status", "success")).lower()
    if status in _DONE:
        if asset.get("url"):
            return asset["url"]
        ids = job.get("metadata", {}).get("assetIds") or ([asset["id"]] if asset.get("id") else [])
        if ids:
            return asset_download_url(ids[0], verbose)
        sys.exit("no result asset in response:\n" + json.dumps(resp, indent=2))
    # Async fallback: poll the job, then fetch the produced asset.
    job_id = job.get("jobId") or job.get("id")
    if not job_id:
        sys.exit("job not done and no jobId:\n" + json.dumps(resp, indent=2))
    return asset_download_url(_poll_job(job_id, verbose), verbose)


def _poll_job(job_id: str, verbose: bool, timeout: int = 180) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        resp = _request("GET", f"/jobs/{job_id}", verbose=verbose)
        job = resp.get("job", resp)
        status = str(job.get("status", "")).lower()
        if status in _DONE:
            ids = job.get("metadata", {}).get("assetIds") or []
            if ids:
                return ids[0]
            sys.exit("job done but no assetIds:\n" + json.dumps(resp, indent=2))
        if status in ("failed", "error", "canceled", "cancelled"):
            sys.exit("job failed:\n" + json.dumps(resp, indent=2))
        time.sleep(2)
    sys.exit(f"timed out polling job {job_id}")


def asset_download_url(asset_id: str, verbose: bool) -> str:
    resp = _request("GET", f"/assets/{asset_id}", verbose=verbose)
    a = resp.get("asset", resp)
    url = a.get("url") or a.get("downloadUrl") or a.get("image")
    if not url:
        sys.exit("no download url on asset:\n" + json.dumps(resp, indent=2))
    return url


def save_result(url: str, dst: str, size: int) -> None:
    raw = _download(url)
    im = Image.open(io.BytesIO(raw)).convert("RGBA")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    im.save(dst, "PNG", optimize=True)


def process(path: str, out_dir: str, size: int, verbose: bool) -> None:
    asset_id = upload(path, verbose)
    url = remove_background(asset_id, verbose)
    save_result(url, os.path.join(out_dir, os.path.basename(path)), size)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description="Scenario AI background removal for the equipment icons.")
    ap.add_argument("--dir", default=DEFAULT_DIR, help="folder of .png icons")
    ap.add_argument("--size", type=int, default=256, help="output square size")
    ap.add_argument("--inplace", action="store_true", help="process + overwrite the icons in one pass (re-runs the API — costs CU)")
    ap.add_argument("--apply", action="store_true", help="just COPY <dir>_nobg/ over the originals (no API calls) — use after reviewing")
    ap.add_argument("--dry-run", action="store_true", help="process ONE image, verbose, to <dir>_nobg/ — validate the API shape first")
    ap.add_argument("--verbose", action="store_true", help="dump raw JSON responses")
    ap.add_argument("--skip", nargs="*", default=["__magic_placeholder"], help="item_key stems to skip")
    ap.add_argument("--sleep", type=float, default=0.5, help="pause between images (rate-limit courtesy)")
    args = ap.parse_args()

    # --apply: pure local copy of the reviewed results over the originals (no API).
    if args.apply:
        src_dir = args.dir.rstrip("/\\") + "_nobg"
        srcs = sorted(glob.glob(os.path.join(src_dir, "*.png")))
        if not srcs:
            sys.exit(f"nothing to apply — {src_dir} is empty (run without --apply first)")
        for f in srcs:
            shutil.copy2(f, os.path.join(args.dir, os.path.basename(f)))
        print(f"copied {len(srcs)} files: {src_dir} -> {args.dir}")
        print("re-import in Godot.")
        return

    files = sorted(glob.glob(os.path.join(args.dir, "*.png")))
    files = [f for f in files if os.path.splitext(os.path.basename(f))[0] not in args.skip]
    if not files:
        sys.exit("no .png files in " + args.dir)
    if args.dry_run:
        files = files[:1]
        args.verbose = True

    out_dir = args.dir if (args.inplace and not args.dry_run) else args.dir.rstrip("/\\") + "_nobg"
    os.makedirs(out_dir, exist_ok=True)

    for i, f in enumerate(files, 1):
        print(f"[{i}/{len(files)}] {os.path.basename(f)} ...", flush=True)
        process(f, out_dir, args.size, args.verbose)
        time.sleep(args.sleep)

    print(f"\ndone -> {out_dir}")
    if not args.inplace:
        print("review, then re-run with --inplace (or copy over) to apply. Re-import in Godot afterward.")


if __name__ == "__main__":
    main()
