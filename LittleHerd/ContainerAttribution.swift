import Foundation

/// Names the container a Linux process is running inside.
///
/// A Docker host's process list is honest but useless on its own: eight rows
/// reading `node`, `python`, `postgres` say what is burning the CPU and give no
/// hint which service it belongs to. The kernel already knows — a containerised
/// process sits in a cgroup whose leaf is the container's ID — so the answer
/// costs one extra read of `/proc/PID/cgroup` per row that is already being
/// reported, and no new connection, daemon, or privilege.
///
/// What the cgroup cannot supply is the *name*. Docker puts only the 64-hex ID
/// in the cgroup path, and the ID-to-name mapping lives behind the runtime's
/// socket. So the probe asks `docker ps` (and `podman ps`) when either is on the
/// PATH, and falls back to the twelve-character short ID — the same form
/// `docker ps` prints — when it is not, or when the SSH account cannot reach the
/// socket. Little Herd never requires that access; it only spends it when the
/// account already has it.
///
/// macOS is deliberately not covered. Docker Desktop and OrbStack run every
/// container inside one virtual machine, so a Mac's `ps` shows a single large
/// helper process and no amount of `/proc` reading — which macOS does not have
/// anyway — would attribute anything.
nonisolated enum ContainerAttributionProbe {
    /// Where the probe looks for `PID/cgroup`. Tests point this at a fixture.
    static let defaultProcDirectory = "/proc"

    /// Longest a runtime is given to answer before its names are given up on.
    ///
    /// `docker ps` against a dead local socket fails immediately, but a
    /// `DOCKER_HOST` aimed at an unresponsive TCP endpoint blocks, and this runs
    /// inside the ten-second sampling command. `timeout` is used when the
    /// machine has it and skipped when it does not, because a missing name is a
    /// far smaller problem than a sample that never returns.
    static let runtimeTimeoutSeconds = 2

    /// A shell function that reads process IDs on standard input, one per line,
    /// and writes `container=PID NAME` for each one found to be inside a
    /// container. Processes running on the host produce no line at all.
    static func shellFunction(
        procDirectory: String = defaultProcDirectory
    ) -> String {
        shellFunctionTemplate
            .replacingOccurrences(of: "@PROC_DIRECTORY@", with: procDirectory)
            .replacingOccurrences(
                of: "@RUNTIME_TIMEOUT@",
                with: String(runtimeTimeoutSeconds)
            )
    }

    /// The leaf of a cgroup path, with each runtime's decoration removed.
    ///
    /// Kept in Swift as well as in the shell so the shapes this has to survive
    /// are written down somewhere a reader will find them:
    ///
    /// - cgroup v2, systemd: `0::/system.slice/docker-<id>.scope`
    /// - cgroup v2, plain:   `0::/docker/<id>`
    /// - cgroup v1:          `12:cpu,cpuacct:/docker/<id>`
    /// - Podman:             `0::/machine.slice/libpod-<id>.scope`
    /// - Kubernetes/CRI:     `…/cri-containerd-<id>.scope`, `…/crio-<id>.scope`
    ///
    /// A process on the host has a leaf like `init.scope`, `user.slice`, or a
    /// unit name, none of which is a run of at least twelve hex digits — which
    /// is the whole test, and the reason a host process yields nothing.
    static func containerID(fromCgroupFile contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            // Drop the "12:cpu,cpuacct:" (v1) or "0::" (v2) prefix.
            guard let pathStart = line.range(
                of: #"^[0-9]+:[^:]*:"#,
                options: .regularExpression
            ) else { continue }

            var leaf = String(line[pathStart.upperBound...])
                .split(separator: "/")
                .last
                .map(String.init) ?? ""

            if leaf.hasSuffix(".scope") { leaf.removeLast(".scope".count) }
            for prefix in ["docker-", "libpod-", "cri-containerd-", "crio-"]
            where leaf.hasPrefix(prefix) {
                leaf.removeFirst(prefix.count)
                break
            }

            guard leaf.count >= shortIDLength,
                  leaf.allSatisfy(hexDigits.contains)
            else { continue }

            return String(leaf.prefix(shortIDLength))
        }

        return nil
    }

    /// What `docker ps` shows, and therefore what a person can paste back into
    /// it when the friendly name is unavailable.
    static let shortIDLength = 12

    /// Lower case only: a cgroup ID is always lower case, and a systemd unit
    /// that happened to be named in upper-case hex is not a container.
    private static let hexDigits = Set("0123456789abcdef")

    /// `awk` here avoids interval expressions (`{12,}`): the `awk` macOS ships
    /// is BWK's, not GNU's, and this same text is exercised by the tests there.
    private static let shellFunctionTemplate = #"""
    little_herd_containers() {
      container_proc="@PROC_DIRECTORY@"
      container_pairs=$(while read -r container_pid; do
        [ -n "$container_pid" ] || continue
        container_id=$(/usr/bin/awk '{
          line = $0
          sub(/^[0-9]+:[^:]*:/, "", line)
          count = split(line, parts, "/")
          leaf = parts[count]
          sub(/\.scope$/, "", leaf)
          sub(/^docker-/, "", leaf)
          sub(/^libpod-/, "", leaf)
          sub(/^cri-containerd-/, "", leaf)
          sub(/^crio-/, "", leaf)
          if (length(leaf) >= 12 && leaf ~ /^[0-9a-f]+$/) {
            print substr(leaf, 1, 12)
            exit
          }
        }' "$container_proc/$container_pid/cgroup" 2>/dev/null)
        [ -n "$container_id" ] && printf "%s %s\n" "$container_pid" "$container_id"
      done)
      [ -n "$container_pairs" ] || return 0

      # Only now — nothing above needed a runtime, and a machine with no
      # containers in its busiest processes never pays for this at all.
      container_timeout=$(command -v timeout 2>/dev/null)
      container_names=""
      for container_runtime in docker podman; do
        container_runtime_path=$(command -v "$container_runtime" 2>/dev/null)
        [ -n "$container_runtime_path" ] || continue
        if [ -n "$container_timeout" ]; then
          container_listing=$("$container_timeout" @RUNTIME_TIMEOUT@ "$container_runtime_path" ps --no-trunc --format '{{.ID}} {{.Names}}' 2>/dev/null)
        else
          container_listing=$("$container_runtime_path" ps --no-trunc --format '{{.ID}} {{.Names}}' 2>/dev/null)
        fi
        [ -n "$container_listing" ] || continue
        container_names="$container_names
    $container_listing"
      done

      printf "%s\n" "$container_pairs" | while read -r container_pid container_id; do
        container_name=$(printf "%s\n" "$container_names" | /usr/bin/awk -v id="$container_id" 'index($1, id) == 1 { print $2; exit }')
        [ -n "$container_name" ] || container_name="$container_id"
        printf "container=%s %s\n" "$container_pid" "$container_name"
      done
    }
    """#
}
