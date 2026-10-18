# GripIt demo API contract, version 1

Agreed collaboration boundary, October 18, 2026. Codex maintains this document. Claude owns the service; Codex owns the native client and extractor. JSON uses camelCase, ISO-8601 UTC timestamps and explicit nullable readings. All `/api` responses use `Cache-Control: no-store`. Do not include credentials, provider error bodies or internal stack traces.

## Authentication

These are application wrappers around Better Auth, not assumed built-in Better Auth routes.

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/api/accounts/register` | `{ "name": string, "email": string, "password": string }` | 201, AuthResult |
| POST | `/api/accounts/login` | `{ "email": string, "password": string }` | 200, AuthResult |
| POST | `/api/accounts/logout` | none | 204; invalidate current session |
| GET | `/api/me` | none | 200, `{ "user": User, "entitlement": Entitlement }` |

`User = { id: string, name: string, email: string }`.
`AuthResult = { user: User, token: string, expiresAt: string, entitlement: Entitlement }`.

All other account/data/plan/OCR routes require `Authorization: Bearer <session token>`. Use 401 for missing, invalid or expired sessions. Codex stores the session token in iOS Keychain, never UserDefaults. User identity comes from the verified session, never a supplied userId. Do not expose MongoDB document IDs or auth-library sessions wholesale.

## Plans and usage

```ts
type UsageKind = "photo_scan" | "throw_review";
type Entitlement = {
  plan: "free" | "pro";
  demo: boolean;
  resetsAt: string;
  limits: { photoScans: number; throwReviews: number };
  used: { photoScans: number; throwReviews: number };
  remaining: { photoScans: number; throwReviews: number };
};
```

Daily limits: Free 3 each, Pro 20 each, reset at UTC midnight. Reserved operations reduce reported remaining while in flight; used reports completed operations. Remaining never goes negative. Plan changes preserve daily usage. Entitlement is returned by `/api/me` and the operations below.

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| POST | `/api/usage/reviews` | `{ "reviewId": string, "sessionId": string, "pitchId": string, "throwIds": string[] }` | 200, `{ "reviewId": string, "entitlement": Entitlement }` |
| POST | `/api/demo/plan` | `{ "plan": "free" \| "pro" }` | 200, `{ "entitlement": Entitlement }` |

Review requests also carry `Idempotency-Key`; use reviewId as the key. A new deliberate review gets a new reviewId even if its throw set is unchanged. Navigating back to the same result does not issue another request. This endpoint authorizes/counts the review; it does not calculate advice or move the rule engine to the server. The app validates the draft before requesting usage, then runs the existing deterministic assessment and presents it.

Demo plan changes are authenticated, affect only the current user, and require `DEMO_FEATURES_ENABLED=true` on the service. Return 404 when disabled. No real billing and no daily-reset endpoint. The Pro UI must communicate that no payment is taken.

Quota exhaustion returns 429 with error code `quota_exceeded`, the `kind`, current entitlement, and `Retry-After` seconds until reset. Rate limits for abuse use `rate_limited`, so the UI does not confuse them with plan exhaustion. Registration/login errors should not expose whether an email exists beyond what the chosen auth flow requires.

## Real photo extraction

`POST /api/photos/read` accepts raw JPEG or PNG image bytes with the corresponding Content-Type and `Idempotency-Key`. Maximum encoded HTTP body is 4 MiB, an engineering limit, not a coaching threshold. The native client resizes/compresses before sending. Do not accept remote image URLs, multipart data, filenames as answers, or client-supplied extracted numbers.

```ts
type PhotoReadings = {
  velocityMph: number | null;
  totalSpinRpm: number | null;
  spinDirectionClock: string | null; // clock text, e.g. "01:56"
  spinEfficiencyPercent: number | null;
  gyroDegree: number | null;
  horizontalBreakInches: number | null;
  verticalBreakInches: number | null;
  releaseHeightFeet: number | null;
  rapsodoScore: number | null;
};
type PhotoExtraction = {
  schemaVersion: "1.0.0";
  model: "perceptron-mk1.5";
  readings: PhotoReadings;
  warnings: string[];
};
type PhotoReadResult = PhotoExtraction & {
  requestId: string;
  entitlement: Entitlement;
};
```

All nine keys are required, even when null. Preserve source units/signs; unreadable, invalid or absent values stay null. Do not infer a missing gyro angle from efficiency in the extraction response. Source sample/manual is assigned locally; do not change the existing downstream ThrowSource enum for OCR. The user can edit and must confirm before a throw is added.

Codex provides `services/photo-reading/extract.ts`, exporting:

```ts
export type ExtractPhotoInput = {
  bytes: Uint8Array;
  contentType: "image/jpeg" | "image/png";
  signal?: AbortSignal;
};
export type PhotoExtractor = (input: ExtractPhotoInput) => Promise<PhotoExtraction>;
export function createPhotoExtractor(options: {
  apiKey: string;
  fetchImpl?: typeof fetch;
}): PhotoExtractor;
```

Contract types will live in `services/photo-reading/types.ts`. Typed provider errors live in `services/photo-reading/errors.ts`: `PhotoExtractionError` has code `provider_unavailable`, `provider_timeout` or `invalid_extraction` and a sanitized message. Before this module exists, Claude should define a compatible injected interface under backend and a test fake, not create files under Codex's ownership. Mount the real module once its committed milestone is available. Native/server request timeouts must allow the provider timeout plus response handling; no automatic paid retries.

Claude owns authentication, body/image signature checks, per-user quota reservation, payload digest/idempotency and returned entitlement. Codex owns the provider request, structured response and reading validation. An identical successful retry returns the cached extraction without another provider call or counter increment. A key reused for different bytes returns 409. An operation still in progress returns 409 `operation_in_progress`; client retry uses the same key. Provider failure releases its quota reservation. Cancellation after successful extraction does not undo completed usage.

No silent fixture fallback on failure. Return manual entry/retry guidance in the app. Uploaded photos are processed in memory; do not store raw images or log base64 bodies. Bound idempotency result retention and prevent cross-user cache reuse.

## Saved progress

Use existing HandProfile and ThrowSessionDraft JSON shapes from the current source. A snapshot is:

```ts
type SessionSnapshot = {
  schemaVersion: "1.0.0";
  sessionId: string;
  title: string;
  handProfile: Record<string, unknown>; // validate existing HandProfile envelope
  pitches: {
    pitchId: "four-seam" | "two-seam" | "slider" | "changeup";
    draft: Record<string, unknown>; // validate existing ThrowSessionDraft shape
    assessment: Record<string, unknown> | null; // historical display only
  }[];
};
type SavedSession = SessionSnapshot & { createdAt: string; updatedAt: string };
type SessionSummary = {
  sessionId: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  pitchIds: string[];
  throwCount: number;
};
```

| Method | Path | Body | Success |
| --- | --- | --- | --- |
| PUT | `/api/sessions/:sessionId` | SessionSnapshot, with matching ID | 200, `{ "session": SavedSession }` |
| GET | `/api/sessions?limit=20&cursor=...` | none | 200, `{ "sessions": SessionSummary[], "nextCursor": string \| null }` |
| GET | `/api/sessions/:sessionId` | none | 200, `{ "session": SavedSession }` |
| DELETE | `/api/sessions/:sessionId` | none | 204 |

Use upsert scoped to authenticated user and sessionId, with createdAt preserved and updatedAt assigned on the server. Lists use stable pagination; default limit 20, maximum 100. Cap snapshot bodies at 1 MiB. Validate finite numbers, string lengths, allowed pitches, draft field types, source values and profile schema/units before storing. Do not mutate existing field names or infer missing measurements. Unowned records return 404, including for deletion, and all queries include user identity. Sessions survive sign-out/restart. Saving/loading does not consume scan or review usage.

## Errors and service setup

```json
{ "error": { "code": "invalid_request", "message": "Check the request and try again." } }
```

Quota errors add top-level `kind` and `entitlement`. Supported codes/statuses: `invalid_request` 400, `unauthenticated` 401, `not_found` 404, `conflict` 409, `operation_in_progress` 409, `payload_too_large` 413, `unsupported_media_type` 415, `quota_exceeded` 429, `rate_limited` 429, `invalid_extraction` 502, `provider_unavailable` 503, `provider_timeout` 504, `internal_error` 500. Unknown errors are sanitized.

`GET /health` is public liveness, 200 `{ "ok": true }`; `GET /ready` returns 200 only after MongoDB/index initialization succeeds, otherwise 503. No credentials or detailed database topology in responses.

Backend `.env.example`: `MONGODB_URI`, `MONGODB_DATABASE`, `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `PERCEPTRON_API_KEY`, `HOST`, `PORT`, `DEMO_FEATURES_ENABLED`. Use an unprivileged local port, default 3001, to avoid Codex's standalone OCR demo service at 5173. No need to copy the ignored root .env. Native base URL wiring is Codex's responsibility. Local same-Wi-Fi HTTP is for the Xcode demo; hosted connections use HTTPS.
