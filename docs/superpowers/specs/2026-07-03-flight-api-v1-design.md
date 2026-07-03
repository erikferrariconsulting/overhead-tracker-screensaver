# Flight API v1 Design

## Goal
Provide a small, versioned backend API for the screensaver to fetch nearby live aircraft data from `https://api.overheadtracker.com` without depending on the current upstream vendor or response format.

This API is not a general aviation platform. It only needs to support the data the screensaver already consumes.

## Scope
In scope:
- Nearby live aircraft query by location and radius
- Normalized response shape for the screensaver
- Minimal health endpoint
- Stable `v1` contract

Out of scope:
- Historical flight search
- Flight schedules
- Airport endpoints
- Weather endpoints
- Authentication and user accounts
- Pagination
- Arbitrary filters beyond location and radius

## Endpoints

### `GET /v1/flights`
Returns nearby aircraft for a geofence centered on a latitude and longitude.

Query parameters:
- `lat` required, decimal degrees
- `lon` required, decimal degrees
- `radius` required, integer nautical miles

Response `200`:
```json
{
  "data": [
    {
      "id": "7cb0db",
      "callsign": "QFA1",
      "airline": "Qantas",
      "aircraftType": "B789",
      "registration": "VH-ZNA",
      "originCity": "Sydney",
      "destinationCity": "Melbourne",
      "altitudeFt": 35000,
      "speedKt": 460,
      "distanceKm": 8.2,
      "phase": "cruising",
      "squawk": "1200",
      "hex": "7cb0db",
      "category": "A3",
      "latitude": -33.9,
      "longitude": 151.2,
      "track": 274.5
    }
  ],
  "meta": {
    "lat": -33.853,
    "lon": 151.141,
    "radius": 20,
    "generatedAt": "2026-07-03T10:48:14Z",
    "sources": ["adsb.lol", "airplanes.live"]
  }
}
```

### `GET /v1/health`
Returns service health for uptime monitoring.

Response `200`:
```json
{
  "ok": true,
  "version": "v1"
}
```

## Data Contract

The `data` array must contain only aircraft records. The backend may filter out ground vehicles and non-aircraft objects before returning them.

Each aircraft record must expose:
- `id`
- `callsign`
- `airline`
- `aircraftType`
- `registration`
- `originCity`
- `destinationCity`
- `altitudeFt`
- `speedKt`
- `distanceKm`
- `phase`
- `squawk`
- `hex`
- `category`
- `latitude`
- `longitude`
- `track`

Field behavior:
- `id` should be stable across requests when possible.
- `phase` may come from the upstream source or be inferred by the backend.
- `hex`, `category`, `latitude`, `longitude`, and `track` may be omitted or null if unavailable.
- Missing required display fields should be normalized to `"Unknown"`.
- Optional text fields may be omitted or set to `null`, but not mixed with blank strings.

## Backend Behavior

The backend should:
- Accept the geofence request
- Query one or more upstream aircraft sources
- Normalize their responses into the `v1` schema
- Filter out invalid records
- Cache results by geofence
- Return stale cached data if upstreams fail and cached data exists

Recommended normalization rules:
- Trim whitespace from text fields
- Parse altitude and speed as integers
- Convert distance to kilometers
- Infer `phase` only when the upstream payload does not provide one
- Reject records with no usable position and no usable altitude
- When multiple upstream sources are queried, include every successful source name in `meta.sources`

## Caching

Cache key should include at least:
- rounded `lat`
- rounded `lon`
- `radius`

Suggested behavior:
- Live requests should be cached for a short TTL, around 10 to 30 seconds
- If upstream requests fail, return the most recent cached response if it is not too stale
- Include `meta.generatedAt` from the actual data generation time, not the response time

## Error Responses

Use JSON for errors.

`400 Bad Request`
```json
{
  "error": {
    "code": "bad_request",
    "message": "lat, lon, and radius are required"
  }
}
```

`502 Bad Gateway`
```json
{
  "error": {
    "code": "upstream_unavailable",
    "message": "Unable to load aircraft data"
  }
}
```

`504 Gateway Timeout`
```json
{
  "error": {
    "code": "upstream_timeout",
    "message": "Flight source timed out"
  }
}
```

If cached data exists, prefer serving it over returning an error.

## Compatibility Notes

The current screensaver client already calls:
- `GET /flights?lat=...&lon=...&radius=...`

The new versioned API should support the same request parameters under:
- `GET /v1/flights?lat=...&lon=...&radius=...`

The client can be updated to point to `/v1` without changing its downstream flight model.

## Testing

Required tests:
- Request validation for missing or malformed query parameters
- Response decoding into the existing flight model
- Filtering of ground vehicles and non-aircraft records
- Cache hit and cache fallback behavior
- Error mapping when all upstream sources fail
- Contract test for the `v1` response shape

## Non-Goals For v1

Do not add:
- Auth headers
- User-specific settings
- Multiple pages
- Search by flight number
- Historical timelines
- Weather or airport APIs
