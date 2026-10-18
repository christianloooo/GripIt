# Coaching performance design

The user approved the proposed backend performance work. This pass brings the
existing Step 4 proxy into the integrated native test branch and removes repeated
AI work without changing provider, model defaults, prompts, grip geometry, or
prototype coaching thresholds. A subsequent user approval expands AI from a
rewrite engine into interpretation and follow-up explanation, described below.

Alternatives: a database alone would persist records but would not prevent repeat
AI calls. Redis plus hosted authentication would support multiple instances but
adds deployment and identity work. The selected first pass uses bounded caches
in the existing Node process and native app, explicit deadlines, and request
timing. It is useful now and can later use a shared cache behind authentication.

## Server

Preserve `/api/coach` and `/api/ask` response contracts. Import the existing
Anthropic adapter and measured-hand/follow-up prompts. Cache only accepted AI
generation outputs for ten minutes, at most 256 items, and share in-flight
identical generation work. Hash the complete provider input, system prompt,
resolved model, token limit, and credential fingerprint. Never use assessment ID
alone. At most 32 distinct generations can be in flight. Failures/rejections are
not cached so Retry can recover. Set SDK timeout to six seconds and retries to
zero, below the native ten-second coach deadline. Preserve parallel coach/fit
requests.

Validate the fields read by the prompt builders. Enforce a 256 KiB request limit
in both development and exported handlers. Use the same handlers in both paths.
Provide `/api/health`; log request IDs, status, total latency, generation cache
status and outcomes without hand measurements, prompts, questions or credentials.
Allow only the configured local development hostname in addition to Vite's
defaults. Keep the existing ignored key file in place and use its directory as
an explicit development environment directory; do not copy keys into this clone.

## Native

Use a per-client actor with a ten-minute, 32-item cache of successful coach and
question responses, plus in-flight deduplication. Keys include the complete
sorted encoded request and endpoint. Cache entries stay in memory and are
discarded with the hand session. Do not cache fallback or partial coach replies,
so Retry remains effective. Retain local deterministic feedback immediately.

## Approved AI flexibility extension, 2026-10-18

The user requested less deterministic advice and more flexible AI answers, then
said to proceed. Supply actual throw records and computed session medians, plus
the measured hand and grip context. Preserve these exact records with the
assessment so timestamps do not defeat native caching. AI may interpret, qualify
or disagree with the unreviewed sample-rule suggestion and offer an optional
experiment. It may explain general principles from the cited research context,
while separating them from personal observations. It must not invent observed
forces, release mechanics, medical diagnoses or promised outcomes.

Show AI coaching first. Display static zone instructions rather than repeated
metric warnings. Keep prototype rule notes and colors available in a disclosure,
with colors off by default and no uncalibrated confidence percentages. Always
offer Retry for partial replies. Explain actionable connection failures.

Bound output and check numerical tokens against signed structured observations
and hand measurements, including formatted clock values. Question text, source
URLs and prototype targets do not authorize new measured values. This guard
checks numerical provenance, not biomechanics or causal validity. Static hand-fit
text receives hand/placement information only, rather than prototype throw flags.

## Scope and validation

This is performance infrastructure, not durable scan/session storage, accounts,
or cloud sync. Process-local caches do not span server restarts or instances.
Fresh or changed requests still pay provider latency. Follow-on persistence and
hosting need their own storage/identity design.

Verify duplicate and concurrent calls, changed inputs, expiry, eviction, failed
retry, malformed/oversized requests, SDK timeout settings, and safe fallback.
Run native tests, web tests/build, live cold/warm API calls, and a signed iPhone
build/install where device availability permits. Preserve local signing changes.
