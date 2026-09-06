# Mac Stats aggregate usage service

This Cloudflare Worker accepts the optional usage events documented in the main privacy policy and writes them to Analytics Engine. It intentionally has no identity field and does not read or store request IP addresses, countries, cookies, or device identifiers.

## Deploy

From the repository root:

```sh
cd website
pnpm exec wrangler deploy --config ../analytics-worker/wrangler.jsonc
```

Use the resulting HTTPS URL plus `/v1/events` as `MAC_STATS_ANALYTICS_ENDPOINT` when building the app:

```sh
MAC_STATS_ANALYTICS_ENDPOINT="https://macstats-api.justbro.ai/v1/events" ./Scripts/build-app.sh
```

The endpoint is public by design because a value embedded in a desktop app cannot be a secret. Payload validation limits accidental or malformed writes, but public aggregate counters should always be treated as approximate.

## Example Analytics Engine queries

```sql
-- Events by day and type
SELECT toDate(timestamp) AS day, blob1 AS event, sum(_sample_interval) AS events
FROM mac_stats_usage
GROUP BY day, event
ORDER BY day DESC, event;

-- Active events by version over the last 30 days
SELECT blob2 AS version, sum(_sample_interval) AS daily_active_events
FROM mac_stats_usage
WHERE blob1 = 'daily_active' AND timestamp > NOW() - INTERVAL '30' DAY
GROUP BY version
ORDER BY daily_active_events DESC;
```

`daily_active` is an event count, not a unique-user metric: Mac Stats never creates a user or device identifier.
