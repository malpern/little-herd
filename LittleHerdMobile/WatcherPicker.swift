import SwiftUI

/// Which Mac to read the herd from.
///
/// Two lists, because there are two kinds of answer: Macs announcing
/// themselves on this network, which need only a tap, and an address typed
/// by hand for a watcher somewhere else. A typed address wins while it is
/// set — it is the more deliberate of the two — and clearing it hands the
/// choice back to whatever is announced.
struct WatcherPicker: View {
    let client: HerdClient
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var codeDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if client.discovered.isEmpty {
                        HStack {
                            if client.isBrowsing { ProgressView() }
                            Text(client.isBrowsing
                                ? "Looking on this network…"
                                : "Not looking. Open the herd first.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(client.discovered, id: \.self) { watcher in
                        Button {
                            client.typedAddress = ""
                            client.preferredName = watcher.displayName
                            dismiss()
                        } label: {
                            HStack {
                                Text(watcher.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if client.typedAddress.isEmpty,
                                   client.current == watcher
                                {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("On this network")
                } footer: {
                    Text("A Mac appears here while Little Herd is running on it "
                        + "with “This Mac watches the herd continuously” on.")
                }

                Section {
                    TextField("XXXX-XXXX", text: $codeDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onSubmit { client.pairingCode = codeDraft }
                } header: {
                    Text("Pairing code")
                } footer: {
                    Text("Shown in Little Herd’s settings on the watcher Mac, next to "
                        + "“This Mac watches the herd continuously”. Case and the dash "
                        + "don’t matter.")
                }

                Section {
                    TextField("mini.tail9d0bb8.ts.net", text: $draft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(useTyped)
                    HStack {
                        Button("Use this address", action: useTyped)
                            .disabled(WatcherEndpoint.typed(from: draft) == nil)
                        Spacer()
                        if !client.typedAddress.isEmpty {
                            Button("Clear", role: .destructive) {
                                client.typedAddress = ""
                                draft = ""
                            }
                        }
                    }
                } header: {
                    Text("Somewhere else")
                } footer: {
                    Text("A Tailscale name or an address, with :port if it is not "
                        + "\(HerdWire.defaultPort). Used instead of anything found "
                        + "on this network while it is set.")
                }
            }
            .navigationTitle("Watcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        client.pairingCode = codeDraft
                        dismiss()
                    }
                }
            }
            .onAppear {
                draft = client.typedAddress
                codeDraft = client.pairingCode
            }
        }
    }

    private func useTyped() {
        guard WatcherEndpoint.typed(from: draft) != nil else { return }
        client.pairingCode = codeDraft
        client.typedAddress = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}
