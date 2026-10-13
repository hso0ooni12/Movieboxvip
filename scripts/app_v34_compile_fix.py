from pathlib import Path

path = Path('FrameNative/Views/SportsLiveViewV33.swift')
text = path.read_text(encoding='utf-8')

old = '''        player.stop()
        let media = VLCMedia(url: urls[index])
        media.addOptions([
            "network-caching": 1400 as NSNumber,
            "live-caching": 1400 as NSNumber,
            "clock-jitter": 0 as NSNumber,
            "clock-synchro": 0 as NSNumber
        ])
        player.media = media
        player.rate = 1.0
        player.play()
'''

new = '''        player.stop()
        guard let media = VLCMedia(url: urls[index]) else {
            tryNextSource()
            return
        }
        media.addOptions([
            "network-caching": 1400 as NSNumber,
            "live-caching": 1400 as NSNumber,
            "clock-jitter": 0 as NSNumber,
            "clock-synchro": 0 as NSNumber
        ])
        player.media = media
        player.rate = 1.0
        player.play()
'''

if old not in text:
    raise SystemExit('V34 compile fix anchor missing')

path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('V34 optional VLCMedia compile fix applied')
