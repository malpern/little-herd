# Little Herd

Little Herd is a compact, native macOS system monitor for a configurable group
of Macs, Linux computers, GPU workstations, and mounted network storage. A new
install begins with the current Mac and can discover or manually add several
machines at once.

![Little Herd CPU dashboard](Documentation/Screenshots/dashboard.png)

The project, target, module, bundle identifier, preferences, helper, and state
paths all use the Little Herd name. Builds that used the former internal name
automatically migrate their saved machine configuration on first launch.

## Herdware avatars

The interface gives each machine a compact isometric animal-and-computer
identity. The shipping suite covers laptop, mini desktop, compact workstation,
all-in-one, NUC, edge AI box, NAS, tower, multi-GPU workstation, rack server,
coordinator, and cloud/remote roles. Little Herd infers a sensible avatar during
discovery and lets the user review it before adding the machine.

## Adding machines

**File → Add Machines…** (`⌘N`) browses the local network for Bonjour SSH and
SMB services. Already-configured machines are hidden, new SSH computers are
selected by default, and several can be added with one action. A manual path
accepts any SSH hostname or alias when a machine does not advertise Bonjour.
Storage discovered before network-volume permission is saved as a deferred
machine so it can finish connecting after the permission flow.

Machine names, hostnames, platforms, connection types, avatars, optional SSH
identity-file paths, and SMB aliases are encoded in the app's
`machineConfigurationsV1` preference. The monitor and Add Machines window share
this one configuration store; there is no second hard-coded machine list.

- The current Mac is sampled with native macOS APIs.
- Remote Macs and Linux computers are sampled over SSH every ten seconds.
- Network storage appears only in Disk and reads capacity from mounted SMB
  shares. Finder and Keychain continue to own the SMB login.

Remote machines need only their built-in system tools and SSH access; no
companion agent, daemon, password, or elevated privilege is required.
Little Herd stores only the configured SSH host and optional identity-file
path; private keys remain in the user's SSH configuration. It uses SSH
connection sharing so it does not repeatedly perform a full handshake.

The **CPU** overview shrinks to a compact window and shows the three computers
together as vertical, segmented thermometers. Green, yellow, orange, and red
blocks communicate increasing CPU load; they do not represent hardware
temperature. Each machine icon and name sits below its thermometer with a green
status dot when live and a red dot when unreachable. CPU percentages above 99%
also turn red. The window contains no tabs or navigation controls. The macOS
**View** menu uses **⌘1–⌘4** for CPU, memory, disk, and AI across all machines.
Configured machines appear dynamically in the **View** menu.
The overview header menu also switches between those same four views
while leaving the Codex and Claude allowance visible. The selected icon sits in
the center; clicking either outer icon rotates it into place, animates the
header, and dissolves the main thermometers into the selected metric. Disk
overview uses the same vertical,
segmented thermometer language as CPU. Each storage container gets its own
thermometer, used percentage, and available capacity. Multiple APFS volumes
sharing one container are combined into one bar so shared free space is not
counted repeatedly. Attached drives are included, while virtual and hidden
system volumes are excluded. The normal
header shows the overview's connection status plus the remaining Codex and
Claude allowance reported by CodexBar.
Little Herd reads CodexBar's existing local summary caches once per minute; it
does not make additional usage-service requests or read authentication
credentials. Each allowance pairs the provider's app icon with a small circular
remaining-budget gauge; hovering reveals the provider names and **left** labels
without moving the surrounding header. The gauge turns orange at 25% remaining,
red at 10%, and adds a pulsing red halo at 1% or less. In that urgent state the
icon opens the provider's usage and billing page so credits or auto-top-up can
be managed. Hovering a machine
column temporarily replaces the machine portion of the header. CPU overview
shows up to three activities from only that machine and their approximate
CPU-core usage. Memory overview uses the operating system's normal, warning,
and critical pressure state—shown as check, warning, and critical symbols—instead
of treating intentionally occupied cache as a problem. Hovering a memory column
shows up to three of that machine's largest
user-app families and their approximate resident memory, making likely apps to
quit immediately visible. App names are the only bold text in these compact
details; memory amounts use the same small, secondary treatment as the overview
status line. Little Herd also keeps a tiny rolling history of those existing
samples. After at least 90 seconds and seven distinct readings, a red dot marks
an app whose memory has grown substantially and consistently. Hovering the dot
shows the measured growth, duration, and rising-sample count. This is labeled as
a possible leak because trend sampling cannot prove that allocations are
unreachable.
Disk overview shows mounted volumes, usage percentages, and free capacity.
Moving the pointer off the column restores the overview header. The allowance is
hidden while process details are visible so the activity header stays focused
and uncluttered. Codex and Claude activity rows show the project they are
working in. The hover header uses provider-colored sparkle icons for AI tasks
and labels operating-system work as **CPU**. Little Herd reads only the newest
session metadata every 30 seconds and does not retain raw transcripts. Active
agent tasks take priority over
background CPU rows; remaining slots show the heaviest processes. Remote titles
use the existing encrypted SSH connection. Compile and build activity includes
the project name when it can be inferred safely from that process's working
folder. Terminal multiplexers retain their app name and may identify a direct
child such as an SSH session.

The **AI** view shows all agents Little Herd currently identifies as active, plus
the six most recent waiting or finished agents across configured machines.
Codex rows use the ChatGPT app icon and Claude rows use the Claude Code app icon.
A green dot means active, a blue dot means finished, and an orange clock means
waiting for more work or output. Hovering a row replaces the stable header with
that agent's machine, project, state, and latest structured plan step. When the
agent has published a plan, a small circular indicator shows both its completed
fraction and the current step number (for example, **4/4**). Agents that do not
publish structured plan data remain visible without an invented percentage.
The probe runs at most every 30 seconds, reads only bounded tails of recent
session files, and never sends prompts, responses, command lines, or credentials
over the network.

## Task handoffs

While the CPU overview is visible, an active AI-task transfer temporarily
replaces it with the physical handoff treatment: the source recedes, the
destination lights up, and the task capsule follows a curved route between
machines. The one-time entrance animation settles immediately, so an extended
handoff does not keep redrawing effects in the background. **Reduce Motion** is
respected.

Little Herd polls `~/.local/state/little-herd/transfer.json` every two seconds.
The file contains only a task ID, short display title, provider, source,
destination, approximate CPU-core usage, timestamps, and status. It contains no
SSH credentials, API keys, prompts, responses, command lines, or transcripts.
The app reads this file; it does not dispatch or move tasks itself.

The included helper writes the record atomically with mode `0600`:

```sh
scripts/little-herd-transfer start codex "Chromium AX review" source-id destination-id 0.8
scripts/little-herd-transfer arrive
scripts/little-herd-transfer fail
scripts/little-herd-transfer clear
```

`start` displays the handoff for up to ten minutes. `arrive` and `fail` show the
completion state briefly before Little Herd returns to its stable CPU overview.
Agent wrappers can call these same commands when they actually dispatch and
confirm a task on another machine.

## Metrics

The current Mac shows CPU, GPU, memory, network, and disk usage using native
macOS system APIs. Remote Macs, Linux, and Synology show CPU, memory, network,
and disk usage; their GPU row intentionally says **Local only**.

Remote collection runs one short, read-only SSH command per machine per sample.
If a machine is asleep or unreachable, its last values remain visible and the
header changes to **Unavailable**. Monitoring reconnects automatically.
Activity collection uses process names, CPU percentages, direct parent/child
process relationships, and—for active build tools only—the process working
folder. It does not inspect command arguments, prompts, responses, environment
variables, or credentials. The same existing process-list sample is reused for
memory attribution, so the memory hover adds no additional periodic process
scan. Helper processes are grouped under their containing app before the three
largest app families are shown.

## Build

Requires macOS 15 or later, Xcode, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project LittleHerd.xcodeproj -scheme LittleHerd -configuration Debug build
xcodebuild -project LittleHerd.xcodeproj -scheme LittleHerd test
```
