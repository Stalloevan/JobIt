#!/usr/bin/env python3
"""Builds the job feed the app downloads.

Reads data/boards.json (live Greenhouse, Lever, Ashby and SmartRecruiters boards), pulls every
posting, keeps relevant US/Northeast/remote roles, and writes out/jobs.json and out/meta.json.
Settings live in data/feed_config.json.
"""
import concurrent.futures as cf
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

UA = "Mozilla/5.0 (compatible; JobItFeed/1.0; +https://github.com/Stalloevan/JobIt)"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(ROOT, "out")

TAG = re.compile(r"<[^>]+>")
SAL = re.compile(r"\$\s?(\d{2,3})(?:,(\d{3})|\s?[kK])")


def get(url, timeout=30, retries=2):
    """Returns (status, body). Never raises. Status 0 means a network error."""
    last = (0, b"")
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
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


def load_json(body):
    try:
        return json.loads(body)
    except Exception:
        return None


# ---------- text helpers ----------

def plain(s):
    s = html.unescape(html.unescape(s or ""))
    s = TAG.sub(" ", s)
    return " ".join(s.split())


def pretty(slug):
    return re.sub(r"[-_.]+", " ", slug).strip().title()


def salary_min(text):
    for m in SAL.finditer(text or ""):
        base = int(m.group(1))
        value = base * 1000 + (int(m.group(2)) if m.group(2) else 0)
        if value >= 20000:
            return value
    return 0


def to_epoch(value):
    if not value:
        return 0
    try:
        if isinstance(value, (int, float)):
            v = float(value)
            return int(v / 1000) if v > 1e11 else int(v)
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp())
    except Exception:
        return 0


# ---------- filters ----------

class Filters:
    def __init__(self, cfg):
        self.cfg = cfg
        self.include = re.compile(cfg["title_include"], re.I)
        self.exclude = re.compile(cfg["title_exclude"], re.I)
        self.states = [re.compile(rf"(?:^|[\s,(/-]){s}(?:$|[\s,)/.-])") for s in cfg["states"]]
        self.state_names = cfg["state_names"]
        self.cities = cfg["cities"]
        self.non_us = [re.compile(rf"\b{re.escape(t)}\b") for t in cfg["non_us"]]
        self.us_token = re.compile(r"\b(united states|usa|u\.s\.a?\.?|us)\b")

    def title_ok(self, title):
        if not title:
            return False
        if self.exclude.search(title):
            return False
        return bool(self.include.search(title))

    def location_ok(self, loc):
        text = (loc or "").strip()
        if not text:
            return False
        low = text.lower()
        has_us = bool(self.us_token.search(low))
        if not has_us and any(p.search(low) for p in self.non_us):
            return False
        if "remote" in low or "anywhere" in low:
            return True
        if any(n in low for n in self.state_names):
            return True
        if any(s.search(text) for s in self.states):
            return True
        return any(c in low for c in self.cities)

    def flags(self, text):
        low = (text or "").lower()
        found = [t for t in self.cfg["defense_terms"] if t in low]
        return " ".join(f"[{t}]" for t in found)


def record(f, rid, title, company, loc, url, posted, salary, desc, ats):
    snippet = (f.flags(desc) + " " + desc[: f.cfg["snippet_chars"]]).strip()
    return {"i": rid, "t": title, "c": company, "l": loc, "u": url, "p": posted, "s": salary, "d": snippet, "a": ats}


# ---------- per-ATS fetchers ----------

def greenhouse(slug, f):
    status, body = get(f"https://boards-api.greenhouse.io/v1/boards/{urllib.parse.quote(slug)}/jobs", timeout=40)
    data = load_json(body) if status == 200 else None
    if not isinstance(data, dict):
        return []
    out = []
    for j in data.get("jobs", []):
        title = j.get("title") or ""
        loc = (j.get("location") or {}).get("name") or ""
        if not f.title_ok(title) or not f.location_ok(loc):
            continue
        if len(out) >= f.cfg["max_per_board"]:
            break
        desc, sal = "", 0
        st, b = get(f"https://boards-api.greenhouse.io/v1/boards/{urllib.parse.quote(slug)}/jobs/{j.get('id')}?pay_transparency=true", retries=1)
        d = load_json(b) if st == 200 else None
        if isinstance(d, dict):
            desc = plain(d.get("content"))
            for r in d.get("pay_input_ranges") or []:
                cents = r.get("min_cents") or 0
                if cents and cents // 100 >= 20000:
                    sal = cents // 100
                    break
            if not sal:
                sal = salary_min(desc)
        out.append(record(
            f, f"gh-{slug}-{j.get('id')}", title, j.get("company_name") or pretty(slug), loc,
            j.get("absolute_url") or "", to_epoch(j.get("updated_at")), sal, desc, "g",
        ))
    return out


def lever(slug, f):
    status, body = get(f"https://api.lever.co/v0/postings/{urllib.parse.quote(slug)}?mode=json", timeout=40)
    data = load_json(body) if status == 200 else None
    if not isinstance(data, list):
        return []
    out = []
    for p in data:
        title = p.get("text") or ""
        cats = p.get("categories") or {}
        locs = [x for x in [cats.get("location")] + list(cats.get("allLocations") or []) if x]
        loc = " / ".join(dict.fromkeys(locs))
        if p.get("workplaceType") == "remote":
            loc = (loc + " Remote").strip()
        if not f.title_ok(title) or not f.location_ok(loc):
            continue
        if len(out) >= f.cfg["max_per_board"]:
            break
        desc = plain((p.get("descriptionPlain") or "") + " " + (p.get("additionalPlain") or ""))
        sal = 0
        sr = p.get("salaryRange") or {}
        if sr.get("min") and sr.get("interval") == "per-year-salary" and sr["min"] >= 20000:
            sal = int(sr["min"])
        if not sal:
            sal = salary_min(desc)
        out.append(record(
            f, f"lv-{slug}-{p.get('id')}", title, pretty(slug), loc,
            p.get("hostedUrl") or p.get("applyUrl") or "", to_epoch(p.get("createdAt")), sal, desc, "l",
        ))
    return out


def ashby(slug, f):
    status, body = get(f"https://api.ashbyhq.com/posting-api/job-board/{urllib.parse.quote(slug)}?includeCompensation=true", timeout=40)
    data = load_json(body) if status == 200 else None
    if not isinstance(data, dict):
        return []
    out = []
    for p in data.get("jobs", []):
        if p.get("isListed") is False:
            continue
        title = p.get("title") or ""
        locs = [p.get("location")] + [s.get("location") for s in (p.get("secondaryLocations") or []) if isinstance(s, dict)]
        loc = " / ".join(dict.fromkeys([x for x in locs if x]))
        if p.get("isRemote") or p.get("workplaceType") == "Remote":
            loc = (loc + " Remote").strip()
        if not f.title_ok(title) or not f.location_ok(loc):
            continue
        if len(out) >= f.cfg["max_per_board"]:
            break
        desc = plain(p.get("descriptionPlain") or p.get("descriptionHtml") or "")
        comp = ((p.get("compensation") or {}).get("compensationTierSummary")) or ""
        sal = salary_min(comp) or salary_min(desc)
        out.append(record(
            f, f"ab-{slug}-{p.get('id') or p.get('jobUrl', '')[-36:]}", title, pretty(slug), loc,
            p.get("jobUrl") or p.get("applyUrl") or "", to_epoch(p.get("publishedAt")), sal, desc, "b",
        ))
    return out


def smartrecruiters(slug, f):
    out = []
    offset = 0
    while offset < 300:
        status, body = get(f"https://api.smartrecruiters.com/v1/companies/{urllib.parse.quote(slug)}/postings?limit=100&offset={offset}", timeout=40)
        data = load_json(body) if status == 200 else None
        if not isinstance(data, dict):
            break
        content = data.get("content") or []
        for p in content:
            title = p.get("name") or ""
            lc = p.get("location") or {}
            parts = [lc.get("city"), (lc.get("region") or "").upper(), (lc.get("country") or "").upper()]
            loc = ", ".join([x for x in parts if x])
            if lc.get("remote"):
                loc = (loc + " Remote").strip()
            if not f.title_ok(title) or not f.location_ok(loc):
                continue
            if len(out) >= f.cfg["max_per_board"]:
                break
            labels = [
                (p.get("function") or {}).get("label"),
                (p.get("department") or {}).get("label"),
                (p.get("experienceLevel") or {}).get("label"),
                (p.get("typeOfEmployment") or {}).get("label"),
            ]
            desc = " | ".join([x for x in labels if x])
            company = (p.get("company") or {}).get("name") or pretty(slug)
            ident = (p.get("company") or {}).get("identifier") or slug
            out.append(record(
                f, f"sr-{slug}-{p.get('id')}", title, company, loc,
                f"https://jobs.smartrecruiters.com/{ident}/{p.get('id')}", to_epoch(p.get("releasedDate")), 0, desc, "s",
            ))
        if len(content) < 100 or len(out) >= f.cfg["max_per_board"]:
            break
        offset += 100
    return out


FETCHERS = {"greenhouse": greenhouse, "lever": lever, "ashby": ashby, "smartrecruiters": smartrecruiters}


def run_board(board, f):
    try:
        return board["a"], FETCHERS[board["a"]](board["s"], f)
    except Exception:
        return board["a"], []


def main():
    started = time.time()
    cfg = json.load(open(os.path.join(DATA, "feed_config.json"), encoding="utf-8"))
    boards = json.load(open(os.path.join(DATA, "boards.json"), encoding="utf-8"))
    f = Filters(cfg)
    print(f"{len(boards)} boards", flush=True)

    jobs, by_ats, boards_with_jobs = [], {}, 0
    done = 0
    with cf.ThreadPoolExecutor(max_workers=32) as pool:
        futures = [pool.submit(run_board, b, f) for b in boards]
        for fut in cf.as_completed(futures):
            ats, found = fut.result()
            done += 1
            if found:
                boards_with_jobs += 1
                jobs.extend(found)
                by_ats[ats] = by_ats.get(ats, 0) + len(found)
            if done % 500 == 0:
                print(f"{done}/{len(boards)} boards, {len(jobs)} jobs", flush=True)

    seen, unique = set(), []
    for j in sorted(jobs, key=lambda x: x["p"], reverse=True):
        key = (j["c"].lower(), j["t"].lower(), j["l"].lower())
        if key in seen or not j["u"]:
            continue
        seen.add(key)
        unique.append(j)
    unique = unique[: cfg["max_total"]]

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "jobs.json"), "w", encoding="utf-8") as fh:
        json.dump(unique, fh, separators=(",", ":"), ensure_ascii=False)
    meta = {
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "boards": len(boards),
        "boards_with_jobs": boards_with_jobs,
        "jobs": len(unique),
        "by_ats": by_ats,
        "seconds": int(time.time() - started),
    }
    with open(os.path.join(OUT, "meta.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh)
    size = os.path.getsize(os.path.join(OUT, "jobs.json"))
    print("::notice title=Feed::" + json.dumps({**meta, "bytes": size}))
    print("done:", meta, "bytes", size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
