# Yogan Hockey

Live NHL scores and stats dashboard on Phoenix LiveView, with a tracker for my brother's season in Germany. Runs on a single small Fly.io machine.

**Live:** [yogan-hockey.fly.dev](https://yogan-hockey.fly.dev)

## What It Is

My brother Andrew plays professional hockey in Germany's DEL league. Every season our family gathers around screens tracking games across time zones. I got tired of slow, ad-infested sports apps, so I built our own.

Yogan Hockey polls ESPN's public NHL endpoints every 30 seconds for live scores (teams and standings every 5 minutes) and renders server-side diffs over WebSockets via Phoenix LiveView. It has live scores, standings, team pages, player stats, and a dedicated tracker for Andrew's season, read from Elite Prospects every 5 minutes.

The entire thing runs on a single $5/month Fly.io machine. No Redis. No external cache. No client-side JavaScript framework. ETS (Erlang Term Storage) provides sub-microsecond in-process reads. PubSub propagates updates to all connected clients. The BEAM VM handles concurrency natively — each connected user is a lightweight process, not a thread.

## Architecture

```
OTP Supervision Tree (one_for_one)
├── Phoenix.PubSub
├── NHL.LiveScoresServer     polls live scores every 30s
├── NHL.TeamsServer          polls teams and standings every 5 min
├── DEL2.YoganStatsServer    polls Elite Prospects every 5 min
└── Endpoint

GenServer ──► ETS ──► PubSub ──► LiveView (per-client process)
```

| Process | Role |
|---------|------|
| **LiveScoresServer** | Polls NHL API every 30s, broadcasts score updates via PubSub |
| **TeamsServer** | Polls teams and standings every 5 minutes, caches in ETS |
| **YoganStatsServer** | Polls Andrew's stats from Elite Prospects every 5 minutes, backs off on failure |

## Why This Matters

The OTP supervision tree is the right abstraction for real-time data aggregation from external APIs. Each GenServer encapsulates one concern (live scores, teams and standings, one player's stats), crashes independently, restarts automatically, and communicates via message passing.

ETS eliminates the Redis dependency that most real-time dashboards require. Reads happen in-process, which is enough for a single-node deployment.

## Status

Live at [yogan-hockey.fly.dev](https://yogan-hockey.fly.dev). Used daily during NHL and DEL seasons by family and friends. Active development — features added throughout the hockey season.

## Stack

- **Backend:** Elixir, Phoenix LiveView
- **Real-time:** GenServer, ETS, PubSub
- **Deployment:** Fly.io ($5/month single instance)
- **Data:** ESPN public NHL API, Elite Prospects (scraped)
- **Frontend:** LiveView (no client-side framework), Tailwind CSS
