import SwiftUI
import AVKit

// V18 native, read-only Febbox library. Reads each folder/page on demand.
// No browser/WebView and no user login form are required to browse public
// shares; the source owner retains control of shared content and playback.
struct XSFebboxLibraryView: View {
    @State private var shelf: XSFebboxShelf = .movies

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill.badge.person.crop")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.purple.opacity(0.40), in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("مكتبة Febbox")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("مشاركة MovieBoy — فهرس متجدد مباشرة من المصدر")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                    Spacer(minLength: 0)
                }
                Picker("المحتوى", selection: $shelf) {
                    ForEach(XSFebboxShelf.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.purple)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            XSFebboxFolderView(shelf: shelf, folderID: "0", folderTitle: shelf.title)
                .id(shelf.id)
        }
        .background(Color(red: 0.042, green: 0.045, blue: 0.066).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private final class XSFebboxFolderModel: ObservableObject {
    @Published var entries: [XSFebboxEntry] = []
    @Published var loading = false
    @Published var error: String?
    @Published var more = true
    private var next = 1
    private var requested = Set<Int>()

    func load(shelf: XSFebboxShelf, folderID: String, reset: Bool = false) async {
        if reset {
            guard !loading else { return }
            next = 1
            requested.removeAll()
            entries = []
            more = true
            error = nil
        }
        guard !loading, more, !requested.contains(next) else { return }
        loading = true
        let current = next
        requested.insert(current)
        defer { loading = false }
        do {
            let page = try await XSFebboxLibraryService.shared.page(
                shelf: shelf, parent: folderID, number: current, force: reset)
            guard !Task.isCancelled else { return }
            let existing = Set(entries.map(\.id))
            entries += page.entries.filter { !existing.contains($0.id) }
            next = current + 1
            more = page.hasNext
            error = nil
        } catch {
            requested.remove(current)
            self.error = error.localizedDescription
        }
    }
}

private struct XSFebboxFolderView: View {
    let shelf: XSFebboxShelf
    let folderID: String
    let folderTitle: String

    @StateObject private var model = XSFebboxFolderModel()
    @State private var search = ""

    private var filtered: [XSFebboxEntry] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return model.entries }
        return model.entries.filter { $0.name.localizedStandardContains(term) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                if folderID != "0" {
                    HStack {
                        Text(folderTitle)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(model.entries.count) عنصر")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.vertical, 10)
                }
                if let error = model.error {
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8))
                        Button("إعادة المحاولة") {
                            Task { await model.load(shelf: shelf, folderID: folderID) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                }
                ForEach(filtered) { file in
                    if file.isDirectory {
                        NavigationLink {
                            XSFebboxFolderView(
                                shelf: shelf, folderID: file.fid, folderTitle: file.name)
                        } label: {
                            XSFebboxFileRow(file: file)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            XSFebboxFileDetailsView(file: file)
                        } label: {
                            XSFebboxFileRow(file: file)
                        }
                        .buttonStyle(.plain)
                    }
                    if file.id == model.entries.last?.id, search.isEmpty, model.more {
                        Color.clear.frame(height: 1)
                            .onAppear {
                                Task { await model.load(shelf: shelf, folderID: folderID) }
                            }
                    }
                }
                if model.loading {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(model.entries.isEmpty ? "جارٍ جلب المحتوى من Febbox…" : "جارٍ تحميل المزيد…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                if !model.loading && model.entries.isEmpty && model.error == nil {
                    VStack(spacing: 9) {
                        Image(systemName: "folder")
                            .font(.system(size: 28))
                        Text("المجلد فارغ")
                            .font(.subheadline.bold())
                        Text("لا توجد ملفات في هذا المجلد حالياً.")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
                if !model.loading && model.more && !model.entries.isEmpty && !search.isEmpty {
                    Text("البحث يشمل العناصر المحملة في هذا المجلد فقط")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding()
                }
                if folderID == "0" && !model.entries.isEmpty {
                    Text("Febbox • يتم تحديث المجلدات تدريجياً ولا تُنزّل الفيديوهات على جهازك.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $search, prompt: "بحث في هذا المجلد")
        .refreshable { await model.load(shelf: shelf, folderID: folderID, reset: true) }
        .task { await model.load(shelf: shelf, folderID: folderID) }
        .navigationTitle(folderID == "0" ? shelf.title : folderTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct XSFebboxFileRow: View {
    let file: XSFebboxEntry

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.08))
                if let image = file.thumbnail {
                    AsyncImage(url: image) { result in
                        if let photo = result.image {
                            photo.resizable().scaledToFill()
                        } else {
                            Image(systemName: file.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(file.isDirectory ? .yellow : .white.opacity(0.75))
                        }
                    }
                    .frame(width: 68, height: 67)
                    .clipped()
                } else {
                    Image(systemName: file.icon)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(file.isDirectory ? .yellow : .white.opacity(0.72))
                }
            }
            .frame(width: 68, height: 67)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(file.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Text(file.isDirectory ? "مجلد" :
                        file.durationSeconds > 0 ? durationLabel : file.fileExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.59))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    }

    private var durationLabel: String {
        let time = Int(file.durationSeconds)
        return time >= 3600 ? "\(time/3600) س \(time%3600/60) د" : "\(time/60) د"
    }
}

struct XSFebboxFileDetailsView: View {
    let file: XSFebboxEntry

    @State private var qualities: [XSFebboxQuality] = []
    @State private var loading = false
    @State private var playbackError: String?
    @State private var selectedQuality: XSFebboxQuality?
    @State private var signInRequired = false
    @State private var showAccount = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 15) {
                    Image(systemName: file.icon)
                        .font(.system(size: 34))
                        .foregroundStyle(.pink)
                        .frame(width: 62, height: 62)
                        .background(.white.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(file.name)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text("Febbox · \(file.fileExtension.uppercased())")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                if file.playable {
                    if loading {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("جارٍ التحقق من روابط التشغيل المسموح بها…")
                                .foregroundStyle(.white.opacity(0.68))
                        }
                    }
                    ForEach(qualities) { variant in
                        Button {
                            selectedQuality = variant
                        } label: {
                            Label("تشغيل · \(variant.name)", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let playbackError {
                        Label(playbackError, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if signInRequired {
                            Button {
                                showAccount = true
                            } label: {
                                Label("تسجيل الدخول إلى Febbox للتشغيل", systemImage: "person.crop.circle.badge.checkmark")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Link(destination: file.shelf.publicSharePage) {
                            Label("فتح مشاركة Febbox الأصلية", systemImage: "arrow.up.right.square")
                        }
                        .font(.footnote.bold())
                    }
                } else if file.subtitles {
                    Label("هذا ملف ترجمة من المصدر. اختيار الترجمة مرتبط بملف الفيديو الأصلي.",
                          systemImage: "captions.bubble")
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Label("الملف متاح للفهرسة، لكن نوعه لا يدعم تشغيل الفيديو مباشرة.",
                          systemImage: "doc")
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("المحتوى مقدم عبر Febbox. تُستخدم روابط التشغيل المتاحة من المصدر فقط؛ لا يجري نسخ الملفات أو تجاوز صلاحيات الحساب.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(18)
        }
        .background(Color(red: 0.042, green: 0.045, blue: 0.066).ignoresSafeArea())
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard file.playable, qualities.isEmpty else { return }
            await loadPlaybackLinks()
        }
        .sheet(isPresented: $showAccount, onDismiss: {
            Task { await loadPlaybackLinks() }
        }) {
            XSFebboxAccountView()
        }
        .fullScreenCover(item: $selectedQuality) { option in
            XSFebboxVLCPlaybackView(quality: option)
        }
    }
    private func loadPlaybackLinks() async {
        guard !loading else { return }
        loading = true
        playbackError = nil
        defer { loading = false }
        do {
            let links = try await XSFebboxLibraryService.shared.publicVideoQualities(for: file)
            qualities = links
            signInRequired = false
        } catch {
            qualities = []
            signInRequired = (error as? XSFebboxError).map {
                if case .signInRequired = $0 { return true }
                return false
            } ?? false
            playbackError = error.localizedDescription
        }
    }

}
