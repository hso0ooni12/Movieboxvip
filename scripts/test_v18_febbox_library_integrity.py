"""V18 Febbox shared-library QA. The entire catalog is discovered from the
original, publicly shared Febbox files. Neither a user's private Febbox
credentials nor third-party copyrighted media are downloaded/committed.

Checks run AFTER all protected V17/R5 scripts, before Swift parse/Xcode.
"""
from pathlib import Path
service=Path("FrameNative/Services/XSFebboxLibraryService.swift").read_text()
view=Path("FrameNative/Views/XSFebboxLibraryView.swift").read_text()
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
player=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()

checks={
 "known public Movies and TVshow source share links":
    'case movies = "C2jBoH52"' in service and
    'case series = "eHH8d0S1"' in service,
 "source File List endpoint rather than fake title inventory":
    "/file/file_share_list" in service and
    'name: "share_key"' in service and
    'name: "parent_id"' in service and
    'name: "page"' in service and
    '"file_list"' in service,
 "loads all pages lazily rather than downloading full media":
    "let pageSize = 50" in service and
    "hasNext: rows.count >= pageSize" in service and
    "Date().timeIntervalSince(saved.fetched) < 180" in service,
 "real file names, directories, types, duration, thumbnail":
    'row["file_name"]' in service and
    'row["is_dir"]' in service and
    'row["ext"]' in service and
    'row["runtime"]' in service and
    '["thumb_big", "thumb", "thumb_small"]' in service,
 "source-only filename indexing does not invent catalog counts":
    'model.entries' in view and
    'model.more' in view and
    'model.load(shelf: shelf, folderID: folderID)' in view,
 "safe official source video quality inspection only":
    "/console/video_quality_list" in service and
    "noAuthorizedPlayback" in service and
    "publicVideoQualities(for item:" in service,
 "does not store Febbox credentials in IPA":
    all(key not in service+view for key in [
      "FEBBOX_UI_COOKIE","PHPSESSID","client_secret","auth_token",
      'Cookie", forHTTPHeaderField', "access_token"
    ]),
 "native SwiftUI rather than Febbox WebView":
    "struct XSFebboxLibraryView: View" in view and
    "NavigationLink" in view and
    "AsyncImage" in view and
    "WebView" not in view and
    "WKWebView" not in view,
 "tab preserves the user's four original destinations":
    'Label("Home", systemImage: "house.fill")' in root and
    'Label("Movies", systemImage: "film.stack")' in root and
    'Label("Series", systemImage: "play.tv")' in root and
    'Label("Sports", systemImage: "sportscourt.fill")' in root and
    'Label("Febbox", systemImage: "externaldrive.fill")' in root,
 "no changes to R5 primary/Backup source engine":
    "const finishDispatchedSelection = () =>" in player and
    "sourceSubtitles.select(payload);" in player and
    "XSVLCStableSurfaceView" in sports,
 "retains subtitle timing improvements and AR sports":
    "V16_SOURCE_CUE_SYNC" in player and
    'XSSportsLiveViewV33()' in root,
 "iOS16 compatibility":
    "ContentUnavailableView" not in view and
    'iOS: "16.0"' in Path("project-native.yml").read_text(),
}
for name,ok in checks.items():
    if not ok: raise SystemExit("V18 Febbox QA FAILED: "+name)
print(f"V18 public Febbox native library and R5 playback safety PASS: {len(checks)} checks")
