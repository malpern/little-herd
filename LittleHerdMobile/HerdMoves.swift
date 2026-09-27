import SwiftUI
import UniformTypeIdentifiers

/// A session a person has asked to move, and where to.
struct MoveIntent: Identifiable, Equatable {
    let session: HerdWire.Session
    let from: String
    let to: String

    var id: String { "\(session.id)→\(to)" }
}

/// What is in a person's hand during a drag.
struct CarriedSession: Equatable {
    let session: HerdWire.Session
    let from: String

    func disposition(onto machine: String) -> String? {
        session.move?.destinations.first { $0.machine == machine }?.disposition
    }
}

extension HerdWire.Session {
    /// Whether it can be picked up at all — the watcher's verdict, not ours.
    var isMovable: Bool {
        guard let move else { return false }
        return move.verdict != "refused" && !move.destinations.isEmpty
    }
}

// MARK: - Drop targets

/// The herd as a row of pens to drop work onto — the Mac's columns, which
/// lift to meet a drag, turned into a strip that fits above a list.
///
/// A pen lights green for a machine that can take the work now and amber for
/// one the watcher would set up first; the rest fade, so a person sees where
/// the work can go before letting go of it.
struct MachinePens: View {
    let snapshot: HerdWire.Snapshot
    @Binding var carrying: CarriedSession?
    let onDrop: (MoveIntent) -> Void

    @State private var over: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(snapshot.machines.filter { !$0.isStorage }) { machine in
                    pen(machine)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .sensoryFeedback(.selection, trigger: over)
    }

    private func pen(_ machine: HerdWire.Machine) -> some View {
        let disposition = carrying?.disposition(onto: machine.id)
        let isOrigin = carrying?.from == machine.id
        let isOver = over == machine.id
        let tint: Color = disposition == "fixable" ? .orange : HerdTheme.loadGreen
        return VStack(spacing: 4) {
            MachineAvatar(machine: machine, size: 40)
            Text(machine.shortName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(caption(machine, disposition: disposition, isOrigin: isOrigin))
                .font(.caption2)
                .foregroundStyle(disposition == "fixable" ? .orange : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 84)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(disposition != nil ? tint.opacity(isOver ? 0.28 : 0.12) : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(disposition != nil ? tint.opacity(isOver ? 0.9 : 0.4) : .clear, lineWidth: isOver ? 2 : 1)
        }
        .scaleEffect(isOver && disposition != nil ? 1.06 : 1)
        .opacity(carrying != nil && disposition == nil && !isOrigin ? 0.35 : 1)
        .animation(.snappy(duration: 0.2), value: isOver)
        .animation(.smooth(duration: 0.2), value: carrying)
        .onDrop(of: [.plainText], delegate: PenDropDelegate(
            machine: machine.id,
            carrying: $carrying,
            over: $over,
            onDrop: onDrop
        ))
        .accessibilityElement(children: .combine)
    }

    private func caption(_ machine: HerdWire.Machine, disposition: String?, isOrigin: Bool) -> String {
        if isOrigin { return "Here now" }
        switch disposition {
        case "ready": return "Can take it"
        case "fixable": return "Needs setup"
        default:
            let working = machine.activeSessionCount
            return working == 0 ? (machine.state == "live" ? "Idle" : "Away") : "\(working) working"
        }
    }
}

private struct PenDropDelegate: DropDelegate {
    let machine: String
    @Binding var carrying: CarriedSession?
    @Binding var over: String?
    let onDrop: (MoveIntent) -> Void

    private var accepts: Bool { carrying?.disposition(onto: machine) != nil }

    func validateDrop(info: DropInfo) -> Bool { accepts }
    func dropEntered(info: DropInfo) { over = machine }
    func dropExited(info: DropInfo) { if over == machine { over = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: accepts ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { over = nil; carrying = nil }
        guard let carrying, accepts else { return false }
        onDrop(MoveIntent(session: carrying.session, from: carrying.from, to: machine))
        return true
    }
}

// MARK: - Drag sources and the menu

extension View {
    /// Lets a session be picked up and dropped on a pen, and offers the same
    /// move from a long-press menu — the path VoiceOver and a steady hand
    /// both prefer to a drag.
    func movable(
        _ session: HerdWire.Session,
        from machine: HerdWire.Machine,
        in snapshot: HerdWire.Snapshot,
        canWrite: Bool,
        carrying: Binding<CarriedSession?>,
        onMove: @escaping (MoveIntent) -> Void
    ) -> some View {
        modifier(MovableSession(
            session: session,
            machine: machine,
            snapshot: snapshot,
            canWrite: canWrite,
            carrying: carrying,
            onMove: onMove
        ))
    }
}

private struct MovableSession: ViewModifier {
    let session: HerdWire.Session
    let machine: HerdWire.Machine
    let snapshot: HerdWire.Snapshot
    let canWrite: Bool
    @Binding var carrying: CarriedSession?
    let onMove: (MoveIntent) -> Void

    func body(content: Content) -> some View {
        if canWrite, session.isMovable {
            content
                .onDrag {
                    carrying = CarriedSession(session: session, from: machine.id)
                    return NSItemProvider(object: session.id as NSString)
                } preview: {
                    DragPreview(session: session)
                }
                .contextMenu { menu }
        } else {
            content.contextMenu { menu }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if canWrite, let move = session.move {
            if move.verdict == "refused" {
                Text(move.reason ?? "Can’t be moved")
            } else {
                Menu {
                    ForEach(move.destinations, id: \.machine) { destination in
                        let name = snapshot.machines.first { $0.id == destination.machine }?.shortName
                            ?? destination.machine
                        Button {
                            onMove(MoveIntent(session: session, from: machine.id, to: destination.machine))
                        } label: {
                            Label(
                                destination.disposition == "fixable" ? "\(name) (needs setup)" : name,
                                systemImage: "arrow.right.circle"
                            )
                        }
                    }
                } label: {
                    Label("Move to", systemImage: "arrow.left.arrow.right")
                }
            }
        }
        Button {
            UIPasteboard.general.string = session.short
        } label: {
            Label("Copy session ID", systemImage: "doc.on.doc")
        }
        if let directory = session.workingDirectory {
            Button {
                UIPasteboard.general.string = directory
            } label: {
                Label("Copy folder path", systemImage: "folder")
            }
        }
    }
}

private struct DragPreview: View {
    let session: HerdWire.Session

    var body: some View {
        HStack(spacing: 10) {
            ProviderMark(provider: session.provider)
            Text(session.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - The confirm sheet

/// A move in two steps, the way the command line does it: first what would
/// happen, from the watcher, with nothing changed; then, on a press, the move.
/// A drop is a thin thing to hang a seven-step transfer on, so the drop only
/// opens this.
struct MoveSheet: View {
    let intent: MoveIntent
    let client: HerdClient
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case asking
        case plan(HerdWire.MoveResponse)
        case moving(HerdWire.MoveResponse)
        case started(HerdWire.MoveResponse)
        case failed(String)
    }

    @State private var stage: Stage = .asking

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    route
                    content
                }
                .padding(20)
            }
            .background(HerdTheme.background.ignoresSafeArea())
            .navigationTitle("Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isStarted ? "Done" : "Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { action }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(trigger: stage) { _, new in
            switch new {
            case .started: .success
            case .failed: .error
            case .plan(let plan) where plan.refusal != nil: .warning
            default: nil
            }
        }
        .task { await ask() }
    }

    private var isStarted: Bool {
        if case .started = stage { return true }
        return false
    }

    private var machines: [HerdWire.Machine] { client.snapshot?.machines ?? [] }

    private var route: some View {
        HStack(spacing: 14) {
            if let from = machines.first(where: { $0.id == intent.from }) {
                MachineAvatar(machine: from, size: 52)
            }
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: isMoving)
            if let to = machines.first(where: { $0.id == intent.to }) {
                MachineAvatar(machine: to, size: 52)
            }
            Spacer()
        }
        .overlay(alignment: .bottomLeading) { EmptyView() }
    }

    private var isMoving: Bool {
        if case .moving = stage { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        Text(intent.session.title)
            .font(.title3.weight(.semibold))
        switch stage {
        case .asking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Asking the watcher what this would do…")
                    .foregroundStyle(.secondary)
            }
        case .plan(let plan), .moving(let plan):
            if let refusal = plan.refusal {
                Label(refusal, systemImage: "hand.raised.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("From \(plan.fromName) to \(plan.toName)")
                    .foregroundStyle(.secondary)
                if plan.fixesFirst {
                    Label("\(plan.toName) will be set up first — a phase you can watch and stop on the Mac.", systemImage: "wrench.and.screwdriver")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                steps(plan.steps)
            }
        case .started(let plan):
            Label("Started. It will appear under In transit, and the phone will say when it lands on \(plan.toName).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(HerdTheme.loadGreen)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func steps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(HerdTheme.forest))
                    Text(step)
                        .font(.subheadline)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var action: some View {
        switch stage {
        case .plan(let plan) where plan.refusal == nil:
            Button {
                Task { await confirm(plan) }
            } label: {
                Text("Move to \(plan.toName)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(HerdTheme.forest)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        case .plan(let plan) where plan.refusal != nil:
            // A refusal is a reading, not a verdict for all time: a session
            // mid-thought is refused and movable a minute later.
            Button("Check again") { Task { await ask() } }
                .buttonStyle(.bordered)
                .padding(.bottom, 16)
        case .moving:
            ProgressView("Starting…")
                .padding(.bottom, 16)
        case .failed:
            Button("Try again") { Task { await ask() } }
                .buttonStyle(.bordered)
                .padding(.bottom, 16)
        default:
            EmptyView()
        }
    }

    private func ask() async {
        stage = .asking
        do {
            stage = .plan(try await client.move(
                session: intent.session, from: intent.from, to: intent.to, dryRun: true
            ))
        } catch {
            stage = .failed(describe(error))
        }
    }

    private func confirm(_ plan: HerdWire.MoveResponse) async {
        stage = .moving(plan)
        do {
            let result = try await client.move(
                session: intent.session, from: intent.from, to: intent.to, dryRun: false
            )
            stage = result.applied ? .started(result) : .plan(result)
        } catch {
            stage = .failed(describe(error))
        }
    }

    private func describe(_ error: Error) -> String {
        client.current.map { HerdClient.describe(error, watcher: $0) } ?? error.localizedDescription
    }
}

// MARK: - In transit

/// Moves under way or just finished — the Mac's transfer strip.
struct TransfersStrip: View {
    let transfers: [HerdWire.Transfer]
    let machines: [HerdWire.Machine]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IN TRANSIT")
                .font(.caption.weight(.semibold))
                .kerning(0.6)
                .foregroundStyle(.secondary)
            ForEach(transfers) { transfer in
                row(transfer)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func name(_ id: String) -> String {
        machines.first { $0.id == id }?.shortName ?? id
    }

    private func row(_ transfer: HerdWire.Transfer) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(transfer.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                statusMark(transfer)
            }
            Text("\(name(transfer.origin)) → \(name(transfer.destination))\(transfer.detail.map { " · \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(transfer.phase == "failed" ? .orange : .secondary)
                .lineLimit(2)
            if transfer.phase != "landed" && transfer.phase != "failed" {
                ProgressView(value: transfer.progress)
                    .tint(HerdTheme.loadTeal)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusMark(_ transfer: HerdWire.Transfer) -> some View {
        switch transfer.phase {
        case "landed":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(HerdTheme.loadGreen)
        case "failed":
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.orange)
        default:
            Text("\(Int(transfer.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// The critical events the watcher is raising, as a short list under the
/// header — what the tab's dot promised.
struct AlertsCallout: View {
    let alerts: [HerdWire.Alert]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(alerts) { alert in
                Button {
                    onOpen(alert.machine)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .symbolRenderingMode(.hierarchical)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                            if !alert.body.isEmpty {
                                Text(alert.body)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if alert.id != alerts.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
