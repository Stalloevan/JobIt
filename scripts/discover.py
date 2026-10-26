#!/usr/bin/env python3
"""Finds company job boards on Greenhouse, Lever, Ashby and SmartRecruiters, checks that each one
is live and has openings, and writes data/boards.json.

Sources: the Internet Archive's index of board URLs, plus data/seed_boards.txt (one "ats:slug" per line).
"""
import concurrent.futures as cf
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (compatible; JobItFeed/1.0; +https://github.com/Stalloevan/JobIt)"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

SOURCES = {
    "greenhouse": [r"boards\.greenhouse\.io", r"job-boards\.greenhouse\.io"],
    "lever": [r"jobs\.lever\.co"],
    "ashby": [r"jobs\.ashbyhq\.com"],
    "smartrecruiters": [r"jobs\.smartrecruiters\.com"],
}
SLUG = r"[A-Za-z0-9][A-Za-z0-9_.%-]*"
RESERVED = {
    "embed", "jobs", "job_app", "api", "v1", "static", "assets", "login", "robots.txt", "sitemap.xml",
    "favicon.ico", "about", "privacy", "terms", "cookies", "search", "careers", "apply", "oauth", "img",
    "images", "css", "js", "fonts", "health", "status", "undefined", "null",
}


def get(url, timeout=30, retries=2, data=None, headers=None):
    """Returns (status, body). Never raises. Status 0 means a network error."""
    h = {"User-Agent": UA, "Accept": "application/json,text/plain,*/*"}
    if headers:
        h.update(headers)
    last = (0, b"")
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, data=data, headers=h)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            last = (e.code, b"")
            if e.code in (400, 403, 404, 410):
                return last
        except Exception:
            last = (0, b"")
        time.sleep(1.5 * (attempt + 1))
    return last


def wayback_slugs(host_re):
    """Board root URLs the Internet Archive has seen for one host, reduced to slugs."""
    host = host_re.replace("\\", "")
    regex = rf"https?://{host_re}/{SLUG}/?(\?.*)?$"
    query = urllib.parse.urlencode({
        "url": host + "/*",
        "output": "txt",
        "fl": "original",
        "collapse": "urlkey",
        "filter": "original:" + regex,
        "limit": "400000",
    })
    status, body = get("https://web.archive.org/cdx/search/cdx?" + query, timeout=420, retries=2)
    pat = re.compile(rf"https?://{host_re}/({SLUG})/?(?:\?.*)?$")
    slugs = set()
    for line in body.decode("utf-8", "replace").splitlines():
        m = pat.match(line.strip())
        if not m:
            continue
        slug = urllib.parse.unquote(m.group(1)).strip().lower()
        if slug and slug not in RESERVED and len(slug) >= 2:
            slugs.add(slug)
    return status, slugs


def check(ats, slug):
    """Returns the number of open postings, or -1 if the board does not exist."""
    q = urllib.parse.quote(slug, safe="")
    if ats == "greenhouse":
        status, body = get(f"https://boards-api.greenhouse.io/v1/boards/{q}/jobs", retries=1)
        key = "jobs"
    elif ats == "lever":
        status, body = get(f"https://api.lever.co/v0/postings/{q}?mode=json", retries=1)
        key = None
    elif ats == "ashby":
        status, body = get(f"https://api.ashbyhq.com/posting-api/job-board/{q}", retries=1)
        key = "jobs"
    else:
        status, body = get(f"https://api.smartrecruiters.com/v1/companies/{q}/postings?limit=1", retries=1)
        key = "totalFound"
    if status != 200:
        return -1
    try:
        data = json.loads(body)
    except Exception:
        return -1
    if ats == "lever":
        return len(data) if isinstance(data, list) else -1
    if ats == "smartrecruiters":
        return int(data.get(key, 0)) if isinstance(data, dict) else -1
    return len(data.get(key, [])) if isinstance(data, dict) else -1


def load_seeds():
    path = os.path.join(DATA, "seed_boards.txt")
    seeds = set()
    if not os.path.exists(path):
        return seeds
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        ats, slug = line.split(":", 1)
        ats, slug = ats.strip().lower(), slug.strip().lower()
        if ats in SOURCES and slug:
            seeds.add((ats, slug))
    return seeds


def main():
    report = {"wayback": {}, "alive": {}, "candidates": {}}
    candidates = set()

    for ats, hosts in SOURCES.items():
        found = set()
        for host_re in hosts:
            status, slugs = wayback_slugs(host_re)
            report["wayback"][host_re.replace("\\", "")] = {"http": status, "slugs": len(slugs)}
            print(f"wayback {host_re}: http {status}, {len(slugs)} slugs", flush=True)
            found |= slugs
        for slug in found:
            candidates.add((ats, slug))

    seeds = load_seeds()
    report["seeds"] = len(seeds)
    candidates |= seeds

    # Also re-check boards that were alive last time.
    prev_path = os.path.join(DATA, "boards.json")
    if os.path.exists(prev_path):
        try:
            for b in json.load(open(prev_path, encoding="utf-8")):
                candidates.add((b["a"], b["s"]))
        except Exception:
            pass

    for ats, _ in candidates:
        report["candidates"][ats] = report["candidates"].get(ats, 0) + 1
    print("candidates:", report["candidates"], flush=True)

    alive = []
    done = 0
    items = sorted(candidates)
    with cf.ThreadPoolExecutor(max_workers=40) as pool:
        futures = {pool.submit(check, ats, slug): (ats, slug) for ats, slug in items}
        for fut in cf.as_completed(futures):
            ats, slug = futures[fut]
            try:
                n = fut.result()
            except Exception:
                n = -1
            done += 1
            if n > 0:
                alive.append({"a": ats, "s": slug, "n": n})
            if done % 1000 == 0:
                print(f"checked {done}/{len(items)}, alive {len(alive)}", flush=True)

    alive.sort(key=lambda b: (b["a"], b["s"]))
    for b in alive:
        report["alive"][b["a"]] = report["alive"].get(b["a"], 0) + 1

    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "boards.json"), "w", encoding="utf-8") as f:
        json.dump(alive, f, separators=(",", ":"))
    with open(os.path.join(DATA, "discovery_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    summary = json.dumps(report)
    print("::notice title=Discovery::" + summary.replace("\n", "%0A"))
    print("done:", summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
