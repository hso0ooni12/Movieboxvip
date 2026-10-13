import SwiftUI
import UIKit
import VLCKitSPM

private let xsSportsV33Accent = Color(red: 1.0, green: 0.12, blue: 0.38)
private let xsSportsServerOverrideKey = "xs.iptv.serverOverride"

struct XSSportsLiveViewV33: View {
    @StateObject private var store = IPTVSportsStore()
    @State private var query = ""
    @State private var selectedCategoryID: String?
    @State private var selectedStream: IPTVLiveStream?
    @State private var showServerSettings = false
    @AppStorage("xs.iptv.favoriteStreamIDs") private var favoriteIDsRaw = ""
    @AppStorage(xsSportsServerOverrideKey) private var serverOverride = ""

    private var favoriteIDs: Set<Int> {
        Set(favoriteIDsRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var filteredStreams: [IPTVLiveStream] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.streams.filter { stream in
            let categoryMatch = selectedCategoryID == nil || stream.categoryID == selectedCategoryID
            let queryMatch = text.isEmpty || stream.name.localizedCaseInsensitiveContains(text)
            return categoryMatch && queryMatch
        }
    }

    private var featured: IPTVLiveStream? {
        let favorites = filteredStreams.filter { favoriteIDs.contains($0.streamID) }
        return favorites.first ?? filteredStreams.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if store.credentials == nil {
                unavailableState
            } else if store.isLoading && store.streams.isEmpty {
                loadingState
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.97), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("SPORTS LIVE")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .tracking(0.6)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { showServerSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sports server settings")
            }
        }
        .sheet(isPresented: $showServerSettings) {
            XSSportsServerSettingsView(serverOverride: $serverOverride) {
                applyConfiguredServer()
                Task { try? await store.refresh() }
            }
            .preferredColorScheme(.dark)
        }
        .task {
            applyConfiguredServer()
            guard store.credentials != nil, store.streams.isEmpty, !store.isLoading else { return }
            try? await store.refresh()
        }
        .onChange(of: serverOverride) { _ in
            applyConfiguredServer()
        }
        .fullScreenCover(item: $selectedStream) { stream in
            XSSportsPlayerV33(
                stream: stream,
                urls: playbackURLs(for: stream),
                logoURL: resolvedLogoURL(for: stream)
            )
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                categoryStrip

                if let error = store.errorMessage {
                    errorCard(error)
                }

                if let featured {
                    featuredCard(featured)
                }

                sectionHeader
                channelGrid
            }
            .padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .refreshable { try? await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Sports")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                Text("Fast access to your live sports channels")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
            }

            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.44))
                    TextField("Search sports channels…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))

                Button {
                    Task { try? await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                categoryChip(title: "All Sports", id: nil, count: store.streams.count)
                ForEach(store.categories) { category in
                    let count = store.streams.lazy.filter { $0.categoryID == category.categoryID }.count
                    categoryChip(title: category.categoryName, id: category.categoryID, count: count)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func categoryChip(title: String, id: String?, count: Int) -> some View {
        let selected = selectedCategoryID == id
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { selectedCategoryID = id }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? .black.opacity(0.62) : .white.opacity(0.48))
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(selected ? Color.white : Color.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(selected ? 0 : 0.10)))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private func featuredCard(_ stream: IPTVLiveStream) -> some View {
        Button { selectedStream = stream } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.10, green: 0.12, blue: 0.17), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                XSSportsChannelArtworkV33(name: stream.name, logoURL: resolvedLogoURL(for: stream), compact: false)
                    .padding(.horizontal, 90)
                    .padding(.vertical, 28)
                    .opacity(0.78)

                LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.92), in: Capsule())
                        if let category = categoryName(for: stream.categoryID) {
                            Text(category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.64))
                                .lineLimit(1)
                        }
                    }

                    Text(stream.name)
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Label("Watch Live", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .frame(height: 39)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(18)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10)))
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedCategoryID.flatMap(categoryName(for:)) ?? "Sports Channels")
                    .font(.title3.bold())
                Text("\(filteredStreams.count) live channels")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.50))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
    }

    private var channelGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 12)], spacing: 16) {
            ForEach(filteredStreams) { stream in
                XSSportsChannelCardV33(
                    stream: stream,
                    category: categoryName(for: stream.categoryID),
                    logoURL: resolvedLogoURL(for: stream),
                    isFavorite: favoriteIDs.contains(stream.streamID),
                    toggleFavorite: { toggleFavorite(stream.streamID) },
                    play: { selectedStream = stream }
                )
            }
        }
        .padding(.horizontal, 18)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(xsSportsV33Accent)
            Text("Loading live sports…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.66))
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sportscourt")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(xsSportsV33Accent)
            Text("Sports IPTV isn’t configured")
                .font(.title3.bold())
            Text("The embedded sports account is not available in this build.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
            Button("Retry") { Task { try? await store.refresh() } }
                .font(.caption.bold())
        }
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
        .padding(.horizontal, 18)
    }

    private func categoryName(for id: String) -> String? {
        store.categories.first(where: { $0.categoryID == id })?.categoryName
    }

    private func toggleFavorite(_ id: Int) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoriteIDsRaw = ids.sorted().map(String.init).joined(separator: ",")
    }

    private func applyConfiguredServer() {
        guard let embedded = XSIPTVEmbeddedConfig.credentials else { return }
        let trimmed = serverOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = trimmed.isEmpty ? embedded.host : trimmed
        let next = IPTVCredentials(host: host, username: embedded.username, password: embedded.password)
        if store.credentials != next {
            store.credentials = next
            store.categories = []
            store.streams = []
            store.errorMessage = nil
        }
    }

    private func resolvedLogoURL(for stream: IPTVLiveStream) -> URL? {
        guard var raw = stream.streamIcon?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        raw = raw.replacingOccurrences(of: " ", with: "%20")
        if raw.hasPrefix("//") { return URL(string: "http:" + raw) }
        if let url = URL(string: raw), url.scheme != nil { return url }
        guard let base = store.credentials?.normalizedHost else { return nil }
        let path = raw.hasPrefix("/") ? raw : "/" + raw
        return URL(string: base + path)
    }

    private func playbackURLs(for stream: IPTVLiveStream) -> [URL] {
        guard let credentials = store.credentials else { return [] }
        let user = credentials.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.username
        let pass = credentials.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.password

        var extensions: [String] = []
        if let providerExt = stream.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !providerExt.isEmpty {
            extensions.append(providerExt)
        }
        for ext in ["ts", "m3u8"] where !extensions.contains(ext) {
            extensions.append(ext)
        }

        var seen = Set<String>()
        return extensions.compactMap { ext in
            let raw = "\(credentials.normalizedHost)/live/\(user)/\(pass)/\(stream.streamID).\(ext)"
            guard seen.insert(raw).inserted else { return nil }
            return URL(string: raw)
        }
    }
}

private struct XSSportsServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var serverOverride: String
    let didSave: () -> Void

    @State private var draft = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sports Server")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                        Text("Only the server address is editable. Your IPTV username and password stay hidden inside the build configuration.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineSpacing(2)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Server Address", systemImage: "server.rack")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.62))

                        TextField("http://server.example:80", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)))

                        if let message {
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red.opacity(0.92))
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))

                    Button {
                        save()
                    } label: {
                        Label("Save Server & Refresh", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(.black)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Sports Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if !serverOverride.isEmpty {
                    draft = serverOverride
                } else if let embedded = XSIPTVEmbeddedConfig.credentials {
                    draft = embedded.normalizedHost
                }
            }
        }
    }

    private func save() {
        var value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty else {
            message = "Enter the IPTV server address."
            return
        }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "http://" + value
        }
        guard let url = URL(string: value), url.host != nil else {
            message = "The server address is not valid."
            return
        }
        serverOverride = value
        message = nil
        didSave()
        dismiss()
    }
}

private struct XSSportsChannelCardV33: View {
    let stream: IPTVLiveStream
    let category: String?
    let logoURL: URL?
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                Button(action: play) {
                    XSSportsChannelArtworkV33(name: stream.name, logoURL: logoURL, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)

                VStack {
                    HStack {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.92), in: Capsule())
                        Spacer()
                        Button(action: toggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(isFavorite ? .yellow : .white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.64), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(8)
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10)))

            Button(action: play) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stream.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let category {
                        Text(category)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct XSSportsChannelArtworkV33: View {
    let name: String
    let logoURL: URL?
    let compact: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let logoURL {
                AsyncImage(url: logoURL, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(compact ? 20 : 12)
                    default:
                        generatedArtwork
                    }
                }
            } else {
                generatedArtwork
            }
        }
    }

    private var generatedArtwork: some View {
        VStack(spacing: compact ? 6 : 9) {
            Image(systemName: brandSymbol)
                .font(.system(size: compact ? 26 : 38, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text(brandText)
                .font(.system(size: compact ? 13 : 18, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(14)
    }

    private var normalizedName: String { name.lowercased() }

    private var brandText: String {
        if normalizedName.contains("bein") { return "beIN SPORTS" }
        if normalizedName.contains("ssc") { return "SSC SPORTS" }
        if normalizedName.contains("espn") { return "ESPN" }
        if normalizedName.contains("dazn") { return "DAZN" }
        if normalizedName.contains("sky") { return "SKY SPORTS" }
        return String(name.replacingOccurrences(of: "|", with: " ").replacingOccurrences(of: "_", with: " ").prefix(compact ? 22 : 34))
    }

    private var brandSymbol: String {
        if normalizedName.contains("football") || normalizedName.contains("soccer") || normalizedName.contains("كرة") { return "soccerball" }
        if normalizedName.contains("tennis") { return "tennisball.fill" }
        if normalizedName.contains("basket") { return "basketball.fill" }
        if normalizedName.contains("formula") || normalizedName.contains("f1") { return "flag.checkered" }
        return "sportscourt.fill"
    }

    private var artworkColors: [Color] {
        if normalizedName.contains("bein") {
            return [Color(red: 0.27, green: 0.04, blue: 0.46), Color(red: 0.52, green: 0.08, blue: 0.63), .black]
        }
        if normalizedName.contains("ssc") {
            return [Color(red: 0.02, green: 0.31, blue: 0.20), Color(red: 0.04, green: 0.16, blue: 0.13), .black]
        }
        if normalizedName.contains("espn") {
            return [Color(red: 0.55, green: 0.02, blue: 0.04), Color(red: 0.21, green: 0.01, blue: 0.02), .black]
        }
        return [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.05, green: 0.06, blue: 0.10), .black]
    }
}

struct XSSportsPlayerV33: View {
    @Environment(\.dismiss) private var dismiss
    let stream: IPTVLiveStream
    let urls: [URL]
    let logoURL: URL?

    @StateObject private var model: XSSportsVLCPlayerModel
    @State private var controlsVisible = true

    init(stream: IPTVLiveStream, urls: [URL], logoURL: URL?) {
        self.stream = stream
        self.urls = urls
        self.logoURL = logoURL
        _model = StateObject(wrappedValue: XSSportsVLCPlayerModel(urls: urls))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            XSVLCVideoSurface(player: model.player)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) { controlsVisible.toggle() }
                }

            if model.statusText != "Live" {
                VStack(spacing: 12) {
                    if model.statusText != "Stream unavailable" {
                        ProgressView().controlSize(.large).tint(.white)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.yellow)
                    }
                    Text(model.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                    if model.statusText == "Stream unavailable" {
                        Button("Retry") { model.start() }
                            .font(.caption.bold())
                            .padding(.horizontal, 15)
                            .frame(height: 34)
                            .background(Color.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 16))
            }

            if controlsVisible {
                playerChrome
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var playerChrome: some View {
        VStack {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.68), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())

                XSSportsChannelArtworkV33(name: stream.name, logoURL: logoURL, compact: true)
                    .frame(width: 58, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(stream.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                Button { model.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.68), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)

                if urls.count > 1 {
                    Menu {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            Button {
                                model.play(index: index)
                            } label: {
                                Label(
                                    index == model.currentIndex ? "Source \(index + 1) · Active" : "Source \(index + 1) · \(url.pathExtension.uppercased())",
                                    systemImage: index == model.currentIndex ? "checkmark.circle.fill" : "play.circle"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.68), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.16)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            HStack {
                HStack(spacing: 7) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text(model.statusText == "Live" ? "LIVE" : model.statusText.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(.black.opacity(0.70), in: Capsule())

                Spacer()

                Button { model.togglePlayPause() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.70), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }
}

@MainActor
private final class XSSportsVLCPlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    let urls: [URL]

    @Published var statusText = "Connecting…"
    @Published var currentIndex = 0
    @Published var isPlaying = false

    private var fallbackTask: Task<Void, Never>?
    private var generation = 0

    init(urls: [URL]) {
        self.urls = urls
        super.init()
        player.delegate = self
    }

    func start() {
        guard !urls.isEmpty else {
            statusText = "Stream unavailable"
            return
        }
        play(index: 0)
    }

    func play(index: Int) {
        guard urls.indices.contains(index) else { return }
        generation += 1
        let myGeneration = generation
        fallbackTask?.cancel()
        currentIndex = index
        statusText = index == 0 ? "Connecting…" : "Trying backup source…"
        isPlaying = false

        player.stop()
        player.media = VLCMedia(url: urls[index])
        player.play()

        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation else { return }
                if !self.player.isPlaying {
                    self.tryNextSource()
                }
            }
        }
    }

    func reload() {
        play(index: currentIndex)
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        generation += 1
        fallbackTask?.cancel()
        player.stop()
        player.delegate = nil
        isPlaying = false
    }

    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handleStateChanged(newState)
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.player.isPlaying {
                self.statusText = "Live"
                self.isPlaying = true
                self.fallbackTask?.cancel()
            }
        }
    }

    private func handleStateChanged(_ state: VLCMediaPlayerState) {
        if state == .playing {
            statusText = "Live"
            isPlaying = true
            fallbackTask?.cancel()
        } else if state == .buffering {
            statusText = "Buffering…"
        } else if state == .paused {
            statusText = "Paused"
            isPlaying = false
        } else if state == .error {
            isPlaying = false
            tryNextSource()
        }
    }

    private func tryNextSource() {
        let next = currentIndex + 1
        if urls.indices.contains(next) {
            play(index: next)
        } else {
            fallbackTask?.cancel()
            statusText = "Stream unavailable"
            isPlaying = false
        }
    }
}

private struct XSVLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if player.drawable as AnyObject? !== uiView {
            player.drawable = uiView
        }
    }
}
