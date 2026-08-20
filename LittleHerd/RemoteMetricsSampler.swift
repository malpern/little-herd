import Foundation

nonisolated enum RemotePlatform: Sendable {
    case macOS
    case linux
}

nonisolated enum RemoteMonitorError: LocalizedError, Sendable {
    case commandFailed(String)
    case invalidHost(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            "SSH collection failed: \(message)"
        case let .invalidHost(host):
            "“\(host)” is not a usable SSH host name."
        case .invalidOutput:
            "The remote machine returned incomplete metrics."
        }
    }
}

nonisolated enum RemoteOutputParser {
    private struct ParsedStorageVolume {
        let name: String
        let mountPath: String
        let totalBytes: Double
        let availableBytes: Double
        let storageGroup: String?
    }

    static func parse(_ output: String) -> [String: [Double]] {
        var values: [String: [Double]] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let numbers = parts[1]
                .split(whereSeparator: \.isWhitespace)
                .compactMap { Double($0) }

            if !numbers.isEmpty {
                values[String(parts[0])] = numbers
            }
        }

        return values
    }

    static func parseActivities(
        _ output: String,
        agentTasks: [AgentTaskProvider: AgentTaskSummary]? = nil
    ) -> [MachineActivity] {
        var workingDirectories: [Int: String] = [:]
        var childProcessNames: [Int: String] = [:]
        for line in output.split(whereSeparator: \.isNewline)
        {
            let prefix: String
            if line.hasPrefix("context=") {
                prefix = "context="
            } else if line.hasPrefix("child=") {
                prefix = "child="
            } else {
                continue
            }

            let fields = line.dropFirst(prefix.count)
                .split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, let processID = Int(fields[0]) else { continue }
            if prefix == "context=" {
                workingDirectories[processID] = String(fields[1])
            } else {
                childProcessNames[processID] = String(fields[1])
            }
        }

        let processOutput = output
            .split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("activity=") }
            .map { String($0.dropFirst("activity=".count)) }
            .joined(separator: "\n")

        let resolvedAgentTasks = agentTasks ?? AgentTaskOutputParser.parse(output)

        let candidateActivities = MachineActivityParser.highlights(
            from: processOutput,
            limit: 20,
            minimumCPUPercent: 0
        )
            .map { activity in
                guard let processID = activity.processID,
                      let workingDirectory = workingDirectories[processID]
                else {
                    return activity
                }
                return activity.addingContext(
                    MachineActivityContext.projectName(
                        fromWorkingDirectory: workingDirectory
                    )
                )
            }
            .map { activity in
                guard let processID = activity.processID else { return activity }
                return activity.addingChildProcessName(childProcessNames[processID])
            }

        return MachineActivityPrioritizer.select(
            from: candidateActivities,
            agentTasks: resolvedAgentTasks,
            limit: MachineActivityParser.detailHighlights
        )
    }

    /// Mount points the machine says are disk images rather than hardware.
    ///
    /// A disk image's bytes already live inside a file on some other volume, so
    /// listing it as storage in its own right counts them twice. When the image
    /// sits on a network share — a Time Machine sparsebundle kept on a NAS —
    /// they are not this machine's bytes at all, and the NAS is the thing to
    /// ask. Its apparent size is a ceiling too: one such backup reported 16 TB
    /// against 2.3 TB written, which read as a machine 95% full when it had
    /// 817 GB free.
    ///
    /// The shell reports which mounts these are; what to do about them is
    /// decided here, where it can be tested.
    static func parseImageVolumeMounts(_ output: String) -> Set<String> {
        Set(
            output
                .split(whereSeparator: \.isNewline)
                .filter { $0.hasPrefix("imagevolume=") }
                .compactMap {
                    decodeBase64($0.dropFirst("imagevolume=".count))
                }
        )
    }

    static func parseStorageVolumes(_ output: String) -> [StorageVolume] {
        let imageMounts = parseImageVolumeMounts(output)
        let parsed: [ParsedStorageVolume] = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard line.hasPrefix("storage=") else { return nil }
                let fields = line.dropFirst("storage=".count).split(
                    separator: "\t",
                    omittingEmptySubsequences: false
                )
                guard fields.count == 4 || fields.count == 5,
                      let name = decodeBase64(fields[0]),
                      let mountPath = decodeBase64(fields[1]),
                      let totalBytes = Double(fields[2]),
                      let availableBytes = Double(fields[3]),
                      totalBytes > 0,
                      !imageMounts.contains(mountPath)
                else {
                    return nil
                }

                let storageGroup = fields.count == 5
                    ? decodeBase64(fields[4])
                    : nil

                return ParsedStorageVolume(
                    name: name,
                    mountPath: mountPath,
                    totalBytes: totalBytes,
                    availableBytes: min(max(availableBytes, 0), totalBytes),
                    storageGroup: storageGroup
                )
            }

        var groupOrder: [String] = []
        var grouped: [String: [ParsedStorageVolume]] = [:]

        for volume in parsed {
            let key = volume.storageGroup.map { "device:\($0)" }
                ?? "mount:\(volume.mountPath)"
            if grouped[key] == nil {
                groupOrder.append(key)
            }
            grouped[key, default: []].append(volume)
        }

        return groupOrder.compactMap { key in
            guard let volumes = grouped[key], let first = volumes.first else {
                return nil
            }

            let name = volumes.count == 1
                ? first.name
                : "\(first.name) +\(volumes.count - 1)"
            let mountPath = volumes
                .map(\.mountPath)
                .joined(separator: ", ")

            return StorageVolume(
                id: key,
                name: name,
                mountPath: mountPath,
                availableBytes: first.availableBytes,
                totalBytes: first.totalBytes,
                volumeCount: volumes.count
            )
        }
    }

    static func parseMemoryConsumers(_ output: String) -> [MemoryConsumer] {
        let samples = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> ProcessMemorySample? in
                guard line.hasPrefix("memory_process=") else { return nil }
                let fields = line.dropFirst("memory_process=".count).split(
                    separator: "\t",
                    omittingEmptySubsequences: false
                )
                guard fields.count == 2,
                      let command = decodeBase64(fields[0]),
                      let residentBytes = Double(fields[1])
                else {
                    return nil
                }

                return ProcessMemorySample(
                    command: command,
                    residentBytes: residentBytes
                )
            }

        return MemoryConsumerAggregator.consumers(from: samples)
    }

    private static func decodeBase64(_ value: Substring) -> String? {
        guard let data = Data(base64Encoded: String(value)),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty
        else {
            return nil
        }
        return decoded
    }
}

actor RemoteMetricsSampler {
    private struct CPUCounters: Sendable {
        let active: Double
        let total: Double
    }

    private struct NetworkCounters: Sendable {
        let received: Double
        let sent: Double
    }

    private let host: String
    private let platform: RemotePlatform
    private let identityFile: String?
    private var previousCPU: CPUCounters?
    private var previousNetwork: NetworkCounters?
    private var previousNetworkTimestamp: ContinuousClock.Instant?
    private var cachedAgentTasks: [AgentTaskProvider: AgentTaskSummary] = [:]
    private var cachedAgentSessions: [AgentSession] = []
    private var previousAgentTaskTimestamp: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    init(host: String, platform: RemotePlatform, identityFile: String? = nil) {
        self.host = host
        self.platform = platform
        self.identityFile = identityFile
    }

    /// The cadence every machine is meant to report on.
    static let samplingInterval = Duration.seconds(10)

    /// How long the first sample watches for, so a machine paints a figure
    /// shortly after launch rather than ten seconds later.
    private static let openingCPUWindow = Duration.seconds(1)

    private var hasSampled = false

    /// A remote Mac has no CPU counter a shell can read — `kern.cp_time` is
    /// FreeBSD, and both `top -l 1` and `iostat -c 1` report since-boot averages
    /// far too coarse to difference. Its utilisation therefore comes from
    /// `iostat` watching for a fixed window, which is a measurement rather than
    /// a difference, and only covers the time it is actually running.
    ///
    /// So the window is the whole interval. Watching for ten seconds out of
    /// every ten makes a remote Mac's figure mean what every other machine's
    /// already means — a continuous ten-second average — instead of one second
    /// glimpsed in every eleven, which quietly missed anything bursty and made
    /// the overview compare machines that had been measured differently.
    private var cpuWindow: Duration {
        hasSampled ? Self.samplingInterval : Self.openingCPUWindow
    }


    func sample() async throws -> SystemSnapshot {
        let now = clock.now
        let shouldRefreshAgentTasks: Bool
        if let previousAgentTaskTimestamp {
            shouldRefreshAgentTasks = previousAgentTaskTimestamp.duration(to: now)
                >= AgentTaskProbe.refreshInterval
        } else {
            shouldRefreshAgentTasks = true
        }

        let metricsCommand = platform == .macOS
            ? Self.macOSCommand(cpuWindowSeconds: Int(cpuWindow.components.seconds))
            : Self.linuxCommand
        let command = shouldRefreshAgentTasks
            ? metricsCommand + "\n" + AgentTaskProbe.shellCommand
            : metricsCommand
        let output = try await SSHCommandRunner.run(
            host: host,
            command: command,
            identityFile: identityFile
        )
        // Only once one has succeeded: a machine that cannot be reached keeps the
        // short opening window, so the first figure it manages to report still
        // arrives promptly rather than a full interval later.
        hasSampled = true
        let raw = RemoteOutputParser.parse(output)
        let timestamp = Date()

        if shouldRefreshAgentTasks {
            cachedAgentTasks = AgentTaskOutputParser.parse(output)
            cachedAgentSessions = AgentResourceJoin.attach(
                processes: AgentProcessOutputParser.parse(output),
                to: AgentSessionOutputParser.parse(output)
            )
            previousAgentTaskTimestamp = now
        }

        guard let memory = raw["mem"], memory.count == 2,
              let disk = raw["disk"], disk.count == 2,
              let network = raw["network"], network.count == 2
        else {
            throw RemoteMonitorError.invalidOutput
        }

        let memoryTotal = memory[0]
        let memoryAvailable = min(memory[1], memoryTotal)
        let memoryUsed = max(memoryTotal - memoryAvailable, 0)
        let memoryPressure = raw["memory_pressure"]?.first
            .flatMap { MemoryPressureLevel(systemValue: Int($0)) }
            ?? MemoryPressureLevel.estimated(
                availableBytes: memoryAvailable,
                totalBytes: memoryTotal
            )
        let diskTotal = disk[0]
        let diskAvailable = min(disk[1], diskTotal)
        let diskUsed = max(diskTotal - diskAvailable, 0)
        var storageVolumes = RemoteOutputParser.parseStorageVolumes(output)
        if storageVolumes.isEmpty {
            storageVolumes = [
                StorageVolume(
                    id: "/",
                    name: platform == .macOS ? "Macintosh HD" : "Root",
                    mountPath: "/",
                    availableBytes: diskAvailable,
                    totalBytes: diskTotal
                ),
            ]
        }

        var readings: [MetricKind: MetricReading] = [
            .memory: MetricReading(
                value: memoryPressure?.visualizationPercent,
                auxiliaryValue: memoryUsed,
                capacity: memoryTotal
            ),
            .disk: MetricReading(
                value: percentage(used: diskUsed, total: diskTotal),
                auxiliaryValue: diskAvailable,
                capacity: diskTotal
            ),
        ]

        if let cpu = cpuUtilization(from: raw) {
            readings[.cpu] = MetricReading(value: cpu)
        }

        if let throughput = networkThroughput(
            current: NetworkCounters(received: network[0], sent: network[1])
        ) {
            readings[.network] = MetricReading(
                value: throughput.received + throughput.sent,
                auxiliaryValue: throughput.received,
                capacity: throughput.sent
            )
        }

        return SystemSnapshot(
            timestamp: timestamp,
            readings: readings,
            activities: RemoteOutputParser.parseActivities(
                output,
                agentTasks: cachedAgentTasks
            ),
            agentSessions: cachedAgentSessions,
            storageVolumes: storageVolumes,
            memoryPressure: memoryPressure,
            memoryConsumers: RemoteOutputParser.parseMemoryConsumers(output),
            coreCount: raw["cores"]?.first.map { Int($0) }
        )
    }

    private func cpuUtilization(from raw: [String: [Double]]) -> Double? {
        if platform == .macOS {
            guard let value = raw["cpu_percent"]?.first else { return nil }
            return min(max(value, 0), 100)
        }

        guard let fields = raw["cpu"], fields.count >= 8 else { return nil }
        let idle = fields[3] + fields[4]
        let total = fields.reduce(0, +)
        let current = CPUCounters(active: total - idle, total: total)
        defer { previousCPU = current }

        guard let previousCPU,
              current.active >= previousCPU.active,
              current.total > previousCPU.total
        else {
            return nil
        }

        return min(
            max((current.active - previousCPU.active) / (current.total - previousCPU.total) * 100, 0),
            100
        )
    }

    private func networkThroughput(
        current: NetworkCounters
    ) -> (received: Double, sent: Double)? {
        let now = clock.now
        defer {
            previousNetwork = current
            previousNetworkTimestamp = now
        }

        guard let previousNetwork, let previousNetworkTimestamp else { return nil }
        let elapsed = previousNetworkTimestamp.duration(to: now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        guard seconds > 0 else { return nil }

        return (
            received: max(current.received - previousNetwork.received, 0) / seconds,
            sent: max(current.sent - previousNetwork.sent, 0) / seconds
        )
    }

    private func percentage(used: Double, total: Double) -> Double? {
        guard total > 0 else { return nil }
        return min(max(used / total * 100, 0), 100)
    }

    /// - Parameter cpuWindowSeconds: how long `iostat` watches before reporting.
    ///   This is the whole of the sampling interval in steady state, so the
    ///   figure covers the time between samples rather than a slice of it.
    static func macOSCommand(cpuWindowSeconds: Int) -> String {
        macOSCommandTemplate.replacingOccurrences(
            of: "@CPU_WINDOW@",
            with: String(max(cpuWindowSeconds, 1))
        )
    }

    private static let macOSCommandTemplate = #"""
    export LC_ALL=C
    cpu=$(/usr/sbin/iostat -c 2 -w @CPU_WINDOW@ | /usr/bin/awk 'NR>2 {idle=$(NF-3)} END {printf "%.2f", 100-idle}')
    echo "cores=$(/usr/sbin/sysctl -n hw.ncpu)"
    total=$(/usr/sbin/sysctl -n hw.memsize)
    pressure=$(/usr/sbin/sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)
    page=$(/usr/bin/pagesize)
    available=$(/usr/bin/vm_stat | /usr/bin/awk -v p="$page" '/Pages free/ {gsub(/\./,"",$3); f=$3} /Pages speculative/ {gsub(/\./,"",$3); s=$3} END {printf "%.0f", (f+s)*p}')
    iface=$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/ {print $2; exit}')
    network=$(/usr/sbin/netstat -ibn -I "$iface" | /usr/bin/awk '$3 ~ /^<Link/ {print $7, $10; exit}')
    disk=$(/bin/df -Pk /System/Volumes/Data | /usr/bin/awk 'NR==2 {printf "%.0f %.0f", $2*1024, $4*1024}')
    echo "cpu_percent=$cpu"
    echo "mem=$total $available"
    echo "memory_pressure=$pressure"
    echo "network=$network"
    echo "disk=$disk"
    # Mounted disk images — installer .dmgs left attached, Simulator runtimes,
    # cryptex mounts — are read-only and report meaningless capacity ("10 MB
    # free of 12 MB" on something that can never fill). They are dropped here.
    # The startup volume is itself read-only on a sealed system, so "/" is
    # always kept regardless.
    readonly_volumes=$(/sbin/mount | /usr/bin/awk '/read-only/ {position=index($0, " on "); rest=substr($0, position + 4); paren=index(rest, " ("); if (paren > 1) print substr(rest, 1, paren - 1)}' | /usr/bin/grep '^/Volumes/' | /usr/bin/tr '\n' '|')
    # A disk image's bytes already live inside a file on some other volume, so
    # counting it again as storage of its own double-counts them. When the image
    # sits on a network share — a Time Machine sparsebundle on a NAS — they are
    # not this machine's bytes at all, and the NAS is the thing to ask.
    /usr/bin/hdiutil info 2>/dev/null | /usr/bin/awk -F'\t' '/^\/dev\/disk/ && $3 != "" {print $3}' | while read -r image_mount; do
      printf "imagevolume=%s\n" "$(printf "%s" "$image_mount" | /usr/bin/base64 | /usr/bin/tr -d '\n')"
    done
    /bin/df -Pk -l | /usr/bin/awk -v readonly="$readonly_volumes" 'NR > 1 {mount=$6; for (i=7; i<=NF; i++) mount=mount " " $i; if ($1 ~ "^/dev/" && (mount == "/" || mount ~ "^/Volumes/") && mount != "/Volumes/Recovery" && index(readonly, mount "|") == 0) {group=$1; sub(/^\/dev\//,"",group); sub(/s[0-9]+.*$/,"",group); printf "%s\t%.0f\t%.0f\t%s\n", group, $2*1024, $4*1024, mount}}' | while IFS="$(printf '\t')" read -r storage_group storage_total storage_available storage_mount; do
      storage_name=${storage_mount##*/}
      if [ "$storage_mount" = "/" ]; then storage_name="Macintosh HD"; fi
      storage_name64=$(printf "%s" "$storage_name" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      storage_mount64=$(printf "%s" "$storage_mount" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      storage_group64=$(printf "%s" "$storage_group" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      printf "storage=%s\t%s\t%s\t%s\t%s\n" "$storage_name64" "$storage_mount64" "$storage_total" "$storage_available" "$storage_group64"
    done
    process_table=$(/bin/ps -Ao pcpu=,rss=,pid=,comm=)
    printf "%s\n" "$process_table" | /usr/bin/awk '{cpu=$1; pid=$3; $1=""; $2=""; $3=""; sub(/^[[:space:]]+/,"",$0); command=$0; base=command; sub(/^.*\//,"",base); if (cpu > 0 && base !~ /^(awk|head|ps|sort)$/) {totals[command]+=cpu; if (cpu > peaks[command]) {peaks[command]=cpu; pids[command]=pid}}} END {for (command in totals) printf "%.1f %s %s\n", totals[command], pids[command], command}' | /usr/bin/sort -k1,1nr | /usr/bin/head -n 12 | while read -r activity_cpu activity_pid activity_command; do
      echo "activity=$activity_cpu $activity_pid $activity_command"
      activity_base=${activity_command##*/}
      case "$activity_base" in
        clang*|swift-frontend|rustc|ninja|xcodebuild|swiftc|cargo|make)
          activity_cwd=$(/usr/sbin/lsof -a -p "$activity_pid" -d cwd -Fn 2>/dev/null | /usr/bin/awk '/^n/ {sub(/^n/,""); print; exit}')
          if [ -n "$activity_cwd" ]; then echo "context=$activity_pid $activity_cwd"; fi
          ;;
        zellij|Terminal|iTerm2)
          child_pid=$(/usr/bin/pgrep -P "$activity_pid" | /usr/bin/head -n 1)
          if [ -n "$child_pid" ]; then
            child_command=$(/bin/ps -p "$child_pid" -o comm= | /usr/bin/awk '{sub(/^[[:space:]]+/,""); print; exit}')
            child_base=${child_command##*/}
            if [ -n "$child_base" ]; then echo "child=$activity_pid $child_base"; fi
          fi
          ;;
      esac
    done
    printf "%s\n" "$process_table" | /usr/bin/awk '{rss=$2; $1=""; $2=""; $3=""; sub(/^[[:space:]]+/,"",$0); if (rss > 0 && $0 != "") printf "%.0f\t%s\n", rss*1024, $0}' | /usr/bin/sort -k1,1nr | /usr/bin/head -n 40 | while IFS="$(printf '\t')" read -r memory_bytes memory_command; do
      memory_command64=$(printf "%s" "$memory_command" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      printf "memory_process=%s\t%s\n" "$memory_command64" "$memory_bytes"
    done
    """#

    private static let linuxCommand = #"""
    export LC_ALL=C
    echo "cores=$(/usr/bin/nproc)"
    cpu=$(/usr/bin/awk '/^cpu / {for(i=2;i<=NF;i++) printf "%s%s", $i, i==NF?"":" "; exit}' /proc/stat)
    mem=$(/usr/bin/awk '/^MemTotal:/ {t=$2*1024} /^MemAvailable:/ {a=$2*1024} END {printf "%.0f %.0f", t, a}' /proc/meminfo)
    iface=$(/usr/bin/awk '$2 == "00000000" {print $1; exit}' /proc/net/route)
    rx=$(/usr/bin/cat /sys/class/net/"$iface"/statistics/rx_bytes)
    tx=$(/usr/bin/cat /sys/class/net/"$iface"/statistics/tx_bytes)
    disk=$(/usr/bin/df -Pk / | /usr/bin/awk 'NR==2 {printf "%.0f %.0f", $2*1024, $4*1024}')
    echo "cpu=$cpu"
    echo "mem=$mem"
    echo "network=$rx $tx"
    echo "disk=$disk"
    root_device=$(/usr/bin/df -Pk / | /usr/bin/awk 'NR==2 {print $1}')
    /usr/bin/df -Pk -l | /usr/bin/awk -v root_device="$root_device" 'NR > 1 {device=$1; mount=$6; for (i=7; i<=NF; i++) mount=mount " " $i; is_root=(device == root_device && mount == "/"); is_other_device=(device ~ "^/dev/" && device !~ "^/dev/loop" && device != root_device && mount !~ "^/boot($|/)"); if (is_root || is_other_device) printf "%s\t%.0f\t%.0f\t%s\n", device, $2*1024, $4*1024, mount}' | while IFS="$(printf '\t')" read -r storage_device storage_total storage_available storage_mount; do
      storage_name=${storage_mount##*/}
      if [ "$storage_mount" = "/" ]; then storage_name="Root"; fi
      storage_name64=$(printf "%s" "$storage_name" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      storage_mount64=$(printf "%s" "$storage_mount" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      storage_group64=$(printf "%s" "$storage_device" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      printf "storage=%s\t%s\t%s\t%s\t%s\n" "$storage_name64" "$storage_mount64" "$storage_total" "$storage_available" "$storage_group64"
    done
    process_table=$(/bin/ps -Ao pcpu=,rss=,pid=,comm=)
    printf "%s\n" "$process_table" | /usr/bin/awk '{cpu=$1; pid=$3; $1=""; $2=""; $3=""; sub(/^[[:space:]]+/,"",$0); command=$0; base=command; sub(/^.*\//,"",base); if (cpu > 0 && base !~ /^(awk|head|ps|sort)$/) {totals[command]+=cpu; if (cpu > peaks[command]) {peaks[command]=cpu; pids[command]=pid}}} END {for (command in totals) printf "%.1f %s %s\n", totals[command], pids[command], command}' | /usr/bin/sort -k1,1nr | /usr/bin/head -n 12 | while read -r activity_cpu activity_pid activity_command; do
      echo "activity=$activity_cpu $activity_pid $activity_command"
      activity_base=${activity_command##*/}
      case "$activity_base" in
        clang*|swift-frontend|rustc|ninja|xcodebuild|swiftc|cargo|make)
          activity_cwd=$(readlink "/proc/$activity_pid/cwd" 2>/dev/null)
          if [ -n "$activity_cwd" ]; then echo "context=$activity_pid $activity_cwd"; fi
          ;;
        zellij|Terminal|iTerm2)
          child_pid=$(/usr/bin/pgrep -P "$activity_pid" | /usr/bin/head -n 1)
          if [ -n "$child_pid" ]; then
            child_command=$(/bin/ps -p "$child_pid" -o comm= | /usr/bin/awk '{sub(/^[[:space:]]+/,""); print; exit}')
            child_base=${child_command##*/}
            if [ -n "$child_base" ]; then echo "child=$activity_pid $child_base"; fi
          fi
          ;;
      esac
    done
    printf "%s\n" "$process_table" | /usr/bin/awk '{rss=$2; $1=""; $2=""; $3=""; sub(/^[[:space:]]+/,"",$0); if (rss > 0 && $0 != "") printf "%.0f\t%s\n", rss*1024, $0}' | /usr/bin/sort -k1,1nr | /usr/bin/head -n 40 | while IFS="$(printf '\t')" read -r memory_bytes memory_command; do
      memory_command64=$(printf "%s" "$memory_command" | /usr/bin/base64 | /usr/bin/tr -d '\n')
      printf "memory_process=%s\t%s\n" "$memory_command64" "$memory_bytes"
    done
    """#
}

/// Carries the result of a pipe read performed on a background queue back to
/// the thread waiting on the process.
nonisolated private final class CollectedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

nonisolated enum SSHCommandRunner {
    /// One definition of how this app talks to a machine over SSH, shared by
    /// the runner that waits for a whole answer and the one that streams it.
    /// Two copies of these flags would be two things to keep in step.
    static func arguments(
        host: String,
        command: String,
        identityFile: String?
    ) -> [String] {
        var arguments = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=4",
            "-o", "ConnectionAttempts=1",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=1",
            "-o", "ForwardAgent=no",
            "-o", "ClearAllForwardings=yes",
        ]
        if let identityFile {
            arguments += ["-o", "IdentitiesOnly=yes", "-i", identityFile]
        }
        // "--" ends option parsing so the host can never be read as a flag.
        return arguments + ["--", host, command]
    }

    static func run(
        host: String,
        command: String,
        identityFile: String? = nil
    ) async throws -> String {
        guard SSHHostName.isValid(host) else {
            throw RemoteMonitorError.invalidHost(host)
        }

        return try await Task.detached(priority: .utility) {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = Self.arguments(
                host: host,
                command: command,
                identityFile: identityFile
            )
            process.standardOutput = standardOutput
            process.standardError = standardError

            try process.run()

            // Both pipes must be drained before waiting. A child that fills the
            // 64 KiB pipe buffer blocks on write, so waiting first would leave
            // parent and child deadlocked on each other. Standard error is read
            // concurrently for the same reason.
            let errorHandle = standardError.fileHandleForReading
            let errorOutput = CollectedOutput()
            let errorQueue = DispatchQueue(
                label: "com.malpern.LittleHerd.ssh-stderr"
            )
            errorQueue.async {
                errorOutput.store(errorHandle.readDataToEndOfFile())
            }

            let outputData = standardOutput.fileHandleForReading
                .readDataToEndOfFile()
            process.waitUntilExit()
            errorQueue.sync {}

            guard process.terminationStatus == 0 else {
                let message = String(decoding: errorOutput.data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw RemoteMonitorError.commandFailed(message)
            }

            return String(decoding: outputData, as: UTF8.self)
        }.value
    }
}
