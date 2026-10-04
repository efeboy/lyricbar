import SwiftUI

struct SettingsView: View {

    @Bindable var model: PlaybackModel

    @State private var draft: CGFloat?
    @State private var dragging = false

    private static let width: CGFloat = 300
    private static let settleDelay = Duration.milliseconds(400)

    var body: some View {
        let rungs = WidthLadder.available()
        let shown = draft ?? model.lyricBoxWidth
        Form {
            Section {
                LabeledContent(String(localized: "Lyric width"),
                               value: String(localized: "\(Int(shown)) pt"))
                if let narrowest = rungs.first, let widest = rungs.last, widest > narrowest {
                    Slider(value: Binding(get: { shown }, set: { draft = $0 }),
                           in: narrowest...widest,
                           step: WidthLadder.step) {
                        Text(String(localized: "Lyric width"))
                    } minimumValueLabel: {
                        Text(String(localized: "Narrow"))
                    } maximumValueLabel: {
                        Text(String(localized: "Wide"))
                    } onEditingChanged: { editing in
                        dragging = editing
                        if !editing { commit() }
                    }
                    .labelsHidden()
                }
            } footer: {
                Text(String(localized: "Long lines wrap to the next chunk instead of being cut off. Widths that don't fit beside the notch are left out."))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(String(localized: "Open at Login"), isOn: $model.loginEnabled)
                    .disabled(!model.loginSupported)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshLoginState() }
        .task(id: draft) {
            guard draft != nil else { return }
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, !dragging else { return }
            commit()
        }
    }

    private func commit() {
        guard let draft else { return }
        model.widthPreference = draft
        self.draft = nil
    }
}
