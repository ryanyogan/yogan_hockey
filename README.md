# Yogan Hockey

Real-time NHL and DEL stats dashboard with AI game predictions, serving dozens of concurrent users on a $5/month server.

**Live:** [yogan-hockey.fly.dev](https://yogan-hockey.fly.dev)

## What It Is

My brother Andrew plays professional hockey in Germany's DEL league. Every season our family gathers around screens tracking games across time zones. I got tired of slow, ad-infested sports apps, so I built our own.

Yogan Hockey polls the undocumented NHL API every 30 seconds, renders server-side diffs over WebSockets via Phoenix LiveView, and uses Claude to generate real-time win probability predictions based on team stats, recent form, and head-to-head records. Live scores, playoff bracket tracking, per-game play-by-play with ice rink visualization, player stats, and a dedicated tracker for Andrew's DEL season.

The entire thing runs on a single $5/month Fly.io machine. No Redis. No external cache. No client-side JavaScript framework. ETS (Erlang Term Storage) provides sub-microsecond in-process reads. PubSub propagates updates to all connected clients. The BEAM VM handles concurrency natively — each connected user is a lightweight process, not a thread.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    OTP Supervision Tree                    │
│                                                           │
│  ┌─────────────────┐  ┌─────────────────┐                │
│  │ LiveScoresServer │  │  TeamsServer    │                │
│  │ (30s NHL poll)   │  │ (ETS cache)     │                │
│  └────────┬────────┘  └─────────────────┘                │
│           │                                               │
│           ▼                                               │
│  ┌─────────────────┐  ┌─────────────────────────────┐    │
│  │PredictionServer │  │    DynamicSupervisor         │    │
│  │(scoring events) │  │                              │    │
│  └─────────────────┘  │  ┌──────────────────────┐   │    │
│                        │  │ GamePlayServer (per  │   │    │
│                        │  │ game, auto-shutdown  │   │    │
│                        │  │ when viewers leave)  │   │    │
│                        │  └──────────────────────┘   │    │
│                        └─────────────────────────────┘    │
│                                                           │
│  ETS ──► PubSub ──► LiveView (per-client process)        │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

| Process | Role |
|---------|------|
| **LiveScoresServer** | Polls NHL API every 30s, broadcasts score updates via PubSub |
| **TeamsServer** | Pre-populates team data, caches in ETS for sub-microsecond reads |
| **PredictionServer** | Watches scoring events, regenerates Claude win probabilities on goals |
| **GamePlayServer** | Spawned on-demand per game via DynamicSupervisor, auto-shuts down when all viewers disconnect |

### Performance

| Metric | Yogan Hockey | Typical Next.js |
|--------|-------------|-----------------|
| Initial load | ~200ms | ~800ms |
| Per-connection memory | ~2KB | ~50KB |
| External cache | None (ETS) | Redis typically |
| Client JS | 0 (LiveView) | Framework bundle |

## Why This Matters

The OTP supervision tree is the right abstraction for real-time data aggregation from external APIs. Each GenServer encapsulates one concern (scores, predictions, per-game state), crashes independently, restarts automatically, and communicates via message passing. The DynamicSupervisor pattern — spawn a process per game, kill it when nobody is watching — is exactly what Erlang was designed for in telecom switches. Applied to sports data, it means resource usage scales with active viewers, not total games.

ETS eliminates the Redis dependency that most real-time dashboards require. Reads are sub-microsecond because they happen in-process. For a single-node deployment on a $5 machine, this architecture serves dozens of concurrent WebSocket connections without breaking a sweat.

## Status

Live at [yogan-hockey.fly.dev](https://yogan-hockey.fly.dev). Used daily during NHL and DEL seasons by family and friends. Active development — features added throughout the hockey season.

## Stack

- **Backend:** Elixir, Phoenix LiveView
- **Real-time:** GenServer, DynamicSupervisor, ETS, PubSub
- **AI predictions:** Claude API
- **Deployment:** Fly.io ($5/month single instance)
- **Data:** NHL API (undocumented), DEL API
- **Frontend:** LiveView (zero client-side JS), Tailwind CSS
