# Open Football Manager

A free, open-source, offline football club management game. Start in the bottom division, build a squad, set your tactics, manage the money and climb to European glory.

- **Completely free.** No payments, premium currency, gear or ads. Everything is earned by managing well.
- **Fair.** AI clubs play by the same budget, wage and transfer rules as you.
- **Tactics matter.** Five playing styles, each strong against two and weak against two. A smaller club with the right plan can beat a bigger one.
- **Personal learning project.** Non-commercial; built to learn game development.

## Play it in your browser

**https://towkirhs.github.io/open-football-manager/**

Every push to `main` runs the tests, builds the web version and publishes it to the `gh-pages` branch, which serves that link. Your career is saved in the browser.

## Android app (APK)

**Download: https://github.com/towkirhs/open-football-manager/releases/latest/download/OpenFootballManager.apk**

Open that link on your phone, then open the downloaded file to install. The first time, Android asks you to allow installing apps from your browser or file manager: allow it, install, then switch it back off if you like. Every push to `main` builds a new APK at the same link, and installing it over the old one keeps your career.

To load a real-data world on the phone, copy `world.json` into the phone's **Download** folder, then use **Settings → Load a world file** (the app asks once for access to your files).

Signing: the build makes its own signing key once and keeps it in the GitHub Actions cache, so updates install over each other. GitHub drops caches that go unused for 7 days; if that happens the next APK has a new key and you need to uninstall the old app first (your career is lost). To make the key permanent, add your own keystore as repository secrets `ANDROID_KEYSTORE_BASE64` (the file, base64-encoded), `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEYSTORE_ALIAS`. Never commit a keystore.

You can also play without installing: open the browser link in Chrome and choose **Add to Home screen**.

> First time only: in the repository go to **Settings → Pages**, set **Source** to **Deploy from a branch**, pick the **gh-pages** branch and the **/ (root)** folder, and save. After a minute the link works, and every later push updates it.

## What's in the game

**The world**
- Three playable countries with full pyramids: England (4 divisions), Spain (2) and Germany (3), each with its own domestic cup.
- 91 clubs from 15 other European countries that play in the three European competitions (Champions League, Europa League and Conference League: groups, two-legged knockouts and a final).
- Around 6,700 players, with template portraits (skin tone, build, hair, club shirt) when there is no photo.
- A fictional world is generated for each new career. You can also load a real-data world you build yourself (see below).

**Your career**
- Start at a random club in the lowest division (the default), anywhere at random, or pick any club in any division.
- Play season after season: promotion and relegation, ageing, retirements, youth intakes, and a full history of tables, honours and awards.
- The owner sets targets each season, reviews you mid-season and at the end, and can sack you. Good seasons bring job offers from bigger clubs.

**Matches and tactics**
- 8 formations, 5 playing styles and 3 mentalities. Style familiarity grows the more your team plays a style, and players suit some styles better than others.
- Watch matches live with a text feed; pause at any time to make substitutions or change formation, style and mentality; or quick-sim.
- AI managers each have their own preferred style, scout your habits, sometimes counter them and react at half-time, so they are not predictable.
- Cards, injuries, fatigue, player ratings, top scorers and season awards.

**Running the club**
- Squad, first eleven and bench on a pitch, or let the assistant pick.
- Transfers and loans with a searchable player database (filter by name, position, overall, age, value, league and more), bids, counter-offers, contracts and renewals. AI clubs bid for your players too.
- Weekly training focus per player; youth academy with a yearly intake.
- Finances: ticket prices, TV money, sponsors (three kinds of deal), wages and prize money, with a weekly ledger.
- The bank: loans sized by your club's assets with interest based on your credit rating, plus advances on next season's TV money.
- Five facilities to upgrade (stadium, training, youth, medical, scouting) and staff to hire.

**Everything else**
- Autosave, five colour themes (Pitch green, Midnight blue, Royal purple, Sunset, Classic light).
- Runs in the browser, and on desktop through Godot.

## Running it on your computer

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (the standard version, not .NET).
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** to run.

## Real players and clubs (private, on your own machine)

This repository only contains fictional data. You can build a world with real clubs and players for your own personal, non-commercial use. Nothing real is ever committed: the `private_data/` folder is ignored by git.

1. Download a players dataset in the common FIFA / EA FC CSV format (one row per player with columns such as `short_name`, `player_positions`, `overall`, `club_name`, `league_name`, `pace` …). Several free ones exist; check the terms of the one you pick.
2. See which leagues it contains and how they are named:
   ```
   python3 tools/build_world.py --players players.csv --list-leagues
   ```
   If a league's name doesn't match, add it to the `names` list in `tools/world_config.json`.
3. Build the world file (add `--photos` to also download player photos into `private_data/photos`; photos work in the desktop version, the browser uses template portraits):
   ```
   python3 tools/build_world.py --players players.csv --out private_data/world.json
   ```
4. In the game open **Settings → Load a world file** and pick `private_data/world.json`. The next new career uses it; you can switch back to a generated world on the new-game screen.

Real overall ratings are kept. Values, wages, stadiums, fans, facilities, staff and money are filled in to fit the game's economy.

## Tests

The simulation can be tested without any UI:

```
godot --headless --path . -s res://tests/run_tests.gd
```

It compiles every script, then plays thousands of matches, full careers and several seasons of the whole world, and prints a balance report: goals per game, home advantage, how often an underdog wins with the right and wrong tactic, whether any formation is broken, fixtures and cup draws, transfers, training, the economy, and whether squads, ratings and money stay sensible over many seasons. The last line says `ALL CHECKS PASSED` when everything is within range. Add `-- --quick` for a faster run (used by the online build).

## Project layout

```
data/balance.json   every tunable number (match engine, styles, economy, development)
src/
  sim/              game rules: match engine, tactics, competitions, economy, transfers, career
  data/             loading and saving world files; no game rules
  ui/               screens and tabs; they call the sim layer
scenes/             Godot scenes
tests/              headless simulation tests
tools/              real-data import (build_world.py) and its league mapping
private_data/       your real players, clubs and photos (git-ignored, never committed)
```

The simulation layer has no UI code, so it can be tested on its own.

## Tactics at a glance

| Style | Strong against | Weak against | Suits players with |
| --- | --- | --- | --- |
| Counter-attack | Possession, High press | Long ball, Low block | Pace, finishing |
| Possession | Low block, Long ball | Counter-attack, High press | Passing, technique |
| High press | Possession, Low block | Counter-attack, Long ball | Stamina, work rate |
| Long ball | High press, Counter-attack | Possession, Low block | Strength, heading |
| Low block | Counter-attack, Long ball | Possession, High press | Defending, discipline |

Formations: 4-4-2, 4-3-3, 4-2-3-1, 4-5-1, 3-5-2, 3-4-3, 5-3-2, 5-4-1.

In testing, a team 8 rating points weaker wins about 25–31% of games with a style that beats the favourite's, about 16% with the same style, and about 3% with a style that loses to it.

## Not included (by design)

National teams, online multiplayer, payments of any kind, heavy club badges.
