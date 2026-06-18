import SwiftUI

struct ContentView: View {
    @EnvironmentObject var browser: BrowserState
    @EnvironmentObject var ai: AIController
    @StateObject private var sceneStore = SceneModelStore()

    @State private var address: String = ""
    @State private var showAI = true
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Layer 0: live 3D scene as an ambient, dim backdrop behind everything.
            Scene3DView(store: sceneStore)
                .opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                toolbar
                tabStrip
                HStack(spacing: 8) {
                    contentArea
                    if showAI { aiSidebar.frame(width: 340) }
                }
            }
            .padding(10)
        }
        .onChange(of: browser.selectedTabID) { _ in
            address = browser.selectedTab?.urlString ?? ""
        }
    }

    // MARK: - Toolbar (beveled metal bar)

    private var toolbar: some View {
        HStack(spacing: 10) {
            Group {
                Button(action: browser.goBack)    { Image(systemName: "chevron.left") }
                    .disabled(!(browser.selectedTab?.canGoBack ?? false))
                Button(action: browser.goForward) { Image(systemName: "chevron.right") }
                    .disabled(!(browser.selectedTab?.canGoForward ?? false))
                Button(action: browser.reload)    { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(ChromeButtonStyle())

            // Address bar — a recessed glass slot
            HStack {
                Image(systemName: "globe").foregroundStyle(Theme.neon.opacity(0.8))
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .onSubmit { browser.go(to: address) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                Capsule().fill(Color.black.opacity(0.55))
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.7), .white.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                if let p = browser.selectedTab?.progress, p > 0, p < 1 {
                    GeometryReader { geo in
                        Capsule().fill(Theme.wireSheen)
                            .frame(width: geo.size.width * p, height: 2)
                            .offset(y: geo.size.height - 2)
                    }
                }
            }

            Button { sceneStore.importModel() } label: { Image(systemName: "cube.transparent") }
                .buttonStyle(ChromeButtonStyle(tint: Theme.amber))
                .help("Load a .3mf model into the 3D backdrop")
            Button { showSettings.toggle() } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(ChromeButtonStyle())
                .popover(isPresented: $showSettings) { settingsPanel }
            Button { withAnimation(.spring()) { showAI.toggle() } } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(ChromeButtonStyle(tint: Theme.neonPink))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.brushedMetal)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .black.opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.4)
        )
        .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
        // Subtle perspective tilt so the bar reads as a 3D slab.
        .rotation3DEffect(.degrees(3), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
    }

    // MARK: - Tab strip (extruded tab tiles)

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(browser.tabs) { tab in
                    tabTile(tab)
                }
                Button { browser.newTab() } label: { Image(systemName: "plus") }
                    .buttonStyle(ChromeButtonStyle())
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 40)
    }

    private func tabTile(_ tab: Tab) -> some View {
        let active = tab.id == browser.selectedTabID
        return HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            } else {
                Image(systemName: "globe").font(.system(size: 10))
            }
            Text(tab.title).lineLimit(1).font(.system(size: 12, weight: active ? .semibold : .regular))
            Button { browser.closeTab(tab) } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                .buttonStyle(.plain)
        }
        .foregroundStyle(active ? .white : .white.opacity(0.65))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? Theme.glassPanel :
                        LinearGradient(colors: [Theme.metalDark, Theme.panelBottom],
                                       startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? Theme.neon.opacity(0.7) : .white.opacity(0.12), lineWidth: active ? 1.3 : 1)
        )
        .shadow(color: active ? Theme.neon.opacity(0.3) : .black.opacity(0.4),
                radius: active ? 8 : 3, y: active ? 4 : 2)
        .scaleEffect(active ? 1.0 : 0.97)
        .onTapGesture { browser.select(tab) }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
    }

    // MARK: - Content area (recessed glass frame around the page)

    private var contentArea: some View {
        ZStack {
            if let tab = browser.selectedTab {
                WebView(tab: tab).id(tab.id)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.18)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.7), radius: 16, y: 10)
    }

    // MARK: - AI sidebar (tilted glass panel)

    private var aiSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.neonPink)
                Text("Prism Agent").font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Toggle("Agent", isOn: $ai.agentMode)
                    .toggleStyle(.switch).controlSize(.mini)
                    .help("Allow the model to drive the browser with tools")
            }
            .foregroundStyle(.white)
            .padding(12)

            Divider().overlay(Theme.neon.opacity(0.3))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(ai.messages) { msg in
                            messageBubble(msg).id(msg.id)
                        }
                        if ai.isThinking {
                            HStack { ProgressView().scaleEffect(0.6); Text("thinking…").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: ai.messages.count) { _ in
                    if let last = ai.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            composer
        }
        .beveledPanel(corner: 16, tilt: 0, glow: Theme.neonPink)
        .rotation3DEffect(.degrees(-4), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }

    @State private var draft: String = ""
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask or command the agent…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .onSubmit(sendDraft)
            Button(action: sendDraft) { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(ChromeButtonStyle(tint: Theme.neon))
        }
        .padding(10)
        .background(Color.black.opacity(0.4))
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        ai.send(text)
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        let (bg, fg, align): (Color, Color, Alignment) = {
            switch msg.role {
            case .user:      return (Theme.neon.opacity(0.18), .white, .trailing)
            case .assistant: return (Color.white.opacity(0.08), .white, .leading)
            case .tool:      return (Theme.amber.opacity(0.15), Theme.amber, .leading)
            case .system:    return (Theme.neonPink.opacity(0.15), Theme.neonPink, .leading)
            }
        }()
        return Text(msg.text)
            .font(.system(size: 12.5, design: msg.role == .tool ? .monospaced : .default))
            .foregroundStyle(fg)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(bg))
            .frame(maxWidth: .infinity, alignment: align)
    }

    // MARK: - Settings popover

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("AI provider").font(.caption).foregroundStyle(.secondary)
                Picker("Provider", selection: $ai.provider) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(ai.provider.displayName) API key").font(.caption).foregroundStyle(.secondary)
                SecureField(ai.provider.keyHint, text: ai.keyBinding()).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Model").font(.caption).foregroundStyle(.secondary)
                TextField(ai.provider.defaultModel, text: ai.modelBinding()).textFieldStyle(.roundedBorder)
            }
            Divider()
            Text("3D backdrop").font(.caption).foregroundStyle(.secondary)
            Text(sceneStore.statusMessage).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Load .3mf…") { sceneStore.importModel() }
                Button("Reset")      { sceneStore.resetToDefault() }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
