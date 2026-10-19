/* FrameXTV source-owned subtitle adapter. No inferred URLs or provider indexes.
 * The public CC menu owns selection, loading, parsing and the default renderer.
 * Kept independent of Swift so the DOM/async boundary can be regression tested.
 */
function createXSSourceSubtitles(env) {
  const {document: doc, window: win, findVideo, emit} = env;
  const frameID = env.frameID || 'source-' + (win.crypto.randomUUID ? win.crypto.randomUUID() : Math.random().toString(36).slice(2));
  let generation = 0, catalog = [], pending = null, active = null, opening = null;
  let lastVideo = null, lastSource = '', lastCaption = '', delay = 0, disposed = false;
  let timingTrack = null;
  // V12: FrameXTV can render React DOM captions without TextTrack cues.
  // Record real caption events at video media-time for positive delays.
  let sourceCaptionHistory = [];
  let sourceCaptionLast = null;
  let sourceCaptionLastTime = -1;
  let lastTimingMode = "";
  let lastTimingOffset = 0;
  let style = {size: 1, color: '#ffffff', background: true, bottom: 76};
  const timers = new Set();
  const text = el => String(el && el.textContent || '').replace(/\s+/g, ' ').trim();
  const normal = s => String(s || '').replace(/\s+/g, ' ').trim();
  const later = (fn, ms) => {
    const id = win.setTimeout(() => { timers.delete(id); if (!disposed) fn(); }, ms);
    timers.add(id); return id;
  };
  const send = payload => emit({...payload, frameID, generation});
  const buttons = root => Array.from(root.querySelectorAll('button'));
  function label(row) {
    // FrameXTV's first span is the label; a separate sibling contains ✓.
    const first = Array.from(row.children).find(el => el.tagName === 'SPAN');
    return normal(first ? text(first) : text(row).replace(/\s*[✓✔]\s*$/, ''));
  }
  function isChecked(row) {
    return row.getAttribute('aria-checked') === 'true' || row.getAttribute('aria-selected') === 'true' ||
      Array.from(row.children).some(el => /^[✓✔]$/.test(text(el)));
  }
  function ccButton() {
    return doc.querySelector('button[title="Subtitles / Captions"]') ||
      buttons(doc).find(el => /^(subtitles?|captions?)(\s*\/\s*captions?)?$/i.test(el.getAttribute('title') || el.getAttribute('aria-label') || '')) || null;
  }
  function panel() {
    const cc = ccButton();
    if (!cc || !cc.parentElement) return null;
    // Only the CC button's own popup, never a body-wide matching label.
    for (const off of buttons(cc.parentElement).filter(b => label(b) === 'Off')) {
      const root = off.parentElement;
      if (!root || root.contains(cc) || root.querySelector('video,iframe')) continue;
      if (Array.from(root.querySelectorAll('span')).some(el => text(el) === 'Subtitles')) return root;
    }
    return null;
  }
  function hidePanels() {
    const cc = ccButton();
    if (cc) {
      const chrome = cc.closest('div.absolute.inset-x-0.bottom-0');
      if (chrome && !chrome.querySelector('video,iframe')) chrome.setAttribute('data-xs-source-panel', '1');
    }
    for (const chrome of doc.querySelectorAll('div.absolute.inset-x-0.top-0')) {
      if (chrome.querySelector('button') && !chrome.querySelector('video,iframe')) chrome.setAttribute('data-xs-source-panel', '1');
    }
    const p = panel();
    if (p) p.setAttribute('data-xs-source-panel', '1');
    // Server/settings panels have an exact heading and no playback descendants.
    for (const heading of doc.querySelectorAll('span')) {
      if (!/^(Select Server|Playback Settings)$/.test(text(heading))) continue;
      const p = heading.parentElement && heading.parentElement.parentElement;
      if (p && p !== doc.body && p.querySelector('button') && !p.querySelector('video,iframe')) p.setAttribute('data-xs-source-panel', '1');
    }
    if (!doc.head) return;
    let css = doc.getElementById('xs-source-ui-style');
    if (!css) { css = doc.createElement('style'); css.id = 'xs-source-ui-style'; doc.head.appendChild(css); }
    const rules = '[data-xs-source-panel="1"]{opacity:0!important;pointer-events:none!important}' +
      'video::cue{font-size:' + Math.round(22 * style.size) + 'px!important;color:' + style.color + '!important;background:' + (style.background ? 'rgba(0,0,0,.68)' : 'transparent') + '!important}';
    if (css.textContent !== rules) css.textContent = rules;
  }
  function rows() {
    const p = panel();
    if (!p) return null;
    const occurrences = new Map();
    return buttons(p).filter(b => b.parentElement === p).map(row => {
      const name = label(row), occurrence = occurrences.get(name) || 0;
      occurrences.set(name, occurrence + 1);
      return {id: frameID + ':' + generation + ':' + encodeURIComponent(name) + ':' + occurrence,
        label: name, occurrence, row, checked: isChecked(row)};
    }).filter(it => it.label && it.label !== '✕');
  }

  // V11_ALL_SOURCE_SUBTITLES: every source-owned row remains selectable,
  // including alternate tracks, SDH/CC, Arabic variants and other languages.
  // Keep occurrences and ordering; only Off is rendered separately in Swift.
  function visibleCatalog() {
    return catalog.filter(item => item.label && item.label !== 'Off');
  }
  function publish(final) {
    const current = rows();
    if (current) catalog = current;
    if (!ccButton()) return; // Empty wrapper/advertising frames cannot overwrite the owner.
    send({event: 'xs:subtitles', final: !!final, items: visibleCatalog().map(it => ({
      id: it.id, label: it.label, language: '', source: 'source-menu', frameID, index: null
    }))});
    hidePanels();
  }
  function ensureMenu() {
    if (panel()) return Promise.resolve(true);
    if (opening) return opening;
    const cc = ccButton();
    if (!cc) return Promise.resolve(false);
    const epoch = generation;
    opening = new Promise(resolve => {
      cc.click(); // A single normal click invokes the site's own React handler.
      // Most source builds mount the menu synchronously. Read it immediately so
      // the native panel does not wait for an arbitrary timer before it can
      // show the exact source-owned subtitle list.
      if (panel()) { hidePanels(); resolve(true); return; }
      let tries = 0;
      const check = () => {
        if (epoch !== generation || disposed) return resolve(false);
        if (panel()) { hidePanels(); return resolve(true); }
        if (++tries >= 20) return resolve(false);
        // Be eager during the source UI's normal first render, then retain the
        // original slower polling window for devices where its React popup is
        // mounted later.
        later(check, tries < 8 ? 40 : 75);
      };
      later(check, 0);
    }).finally(() => { opening = null; });
    return opening;
  }
  async function scan() {
    const epoch = generation;
    if (await ensureMenu()) { if (epoch === generation) publish(true); }
    else if (epoch === generation) publish(true);
  }
  function tracks() {
    const v = findVideo();
    return Array.from(v && v.textTracks || []).filter(t => /^(subtitles|captions)$/.test(t.kind) && t.mode !== 'disabled' && t.cues && t.cues.length);
  }
  function trackFor(item) {
    // The site sometimes appends (SDH) / (Uploaded) to a menu choice while
    // the loaded TextTrack exposes the base language. The checked source row
    // remains mandatory before we report a successful track load.
    const clean = value => normal(value).replace(/ \((?:In-Stream|Uploaded|SDH|CC|Forced|Hearing Impaired)\)$/i, '').toLowerCase();
    const wanted = clean(item.label);
    return tracks().find(t => clean(t.label || t.language) === wanted ||
      ((!t.label || t.label === 'Subtitles') && clean(t.language) === wanted)) || null;
  }
  function caption(value) {
    if (value === lastCaption) return;
    lastCaption = value;
    send({event: 'xs:caption', text: value});
  }
  function sourceCaptionNodes() {
    // This is the source player's dedicated cue div, not the controls or menus.
    return Array.from(doc.querySelectorAll('div.pointer-events-none.text-center[style]')).filter(el =>
      !!el.style.textShadow && !el.querySelector('button,video,iframe'));
  }
  function timingStatus(mode) {
    if (mode === lastTimingMode && delay === lastTimingOffset) return;
    lastTimingMode = mode;
    lastTimingOffset = delay;
    send({event:'xs:subtitleTimingStatus', mode, offset:delay});
  }
  function captureSourceCaption(video) {
    if (!video || !active) return false;
    const time = Number(video.currentTime || 0);
    if (!Number.isFinite(time)) return false;
    if (sourceCaptionLastTime >= 0 && time < sourceCaptionLastTime - 1.5) {
      sourceCaptionHistory = [];
      sourceCaptionLast = null;
    }
    sourceCaptionLastTime = time;
    const names = [];
    for (const node of sourceCaptionNodes()) {
      const value = normal(node.textContent);
      if (value && !names.includes(value)) names.push(value);
    }
    const cue = names.join('\n');
    if (cue !== sourceCaptionLast) {
      sourceCaptionLast = cue;
      sourceCaptionHistory.push({at:time, text:cue});
    }
    while (sourceCaptionHistory.length > 300 || (sourceCaptionHistory.length &&
      sourceCaptionHistory[0].at < time - 90)) {
      sourceCaptionHistory.shift();
    }
    return names.length > 0 || sourceCaptionHistory.length > 0;
  }
  function delayedSourceCaption(at) {
    let low=0, high=sourceCaptionHistory.length-1, match=-1;
    while (low<=high) {
      const mid=(low+high)>>>1;
      if (sourceCaptionHistory[mid].at<=at) { match=mid;low=mid+1; }
      else high=mid-1;
    }
    return match<0 ? '' : sourceCaptionHistory[match].text;
  }
  function applyStyle() {
    hidePanels();
    const customTiming = delay !== 0 && active &&
      (trackFor(active) || (delay > 0 && sourceCaptionNodes().length > 0));
    for (const el of sourceCaptionNodes()) {
      el.style.setProperty('font-size', Math.round(22 * style.size) + 'px', 'important');
      // Keep rendered cues legible on 4K/SD sources and within video width.
      el.style.setProperty('max-width', '92%', 'important');
      el.style.setProperty('line-height', '1.32', 'important');
      el.style.setProperty('text-shadow', '0 1px 3px rgba(0,0,0,.90),0 2px 6px rgba(0,0,0,.55)', 'important');
      el.style.setProperty('color', style.color, 'important');
      el.style.setProperty('bottom', style.bottom + 'px', 'important');
      el.style.setProperty('background-color', style.background ? 'rgba(0,0,0,.68)' : 'transparent', 'important');
      if (customTiming) el.style.setProperty('opacity', '0', 'important');
      else el.style.removeProperty('opacity');
    }
  }
  function reportCaption() {
    const v = findVideo();
    if (!active || !v || !delay) {
      if (timingTrack && timingTrack.mode === 'hidden') {
        try { timingTrack.mode = 'showing'; } catch (_) {}
      }
      timingTrack = null;
      caption('');
      timingStatus(!delay ? 'idle' : 'waiting');
      applyStyle();
      return;
    }
    // Capture original source DOM text before suppressing it; native Swift
    // draws only the delayed line, without touching the video/audio pipeline.
    const hasSourceDom = captureSourceCaption(v);
    const selectedTrack = trackFor(active);
    if (timingTrack && timingTrack !== selectedTrack) {
      if (timingTrack.mode === 'hidden') {
        try { timingTrack.mode = 'showing'; } catch (_) {}
      }
      timingTrack = null;
    }
    if (selectedTrack && selectedTrack.mode === 'showing') {
      timingTrack = selectedTrack;
      selectedTrack.mode = 'hidden';
    }
    if (selectedTrack && selectedTrack.cues) {
      const at = Number(v.currentTime || 0) + delay;
      const cues = selectedTrack.cues;
      let low=0, high=cues.length-1, match=-1;
      while (low<=high) {
        const mid=(low+high)>>>1;
        if (cues[mid].startTime<=at) { match=mid; low=mid+1; }
        else high=mid-1;
      }
      const lines=[];
      for (let i=Math.max(0,match-4);i<=match;i++) {
        const cue=cues[i];
        if (cue.startTime<=at && at<cue.endTime) lines.push(cue.text||'');
      }
      caption(lines.join('\n'));
      timingStatus('cues');
    } else if (delay > 0 && hasSourceDom) {
      caption(delayedSourceCaption(Number(v.currentTime || 0)-delay));
      timingStatus('buffered');
    } else {
      caption('');
      timingStatus('unsupported');
    }
    applyStyle();
  }
  function reset() {
    // Switching a provider must restore any text track hidden by our
    // non-zero delay renderer. Keep the chosen delay within this movie/episode;
    // Swift resets it to zero when a NEW content item starts.
    if (timingTrack && timingTrack.mode === 'hidden') {
      try { timingTrack.mode = 'showing'; } catch (_) {}
    }
    timingTrack = null;
    generation++; pending = null; active = null; catalog = []; caption('');
    sourceCaptionHistory = []; sourceCaptionLast = null; sourceCaptionLastTime = -1;
    lastTimingMode = '';
    if (ccButton()) send({event: 'xs:subtitles', final: false, items: []});
  }
  function observeSource() {
    const v = findVideo();
    const src = v && (v.currentSrc || v.getAttribute('src')) || '';
    if ((lastVideo && v && lastVideo !== v) || (lastSource && src && lastSource !== src)) reset();
    if (v) lastVideo = v;
    if (src) lastSource = src;
  }
  function finishFailure(request, message) {
    if (pending !== request) return;
    pending = null; active = null; caption('');
    // Do not let a provider's failed-file fallback silently display another language.
    const off = (rows() || []).find(it => it.label === 'Off');
    if (off && !off.checked) off.row.click();
    send({event: 'xs:subtitleSelectionFailed', requestID: request.requestID, id: request.id, message});
  }
  async function select(payload) {
    if (payload.frameID !== frameID) return;
    observeSource();
    const wanted = payload.id === 'off' ? {id: 'off', label: 'Off'} : catalog.find(it => it.id === payload.id);
    const request = {requestID: payload.requestID, id: payload.id, epoch: generation};
    pending = request; active = null; caption('');
    sourceCaptionHistory = []; sourceCaptionLast = null; sourceCaptionLastTime = -1;
    lastTimingMode = '';
    if (!wanted) { finishFailure(request, 'This subtitle list changed. Open Subtitles again.'); return; }
    if (!await ensureMenu() || pending !== request || request.epoch !== generation) {
      finishFailure(request, 'Could not open the source subtitle menu. Try again.'); return;
    }
    const choice = (rows() || []).find(it => wanted.id === 'off' ? it.label === 'Off' : it.id === wanted.id);
    if (!choice) { finishFailure(request, 'This subtitle is no longer available on this server.'); return; }
    choice.row.click();
    let tries = 0;
    const verify = async () => {
      if (pending !== request || request.epoch !== generation) return;
      // Re-open without re-clicking the selection to read the source's real ✓ state.
      await ensureMenu();
      if (pending !== request || request.epoch !== generation) return;
      const current = rows() || [];
      const selected = current.find(it => it.checked);
      const match = selected && (wanted.id === 'off' ? selected.label === 'Off' : selected.id === wanted.id);
      const loaded = wanted.id === 'off' ? tracks().length === 0 : !!trackFor(choice);
      if (match && loaded) {
        pending = null; active = wanted.id === 'off' ? null : choice;
        send({event: 'xs:subtitleSelected', requestID: request.requestID, id: wanted.id});
        reportCaption(); return;
      }
      if (++tries >= 60) { finishFailure(request, 'The source could not load this subtitle. Try another subtitle or server.'); return; }
      // Confirm fast-loading tracks quickly, but keep the original long tail
      // so a slower source response is never mistaken for a failed selection.
      later(verify, tries < 8 ? 90 : 250);
    };
    later(verify, 70);
  }
  function tick() { observeSource(); reportCaption(); }
  function dispose() { disposed = true; pending = null; for (const id of timers) win.clearTimeout(id); timers.clear(); }
  return {frameID, scan, publish, select, reset, tick, hidePanels, dispose,
    setDelay(value) { delay = Number(value) || 0; reportCaption(); },
    setStyle(value) { style = {...style, ...value}; applyStyle(); }};
}
if (typeof module !== 'undefined' && module.exports) module.exports = {createXSSourceSubtitles};
