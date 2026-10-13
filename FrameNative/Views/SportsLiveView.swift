import SwiftUI
import AVKit
import UIKit

private let xsSportsAccent = Color(red: 1.0, green: 0.12, blue: 0.38)

struct XSSportsLiveView: View {
    @StateObject private var store = IPTVSportsStore()
    @State private var query = ""
    @State private var selectedCategoryID: String? = nil
    @State private var showAccount = false
    @AppStorage("xs.iptv.favoriteStreamIDs") private var favoriteIDsRaw = ""

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
                IPTVConnectionView(store: store)
            } else if store.isLoading && store.streams.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(xsSportsAccent)
                    Text("Loading live sports…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                }
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
            if store.credentials != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccount = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .sheet(isPresented: $showAccount) {
            NavigationStack {
                IPTVAccountView(store: store)
            }
            .preferredColorScheme(.dark)
        }
        .task {
            guard store.credentials != nil, store.streams.isEmpty, !store.isLoading else { return }
            try? await store.refresh()
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
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
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { try? await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Live Sports")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text("Your sports channels, organized for fast live viewing.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
            }

            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.42))
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
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 9) {
                categoryChip(title: "All Sports", id: nil, count: store.streams.count)
                ForEach(store.categories) { category in
                    let count = store.streams.lazy.filter { $0.categoryID == category.categoryID }.count
                    categoryChip(title: category.categoryName, id: category.categoryID, count: count)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func categoryChip(title: String, id: String?, count: Int) -> some View {
        let selected = selectedCategoryID == id
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedCategoryID = id }
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? .black.opacity(0.62) : .white.opacity(0.48))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(selected ? Color.black.opacity(0.10) : Color.white.opacity(0.06), in: Capsule())
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(selected ? Color.white : Color.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(selected ? 0 : 0.10)))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private func featuredCard(_ stream: IPTVLiveStream) -> some View {
        NavigationLink {
            if let url = store.streamURL(for: stream) {
                IPTVLivePlayerView(stream: stream, url: url)
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.13, blue: 0.18), Color.black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let logo = stream.streamIcon, let url = URL(string: logo), !logo.isEmpty {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                                .padding(40)
                                .opacity(0.45)
                        }
                    }
                }

                LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.90), in: Capsule())
                        if let name = categoryName(for: stream.categoryID) {
                            Text(name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }

                    Text(stream.name)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Label("Watch Live", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(20)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10)))
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCategoryID.flatMap(categoryName(for:)) ?? "Sports Channels")
                    .font(.title3.bold())
                Text("\(filteredStreams.count) live channels")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.50))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var channelGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 16) {
            ForEach(filteredStreams) { stream in
                NavigationLink {
                    if let url = store.streamURL(for: stream) {
                        IPTVLivePlayerView(stream: stream, url: url)
                    }
                } label: {
                    IPTVChannelCard(
                        stream: stream,
                        category: categoryName(for: stream.categoryID),
                        isFavorite: favoriteIDs.contains(stream.streamID),
                        toggleFavorite: { toggleFavorite(stream.streamID) }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
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
        .padding(.horizontal, 20)
    }

    private func categoryName(for id: String) -> String? {
        store.categories.first(where: { $0.categoryID == id })?.categoryName
    }

    private func toggleFavorite(_ id: Int) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoriteIDsRaw = ids.sorted().map(String.init).joined(separator: ",")
    }
}

private struct IPTVChannelCard: View {
    let stream: IPTVLiveStream
    let category: String?
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.055))

                if let raw = stream.streamIcon, let url = URL(string: raw), !raw.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().padding(20)
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }

                VStack {
                    HStack {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.90), in: Capsule())
                        Spacer()
                        Button(action: toggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.52), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    }
                    Spacer()
                }
                .padding(9)
            }
            .aspectRatio(16/10, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10)))

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
        .contentShape(Rectangle())
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 28, weight: .semibold))
            Text("XS SPORTS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(.white.opacity(0.35))
    }
}

private struct IPTVConnectionView: View {
    @ObservedObject var store: IPTVSportsStore
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 30)

                ZStack {
                    Circle().fill(xsSportsAccent.opacity(0.16)).frame(width: 92, height: 92)
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(xsSportsAccent)
                }

                VStack(spacing: 8) {
                    Text("Connect Sports IPTV")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                    Text("Add your authorized Xtream Codes subscription once. XS TV keeps the credentials in the iPhone Keychain, not in the app project.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 12) {
                    connectionField(title: "Host / Server URL", icon: "globe", text: $host, secure: false)
                    connectionField(title: "Username", icon: "person", text: $username, secure: false)
                    connectionField(title: "Password", icon: "lock", text: $password, secure: true)

                    HStack(spacing: 10) {
                        Button {
                            parseClipboard()
                        } label: {
                            Label("Paste M3U URL", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(IPTVSecondaryButtonStyle())

                        Button {
                            connect()
                        } label: {
                            HStack(spacing: 8) {
                                if isConnecting { ProgressView().tint(.black) }
                                Text(isConnecting ? "Connecting…" : "Connect")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(IPTVPrimaryButtonStyle())
                        .disabled(isConnecting || !IPTVCredentials(host: host, username: username, password: password).isComplete)
                    }

                    if let message {
                        Text(message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10)))
                .frame(maxWidth: 620)

                Text("Use this feature only with IPTV services and channels you’re authorized to access.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.34))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func connectionField(title: String, icon: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.white.opacity(0.48))
            if secure {
                SecureField(title, text: text)
                    .textContentType(.password)
            } else {
                TextField(title, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)))
    }

    private func connect() {
        let credentials = IPTVCredentials(host: host, username: username, password: password)
        isConnecting = true
        message = nil
        Task {
            do {
                try await store.save(credentials: credentials)
            } catch {
                message = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func parseClipboard() {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: raw),
              let scheme = components.scheme,
              let hostName = components.host else {
            message = "Copy the M3U/Xtream URL first, then tap Paste M3U URL."
            return
        }
        var server = "\(scheme)://\(hostName)"
        if let port = components.port { server += ":\(port)" }
        let items = components.queryItems ?? []
        host = server
        username = items.first(where: { $0.name == "username" })?.value ?? username
        password = items.first(where: { $0.name == "password" })?.value ?? password
        message = nil
    }
}

private struct IPTVAccountView: View {
    @ObservedObject var store: IPTVSportsStore
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("IPTV Account") {
                TextField("Host", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text("Save & Refresh")
                    }
                }
                .disabled(isSaving || !IPTVCredentials(host: host, username: username, password: password).isComplete)

                Button("Disconnect IPTV", role: .destructive) {
                    store.disconnect()
                    dismiss()
                }
            }

            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Sports IPTV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            guard let credentials = store.credentials else { return }
            host = credentials.host
            username = credentials.username
            password = credentials.password
        }
    }

    private func save() {
        isSaving = true
        message = nil
        let credentials = IPTVCredentials(host: host, username: username, password: password)
        Task {
            do {
                try await store.save(credentials: credentials)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct IPTVLivePlayerView: View {
    let stream: IPTVLiveStream
    let url: URL

    @State private var player: AVPlayer
    @State private var statusText = "Connecting…"

    init(stream: IPTVLiveStream, url: URL) {
        self.stream = stream
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()

            VStack {
                HStack(spacing: 10) {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red, in: Capsule())
                    Text(stream.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55))

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            player.automaticallyWaitsToMinimizeStalling = true
            player.play()
            statusText = "Live"
        }
        .onDisappear { player.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled)) { _ in
            statusText = "Reconnecting…"
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                player.play()
                statusText = "Live"
            }
        }
    }
}

private struct IPTVPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.black)
            .frame(height: 46)
            .background(Color.white.opacity(configuration.isPressed ? 0.78 : 1.0), in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct IPTVSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(height: 46)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10)))
    }
}
