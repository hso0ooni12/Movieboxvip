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
  function publish(final) {
    const current = rows();
    if (current) catalog = current;
    if (!ccButton()) return; // Empty wrapper/advertising frames cannot overwrite the owner.
    send({event: 'xs:subtitles', final: !!final, items: catalog.filter(it => it.label !== 'Off').map(it => ({
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
      let tries = 0;
      const check = () => {
        if (epoch !== generation || disposed) return resolve(false);
        if (panel()) { hidePanels(); return resolve(true); }
        if (++tries >= 20) return resolve(false);
        later(check, 75);
      };
      later(check, 25);
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
    const name = item.label.replace(/ \((In-Stream|Uploaded)\)$/, '');
    return tracks().find(t => normal(t.label || t.language) === name ||
      ((!t.label || t.label === 'Subtitles') && normal(t.language) === name)) || null;
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
  function applyStyle() {
    hidePanels();
    const customTiming = delay !== 0 && active && trackFor(active);
    for (const el of sourceCaptionNodes()) {
      el.style.setProperty('font-size', Math.round(22 * style.size) + 'px', 'important');
      el.style.setProperty('color', style.color, 'important');
      el.style.setProperty('bottom', style.bottom + 'px', 'important');
      el.style.setProperty('background-color', style.background ? 'rgba(0,0,0,.68)' : 'transparent', 'important');
      if (customTiming) el.style.setProperty('opacity', '0', 'important');
      else el.style.removeProperty('opacity');
    }
  }
  function reportCaption() {
    const selectedTrack = delay && active ? trackFor(active) : null;
    if (timingTrack && timingTrack !== selectedTrack) {
      if (timingTrack.mode === 'hidden' && timingTrack.cues && timingTrack.cues.length) timingTrack.mode = 'showing';
      timingTrack = null;
    }
    if (selectedTrack && selectedTrack.mode === 'showing') {
      timingTrack = selectedTrack;
      selectedTrack.mode = 'hidden';
    }
    applyStyle();
    if (!delay || !active) { caption(''); return; }
    const track = selectedTrack, v = findVideo();
    if (!track || !v) { caption(''); return; }
    const at = Number(v.currentTime || 0) + delay;
    const lines = Array.from(track.cues).filter(c => c.startTime <= at && at < c.endTime).map(c => c.text || '');
    caption(lines.join('\n'));
  }
  function reset() {
    generation++; pending = null; active = null; catalog = []; caption('');
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
      later(verify, 250);
    };
    later(verify, 100);
  }
  function tick() { observeSource(); reportCaption(); }
  function dispose() { disposed = true; pending = null; for (const id of timers) win.clearTimeout(id); timers.clear(); }
  return {frameID, scan, publish, select, reset, tick, hidePanels, dispose,
    setDelay(value) { delay = Number(value) || 0; reportCaption(); },
    setStyle(value) { style = {...style, ...value}; applyStyle(); }};
}
if (typeof module !== 'undefined' && module.exports) module.exports = {createXSSourceSubtitles};
