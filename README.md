# Open Football Manager

A free, open-source, offline football club management game. Build a squad, set your tactics, manage the money and climb from the lowest division to European glory.

- **Completely free.** No payments, premium currency, gear or ads. Every upgrade is earned by managing well.
- **Fair.** AI clubs play by the same budget, wage and transfer rules as you.
- **Tactics matter.** Five playing styles, each strong against two and weak against two. A smaller club with the right plan can beat a bigger one.
- **Personal learning project.** Non-commercial; built to learn game development.

## Play it in your browser

**https://towkirhs.github.io/open-football-manager/**

The link always has the latest version: every push to `main` runs the tests, builds the web version and publishes it. Your career is saved in the browser.

## Status

Early development. What works now:

- [x] Career mode: pick a club and play a full 38-week league season
- [x] Club hub: next match with opponent scouting, your tactics, league table, recent results, inbox
- [x] Squad, League (table and top scorers), Fixtures and Settings screens
- [x] Live matches with a text feed; change formation, style or mentality at half-time; or quick-sim
- [x] Match engine with formations, playing styles, mentality, familiarity and player fit
- [x] Cards, injuries, fatigue, substitutions, player ratings and season stats
- [x] AI managers who pick tactics, scout and counter your style, and react at half-time
- [x] Autosave, and five colour themes
- [x] Fictional 20-club sample league
- [x] Headless tests and balance report

Next up (see the roadmap below): squad screens with player profiles and lineup picking.

## Running it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (the standard version, not .NET).
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** to run.

### Tests

The simulation can be tested without any UI:

```
godot --headless --path . -s res://tests/run_tests.gd
```

It plays thousands of matches and a full season, then prints a balance report: goals per game, home advantage, how often an underdog wins with the right and wrong tactics, whether any formation is broken, and whether fixtures, the table and saving work. The last line says `ALL CHECKS PASSED` when everything is within range. Add `-- --quick` at the end for a faster run.

### Regenerating the sample league

```
godot --headless --path . -s res://tools/make_sample_league.gd
```

## Project layout

```
data/
  balance.json          every tunable number (match engine, styles, ratings)
  sample/               fictional sample league (safe to share)
src/
  data/                 loading and saving; no game rules
  sim/                  game rules: match engine, tactics, lineups, AI managers
  ui/                   screens; they call the sim layer and never change data directly
scenes/                 Godot scenes
tests/                  headless simulation tests
tools/                  generators and (later) the real-data import scripts
private_data/           real players, clubs and photos (git-ignored, never committed)
```

The simulation layer has no UI code, so it can be tested on its own and reused for other sports management games.

## Tactics at a glance

| Style | Strong against | Weak against | Suits players with |
| --- | --- | --- | --- |
| Counter-attack | Possession, High press | Long ball, Low block | Pace, finishing |
| Possession | Low block, Long ball | Counter-attack, High press | Passing, technique |
| High press | Possession, Low block | Counter-attack, Long ball | Stamina, work rate |
| Long ball | High press, Counter-attack | Possession, Low block | Strength, heading |
| Low block | Counter-attack, Long ball | Possession, High press | Defending, discipline |

Formations: 4-4-2, 4-3-3, 4-2-3-1, 4-5-1, 3-5-2, 3-4-3, 5-3-2, 5-4-1.

## Real players and clubs

This repository only contains fictional data. Real clubs, players and photos are built into `private_data/` on your own machine by import scripts (coming in a later milestone) and are never committed. That keeps the code open source while each person's own copy can use real data for personal, non-commercial play.

## Roadmap

1. [x] Project setup and fictional sample league
2. [x] Match engine
3. [x] Tactics: formations, styles, matchups, familiarity, fit
4. [x] One full season: fixtures, weekly Continue, league table, results
5. [ ] Squad screens: squad list, player profile, lineup and tactics
6. [ ] League pyramids with promotion and relegation; season rollover
7. [ ] Finances, owner goals and the bank (loans and advances)
8. [ ] Transfers and contracts, with a global player search
9. [ ] Training, youth academy and staff
10. [ ] Facilities
11. [ ] Real data import (private, local only)
12. [ ] Player photos with template portraits as fallback
13. [ ] Domestic cups and European competitions
14. [ ] Smarter AI managers and sackings
15. [ ] Stats and awards
16. [ ] Long-run balance pass
17. [ ] Polish and Android build
