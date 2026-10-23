"""Run the production catalogue actor against real source-title metadata."""
from pathlib import Path
import subprocess,tempfile
service=Path('FrameNative/Services/XSCinemaNativeSource.swift').read_text().split('@MainActor\nfinal class XSCinemaNativeStore')[0].replace('import SwiftUI\n','')
main=r'''
import Foundation
@main struct MetadataTest {
    static func main() async {
        let source = XSCinemaMedia(id:"etwatch:series:1396",title:"Breaking Bad",kind:.series,
            poster:nil,backdrop:nil,summary:"",year:"2008",rating:9,
            playableURL:nil,sourceURL:"https://www.etwatch.net/series/1396-breaking-bad-2008",
            licenseURL:nil,imdbID:nil,episodes:[])
        let details = await XSCinemaCatalogAPI.shared.detail(source)
        precondition(details.id == source.id, "Source identity changed")
        precondition(details.sourceURL == source.sourceURL, "Source navigation changed")
        precondition(details.imdbID == "tt0903747", "Failed to resolve the exact source title")
        precondition(Set(details.episodes.map(\.season)) == Set([1,2,3,4,5]), "Missing seasons")
        precondition(details.episodes.contains { $0.season == 2 && $0.number == 3 }, "Missing exact episode")
        print("V27 live native metadata PASS: source title resolved, five seasons, exact S2 E3, stable identity")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='v27-metadata-') as directory:
    folder=Path(directory)
    (folder/'Service.swift').write_text(service)
    (folder/'Main.swift').write_text(main)
    subprocess.run(['swiftc','-parse-as-library','FrameNative/Core/XSETWatchRoutes.swift',str(folder/'Service.swift'),str(folder/'Main.swift'),'-o',str(folder/'metadata-test')],check=True,timeout=60)
    subprocess.run([str(folder/'metadata-test')],check=True,timeout=90)
