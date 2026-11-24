import SwiftUI
import AVFoundation
import WidgetKit

struct Bubble: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var bubbles: [Bubble] = []
    @Published var busy = false
    @Published var speak = false
    private var history: [[String: Any]] = []
    private let synth = AVSpeechSynthesizer()

    private func add(_ b: Bubble) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { bubbles.append(b) }
    }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        add(Bubble(text: t, isUser: true))
        history.append(["role": "user", "content": t])
        withAnimation { busy = true }
        let snapshot = history
        Task {
            do {
                let (reply, newHistory) = try await AIAssistant.shared.converse(snapshot)
                history = newHistory
                add(Bubble(text: reply, isUser: false))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if speak { synth.speak(AVSpeechUtterance(string: reply)) }
            } catch {
                history.removeLast()
                add(Bubble(text: error.localizedDescription, isUser: false))
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            withAnimation { busy = false }
        }
    }
}

struct ChatView: View {
    @StateObject private var model = ChatModel()
    @StateObject private var speech = SpeechInput()
    @State private var input = ""
    @State private var showSettings = false
    @FocusState private var focused: Bool

    private let chips = ["Plan my day", "Remind me to drink water at 5pm",
                         "Give me a fun fact", "What's on my calendar today?"]

    var body: some View {
        ZStack {
            AnimatedBackground()
            VStack(spacing: 0) {
                header
                if model.bubbles.isEmpty { welcome } else { messages }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onOpenURL { url in if url.host == "ask" { focused = true } }
        .onChange(of: speech.transcript) { _, t in if speech.listening { input = t } }
        .onChange(of: speech.listening) { old, new in
            if old && !new { model.send(input); input = "" }
        }
    }

    private var header: some View {
        HStack {
            Button { withAnimation(.spring) { model.speak.toggle() } } label: {
                Image(systemName: model.speak ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            if !model.bubbles.isEmpty { OrbView(size: 36, busy: model.busy).transition(.scale.combined(with: .opacity)) }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            OrbView(size: 130, busy: model.busy)
            VStack(spacing: 6) {
                Text("How can I help?").font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Or just say “Hey SiriAI”").foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(chips.enumerated()), id: \.offset) { i, c in
                    Button { model.send(c) } label: {
                        Text(c).font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.15)))
                    }
                    .foregroundStyle(.white)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.bubbles) { b in
                        BubbleView(bubble: b)
                            .id(b.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                                removal: .opacity))
                    }
                    if model.busy {
                        HStack { TypingDots(); Spacer() }.id("typing").transition(.opacity.combined(with: .scale))
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.bubbles.count) { _, _ in
                withAnimation { proxy.scrollTo(model.bubbles.last?.id, anchor: .bottom) }
            }
            .onChange(of: model.busy) { _, b in
                if b { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { speech.toggle() } label: {
                Image(systemName: speech.listening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: speech.listening)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(speech.listening ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
            }
            TextField("Ask anything…", text: $input, axis: .vertical)
                .focused($focused)
                .lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15)))
            Button {
                model.send(input); input = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .scaleEffect(input.isEmpty ? 0.8 : 1)
                    .opacity(input.isEmpty ? 0.4 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: input.isEmpty)
            }
            .disabled(input.isEmpty || model.busy)
        }
        .foregroundStyle(.white)
        .padding(.horizontal).padding(.vertical, 8)
    }
}

struct BubbleView: View {
    let bubble: Bubble

    private var attributed: AttributedString {
        (try? AttributedString(markdown: bubble.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(bubble.text)
    }

    var body: some View {
        HStack {
            if bubble.isUser { Spacer(minLength: 50) }
            Text(attributed)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background {
                    if bubble.isUser {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.12)))
                    }
                }
                .textSelection(.enabled)
            if !bubble.isUser { Spacer(minLength: 50) }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = Shared.apiKey
    @State private var model = Shared.model
    @State private var relay = Shared.relay
    @State private var roomToken = Shared.roomToken
    @State private var laptop = Shared.laptopName

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API key") {
                    SecureField("sk-ant-...", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Model") {
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Laptop link") {
                    TextField("Relay URL (https://...)", text: $relay)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Room token", text: $roomToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Laptop name", text: $laptop)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Home screen") {
                    Text("Long-press the Home Screen → + → SiriAI to add the widget. Its buttons work without opening the app. Lock Screen widgets are available too.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Siri, Shortcuts and the widget share this key and model. Notes stay on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Save") {
                    Shared.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    Shared.model = model
                    Shared.relay = relay.trimmingCharacters(in: .whitespacesAndNewlines)
                    Shared.roomToken = roomToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    Shared.laptopName = laptop.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "laptop" : laptop
                    WidgetCenter.shared.reloadAllTimelines()
                    dismiss()
                }
            }
        }
    }
}
