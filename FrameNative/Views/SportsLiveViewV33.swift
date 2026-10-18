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
    @State private var favoritesOnly = false
    @AppStorage("xs.iptv.favoriteStreamIDs") private var favoriteIDsRaw = ""
    @AppStorage(xsSportsServerOverrideKey) private var serverOverride = ""

    private var favoriteIDs: Set<Int> {
        Set(favoriteIDsRaw.split(separator: ",").compactMap { Int($0) })
    }

    // Only explicitly AR-prefixed channels are shown; all other streams
    // remain untouched in the provider catalog.
    private var arabicStreams: [IPTVLiveStream] {
        store.streams.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased().hasPrefix("AR")
        }
    }

    private var filteredStreams: [IPTVLiveStream] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return arabicStreams.filter { stream in
            let categoryMatch = selectedCategoryID == nil || stream.categoryID == selectedCategoryID
            let queryMatch = text.isEmpty || stream.name.localizedCaseInsensitiveContains(text)
            let favoriteMatch = !favoritesOnly || favoriteIDs.contains(stream.streamID)
            return categoryMatch && queryMatch && favoriteMatch
        }
    }

    private var featured: IPTVLiveStream? {
        let favorites = filteredStreams.filter { favoriteIDs.contains($0.streamID) }
        return favorites.first ?? filteredStreams.first
    }

    var body: some View {
        ZStack {
            XSCinemaStyle.background.ignoresSafeArea()

            if store.credentials == nil {
                unavailableState
            } else if store.isLoading && store.streams.isEmpty {
                loadingState
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.95), for: .navigationBar)
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
            LazyVStack(alignment: .leading, spacing: 27) {
                header
                categoryStrip

                if let error = store.errorMessage {
                    errorCard(error)
                }

                if let featured {
                    featuredCard(featured)
                }

                sectionHeader
                if filteredStreams.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: favoritesOnly ? "star.slash" : "magnifyingglass")
                            .font(.system(size: 29, weight: .medium))
                            .foregroundStyle(XSV3.amber)
                        Text(favoritesOnly ? "No saved channels yet" : "No channels match")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(favoritesOnly ? "Tap the star on a channel to save it here." : "Try another category or search.")
                            .font(.system(size: 13))
                            .foregroundStyle(XSV3.muted)
                            .multilineTextAlignment(.center)
                        Button("Show all channels") {
                            favoritesOnly = false
                            selectedCategoryID = nil
                            query = ""
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 45)
                    .padding(.horizontal, 24)
                } else {
                    channelGrid
                }
            }
            .padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .refreshable { try? await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("LIVE ARENA")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2.6)
                    .foregroundStyle(XSCinemaStyle.warm)
                Spacer()
                Text("\(arabicStreams.count) AR CHANNELS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.53))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Every moment. Live.")
                    .font(.system(size: 33, weight: .black, design: .rounded))
                    .tracking(-0.9)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.78)
                    .lineLimit(2)
                Text("Your front row to the action.")
                    .font(.system(size: 14))
                    .foregroundStyle(XSCinemaStyle.secondary)
            }
            HStack(spacing: 10) {
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                    TextField("Search live channels", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 15)
                .frame(height: 52)
                .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))

                Button {
                    Task { try? await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh live channels")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 15)
    }

    private var categoryStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BROWSE THE ACTION")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(XSV3.amber)
                Spacer()
                Text("\(store.categories.filter { category in arabicStreams.contains { $0.categoryID == category.categoryID } }.count) CATEGORIES")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(.horizontal, 22)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 9) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { favoritesOnly.toggle() }
                    } label: {
                        Label("Saved", systemImage: favoritesOnly ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(favoritesOnly ? .black : XSV3.amber)
                            .padding(.horizontal, 14)
                            .frame(height: 39)
                            .background(favoritesOnly ? XSV3.amber : XSV3.lifted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    categoryChip(title: "All Arabic", id: nil, count: arabicStreams.count)
                    ForEach(store.categories.filter { category in arabicStreams.contains { $0.categoryID == category.categoryID } }) { category in
                        let count = arabicStreams.lazy.filter { $0.categoryID == category.categoryID }.count
                        categoryChip(title: category.categoryName, id: category.categoryID, count: count)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
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
                RoundedRectangle(cornerRadius: 25)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.15, green: 0.19, blue: 0.26), XSCinemaStyle.background],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))

                XSSportsChannelArtworkV33(name: stream.name, logoURL: resolvedLogoURL(for: stream), compact: false)
                    .padding(.leading, 95)
                    .padding(.bottom, 30)
                    .opacity(0.86)

                LinearGradient(
                    colors: [.black.opacity(0.06), .black.opacity(0.22), .black.opacity(0.95)],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(.white).frame(width: 6, height: 6)
                        Text("LIVE NOW")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.red, in: Capsule())

                    Spacer(minLength: 6)

                    if let category = categoryName(for: stream.categoryID) {
                        Text(category.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(XSCinemaStyle.warm)
                            .lineLimit(1)
                    }
                    Text(stream.name)
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 27))
                        Text("Watch live")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                }
                .padding(21)
            }
            .frame(height: 278)
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.15)))
            .padding(.horizontal, 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch live: \(stream.name)")
    }

    private var sectionHeader: some View {
        HStack(alignment: .bottom, spacing: 9) {
            VStack(alignment: .leading, spacing: 6) {
                Text(favoritesOnly ? "YOUR SAVED STREAMS" : "ALL LIVE CHANNELS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2.1)
                    .foregroundStyle(XSV3.coral)
                Text(selectedCategoryID.flatMap(categoryName(for:))
                     ?? (favoritesOnly ? "Your favorites" : "Live channels"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("\(filteredStreams.count) CHANNELS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(.horizontal, 22)
    }

    private var channelGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 250), spacing: 13)], spacing: 20) {
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
        .padding(.horizontal, 22)
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
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Button(action: play) {
                    ZStack(alignment: .bottomLeading) {
                        XSSportsChannelArtworkV33(name: stream.name, logoURL: logoURL, compact: true)
                        LinearGradient(colors: [.clear, .black.opacity(0.40)], startPoint: .center, endPoint: .bottom)
                        Text("ON AIR")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.94), in: Capsule())
                            .padding(10)
                    }
                }
                .buttonStyle(XSV3PressStyle())

                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFavorite ? XSCinemaStyle.warm : .white)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.69), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.17)))

            Button(action: play) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(stream.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let category {
                        Text(category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(XSCinemaStyle.secondary)
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
    @State private var controlsHideTask: Task<Void, Never>?

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
                .allowsHitTesting(false)

            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    revealControls()
                }

            if model.statusText != "Live" && model.statusText != "Paused" {
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
                    .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            model.start()
            revealControls()
        }
        .onDisappear {
            controlsHideTask?.cancel()
            model.stop()
        }
    }

    private func revealControls() {
        controlsHideTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = true }
        }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { controlsVisible = false }
        }
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

                Button {
                    revealControls()
                    model.reload()
                } label: {
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
                                revealControls()
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

                Button {
                    revealControls()
                    model.togglePlayPause()
                } label: {
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
        view.isUserInteractionEnabled = false
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = false
        if player.drawable as AnyObject? !== uiView {
            player.drawable = uiView
        }
    }
}
