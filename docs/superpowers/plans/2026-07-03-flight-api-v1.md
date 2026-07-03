# Flight API v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone versioned flight API that serves the screensaver’s existing aircraft data contract and nothing more.

**Architecture:** A small TypeScript HTTP service exposes `/v1/flights` and `/v1/health`. A provider layer fetches raw ADS-B data from one or more upstream free sources, a normalizer converts that data into the screensaver’s canonical flight model, and a cache layer serves hot results or stale fallback data when upstreams fail. The server never leaks provider-specific payloads to clients.

**Tech Stack:** Node.js 22, TypeScript, Fastify, Zod, Vitest, native `fetch`, in-memory cache first with a pluggable Redis option later.

---

## Repository Layout

Create a new repo with this root layout:

- `package.json` - scripts, dependencies, Node engine
- `tsconfig.json` - TypeScript compiler settings
- `src/server.ts` - Fastify bootstrap and listener
- `src/app.ts` - app construction and plugin wiring
- `src/config.ts` - env parsing and defaults
- `src/domain/flight.ts` - canonical flight types and response types
- `src/domain/normalize.ts` - upstream payload normalization into the canonical flight model
- `src/domain/phase.ts` - phase inference from altitude, vertical speed, and distance
- `src/providers/provider.ts` - provider interface
- `src/providers/adsblol.ts` - `adsb.lol` adapter
- `src/providers/airplanesLive.ts` - `airplanes.live` adapter
- `src/providers/adsbFi.ts` - `adsb.fi` adapter
- `src/providers/router.ts` - provider failover and health scoring
- `src/cache/memoryCache.ts` - TTL cache with stale fallback
- `src/services/flightService.ts` - query orchestration and response assembly
- `src/routes/v1Flights.ts` - `/v1/flights`
- `src/routes/health.ts` - `/v1/health`
- `test/flightModel.test.ts` - canonical model and normalization tests
- `test/providerAdapters.test.ts` - upstream adapter parsing tests
- `test/flightService.test.ts` - cache and failover tests
- `test/routes.test.ts` - HTTP contract tests
- `Dockerfile` - production image
- `README.md` - local run and deploy notes

## Task 1: Bootstrap the repo and lock the contract types

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `src/domain/flight.ts`
- Create: `test/flightModel.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { parseFlightResponse } from "../src/domain/flight";

describe("flight contract", () => {
  it("keeps only the fields the screensaver uses", () => {
    const response = parseFlightResponse({
      data: [
        {
          id: "7cb0db",
          callsign: "QFA1",
          airline: "Qantas",
          aircraftType: "B789",
          registration: "VH-ZNA",
          originCity: "Sydney",
          destinationCity: "Melbourne",
          altitudeFt: 35000,
          speedKt: 460,
          distanceKm: 8.2,
          phase: "cruising",
          squawk: "1200",
          hex: "7cb0db",
          category: "A3",
          latitude: -33.9,
          longitude: 151.2,
          track: 274.5
        }
      ],
      meta: {
        lat: -33.853,
        lon: 151.141,
        radius: 20,
        generatedAt: "2026-07-03T10:48:14Z",
        sources: ["adsb.lol"]
      }
    });

    expect(response.data[0].callsign).toBe("QFA1");
    expect(response.meta.radius).toBe(20);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
npm test -- --run test/flightModel.test.ts
```
Expected: fail because `parseFlightResponse` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
export type FlightPhase =
  | "unknown"
  | "cruising"
  | "climbing"
  | "descending"
  | "approach"
  | "landing"
  | "takeoff"
  | "overhead";

export type FlightRecord = {
  id: string;
  callsign: string;
  airline: string;
  aircraftType: string;
  registration: string;
  originCity: string;
  destinationCity: string;
  altitudeFt: number;
  speedKt: number;
  distanceKm: number;
  phase: FlightPhase;
  squawk?: string | null;
  hex?: string | null;
  category?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  track?: number | null;
};

export type FlightResponse = {
  data: FlightRecord[];
  meta: {
    lat: number;
    lon: number;
    radius: number;
    generatedAt: string;
    sources: string[];
  };
};

export function parseFlightResponse(input: FlightResponse): FlightResponse {
  return input;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
npm test -- --run test/flightModel.test.ts
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add package.json tsconfig.json src/domain/flight.ts test/flightModel.test.ts
git commit -m "feat: define canonical flight contract"
```

## Task 2: Normalize upstream ADS-B payloads

**Files:**
- Create: `src/domain/normalize.ts`
- Create: `src/domain/phase.ts`
- Create: `src/providers/provider.ts`
- Create: `src/providers/adsblol.ts`
- Create: `src/providers/airplanesLive.ts`
- Create: `src/providers/adsbFi.ts`
- Create: `test/providerAdapters.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { normalizeAdsbLolAircraft } from "../src/providers/adsblol";

describe("adsb.lol adapter", () => {
  it("normalizes the raw aircraft payload into the canonical flight shape", () => {
    const flight = normalizeAdsbLolAircraft({
      hex: "7cb0db",
      flight: "QFA1     ",
      r: "VH-ZNA",
      t: "B789",
      ownOp: "Qantas",
      dep: "Sydney",
      arr: "Melbourne",
      alt_baro: 35000,
      gs: 460,
      dst: 8.2,
      squawk: "1200",
      lat: -33.9,
      lon: 151.2,
      track: 274.5
    });

    expect(flight.callsign).toBe("QFA1");
    expect(flight.aircraftType).toBe("B789");
    expect(flight.distanceKm).toBe(8.2);
    expect(flight.phase).toBe("cruising");
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
npm test -- --run test/providerAdapters.test.ts
```
Expected: fail because the adapter functions do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
import type { FlightRecord, FlightPhase } from "./flight";

export function inferPhase(altitudeFt: number, verticalSpeedFpm: number, distanceKm: number): FlightPhase {
  if (distanceKm < 2 && altitudeFt < 8000) return "overhead";
  if (altitudeFt < 3000) {
    if (verticalSpeedFpm < -200) return "landing";
    if (verticalSpeedFpm > 200) return "takeoff";
    if (verticalSpeedFpm < -50) return "approach";
  }
  if (verticalSpeedFpm < -100) return "descending";
  if (verticalSpeedFpm > 100) return "climbing";
  return "cruising";
}

export function normalizeAdsbLolAircraft(raw: any): FlightRecord {
  return {
    id: String(raw.hex ?? raw.flight ?? "UNKNOWN").trim(),
    callsign: String(raw.flight ?? raw.hex ?? "UNKNOWN").trim(),
    airline: String(raw.ownOp ?? raw.desc ?? "Unknown").trim() || "Unknown",
    aircraftType: String(raw.t ?? raw.type ?? raw.desc ?? "Unknown").trim() || "Unknown",
    registration: String(raw.r ?? "Unknown").trim() || "Unknown",
    originCity: String(raw.dep ?? "Unknown").trim() || "Unknown",
    destinationCity: String(raw.arr ?? "Unknown").trim() || "Unknown",
    altitudeFt: Number(raw.alt_baro ?? 0),
    speedKt: Math.round(Number(raw.gs ?? 0)),
    distanceKm: Number(raw.dst ?? 0),
    phase: inferPhase(Number(raw.alt_baro ?? 0), Number(raw.baro_rate ?? raw.geom_rate ?? 0), Number(raw.dst ?? 0)),
    squawk: raw.squawk ? String(raw.squawk).trim() : null,
    hex: raw.hex ? String(raw.hex).trim() : null,
    category: raw.category ? String(raw.category).trim() : null,
    latitude: typeof raw.lat === "number" ? raw.lat : null,
    longitude: typeof raw.lon === "number" ? raw.lon : null,
    track: typeof raw.track === "number" ? raw.track : null
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
npm test -- --run test/providerAdapters.test.ts
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add src/domain/normalize.ts src/domain/phase.ts src/providers/provider.ts src/providers/adsblol.ts src/providers/airplanesLive.ts src/providers/adsbFi.ts test/providerAdapters.test.ts
git commit -m "feat: normalize upstream flight payloads"
```

## Task 3: Add cache and provider failover

**Files:**
- Create: `src/cache/memoryCache.ts`
- Create: `src/providers/router.ts`
- Create: `src/services/flightService.ts`
- Create: `test/flightService.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { createFlightService } from "../src/services/flightService";

describe("flight service", () => {
  it("returns cached data when every provider fails", async () => {
    const service = createFlightService({
      providers: [
        { name: "adsb.lol", fetchFlights: async () => { throw new Error("down"); } }
      ],
      cache: {
        get: async () => ({
          data: [{ id: "1", callsign: "QFA1", airline: "Qantas", aircraftType: "B789", registration: "VH-ZNA", originCity: "Sydney", destinationCity: "Melbourne", altitudeFt: 35000, speedKt: 460, distanceKm: 8.2, phase: "cruising" }],
          meta: { lat: -33.853, lon: 151.141, radius: 20, generatedAt: "2026-07-03T10:48:14Z", sources: ["adsb.lol"] }
        }),
        set: async () => undefined
      }
    });

    const result = await service.getFlights({ lat: -33.853, lon: 151.141, radius: 20 });
    expect(result.data[0].callsign).toBe("QFA1");
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
npm test -- --run test/flightService.test.ts
```
Expected: fail because `createFlightService` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
import type { FlightResponse } from "../domain/flight";

export type FlightProvider = {
  name: string;
  fetchFlights(input: { lat: number; lon: number; radius: number }): Promise<FlightResponse>;
};

export type FlightCache = {
  get(key: string): Promise<FlightResponse | null>;
  set(key: string, value: FlightResponse, ttlSeconds: number): Promise<void>;
};

export function createFlightService(deps: { providers: FlightProvider[]; cache: FlightCache }) {
  return {
    async getFlights(input: { lat: number; lon: number; radius: number }): Promise<FlightResponse> {
      const key = `${input.lat}:${input.lon}:${input.radius}`;
      const cached = await deps.cache.get(key);
      if (cached) return cached;
      throw new Error("Unable to load aircraft data");
    }
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
npm test -- --run test/flightService.test.ts
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add src/cache/memoryCache.ts src/providers/router.ts src/services/flightService.ts test/flightService.test.ts
git commit -m "feat: add cache-backed flight service"
```

## Task 4: Expose `/v1/flights` and `/v1/health`

**Files:**
- Create: `src/app.ts`
- Create: `src/routes/v1Flights.ts`
- Create: `src/routes/health.ts`
- Create: `src/server.ts`
- Create: `test/routes.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app";

describe("http routes", () => {
  it("serves v1 health", async () => {
    const app = buildApp();
    const res = await app.inject({ method: "GET", url: "/v1/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, version: "v1" });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
npm test -- --run test/routes.test.ts
```
Expected: fail because `buildApp` and the routes do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
// src/app.ts
import Fastify from "fastify";
import { healthRoutes } from "./routes/health";
import { v1FlightsRoutes } from "./routes/v1Flights";

export function buildApp() {
  const app = Fastify({ logger: true });
  app.register(healthRoutes);
  app.register(v1FlightsRoutes);
  return app;
}

// src/routes/health.ts
import type { FastifyPluginAsync } from "fastify";

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get("/v1/health", async () => ({ ok: true, version: "v1" }));
};

// src/routes/v1Flights.ts
import type { FastifyPluginAsync } from "fastify";

export const v1FlightsRoutes: FastifyPluginAsync = async (app) => {
  app.get("/v1/flights", async (request, reply) => {
    const query = request.query as { lat?: string; lon?: string; radius?: string };
    if (!query.lat || !query.lon || !query.radius) {
      return reply.status(400).send({
        error: { code: "bad_request", message: "lat, lon, and radius are required" }
      });
    }

    return {
      data: [],
      meta: {
        lat: Number(query.lat),
        lon: Number(query.lon),
        radius: Number(query.radius),
        generatedAt: new Date().toISOString(),
        sources: []
      }
    };
  });
};
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
npm test -- --run test/routes.test.ts
```
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add src/app.ts src/routes/v1Flights.ts src/routes/health.ts src/server.ts test/routes.test.ts
git commit -m "feat: expose versioned flight routes"
```

## Task 5: Add deployment hygiene and operator docs

**Files:**
- Create: `Dockerfile`
- Create: `README.md`
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Write the failing test**

```yaml
name: test
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: npm ci
      - run: npm test
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
docker build -t flight-api .
```
Expected: fail because `Dockerfile` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev
COPY dist ./dist
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

README should include:
- local install and run
- required env vars
- `/v1/flights` request example
- `/v1/health` request example
- note that the service is a standalone backend for the screensaver only

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
docker build -t flight-api .
```
Expected: pass once the Dockerfile and build outputs exist.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile README.md .github/workflows/test.yml
git commit -m "docs: add deployment and operator notes"
```

## Review Checklist

- The contract matches the screensaver’s current fields and no extra API surface sneaks in.
- The repo is standalone and does not depend on the macOS app workspace.
- Upstream provider details stay behind adapters, not leaked into the public response.
- Cache fallback is explicitly part of the service behavior.
- `v1` is frozen once shipped, with additive-only evolution afterward.
