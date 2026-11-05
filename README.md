# PowerKit

A native Windows 11 power-user control panel: 54 registry tweaks and 30 one-click
power/tool commands, in a Fluent window that follows your Windows light/dark theme
and accent colour. The theme button in the header - a sun in light mode, a moon in
dark - cycles light, dark and following Windows, and remembers the choice; either way
the accent colour keeps following Windows, and the activity log and dialogs repaint
with the rest of the app the moment it changes.

No installers, no dependencies, no background service. It is a PowerShell + WPF
app that talks to the registry directly.

## Run it

Double-click `PowerKit.cmd`. It launches without a console window.

For a desktop or Start menu entry, create a shortcut to `PowerKit.cmd` - either on the
desktop or in `%APPDATA%\Microsoft\Windows\Start Menu\Programs` - and set its icon to
`src\powerkit.ico`. That file carries the icon at every size from 16 to 256 px, and it
is the same one the taskbar and Alt-Tab show while the app is open. Set the shortcut's
run style to `Minimized` so the launcher window never flashes up.

### Desktop right-click menu

Right-clicking the desktop shows a **PowerKit** submenu. It holds **Launch PowerKit**
plus one entry for every pinned card - tweaks and commands alike. Pin with the pin button
in a card's title row and it appears in the pinned strip and in that menu; unpin and it
leaves both. On Windows 11 the submenu is under **Show more options** (or Shift+F10),
because third-party entries cannot be added to the shortened menu itself.

A pinned entry opens PowerKit scrolled to its card rather than applying anything
silently, so the toggle or the **Run** button is still in front of you when the change
happens. The menu is rebuilt from the pinned list on every start and on every pin change.

It lives in `HKCU\Software\Classes\DesktopBackground\Shell\PowerKit`. Deleting that key
removes the submenu, and PowerKit writes it again the next time it starts.

Or from a terminal:

```
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\PowerKit.ps1
```

- Standard user: all user-level tweaks work straight away. Machine-wide (ADMIN)
  tweaks ask Windows for approval once per session, then apply in place - no need
  to restart PowerKit.
- Every change is written straight to the registry; there is no shadow state to
  drift out of sync. The switch position is always read live from Windows.

## Administrator-only tweaks

The first time you toggle an ADMIN card (or run an admin command), PowerKit starts a
small hidden helper process through a normal UAC consent prompt. That helper keeps
the elevated rights for the session, so the next machine-wide change applies
instantly with no second prompt. It exits when PowerKit closes, after 15 minutes of
inactivity, or when the app window is gone.

The helper is not a general-purpose shell:

- It only accepts requests over a randomly named named pipe, gated by a
  per-session token and by the client process ID of the PowerKit window that
  launched it.
- It only applies catalog tweaks whose keys are machine-wide, and catalog commands
  marked ADMIN. It cannot be asked to run arbitrary commands or write arbitrary keys.
- Requests are answered over that pipe; nothing is left behind on disk.

If you decline the prompt, nothing is written and the card explains what happened,
with the option to restart the whole app elevated instead.

## What is in it

| Group | Examples |
| --- | --- |
| File Explorer | file extensions, hidden/system files, classic right-click menu, seconds in the clock |
| Taskbar and Start | left-aligned taskbar, hide Widgets/Chat/Copilot/search, small taskbar buttons |
| Appearance | dark mode, transparency, accent title bars, disable animations and menu delay |
| Performance | Fast Startup, startup app delay, Game DVR, mouse acceleration, power throttling |
| Privacy and Ads | advertising ID, activity history, tips and suggestions, telemetry, location |
| System and Updates | long paths, Developer Mode, verbose boot, update auto-restart, lock screen |
| Power and Session | restart, shut down, sleep, hibernate, lock, UEFI restart, power plans |
| Quick Tools | Task Manager, Services, Device Manager, God Mode folder, DNS flush, temp cleanup |

Every card explains what the setting does, and anything with a real downside carries
an inline warning plus a CAUTION or ADVANCED badge.

## Categories

The cards are grouped into categories, and every category header folds. Click a
header (or the chevron on its right) to collapse it, click again to open it; the
folded categories are remembered in `settings.json`, so the app opens the way you
left it. A folded category never hides a result: typing in the search box opens
every category with a match, and picking a category in the navigation pane opens
it too.

## Toggling and resetting

- **Toggle** applies the tweak immediately. Where Windows caches the setting, the
  card says what is needed (Restart Explorer, sign out, reboot) and a banner at the
  top offers the restart.
- **Reset** restores the value that was in the registry the first time PowerKit ran.
  On first launch it captures a baseline of every setting it manages and stores it in
  `%LOCALAPPDATA%\PowerKit\defaults.json`.
- **Re-capture defaults** (bottom of the navigation pane) makes the current state the
  new baseline - useful once you have Windows configured the way you like it.
- **Reset all tweaks** sits at the top of the Active tweaks section.

## Activity log

Every registry write, command and elevation event is recorded to
`%LOCALAPPDATA%\PowerKit\app.log`. The **Activity log** button at the bottom of the
navigation pane opens it inside PowerKit:

-  Newest entries first, each tagged WRITE, RUN, HELPER, ERROR or INFO, with
  `ADMIN` on anything the elevated helper wrote.
- Live refresh every three seconds while the window is open, plus a filter box,
  a Refresh button, Open folder and Clear log (with confirmation).
- The file rotates at 512 KB into `app.log.1` and `app.log.2`, so it can never grow
  without bound. Both the window and the elevated helper write through the same
  rotating writer.
- Rows that belong to a card are clickable (hand cursor, chevron on the right):
  tweak writes and commands alike. Clicking one closes the log, switches the
  navigation pane to that card's group, clears any active search, scrolls the card
  into view and outlines it in the accent colour for a moment. Free-form events stay
  plain, since no card produced them.
- Write rows carry an **Undo** button. Every write records the value it replaced, so
  Undo puts that one registry value back without touching the other values on the
  card. A machine-wide write needs administrator approval, so there Undo points at
  the card's Reset instead. Lines written by an older version have no recorded old
  value and show no Undo.

## Active tweaks on top

Any tweak that is currently on and differs from the baseline is pinned to an
"Active tweaks" section at the top, also reachable from the navigation pane, with a
running count in the header.

## Pinned cards

Every tweak card carries a pin button in its header. A pinned card also appears in a
**Pinned** section at the top of the list, above Active tweaks, and stays there
across restarts - the ids are kept in `settings.json` as `pinned`. The button turns
accent-coloured while the card is pinned; click it again to unpin. The Pinned
section only appears in the full list, and it hides while a search is running.

## Create your own actions

The **+ New** button opens a box where you describe the action you want in plain
English, for example "stop Windows searching the web from the Start menu". The
description goes to the model API configured in **Settings** and comes back as a
complete card - title, description, risk and the exact registry values - which is
shown for review before anything is added.

Nothing is applied when a card is added: it is a normal card with a normal switch,
so ADMIN entries still go through the usual approval prompt. Drafted cards carry an
**AI** badge and a Remove button; removing one only deletes the card, never a
registry value. They are stored in `%LOCALAPPDATA%\PowerKit\custom.json`, get a
Reset baseline like every other tweak, and appear in search, the Active list and the
activity log.

Every drafted entry is validated before it is shown:

- the id, group, title and description have to match the catalog's shape;
- only `HKCU` and `HKLM` under `Software`, `System` and `Control Panel` may be
  written, and keys such as `CurrentControlSet\Services`, `SAM`, `Winlogon`,
  `Run`/`RunOnce` and file associations are refused outright;
- value kinds are limited to DWord, QWord, String and ExpandString, with numbers
  range-checked and strings length-checked;
- a drafted command may only press one of the existing handlers, so it can never
  introduce new code.

### Settings

**Settings** stores the API key, endpoint and model. The key is encrypted with
Windows DPAPI for your account and kept in `%LOCALAPPDATA%\PowerKit\ai-key.dat`, so
it is never written to `settings.json` in readable form. Pressing **+ New** without
a key offers to open Settings first, unless the endpoint is on this PC.

The key field carries a **Get a z.ai API key** link that opens Z.ai's API key page
in your browser. Creating the key costs nothing, but it is not a free plan - see the
cost table below.

**Test** sends one short prompt with whatever is in the dialog - key, endpoint and
model - before you save. It reports the model that answered and how many
milliseconds it took, or the endpoint's own error text, which is usually enough to
tell a wrong key from a wrong model id. A test stores nothing.

If the model breaks one of the builder's rules - an invented group, a forbidden
registry path, a missing value - PowerKit sends the rejection back and asks once more
before it shows the error. That repair pass is what makes a small local model usable:
`qwen2.5-coder:7b` drafted a valid card first time, `llama3.1:8b` got there on the
second try.

Any OpenAI-compatible `/chat/completions` endpoint works. Three ways to keep the
cost at zero:

| Endpoint | Model | Key |
| --- | --- | --- |
| `https://api.z.ai/api/paas/v4` (default) | `glm-4.7-flash` or `glm-4.5-flash` - the only Z.ai ids priced at $0 per token | a Z.ai key, free to create |
| `http://localhost:11434/v1` (Ollama) | whatever you have pulled, for example `qwen3:8b` | none; a local server ignores it |
| `https://generativelanguage.googleapis.com/v1beta/openai` (Gemini) or `https://api.groq.com/openai/v1` (Groq) | a free-tier model | that provider's key |

An Ollama box on your own network is used the same way: put `http://<address>:11434/v1`
in Endpoint and the pulled tag in Model, with the key box left empty. PowerKit treats
loopback, private addresses and single-label hostnames as keyless, so it never asks for
a key there; a public domain still needs one. The machine here points at
`http://192.168.50.243:11434/v1` with `qwen2.5-coder:7b`, which drafts a card in a
couple of seconds once the model is loaded. A box that only answers on its own
loopback needs Ollama listening on the network (`OLLAMA_HOST=0.0.0.0`).

Paying nothing means staying on one of those ids. On Z.ai's price list only
`glm-4.7-flash`, `glm-4.5-flash` and the vision model `glm-4.6v-flash` are free in
all four columns; every other model, including `glm-5.3-flash` (around $0.15 in /
$0.50 out per million tokens), bills per token. On the paid rows the only free column
is *Cached Input Storage*, marked limited-time free - that is storage of prompts you
reuse, not free usage, and it will read as a charge if you mistake it for the price.
Z.ai does not publish the rate limit that applies to its free models, and it has
moved models in and out of the free list before, so check
<https://docs.z.ai/guides/overview/pricing> before you rely on it.

## Backup and sharing

**Export setup** at the bottom of the navigation pane writes one JSON file holding
your settings (theme, endpoint, model and pins), the Reset baseline and every
AI-drafted card. **Import setup** reads one back: the settings, baseline and drafted
cards in the file replace what is on this PC, which moves a setup to another machine
or restores a copy taken before experimenting.

The API key is never exported - DPAPI ties it to your account on this PC - and an
import never touches a saved key. Drafted cards already present are skipped, so
importing the same file twice adds nothing.

## Run box and terminals

The play button in the header opens a run box that works like Win+R: type a program,
file, folder or web address and it launches exactly as written, then shows up in the
activity log.

Recent entries are listed in a dropdown straight under the box, newest first. Click
one to put it back in the box, type to narrow the list, or press Up/Down to step
through the history from the keyboard. PowerKit keeps its own last 12 entries in
`%LOCALAPPDATA%\PowerKit\run-history.json` and also shows whatever Windows still
has in its own Run history (`RunMRU`), so the list is useful on first launch too.

Quick Tools also carries Command Prompt, PowerShell and Windows Terminal cards.

## Layout

PowerKit draws its own title bar - the header doubles as the caption, so dragging it
moves the window and double-clicking maximises or restores it. Minimise, maximise
and close sit at the right, and the window still resizes from every edge.

The window is fully resizable. Cards live in a responsive grid: columns are
recalculated from the available width (1 to 6 columns), so a wide window shows more
cards per row and a narrow one stacks them. Below 960 px the navigation pane
collapses automatically; the hamburger button brings it back.

Search filters both tweaks and commands (Ctrl+F focuses, Esc clears, F5 reloads
everything from the registry).

## Files

- `PowerKit.ps1` - entry point, STA relaunch, fatal error reporting
- `src/Catalog.ps1` - every tweak and command definition
- `src/RegistryTools.ps1` - registry read/write, baseline capture, state, reset
- `src/Commands.ps1` - the actual power/tool actions
- `src/ElevatedHelper.ps1` - the elevated process that applies machine-wide settings
- `src/Elevation.ps1` - starts the helper, waits for UAC, and sends requests to it
- `src/Theme.ps1` - Windows 11 palette, system accent colour, dark title bar
- `src/Styles.xaml` - Fluent styles: cards, switches, buttons, nav, scrollbars
- `src/Ui.ps1` - window shell, sections, cards, responsive grid
- `src/Interactions.ps1` - toggles, dialogs, toasts, filtering, startup
- `src/AiBuilder.ps1` - API key storage, the AI card builder, Settings and the new-action dialog
- `src/LogViewer.ps1` - the in-app activity log, its filters and the per-write Undo
- `%LOCALAPPDATA%\PowerKit\app.log` - every registry write and command, for auditing

## Safety

- Nothing runs on a timer; changes happen only when you click.
- Destructive commands (restart, shut down, sign out, disable hibernation, clear temp)
  ask for confirmation first.
- Machine-wide writes are blocked unless the app is elevated, so a standard-user
  session cannot silently change HKLM. The elevated helper is started only by your
  click on an ADMIN item, asks for UAC approval, and validates every request.
- The log records each registry write (from the window and from the helper) so you
  can always see what was changed and when.
