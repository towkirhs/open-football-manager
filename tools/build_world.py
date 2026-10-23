#!/usr/bin/env python3
"""
Build a private, real-data world file for Open Football Manager.

Input: a players dataset in the common FIFA / EA FC format (one row per player, with
columns such as short_name, player_positions, overall, potential, age, club_name,
league_name, pace, shooting, passing, dribbling, defending, physic, goalkeeping_*,
player_face_url). Several free datasets in this format exist; download one yourself
and check its terms. This script never downloads player data on its own.

Output: a world JSON file that you load in the game (Settings -> Load a world file).
Keep it, and any photos, out of the repository: the default output folder,
private_data/, is ignored by git.

Usage:
    python3 tools/build_world.py --players players.csv --list-leagues
    python3 tools/build_world.py --players players.csv --out private_data/world.json
    python3 tools/build_world.py --players players.csv --out private_data/world.json --photos

Only the Python standard library is needed.
"""

import argparse
import csv
import json
import os
import re
import sys
import unicodedata
import urllib.request
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.join(HERE, "world_config.json")

# Dataset positions -> game positions (GK, CB, FB, DM, CM, AM, WG, ST).
POSITIONS = {
    "GK": "GK", "CB": "CB", "LCB": "CB", "RCB": "CB", "SW": "CB",
    "LB": "FB", "RB": "FB", "LWB": "FB", "RWB": "FB",
    "CDM": "DM", "LDM": "DM", "RDM": "DM",
    "CM": "CM", "LCM": "CM", "RCM": "CM",
    "CAM": "AM", "LAM": "AM", "RAM": "AM",
    "LM": "WG", "RM": "WG", "LW": "WG", "RW": "WG", "LF": "WG", "RF": "WG",
    "ST": "ST", "CF": "ST", "LS": "ST", "RS": "ST",
}

# Column names vary between dataset versions; the first one found is used.
COLUMNS = {
    "id": ["player_id", "sofifa_id", "id", "ID"],
    "short_name": ["short_name", "name", "Name", "known_as"],
    "long_name": ["long_name", "full_name"],
    "positions": ["player_positions", "positions", "Positions", "best_position"],
    "overall": ["overall", "Overall", "overall_rating"],
    "potential": ["potential", "Potential"],
    "age": ["age", "Age"],
    "club": ["club_name", "Club", "club", "team"],
    "club_id": ["club_team_id", "club_id", "team_id"],
    "league": ["league_name", "League", "league"],
    "league_level": ["league_level"],
    "nationality": ["nationality_name", "nationality", "Nationality"],
    "pace": ["pace", "Pace", "PAC"],
    "shooting": ["shooting", "Shooting", "SHO"],
    "passing": ["passing", "Passing", "PAS"],
    "dribbling": ["dribbling", "Dribbling", "DRI"],
    "defending": ["defending", "Defending", "DEF"],
    "physical": ["physic", "physical", "Physicality", "PHY"],
    "gk_diving": ["goalkeeping_diving", "gk_diving", "GKDiving"],
    "gk_handling": ["goalkeeping_handling", "gk_handling", "GKHandling"],
    "gk_positioning": ["goalkeeping_positioning", "gk_positioning", "GKPositioning"],
    "gk_reflexes": ["goalkeeping_reflexes", "gk_reflexes", "GKReflexes"],
    "contract": ["club_contract_valid_until_year", "club_contract_valid_until", "contract_valid_until"],
    "loaned_from": ["club_loaned_from"],
    "face": ["player_face_url", "face_url", "photo_url", "image"],
    "version": ["fifa_version", "fc_version", "version"],
    "update": ["fifa_update", "update_as_of", "update"],
}

NATION_CODES = {
    "England": "ENG", "Spain": "ESP", "Germany": "GER", "France": "FRA", "Italy": "ITA", "Portugal": "POR",
    "Netherlands": "NED", "Holland": "NED", "Turkey": "TUR", "Türkiye": "TUR", "Belgium": "BEL", "Scotland": "SCO",
    "Wales": "WAL", "Northern Ireland": "NIR", "Republic of Ireland": "IRL", "Ireland": "IRL", "Austria": "AUT",
    "Switzerland": "SUI", "Greece": "GRE", "Denmark": "DEN", "Czech Republic": "CZE", "Czechia": "CZE",
    "Ukraine": "UKR", "Croatia": "CRO", "Serbia": "SRB", "Norway": "NOR", "Sweden": "SWE", "Poland": "POL",
    "Brazil": "BRA", "Argentina": "ARG", "Uruguay": "URU", "Colombia": "COL", "Chile": "CHI", "Mexico": "MEX",
    "United States": "USA", "Canada": "CAN", "Japan": "JPN", "Korea Republic": "KOR", "South Korea": "KOR",
    "Australia": "AUS", "Nigeria": "NGA", "Ghana": "GHA", "Senegal": "SEN", "Côte d'Ivoire": "CIV",
    "Ivory Coast": "CIV", "Cameroon": "CMR", "Morocco": "MAR", "Algeria": "ALG", "Egypt": "EGY", "Mali": "MLI",
    "Hungary": "HUN", "Slovakia": "SVK", "Slovenia": "SVN", "Romania": "ROU", "Bulgaria": "BUL", "Russia": "RUS",
    "Finland": "FIN", "Iceland": "ISL", "Bosnia and Herzegovina": "BIH", "Albania": "ALB", "Kosovo": "KOS",
    "North Macedonia": "MKD", "Montenegro": "MNE", "Ecuador": "ECU", "Paraguay": "PAR", "Peru": "PER",
    "Venezuela": "VEN", "Jamaica": "JAM", "Georgia": "GEO", "Israel": "ISR", "Bangladesh": "BAN", "India": "IND",
}

COLOURS = [["#c62828", "#ffffff"], ["#1565c0", "#ffffff"], ["#2e7d32", "#ffffff"], ["#111111", "#ffffff"],
           ["#f9a825", "#111111"], ["#6a1b9a", "#ffffff"], ["#ef6c00", "#111111"], ["#00838f", "#ffffff"],
           ["#ad1457", "#ffffff"], ["#ffffff", "#c62828"], ["#ffffff", "#1565c0"], ["#0d47a1", "#ffeb3b"]]


def norm(text):
    """Lower case, no accents, no punctuation: for matching league names."""
    text = unicodedata.normalize("NFKD", str(text)).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def pick(row, key):
    for col in COLUMNS[key]:
        if col in row and str(row[col]).strip() not in ("", "nan", "None"):
            return str(row[col]).strip()
    return ""


def to_int(value, default):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def read_rows(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        sys.exit("No rows found in %s" % path)
    # Datasets with several game versions: keep each player's latest row.
    if pick(rows[0], "version"):
        latest = {}
        for r in rows:
            pid = pick(r, "id") or pick(r, "long_name") or pick(r, "short_name")
            key = (to_int(pick(r, "version"), 0), to_int(pick(r, "update"), 0))
            if pid not in latest or key >= latest[pid][0]:
                latest[pid] = (key, r)
        rows = [v[1] for v in latest.values()]
    return rows


def game_position(raw):
    first = re.split(r"[,/ ]+", raw.strip())[0].upper() if raw else ""
    return POSITIONS.get(first, "CM")


def make_player(row, club_id, n, year):
    pos = game_position(pick(row, "positions"))
    gk_parts = [to_int(pick(row, k), 0) for k in ("gk_diving", "gk_handling", "gk_positioning", "gk_reflexes")]
    gk = round(sum(gk_parts) / len(gk_parts)) if any(gk_parts) else 20
    overall = to_int(pick(row, "overall"), 50)
    attrs = {
        "pace": to_int(pick(row, "pace"), 40), "shooting": to_int(pick(row, "shooting"), 30),
        "passing": to_int(pick(row, "passing"), 40), "dribbling": to_int(pick(row, "dribbling"), 35),
        "defending": to_int(pick(row, "defending"), 30), "physical": to_int(pick(row, "physical"), 50),
        "goalkeeping": gk if pos == "GK" else min(gk, 25),
    }
    if pos == "GK":
        # Outfield ratings are often missing for keepers.
        attrs["goalkeeping"] = gk or overall
        for k in ("pace", "shooting", "dribbling"):
            attrs[k] = min(attrs[k], 45)
    nat = pick(row, "nationality")
    contract = to_int(pick(row, "contract"), year + 1)
    return {
        "id": "%s-%s" % (club_id, pick(row, "id") or n),
        "name": pick(row, "short_name") or pick(row, "long_name") or "Player %d" % n,
        "age": to_int(pick(row, "age"), 25),
        "nationality": NATION_CODES.get(nat, nat[:3].upper() if nat else ""),
        "position": pos,
        "attrs": attrs,
        "overall": overall,
        "potential": max(overall, to_int(pick(row, "potential"), overall)),
        "contract_end": max(year, contract - 1),
        "face_url": pick(row, "face"),
    }


def short_name(name):
    words = [w for w in re.split(r"[\s\-]+", name) if w and w.upper() not in ("FC", "CF", "AFC", "SC", "CD", "UD", "SD", "AC", "AS", "SV", "VFB", "VFL", "TSG", "RC", "FK", "SK", "1.")]
    if not words:
        words = [name]
    if len(words) >= 3:
        return "".join(w[0] for w in words[:3]).upper()
    return norm(words[0]).replace(" ", "")[:3].upper() or name[:3].upper()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--players", required=True, help="players CSV file")
    ap.add_argument("--config", default=DEFAULT_CONFIG, help="league mapping (default: tools/world_config.json)")
    ap.add_argument("--out", default="private_data/world.json", help="world file to write")
    ap.add_argument("--list-leagues", action="store_true", help="print the dataset's leagues and club counts, then stop")
    ap.add_argument("--photos", action="store_true", help="download player photos into private_data/photos (desktop only)")
    ap.add_argument("--year", type=int, default=None, help="first season of the career (default from the config)")
    args = ap.parse_args()

    rows = read_rows(args.players)
    if args.list_leagues:
        clubs = defaultdict(set)
        for r in rows:
            clubs[pick(r, "league")].add(pick(r, "club"))
        for league, cs in sorted(clubs.items(), key=lambda x: -len(x[1])):
            print("%4d clubs  %s" % (len(cs), league or "(no league)"))
        return

    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)
    year = args.year or int(cfg.get("start_year", 2026))

    by_league = defaultdict(lambda: defaultdict(list))
    for r in rows:
        # Players on loan are listed at the club they play for; they stay there.
        by_league[norm(pick(r, "league"))][pick(r, "club")].append(r)

    countries, leagues, clubs = [], [], []
    used_ids = set()
    report = []

    def add_club(name, rows_, country, league_id):
        cid = "r" + re.sub(r"[^a-z0-9]", "", norm(name))[:16]
        while cid in used_ids:
            cid += "x"
        used_ids.add(cid)
        players = [make_player(r, cid, i + 1, year) for i, r in enumerate(rows_)]
        players.sort(key=lambda p: -p["overall"])
        clubs.append({"id": cid, "name": name, "short_name": short_name(name), "country": country,
                      "league": league_id, "colours": COLOURS[len(clubs) % len(COLOURS)], "players": players[:32]})

    for c in cfg["playable"]:
        countries.append({"id": c["country"], "name": c["name"], "playable": True, "cup": c.get("cup", c["name"] + " Cup")})
        for tier, l in enumerate(c["leagues"], start=1):
            names = {norm(n) for n in l["names"]}
            found = None
            for key in by_league:
                if key in names:
                    found = key
                    break
            if found is None:
                report.append("  missing: %s (%s), looked for %s" % (l["display"], c["name"], ", ".join(l["names"])))
                continue
            lid = "%s%d" % (c["country"], tier)
            leagues.append({"id": lid, "name": l["display"], "country": c["country"], "tier": tier, "relegate": l.get("relegate", 0)})
            for club_name, crow in sorted(by_league[found].items()):
                if club_name and len(crow) >= 11:
                    add_club(club_name, crow, c["country"], lid)
            report.append("  %-28s %3d clubs" % (l["display"], len(by_league[found])))
        # Remove relegation from the last division found.
        mine = [l for l in leagues if l["country"] == c["country"]]
        if mine:
            mine[-1]["relegate"] = 0
        used_names = {norm(n) for l in c["leagues"] for n in l["names"]}
        for key in list(by_league):
            if key in used_names:
                del by_league[key]

    for fcfg in cfg.get("foreign", []):
        names = {norm(n) for n in fcfg["names"]}
        found = next((k for k in by_league if k in names), None)
        if found is None:
            report.append("  missing (Europe): %s" % fcfg["name"])
            continue
        countries.append({"id": fcfg["country"], "name": fcfg["name"], "playable": False, "cup": ""})
        ranked = sorted(by_league[found].items(), key=lambda kv: -sum(sorted((to_int(pick(r, "overall"), 0) for r in kv[1]), reverse=True)[:16]))
        for club_name, crow in ranked[: fcfg.get("clubs", 6)]:
            if len(crow) >= 11:
                add_club(club_name, crow, fcfg["country"], "")
        report.append("  %-28s top %d clubs for Europe" % (fcfg["name"], fcfg.get("clubs", 6)))

    if args.photos:
        photo_dir = os.path.join(os.path.dirname(os.path.abspath(args.out)), "photos")
        os.makedirs(photo_dir, exist_ok=True)
        done = failed = 0
        for c in clubs:
            for p in c["players"]:
                url = p.get("face_url", "")
                if not url:
                    continue
                path = os.path.join(photo_dir, "%s.png" % p["id"])
                if not os.path.exists(path):
                    try:
                        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (personal use)"})
                        with urllib.request.urlopen(req, timeout=20) as resp, open(path, "wb") as out:
                            out.write(resp.read())
                        done += 1
                    except Exception:
                        failed += 1
                        continue
                p["photo"] = path
        print("photos: %d downloaded, %d failed (template portraits are used for those)" % (done, failed))
    for c in clubs:
        for p in c["players"]:
            p.pop("face_url", None)

    world = {
        "name": cfg.get("name", "Real world (private)"),
        "fictional": False,
        "normalize_values": True,
        "start_year": year,
        "countries": countries,
        "leagues": leagues,
        "europe": cfg.get("europe", []),
        "clubs": clubs,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(world, f, ensure_ascii=False)
    n_players = sum(len(c["players"]) for c in clubs)
    print("Leagues:")
    print("\n".join(report))
    print("Wrote %s: %d clubs, %d players, %d leagues." % (args.out, len(clubs), n_players, len(leagues)))
    if len([c for c in clubs if not c["league"]]) < 75:
        print("Note: fewer than 75 clubs for Europe; the game fills the European cups with extra first-division clubs.")


if __name__ == "__main__":
    main()
