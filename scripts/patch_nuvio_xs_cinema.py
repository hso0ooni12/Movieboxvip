#!/usr/bin/env python3
"""Apply XS TV Cinema proof-of-concept customizations to NuvioMobile."""
from pathlib import Path
import shutil, plistlib, sys
upstream=Path(sys.argv[1]).resolve()
xsrepo=Path(sys.argv[2]).resolve()
path=upstream/"composeApp/src/iosMain/kotlin/com/nuvio/app/features/addons/AddonPlatform.ios.kt"
data=path.read_text()
start=data.index("    actual fun loadInstalledAddonUrls(profileId: Int): List<String> =")
end=data.index("    actual fun saveInstalledAddonUrls(profileId: Int, urls: List<String>) {",start)
replacement='''    // XS TV: seed only if no addons list has ever been saved for this profile.
    // An intentionally empty saved list stays empty if user removes addons.
    actual fun loadInstalledAddonUrls(profileId: Int): List<String> {
        val saved = NSUserDefaults.standardUserDefaults
            .stringForKey("installed_manifest_urls_$profileId")
        if (saved == null) return listOf(
            "https://v3-cinemeta.strem.io/manifest.json",
            "https://caching.stremio.net/publicdomainmovies.now.sh/manifest.json",
            "https://watchhub.strem.io/manifest.json",
            "https://opensubtitles-v3.strem.io/manifest.json",
        )
        return saved.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()
    }

'''
data=data[:start]+replacement+data[end:]
path.write_text(data)
config_path=upstream/"iosApp/Configuration/Config.xcconfig"
cfg=config_path.read_text()
assert "PRODUCT_BUNDLE_IDENTIFIER=com.nuvio.app.Nuvio$(TEAM_ID)" in cfg
config_path.write_text(cfg.replace("PRODUCT_BUNDLE_IDENTIFIER=com.nuvio.app.Nuvio$(TEAM_ID)",
                                   "PRODUCT_BUNDLE_IDENTIFIER=com.xstv.cinema.preview"))
# Xcode target build settings override Config.xcconfig's bundle ID, so
# update Release AND Debug, including the optional widget extension.
pbx=upstream/"iosApp/iosApp.xcodeproj/project.pbxproj"
project=pbx.read_text()
bundle_ids={
    "PRODUCT_BUNDLE_IDENTIFIER = com.nuvio.media;":
        "PRODUCT_BUNDLE_IDENTIFIER = com.xstv.cinema.preview;",
    "PRODUCT_BUNDLE_IDENTIFIER = com.nuvio.app;":
        "PRODUCT_BUNDLE_IDENTIFIER = com.xstv.cinema.preview;",
    "PRODUCT_BUNDLE_IDENTIFIER = com.nuvio.media.DownloadsWidgetExtension;":
        "PRODUCT_BUNDLE_IDENTIFIER = com.xstv.cinema.preview.DownloadsWidgetExtension;",
    "PRODUCT_BUNDLE_IDENTIFIER = com.nuvio.app.DownloadsWidgetExtension;":
        "PRODUCT_BUNDLE_IDENTIFIER = com.xstv.cinema.preview.DownloadsWidgetExtension;",
}
for original,new in bundle_ids.items():
    assert original in project, f"Expected Xcode setting not found: {original}"
    project=project.replace(original,new)
assert project.count("PRODUCT_BUNDLE_IDENTIFIER = com.xstv.cinema.preview;") == 2
assert project.count("PRODUCT_BUNDLE_IDENTIFIER = com.xstv.cinema.preview.DownloadsWidgetExtension;") == 2
pbx.write_text(project)
plist_path=upstream/"iosApp/iosApp/Info.plist"
with plist_path.open("rb") as f: info=plistlib.load(f)
info["CFBundleDisplayName"]="XS TV Cinema"
info["CFBundleName"]="XS TV Cinema"
with plist_path.open("wb") as f: plistlib.dump(info,f,sort_keys=False)
source_icon=xsrepo/"StreamWeb/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
target_icon=upstream/"iosApp/iosApp/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png"
assert source_icon.exists()
shutil.copyfile(source_icon,target_icon)
(upstream/"XS_TV_CINEMA_README.md").write_text("""# XS TV Cinema / Nuvio proof of concept

This iOS app uses NuvioMobile (GNU GPLv3) and user-manageable Stremio
addon URLs on first run:
- Cinemeta: global metadata catalog; no video guarantee.
- Public Domain Movies: independently hosted public-domain torrent source,
  about 500 titles claimed; requires working peers.
- WatchHub: legal streaming availability; some links are paid.
- OpenSubtitles v3: third-party movie/series subtitles.
The sources and quality are independent and can change. Not all catalog
items have playback streams, nor do they guarantee Arabic subtitles.
The original separate XS TV sports app is NOT replaced by this build,
which does not yet embed sports. Keep the old sports app installed.
Source attribution: https://github.com/NuvioMedia/NuvioMobile
GPLv3 compliance is required if redistributing modified binaries.
""",encoding="utf-8")
assert "opensubtitles-v3.strem.io/manifest.json" in data
print("XS TV Cinema: configured original icon, bundle ID and first-run addons")
