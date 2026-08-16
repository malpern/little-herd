import SwiftUI

/// Collects the DSM account for a NAS and proves it works before saving.
///
/// Testing first is the point: DSM's answer to "this account is not an
/// administrator" or "this account requires 2FA" is specific and actionable, and
/// it arrives here, next to the fields, rather than three minutes later as a
/// machine that quietly went offline.
struct SynologyCredentialsView: View {
    let machine: MachineConfiguration
    let onSave: (MachineConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var password = ""
    @State private var port: String
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle
        case testing
        case failed(String)
        case succeeded(volumes: Int, drives: Int)
    }

    init(
        machine: MachineConfiguration,
        onSave: @escaping (MachineConfiguration) -> Void
    ) {
        self.machine = machine
        self.onSave = onSave
        _username = State(initialValue: machine.dsmUsername ?? "")
        _port = State(
            initialValue: String(machine.dsmPort ?? SynologyDSM.defaultPort)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect to \(machine.name)")
                    .font(.headline)
                Text("Little Herd reads capacity and drive health from DSM. Storage details need an account in DSM’s administrators group, with two-factor authentication turned off for that account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                LabeledContent("Address") {
                    Text(machine.hostname)
                        .foregroundStyle(.secondary)
                }
                TextField("DSM account", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                TextField("Port", text: $port)
                    .frame(width: 80)
            }
            .formStyle(.grouped)
            .onChange(of: username) { status = .idle }
            .onChange(of: password) { status = .idle }
            .onChange(of: port) { status = .idle }

            statusView

            HStack {
                Text("The password is stored in your login keychain, not in Little Herd’s preferences.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(saveButtonTitle) {
                    Task { await testAndSave() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canTest || status == .testing)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            Label {
                Text("Asking \(machine.hostname)…")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .succeeded(let volumes, let drives):
            Label(
                "Connected. \(volumes) \(volumes == 1 ? "volume" : "volumes"), \(drives) \(drives == 1 ? "drive" : "drives").",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        }
    }

    private var saveButtonTitle: String {
        if case .succeeded = status { return "Save" }
        return "Test and Save"
    }

    private var canTest: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && Int(port) != nil
    }

    private func testAndSave() async {
        guard let portNumber = Int(port) else { return }
        let account = username.trimmingCharacters(in: .whitespaces)
        let endpoint = SynologyDSMEndpoint(
            host: machine.hostname,
            port: portNumber,
            username: account
        )
        guard endpoint.isValid else {
            status = .failed("\(machine.hostname) is not a usable address.")
            return
        }

        status = .testing
        let typed = password
        let client = SynologyDSMClient(
            endpoint: endpoint,
            pinnedCertificate: machine.dsmCertificateFingerprint,
            passwordProvider: { typed }
        )

        do {
            let storage = try await client.storage()
            let volumes = SynologyDSMParser.storageVolumes(from: storage)
            let drives = SynologyDSMParser.drives(from: storage)
            let certificate = await client.observedCertificate
            await client.signOut()

            guard KeychainSecret.store(
                typed,
                account: KeychainSecret.account(for: endpoint)
            ) else {
                status = .failed(
                    "Could not save the password to your keychain."
                )
                return
            }

            var updated = machine
            updated.connection = .dsm
            updated.dsmUsername = account
            updated.dsmPort = portNumber
            // Record the certificate seen during this successful test, so any
            // later change to it is refused rather than trusted.
            if updated.dsmCertificateFingerprint == nil {
                updated.dsmCertificateFingerprint = certificate
            }

            status = .succeeded(volumes: volumes.count, drives: drives.count)
            onSave(updated)
            dismiss()
        } catch let error as SynologyDSMError {
            status = .failed(error.detail)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
