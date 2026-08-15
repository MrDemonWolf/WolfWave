# WolfWave log format

This is the contract for WolfWave's on-disk log. Read it before writing anything
that parses a log file. The writer is [`Core/Logger.swift`](../WolfWave/Core/Logger.swift);
the canonical reader is [`Core/LogRecord.swift`](../WolfWave/Core/LogRecord.swift).

Do not hand-roll a second parser. If you need to read logs, call
`LogRecord.parse(contents:)`. That is the whole reason it is a pure, dependency-free
type: one definition of the grammar instead of a writer and several regexes that
drift apart.

## The invariant

Everything below follows from one rule:

> **A log record starts with an ISO-8601 timestamp at column 0.
> A line starting with whitespace is a continuation of the record above it.**

That is enough to split a file into records without understanding any other
field. Anything that is neither is noise (a blank line, or the truncated head of
a tail read) and is dropped rather than guessed at.

## Line grammar

```
<timestamp>  <LEVEL>  <Category>  <File.swift:line>  <message>[ key=value ...]
```

Fields are separated by runs of **two or more spaces**. Reading left to right,
take four fields and treat the remainder as the message, so a message containing
its own double spaces survives intact.

| Field | Width | Notes |
|---|---|---|
| timestamp | 29 | ISO 8601, milliseconds, explicit UTC offset (`-05:00`, or `Z`) |
| level | padded to 5 | `DEBUG`, `INFO`, `WARN`, `ERROR` |
| category | padded to 12 | `LogCategory` raw value. Longer names overflow |
| location | padded to 34 | `#fileID` basename + `#line`. Longer paths overflow |
| message | rest of line | Free-form, already redacted |
| fields | tail | Optional ` key=value` pairs |

Padding is what keeps the file readable: the timestamp, level, and category
columns line up so a human scans down them. The location column is padded on a
best-effort basis and deliberately overflows rather than truncates, because
truncating would break the click-through to a source line.

Levels are bare uppercase words, not emoji. An emoji level is multi-codepoint
(`ℹ️` is U+2139 U+FE0F), variable-width in bytes, impossible to align, and makes
`grep -c ERROR` ambiguous against message text.

### Example

```
2026-08-14T10:48:09.184-05:00  INFO   App           Logger.swift:0                      WolfWave session start session=0e9c35 version=2.1.0 build=9 os=26.5.2 arch=arm64 pid=54837
2026-08-14T10:48:09.431-05:00  ERROR  Twitch        TwitchChatService+EventSub.swift:812  EventSub reconnect failed attempt=3 code=4003
2026-08-14T10:48:09.446-05:00  WARN   Music         AppleMusicSource.swift:661          Unknown player state, trusting track raw="kPSX"
```

## Categories

`LogCategory` is the **only** accepted category type. There is deliberately no
`String` overload on `Log`, so a category typo is a compile error rather than a
phantom category nobody ever filters on. (When a `String` overload existed, every
call site used it, the enum sat at zero uses, and a `"Reset"` typo shipped to
three sites unnoticed.)

The raw value is what lands in the log's category column and in Console.app's
Category field. Keep raw values at 12 characters or fewer or the column stops
aligning; `LoggerTests` enforces that, plus uniqueness and no embedded spaces.

Twitch is split rather than being one bucket. It was 236 of 458 categorized call
sites, so filtering `Twitch` selected half the log and told you almost nothing.
The split follows the existing `TwitchChatService+*` file seams, which keeps the
mapping mechanical:

| Category | Covers |
|---|---|
| `TwitchAuth` | Device-code flow, token refresh and validation |
| `TwitchChat` | Chat send/receive, bot-command routing |
| `TwitchEvents` | EventSub subscription lifecycle and its WebSocket |
| `TwitchRedeem` | Channel points, bit cheers, the resolution outbox |
| `Twitch` | Everything else: view models, wiring, settings |

The rest: `App`, `Discord`, `Music`, `Keychain`, `Network`, `WebSocket`,
`Update`, `SongRequest`, `DevTools`, `Dev`, `Diagnostics`, `Onboarding`,
`Artwork`, `WhatsNew`, `History`, `Reset`.

Filter one subsystem in Console.app with subsystem `com.mrdemonwolf.wolfwave`
and the Category column, or in a file:

```bash
grep -E '^\S+  \w+ +TwitchEvents' wolfwave.log
```

## Structured fields

Call sites may attach ordered key/value pairs:

```swift
Log.error(
    "EventSub reconnect failed",
    category: "Twitch",
    fields: ["attempt": 3, "code": 4003, "reason": "transport closed"]
)
```

They render as a ` key=value` tail in declaration order. A value is
double-quoted when it is empty or contains whitespace, `=`, or `"`; backslash,
quote, and newline are escaped inside the quotes.

Keys match `[A-Za-z_][A-Za-z0-9_.]*`. The parser walks tokens from the end of
the line and takes the longest suffix that all parse as fields. A message that
genuinely ends in `word=word` is absorbed as a field, which is harmless: the
text and the parsed field carry the same information.

**Prefer fields over interpolation.** `attempt=3` is queryable; "on attempt 3"
needs a bespoke regex per message. Fields are also how you keep large numbers
out of the redactor's way (see below).

## Continuation lines

A message containing newlines is written with every line after the first
indented by two spaces. `LogRecord.parse(contents:)` strips that indent and
folds the lines back into one `message`. Without the frame, a multi-line
`error.localizedDescription` or a crash backtrace would produce orphan lines
with no timestamp, level, or category.

## Session banner

The first write of each launch, and the first write after every rotation, emits:

```
2026-08-14T10:48:09.184-05:00  INFO   App  Logger.swift:0  WolfWave session start session=0e9c35 version=2.1.0 build=9 os=26.5.2 arch=arm64 pid=54837
```

This is what makes an exported log attributable to a build. Per-line session IDs
are deliberately not written: the banner marks the boundary and a reader carries
it forward, at zero cost per line.

Because the banner is emitted lazily on the first *write*, its timestamp can
trail the first log line's by a few milliseconds. It is a boundary marker, not
an event; do not rely on it being the earliest timestamp in the file.

## Redaction

Every message body and every field value is redacted before it reaches disk or
Console.app. Rules:

| Pattern | Becomes |
|---|---|
| `oauth_…` | `oauth_[REDACTED]` |
| `Bearer …` | `Bearer [REDACTED]` |
| `Client-ID: …` | `Client-ID: [REDACTED]` |
| digits in an ID context (`user_id=`, `broadcaster_user_id=`, `channel_id:`, …) | key preserved, value → `[USER_ID_REDACTED]` |
| any 30+ character alphanumeric run | `[TOKEN_REDACTED]` |
| any bare 9+ digit run | `[USER_ID_REDACTED]` |

Field keys are never redacted; they carry no user data and are what make a line
searchable.

Two key sets change how a field's value is treated:

- **Sensitive keys** (`token`, `secret`, `password`, `user_id`, `channel_id`, …)
  are replaced wholesale with `[REDACTED]`, whatever the value looks like.
- **Numeric-safe keys** (`bytes`, `ms`, `duration`, `port`, `count`, `code`,
  `status`, `epoch`, …) skip the bare-digit rule, so `bytes=1073741824` survives.

This last part is the point. The rule used to be a blanket `\b\d{6,}\b`, which
rewrote byte counts, millisecond durations, ports, and epoch values into
`[USER_ID_REDACTED]` in the one artifact a user actually hands over. **If you
are logging a large number, log it as a field with a numeric-safe key.** In
prose it will be redacted at 9 digits.

Redaction is a security boundary. If you change these rules, prove both
directions in `LoggerTests`: identifiers still die, and diagnostic numbers still
survive.

## Files and rotation

Logs live in the sandboxed container:

```
~/Library/Containers/com.mrdemonwolf.wolfwave/Data/Library/Application Support/WolfWave/Logs/
```

(`com.mrdemonwolf.wolfwave.dev` for Debug builds and the test host.)

| File | Role |
|---|---|
| `wolfwave.log` | Live |
| `wolfwave.log.1` … `.3` | Rotated backups, `.1` newest |

Rotation fires at 5 MB, so 20 MB worst case. Depth is 3 rather than 1 because a
tight reconnect loop rotates twice in seconds and a single backup let it evict
the original failure. Anything reading logs for diagnosis should read the
backups too: `Log.rotatedLogFiles()` returns them oldest first.

## Severity gate

`WOLFWAVE_LOG_LEVEL` (`silent` / `error` / `warn` / `info` / `debug`) gates
**both** sinks, file and OSLog. Under XCTest it defaults to `error`; otherwise
`debug`. `Log.debug` is additionally compiled out of release builds.

The XCTest default matters when writing tests: a test that asserts on log file
contents must log at `.error`, or its lines never land. That gate is also why
suites no longer flood and rotate the shared log mid-run.

## Parsing from outside the app

There is no JSON sidecar; this text format is the only log. For ad-hoc work the
invariant makes standard tools sufficient:

```bash
# Errors only
grep -E '^\S+  ERROR' wolfwave.log
```

```bash
# One subsystem, most recent first, across rotated files
cat wolfwave.log.3 wolfwave.log.2 wolfwave.log.1 wolfwave.log 2>/dev/null | grep -E '^\S+  \w+ +Twitch'
```

```bash
# Every record boundary (continuations excluded)
grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' wolfwave.log
```

For anything structured, use `LogRecord`.
