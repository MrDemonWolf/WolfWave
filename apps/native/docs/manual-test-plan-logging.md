# Manual test plan: logging, Debug tab, crash and export

Everything here is deliberately **not** covered by `make test`. Each item either
needs the app running with real services attached, or needs the process to
actually die, which the xctest host cannot survive.

Automated coverage already proves the pure layers: line format, parser,
redaction rules both directions, tail cursor, crash-marker parsing, bundle
composition, rail coverage. Don't re-test those by hand. Test the seams where
code meets a running app.

**Build:** Debug (`WolfWave Dev.app`, bundle id `com.mrdemonwolf.wolfwave.dev`).
**Log path:**

```bash
open ~/Library/Containers/com.mrdemonwolf.wolfwave.dev/Data/Library/Application\ Support/WolfWave/Logs/
```

Useful throughout:

```bash
tail -f ~/Library/Containers/com.mrdemonwolf.wolfwave.dev/Data/Library/Application\ Support/WolfWave/Logs/wolfwave.log
```

---

## 1. Log format on a real run

- [ ] **1.1 Launch banner.** Quit the app fully, relaunch, then look at the top of the newest lines. There should be one `WolfWave session start` line carrying `session=`, `version=`, `build=`, `os=`, `arch=`, `pid=`.
- [ ] **1.2 Column-0 invariant holds in the wild.** Every line either starts with a digit (an ISO timestamp) or with whitespace (a continuation). Anything else is a bug:

  ```bash
  grep -cvE '^([0-9]{4}-[0-9]{2}-[0-9]{2}T|[[:space:]])' ~/Library/Containers/com.mrdemonwolf.wolfwave.dev/Data/Library/Application\ Support/WolfWave/Logs/wolfwave.log
  ```

  Expect `0`.
- [ ] **1.3 Columns line up.** Timestamp, level, and category should form clean vertical columns when read in a monospaced editor. Long filenames may push the message right; that is expected and only affects the location column.
- [ ] **1.4 Multi-line messages are indented.** Trigger something with a multi-line error (disconnect Wi-Fi during a Twitch reconnect). The continuation lines must be indented two spaces, never sitting at column 0.

## 2. Redaction, on real credentials

> This is a security boundary. Do these before shipping.

- [ ] **2.1 No live token in the log.** Sign in to Twitch, then search the log for any fragment of your real OAuth token. Expect zero hits.
- [ ] **2.2 Your Twitch user ID is not readable.** Search for your numeric Twitch user ID. Expect `[USER_ID_REDACTED]` in its place, never the digits.
- [ ] **2.3 Diagnostic numbers survived.** Confirm byte counts, durations, and ports still read as numbers. This is the half that regressed before:

  ```bash
  grep -E 'bytes=|ms=|port=|code=' ~/Library/Containers/com.mrdemonwolf.wolfwave.dev/Data/Library/Application\ Support/WolfWave/Logs/wolfwave.log | head
  ```

  Values must be digits, not `[USER_ID_REDACTED]`.
- [ ] **2.4 Exported file is clean too.** Run the export from step 5 and repeat 2.1 and 2.2 against the exported file.

## 3. Debug tab: log viewer

Settings → Debug → Log Viewer.

- [ ] **3.1 It shows content.** Lines appear on open, not an empty box.
- [ ] **3.2 It follows live.** With Follow on, click the `Log .info` / `Log .warn` / `Log .error` buttons further down the pane. New lines appear within about a second and the view scrolls to them.
- [ ] **3.3 Follow can be paused.** Turn Follow off, scroll up, emit more lines. The view must stay where you put it.
- [ ] **3.4 Level filter.** Set the level to Error. Only `ERROR` rows remain. Set back to All.
- [ ] **3.5 Category filter.** Pick `DevTools`. Only test lines remain. Confirm the new Twitch sub-categories (`TwitchAuth`, `TwitchChat`, `TwitchEvents`, `TwitchRedeem`) appear in the menu and each selects a real subset.
- [ ] **3.6 Search.** Type a word from a recent message. Then search for a **field value** (e.g. an attempt number) and confirm it matches too, since search covers fields as well as message text.
- [ ] **3.7 Expansion.** Click a row with fields. It should expand to show the source location and the full `key=value` list.
- [ ] **3.8 Copy Visible** puts exactly the filtered lines on the clipboard.
- [ ] **3.9 Clear View** empties the display but **does not** touch the file. Verify the file still has its lines afterwards.
- [ ] **3.10 Survives a Clear Log.** With the viewer open, use Clear Log in the Logs & Events card. The viewer must recover and keep tailing rather than freezing or duplicating (this is the cursor's re-prime path).

## 4. Debug tab: the frozen-state fixes

> These are the ones that only reproduce with real services. This is the most
> important section.

- [ ] **4.1 Twitch connection is live.** Settings → Debug → Service Controls. Note the "Connected:" row. Now connect Twitch from the Twitch pane. **Within ~2 seconds and without switching tabs**, the row must flip to `yes`. Previously it stayed frozen for the whole session.
- [ ] **4.2 It flips back.** Click Force Disconnect. Row returns to `no` on its own.
- [ ] **4.3 Send Test Chat tracks reality.** While disconnected, the button is disabled. After connecting, it becomes enabled **without** needing a tab switch. This was the stuck-disabled bug.
- [ ] **4.4 Discord RPC state shows.** The Discord section shows a live `State:` line. Quit Discord and confirm it changes.
- [ ] **4.5 Sparkle explains itself.** Click Check for Updates. On a normal Debug build it should proceed; on a Homebrew install it must print the "Sparkle is disabled" note rather than silently doing nothing.
- [ ] **4.6 Copy Diagnostics does not beachball.** With a large log (a few MB), click Copy Diagnostics. The UI must stay responsive.
- [ ] **4.7 Diagnostics tells the truth.** Paste the result. Confirm **Connections** and **Preferences** are separate tables, and that turning Discord presence *on* while Discord is *not* connected shows `Discord presence | Yes` under Preferences and `Discord RPC | disconnected` under Connections. Reporting a preference as a connection was the old bug.
- [ ] **4.8 Rail navigation.** Every rail row jumps to its section, including the new Log Viewer entry, and the highlight follows as you scroll.

## 5. Export and bug report

- [ ] **5.1 Export writes a bundle.** Settings → Advanced → Export Logs. Filename should be `wolfwave-diagnostics-<date>-<time>.log`. Open it and confirm, in order: an `ENVIRONMENT` block with version/OS/arch/install, then one `LOG` section per file.
- [ ] **5.2 Rotated logs are included.** Force a rotation (or rename a copy to `wolfwave.log.1` in the Logs folder), export again, and confirm the backup appears **before** the live log.
- [ ] **5.3 Second export does not overwrite.** Export twice in the same folder. Two files, distinct names.
- [ ] **5.4 Clipboard copy has the header.** Advanced → Copy to Clipboard. The paste must begin with the environment block.
- [ ] **5.5 Bug report is prefilled.** Advanced → Report a Bug. The GitHub issue body should contain app version, macOS, architecture, install method, log size, and diagnostics opt-in.

## 6. Crash path

> Cannot be automated: raising a fatal signal kills the test host. The handler's
> three writes are verified against the parser in `CrashMarkerTests`, but that
> proves composition, **not** that the handler runs correctly under a real
> signal. This section is the only thing that proves that.

- [ ] **6.1 Force a real crash.** With the Debug app running, from Terminal:

  ```bash
  kill -SEGV $(pgrep -f "WolfWave Dev")
  ```

- [ ] **6.2 Marker was written, and is readable.** Before relaunching:

  ```bash
  cat ~/Library/Containers/com.mrdemonwolf.wolfwave.dev/Data/Library/Application\ Support/WolfWave/State/last-crash.marker
  ```

  Expect `WOLFWAVE-CRASH 1`, then `kind=signal`, `pid=`, `version=`, `build=`, `signal=SIGSEGV`, `epoch=`. **If this is empty or truncated, the async-signal-safe write path is broken** and that is a release blocker.
- [ ] **6.3 The OS still saw the crash.** Confirm a normal macOS crash report exists in Console.app → Crash Reports. This proves the handler still chains and re-raises rather than swallowing.
- [ ] **6.4 Next launch surfaces it.** Relaunch. Settings → Advanced shows the "Recovered from a crash" callout **naming the signal and time**, not generic text.
- [ ] **6.5 It reached the log.** The new log should contain an `ERROR` line for the previous crash with `kind=signal` and `signal=SIGSEGV` fields.
- [ ] **6.6 It reached the export.** Export now. The bundle must contain a `LAST CRASH` section.
- [ ] **6.7 It shows exactly once.** Relaunch again cleanly. The callout must be gone.
- [ ] **6.8 Legacy marker still readable.** Optional. Write an old-format marker by hand and confirm the callout still renders:

  ```bash
  printf 'SIGBUS\n' > ~/Library/Containers/com.mrdemonwolf.wolfwave.dev/Data/Library/Application\ Support/WolfWave/State/last-crash.marker
  ```

## 7. Regression watch

- [ ] **7.1 Music.app control still works.** Play a track and confirm the now-playing card, Discord presence, and overlay all update. The entitlements were not touched, but this is the app's core path and the category sweep touched `AppleMusicSource`.
- [ ] **7.2 Console.app filters.** Filter subsystem `com.mrdemonwolf.wolfwave`. Category strings changed: a saved `Twitch` filter now shows only leftover wiring lines. The traffic is under `TwitchAuth` / `TwitchChat` / `TwitchEvents` / `TwitchRedeem`.
- [ ] **7.3 No log spam.** Idle the app a few minutes with music playing. Log growth should be modest; a runaway loop would show as rapid rotation.

---

## Known issues, do not re-report

- **Flaky tests unrelated to this work.** `SongRequestServiceTests` and `TwitchTokenRefreshTests` fail intermittently in a full `make test` run. Several suites write `songRequestEnabled` on the process-global `DefaultsStore.store` while Swift Testing suites run in parallel with XCTest. Confirmed on unmodified `main` (1 and 3 failures across two runs), so it is not from this branch. Being fixed separately.
- **`AdvancedSettingsView` `type_body_length`** reappeared in SwiftLint. It was already baselined at that line; editing the type changed the body size so the entry stopped matching.
- **Session banner timestamp** can trail the first log line by a few milliseconds. It is emitted lazily on first write and is a boundary marker, not an event.
