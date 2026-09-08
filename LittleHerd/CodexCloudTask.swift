import Foundation

/// Work sitting in Codex Cloud, which is somewhere the herd cannot see.
///
/// **The two vendors get honestly different treatment, and that asymmetry is the
/// design rather than a gap in it.** A Codex cloud task can be *enumerated* — `codex
/// cloud list` answers headlessly, verified again on 7 September against 0.153.4, three
/// weeks and five minor versions after the claim was first measured. Claude cloud
/// cannot be listed from here at all, so it can only ever be an affordance: "pull a
/// session by id onto…". Showing them as one uniform column would be a lie about what
/// is knowable, and the interface says which is which.
///
/// Local→cloud stays out entirely. That is the vendors' own button, and duplicating it
/// would mean this app owning a protocol for moving work *up*, which is the thing item
/// 9 rules out.
nonisolated struct CodexCloudTask: Equatable, Sendable, Identifiable {
    var id: String
    var url: String
    var status: Status
    var title: String
    /// `owner/name`, as the task itself reports it. **This is the placement decision's
    /// input**: a task names its repository, so the eligibility probe can ask whether a
    /// destination has that checkout — the same question a session transfer already
    /// asks, reached from the other direction.
    var repository: String
    var when: String
    var diff: Diff

    nonisolated enum Status: String, Equatable, Sendable {
        case ready = "READY"
        case error = "ERROR"
        case running = "RUNNING"
        case pending = "PENDING"
        case applied = "APPLIED"
        /// Anything the vendor adds later. Kept rather than dropped, because a task
        /// with a status this does not know is still a task, and hiding it would be a
        /// worse answer than showing it plainly.
        case unknown

        init(raw: String) {
            self = Status(rawValue: raw.uppercased()) ?? .unknown
        }
    }

    /// What applying it would change. `none` is a real answer — most finished tasks
    /// report "no diff" — and is not the same as not knowing.
    nonisolated enum Diff: Equatable, Sendable {
        case none
        case changes(added: Int, removed: Int, files: Int)
        case unreadable(String)
    }
}

/// Reads `codex cloud list`.
///
/// **There is no `--json`, so this parses what a person would read.** Checked against
/// the real command rather than imagined: four lines per task, blank-separated, the URL
/// unindented and the rest indented under it.
///
///     https://chatgpt.com/codex/tasks/task_e_69c9…
///       [READY] Check readiness for new release version
///       malpern/KeyPath  •  Mar 29 08:55
///       no diff
///
/// Anchored on the URL line rather than on line counts, so a vendor adding a fifth line
/// costs a field rather than every record after it. A record missing its URL is not a
/// record.
nonisolated enum CodexCloudListParser {
    static func parse(_ output: String) -> [CodexCloudTask] {
        var tasks: [CodexCloudTask] = []
        var pending: [String] = []

        func flush() {
            defer { pending = [] }
            guard let urlLine = pending.first,
                  let id = urlLine.split(separator: "/").last.map(String.init),
                  !id.isEmpty
            else { return }
            let body = pending.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }

            var status = CodexCloudTask.Status.unknown
            var title = ""
            if let head = body.first, head.hasPrefix("["), let close = head.firstIndex(of: "]") {
                status = .init(raw: String(head[head.index(after: head.startIndex)..<close]))
                title = String(head[head.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            } else if let head = body.first {
                title = head
            }

            // "owner/name  •  Mar 29 08:55" — split on the bullet the vendor prints.
            var repository = ""
            var when = ""
            if body.count > 1 {
                let parts = body[1].components(separatedBy: "•").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                repository = parts.first ?? ""
                when = parts.count > 1 ? parts[1] : ""
            }

            tasks.append(
                CodexCloudTask(
                    id: id, url: urlLine, status: status, title: title,
                    repository: repository, when: when,
                    diff: body.count > 2 ? diff(from: body[2]) : .none
                )
            )
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("https://") {
                flush()
                pending = [line.trimmingCharacters(in: .whitespaces)]
            } else if !pending.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                pending.append(line)
            }
        }
        flush()
        return tasks
    }

    /// `no diff`, or `+94/-0 • 1 file`.
    static func diff(from text: String) -> CodexCloudTask.Diff {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "no diff" { return .none }
        guard trimmed.hasPrefix("+") else { return .unreadable(trimmed) }
        let head = trimmed.components(separatedBy: "•")[0]
        let numbers = head.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard numbers.count >= 2 else { return .unreadable(trimmed) }
        let files = trimmed.components(separatedBy: "•").count > 1
            ? (trimmed.components(separatedBy: "•")[1]
                .split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first ?? 0)
            : 0
        return .changes(added: numbers[0], removed: numbers[1], files: files)
    }
}

nonisolated extension CodexCloudTask {
    /// The checkout key this task's repository corresponds to.
    ///
    /// A task says `malpern/KeyPath`; the probe keys checkouts by the last component of
    /// the origin remote — `KeyPath` — because that is what identifies a repository
    /// across accounts and forks. Taking the same component of the task's name is the
    /// join between the two.
    var repositorySlug: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}

/// Which machines could take a cloud task, and why not where they could not.
///
/// **This is Little Herd's whole contribution to cloud work.** The vendors move it —
/// `codex cloud apply` on the machine that receives it — and this app answers the
/// question they do not: *which machine*. That is the eligibility probe again, reached
/// from the other direction: a session transfer asks whether the destination has the
/// repository the session is in, and this asks whether it has the one the task names.
nonisolated enum CodexCloudPlacement {
    nonisolated struct Candidate: Equatable, Sendable {
        let machine: String
        /// Which machine, for actually reaching it. The name is for reading; this is
        /// for running.
        let id: MachineID
        /// Where the checkout is, when there is one — the directory `codex cloud apply`
        /// would have to run in.
        let directory: String?
        var canTake: Bool { directory != nil }
    }

    /// Every machine, said plainly: the ones that have the checkout and the ones that
    /// do not. Both are reported, because "nowhere can take this" is an answer a person
    /// needs, and a list that silently omits the machines is one they cannot check.
    static func candidates(
        for task: CodexCloudTask,
        in herd: [DestinationAccount]
    ) -> [Candidate] {
        let wanted = task.repositorySlug.lowercased()
        return herd.map { account in
            // Case-insensitively: the slug comes from a URL on one machine and from the
            // task's own name on the vendor's side, and a repository that differs only
            // in case is not a distinction worth failing a placement over.
            let match = (account.report?.checkouts ?? [:])
                .first { $0.key.lowercased() == wanted }
            return Candidate(machine: account.name, id: account.machine, directory: match?.value)
        }
    }
}


nonisolated extension CodexCloudTask {
    /// What applying this task on a machine actually runs.
    ///
    /// **The vendor's own command, in the checkout it belongs to.** Item 9's rule is
    /// that cloud work moves by the vendors' vehicles and never by a protocol of ours;
    /// this app's contribution ends at deciding *which machine*, and begins and ends
    /// there. The `cd` is the whole of the placement decision made real.
    func applyCommand(in directory: String) -> String {
        "cd \(RemoteShell.quoted(directory)) && codex cloud apply \(RemoteShell.quoted(id))"
    }
}
