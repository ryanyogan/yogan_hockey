# How I Built a Real-Time NHL Stats App in a Day with Phoenix LiveView

Every year I rebuild my hockey stats app. It started as a way to track my brother Andrew's professional career (he plays in the German DEL), but it's become my annual benchmark for evaluating web frameworks. This year, I finally stopped fighting uphill and just used the right tool for the job.

## The Annual Rebuild Tradition

**2023: Next.js**

Static. Slow. No real-time anything. I had to tell people to refresh the page during games. The shame.

**2024: Tanstack Start + Cloudflare**

I went all-in on the edge. Cloudflare Workers. KV for caching. D1 for persistence. Durable Objects for... I'm still not sure what Durable Objects are actually for. I spent more time configuring infrastructure than building features. The app worked, but I mass-deleted 47 Cloudflare resources when I was done and mass-deleted the repo.

**2025: Phoenix LiveView**

One day. Real-time scores updating every 30 seconds across all connected clients. No WebSocket code. No state synchronization bugs. No infrastructure configuration. Just... it works. I mass-deleted nothing.

## The Architecture

Here's what I built:

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Phoenix LiveView                        │    │
│  │         (WebSocket, auto-reconnect)                  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Phoenix Server                            │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ LiveScores   │  │   Teams      │  │  YoganStats  │       │
│  │  GenServer   │  │  GenServer   │  │  GenServer   │       │
│  │  (30 sec)    │  │  (5 min)     │  │  (5 min)     │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │                │
│         └────────────┬────┴─────────────────┘                │
│                      ▼                                       │
│         ┌─────────────────────────┐                         │
│         │   Phoenix.PubSub        │                         │
│         │  (Broadcast to clients) │                         │
│         └─────────────────────────┘                         │
│                      │                                       │
│         ┌────────────┴────────────┐                         │
│         ▼                         ▼                         │
│  ┌─────────────┐          ┌─────────────┐                   │
│  │  ETS Cache  │          │  LiveViews  │                   │
│  │  (7 tables) │          │ (subscribers)│                   │
│  └─────────────┘          └─────────────┘                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     External APIs                            │
│  ┌─────────────────────┐    ┌─────────────────────┐         │
│  │      ESPN API       │    │   Elite Prospects   │         │
│  │  (NHL scores/teams) │    │   (DEL stats)       │         │
│  └─────────────────────┘    └─────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

Three GenServers poll external APIs on intervals. When data changes, they broadcast via PubSub. Every connected LiveView receives the update and re-renders. That's it. That's the whole real-time architecture.

## Key Features

### 1. Live Scores (The Whole Point)

Games update every 30 seconds. Period scores, shots, game status. All clients stay in sync automatically.

```elixir
# Subscribe on mount
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(YoganHockey.PubSub, "nhl:live_scores")
  end
  {:ok, assign(socket, :games, NHL.list_live_scores())}
end

# Handle broadcasts
def handle_info({:live_scores_updated, games}, socket) do
  {:noreply, assign(socket, :games, games)}
end
```

That's 10 lines of code for real-time updates. In my Tanstack/Cloudflare setup, the equivalent logic was spread across 4 files and required a Durable Object that I definitely understood completely and did not just copy from a tutorial.

### 2. ETS Caching

Seven in-memory cache tables. No Redis. No external dependencies. Just process memory that survives across requests.

```elixir
@tables [
  :nhl_live_scores,   # Current scoreboard
  :nhl_teams,         # Team metadata
  :nhl_standings,     # League standings
  :nhl_team_stats,    # Rosters + schedules
  :player_cache,      # Player career stats
  :yogan_stats,       # My brother's stats
  :del2_team          # German league team info
]
```

Cache reads are concurrent and fast. No network hop. No serialization. Just a function call.

### 3. Player Search with Favorites

Users can search any NHL player and favorite them. Favorites persist in localStorage (no auth required) and load asynchronously:

```elixir
socket
|> assign(:favorite_ids, player_ids)
|> assign_async(:favorite_players, fn ->
  {:ok, %{favorite_players: NHL.get_players(player_ids)}}
end)
```

The `assign_async` pattern loads data without blocking the page render. Users see skeleton cards that fill in when data arrives. No loading spinners. No layout shift. Just smooth.

### 4. Smart API Polling

The TeamsServer pre-fetches all 32 team rosters in batches of 4 with rate limiting:

```elixir
teams
|> Enum.chunk_every(4)
|> Enum.each(fn chunk ->
  tasks = Enum.map(chunk, &Task.async(fn -> refresh_team(&1) end))
  Task.await_many(tasks, 30_000)
  Process.sleep(500)  # Don't anger ESPN
end)
```

When you click a team, the data is already cached. Instant page loads.

### 5. Graceful Degradation

The YoganStatsServer uses exponential backoff when Elite Prospects is slow (which is often):

```elixir
interval = if state.consecutive_failures > 0 do
  min(@poll_interval * state.consecutive_failures, :timer.minutes(30))
else
  @poll_interval
end
```

Failed requests don't hammer the API. The app stays responsive even when external services are struggling.

## Why LiveView Wins for This Use Case

Let me be direct: Phoenix LiveView is a secret weapon for real-time applications.

| Feature | Next.js | Tanstack + Cloudflare | Phoenix LiveView |
|---------|---------|----------------------|------------------|
| Real-time updates | Manual WebSocket setup | Durable Objects (pain) | Built-in |
| Server state | External (Redis/KV) | KV + D1 + Durable Objects | ETS (in-process) |
| Reconnection | You build it | You build it | Automatic |
| Client JS | Lots | Some | Almost none |
| Deploy complexity | Medium | High | Low |
| Time to build | Days | Days | Hours |

The JavaScript ecosystem has incredible tools. I genuinely like Tanstack. But for this specific problem (real-time data, server-rendered UI, minimal client state), LiveView is the right abstraction.

I wrote almost no JavaScript. The LiveView JS hooks I needed were ~20 lines total. The rest is Elixir on the server, HTML templates, and Tailwind CSS. When game scores update, the server diffs the HTML and sends minimal patches over the WebSocket. No JSON serialization, no client-side state management, no hydration mismatches.

## The Numbers

- **Build time**: ~8 hours (with AI assistance)
- **Lines of Elixir**: ~2,500
- **Lines of JavaScript**: ~100 (hooks only)
- **External services**: 0 (no database, no Redis, no nothing)
- **Deploy**: Single Fly.io instance

For comparison, my Cloudflare setup last year required:
- Workers (3)
- KV namespaces (2)
- D1 databases (1)
- Durable Objects (1)
- Pages deployment (1)
- A mass-delete of everything at the end

## The Secret Weapon

I've been using LiveView since 2020. Every year it gets better. The patterns are mature. The documentation is excellent. The community actually helps.

But the real advantage is conceptual simplicity. There's one mental model: server renders HTML, browser displays it, user events go back to server, server re-renders. No split-brain state. No "where does this data live?" questions. No hydration.

For real-time dashboards, admin panels, live scoreboards, collaborative tools, or anything where the server is the source of truth, LiveView is the fastest path from idea to working software.

## Try It Yourself

The stack:
- **Elixir + Phoenix LiveView** for the app
- **ETS** for caching (built into Erlang/OTP)
- **Tailwind + DaisyUI** for styling
- **Fly.io** for hosting

If you're building something that needs real-time updates and you're dreading the WebSocket/state-sync complexity, give LiveView a look. It might save you from mass-deleting a bunch of Cloudflare resources.

---

*The app tracks NHL scores, standings, and player stats. It also has an easter egg: my 11-year-old nephew Rylan is listed on the Toronto Maple Leafs roster with legendary stats. He's projected to go 1st overall in the 2029 draft. The future is bright.*
