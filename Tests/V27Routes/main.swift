import Foundation

func route(_ source: String, series: Bool = false, season: Int? = nil, episode: Int? = nil) -> String? {
    XSETWatchRoutes.watchURL(source: URL(string: source)!, isSeries: series,
                            season: season, episode: episode)?.absoluteString
}
assert(route("https://www.etwatch.net/movie/9383-hollow-man-2000") == "https://www.etwatch.net/watch/movie/9383")
assert(route("https://etwatch.net/series/1396-breaking-bad-2008", series: true, season: 2, episode: 3) == "https://www.etwatch.net/watch/tv/1396/2/3")
assert(route("https://www.etwatch.net/series/1396-breaking-bad-2008", series: true, season: 5, episode: 16) == "https://www.etwatch.net/watch/tv/1396/5/16")
assert(route("https://www.etwatch.net/series/1396-breaking-bad-2008", series: true) == "https://www.etwatch.net/watch/tv/1396/1/1")
assert(route("https://www.etwatch.net/watch/movie/9383") == "https://www.etwatch.net/watch/movie/9383")
assert(route("https://www.etwatch.net/watch/tv/1396/1/1", series: true, season: 2, episode: 2) == "https://www.etwatch.net/watch/tv/1396/2/2")
assert(route("https://www.etwatch.net.evil.example/movie/9383-title") == nil)
assert(route("http://www.etwatch.net/movie/9383-title") == nil)
assert(route("https://www.etwatch.net/movie/not-an-id") == nil)
assert(route("https://www.etwatch.net/home") == nil)
assert(route("https://www.etwatch.net/movie/9383-title?redirect=https://evil.example") == "https://www.etwatch.net/watch/movie/9383")
print("V27 watch navigation PASS: 11 route, season/episode and URL validation cases")
