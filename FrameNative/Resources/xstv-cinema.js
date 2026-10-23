/* XS TV V27: retain the source's player, captions and controls as one surface. */
(function () {
  'use strict';
  if (window.__xstvCinemaReady) return;
  window.__xstvCinemaReady = true;
  const config = window.__xstvPlaybackConfig || {};
  let theater = null;
  let lastProgress = -20;
  let restored = false;
  let observer;
  let stopped = false;
  let scanPending = false;

  function post(event, video, extra) {
    try {
      window.webkit.messageHandlers.xstvVideoStatus.postMessage(Object.assign({
        event: event,
        seconds: video && Number.isFinite(video.currentTime) ? video.currentTime : 0,
        duration: video && Number.isFinite(video.duration) ? video.duration : 0
      }, extra || {}));
    } catch (_) {}
  }

  function playerFor(video) {
    return video.closest('.player-root,.jwplayer,.plyr,.video-js,.artplayer,.dplayer,[data-player-container]')
      || video.parentElement;
  }
  function candidate() {
    const videos = Array.from(document.querySelectorAll('video'));
    const video = videos.find(v => v.readyState > 0 && !v.paused)
      || videos.find(v => v.getBoundingClientRect().width > 100);
    if (video) return playerFor(video);
    // Preserve cross-origin player frames as complete frames, including captions.
    return Array.from(document.querySelectorAll('iframe[allow*="fullscreen"]'))
      .find(f => f.getBoundingClientRect().width > 240 && f.getBoundingClientRect().height > 100) || null;
  }
  window.__xstvEnterTheater = function () {
    const target = candidate();
    if (!target) return false;
    if (theater && theater !== target) theater.classList.remove('xstv-theater-player');
    theater = target;
    theater.classList.add('xstv-theater-player');
    document.documentElement.classList.add('xstv-cinema-on');
    post('theaterStarted');
    return true;
  };
  window.__xstvExitTheater = function () {
    if (theater) theater.classList.remove('xstv-theater-player');
    document.documentElement.classList.remove('xstv-cinema-on');
    theater = null;
    post('theaterStopped');
    return true;
  };

  function report(video, event) {
    if (event === 'timeupdate') {
      if (video.currentTime - lastProgress < 5 && video.currentTime >= lastProgress) return;
      lastProgress = video.currentTime;
    }
    if (!restored && video.readyState > 0 && Number(config.resumePosition) > 5) {
      const resume = Number(config.resumePosition);
      if (Number.isFinite(video.duration) && resume < video.duration - 8) {
        restored = true;
        try { video.currentTime = resume; } catch (_) {}
      }
    }
    post(event, video);
  }
  function scan() {
    scanPending = false;
    if (stopped) return;
    document.querySelectorAll('video').forEach(video => {
      if (video.__xstvObserved) return;
      video.__xstvObserved = true;
      video.playsInline = true;
      video.setAttribute('playsinline', '');
      video.setAttribute('webkit-playsinline', 'true');
      ['playing', 'timeupdate', 'pause', 'ended', 'waiting', 'stalled', 'error', 'loadedmetadata']
        .forEach(event => video.addEventListener(event, () => report(video, event), { passive: true }));
      if (video.readyState > 0) report(video, 'loadedmetadata');
    });
    if (theater && !theater.isConnected) window.__xstvExitTheater();
  }
  function start() {
    const css = document.createElement('style');
    css.id = 'xstv-cinema-style';
    css.textContent =
      '.xstv-theater-player{position:fixed!important;inset:0!important;z-index:2147483000!important;width:100vw!important;height:100dvh!important;max-width:none!important;max-height:none!important;transform:none!important;background:#000!important}' +
      '.xstv-theater-player video{width:100%!important;height:100%!important;max-width:100%!important;max-height:100%!important;object-fit:contain!important}' +
      'html.xstv-cinema-on,html.xstv-cinema-on body{overflow:hidden!important;background:#000!important}';
    (document.head || document.documentElement).appendChild(css);
    // Handle only the source player's fullscreen button. Subtitle, quality,
    // server and seek interactions continue through the site's own handlers.
    document.addEventListener('click', event => {
      const button = event.target.closest && event.target.closest('button[aria-label],button[title]');
      if (!button || !button.closest('.player-root,.jwplayer,.plyr,.video-js,.artplayer,.dplayer')) return;
      const label = (button.getAttribute('aria-label') || button.getAttribute('title') || '').trim();
      if (!/^(fullscreen|exit fullscreen|enter fullscreen|ملء الشاشة|خروج من ملء الشاشة)$/i.test(label)) return;
      const success = theater ? window.__xstvExitTheater() : window.__xstvEnterTheater();
      if (success) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    }, true);
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && theater) window.__xstvExitTheater();
    });
    observer = new MutationObserver(() => {
      if (!scanPending) { scanPending = true; queueMicrotask(scan); }
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    scan();
  }
  window.__xstvPause = function () {
    document.querySelectorAll('video').forEach(v => { report(v, 'pause'); v.pause(); });
  };
  window.addEventListener('pagehide', () => { stopped = true; if (observer) observer.disconnect(); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
