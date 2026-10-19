const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {JSDOM} = require('jsdom');
const FakeTimers = require('@sinonjs/fake-timers');
const {createXSSourceSubtitles} = require('./xs_source_subtitles.js');

// The relevant structure and click behavior of FrameXTV's public CC component:
// a title button; conditionally mounted popup; label + separate ✓; async source
// loading creates a hidden, populated TextTrack while React renders the cue div.
function fixture(options = {}) {
  const dom = new JSDOM(`<!doctype html><html><head></head><body>
    <div id="player"><video src="https://media.example/movie.mp4"></video>
    <div id="cue" class="absolute pointer-events-none text-center" style="text-shadow:0 2px 4px black;line-height:1.35">مرحبا</div>
    <div class="absolute inset-x-0 bottom-0"><div id="cc"><button title="Subtitles / Captions"></button></div></div></div>
    <button id="unrelated">Arabic</button></body></html>`, {url:'https://framextv.tech/embed/1'});
  const {window} = dom, doc = window.document;
  const clock = FakeTimers.withGlobal(window).install();
  const video = doc.querySelector('video'), textTracks = [];
  const cue = doc.querySelector('#cue');
  if (options.domOnly) cue.textContent = '';
  Object.defineProperty(video, 'textTracks', {value: textTracks});
  let selected = -1, clickCount = 0, openClicks = 0;
  const labels = options.labels || ['English', 'Arabic', 'Arabic (SDH)', 'Español'];
  const emitted = [];
  function load(index) {
    for (const t of textTracks) { t.mode='disabled'; t.cues=[]; }
    if (index < 0) {
      if (options.domOnly) cue.textContent = '';
      return;
    }
    if (options.domOnly) {
      cue.textContent = labels[index] + ' message';
      return;
    }
    textTracks.push({kind:'subtitles', label:options.genericTrackLabel?'Subtitles':labels[index], language:index===1?'ar':'en', mode:'hidden',
      cues:[{startTime:0,endTime:5,text:index===1?'مرحبا':'Hello'},{startTime:5,endTime:9,text:'Next'}]});
  }
  function open() {
    if (doc.querySelector('#menu')) return;
    const menu = doc.createElement('div'); menu.id='menu';
    menu.innerHTML='<div><span>Subtitles</span><button>✕</button></div>';
    menu.querySelector('button').onclick = () => menu.remove();
    ['Off', ...labels].forEach((name, n) => {
      const index = n-1, row = doc.createElement('button');
      row.innerHTML='<span></span>'+(selected===index?'<span>✓</span>':'');
      row.firstElementChild.textContent=name;
      row.onclick=() => {
        selected=index; clickCount++; menu.remove();
        window.setTimeout(() => {
          if (options.fail && index >= 0) return;
          if (selected !== index) return;
          load(index);
        }, options.loadDelay || 300);
      };
      menu.appendChild(row);
    });
    doc.querySelector('#cc').appendChild(menu);
  }
  doc.querySelector('[title]').onclick=() => {
    openClicks++;
    const p=doc.querySelector('#menu'); if(p)p.remove();else open();
  };
  const adapter=createXSSourceSubtitles({document:doc,window,findVideo:()=>video,emit:p=>emitted.push(p),frameID:options.frameID||'frame-A'});
  async function scan() { const p=adapter.scan(); await clock.tickAsync(100); await p; return last('xs:subtitles').items; }
  function last(event) { return emitted.filter(e=>e.event===event).at(-1); }
  function select(item, requestID='r1') { return adapter.select({id:item.id, frameID:adapter.frameID,requestID}); }
  function cleanup() { adapter.dispose(); clock.uninstall(); window.close(); }
  return {doc,video,cue,textTracks,clock,adapter,emitted,scan,last,select,cleanup,load,
    clicks:()=>clickCount,opens:()=>openClicks,labels};
}

test('list exposes ALL source subtitles, without invented indexes or duplicates', async()=>{
  const f=fixture(); const items=await f.scan();
  assert.deepEqual(items.map(x=>x.label),['English','Arabic','Arabic (SDH)','Español']);
  assert(items.every(x=>x.source==='source-menu' && x.index===null && x.frameID==='frame-A'));
  const p1=f.adapter.scan(),p2=f.adapter.scan(); await f.clock.tickAsync(100);await Promise.all([p1,p2]);
  assert.equal(f.opens(),1); f.cleanup();
});
test('synchronously mounted source popup publishes without an artificial scan delay', async()=>{
  const f=fixture();
  await f.adapter.scan();
  assert.deepEqual(f.last('xs:subtitles').items.map(x=>x.label),['English','Arabic','Arabic (SDH)','Español']);
  assert.equal(f.opens(),1);
  f.cleanup();
});
test('Arabic invokes the source row and waits for both selection and loaded cues', async()=>{
  const f=fixture();const items=await f.scan();await f.select(items[1]);
  await f.clock.tickAsync(150);assert.equal(f.last('xs:subtitleSelected'),undefined);
  await f.clock.tickAsync(800);assert.equal(f.last('xs:subtitleSelected').id,items[1].id);
  assert.equal(f.clicks(),1);assert.equal(f.textTracks.at(-1).label,'Arabic');
  assert.equal(f.textTracks.at(-1).mode,'hidden'); // Source renderer owns its hidden track.
  assert.equal(f.doc.querySelectorAll('track').length,0);f.cleanup();
});
test('reselecting the checked language ignores ✓ and does not toggle the popup closed', async()=>{
  const f=fixture();let items=await f.scan();await f.select(items[1]);await f.clock.tickAsync(1000);
  items=await f.scan();assert.equal(items[1].label,'Arabic');
  await f.select(items[1],'r2');await f.clock.tickAsync(1000);
  assert.equal(f.last('xs:subtitleSelected').requestID,'r2');f.cleanup();
});
test('subtitle variants and every source language remain available with exact selection',async()=>{
  const f=fixture({labels:['Arabic','Arabic (SDH)','English','Español']});const items=await f.scan();
  assert.deepEqual(items.map(x=>x.label),['Arabic','Arabic (SDH)','English','Español']);
  await f.select(items[0]);await f.clock.tickAsync(1000);
  assert.equal(f.last('xs:subtitleSelected').id,items[0].id);
  assert.equal(f.textTracks.at(-1).label,'Arabic');f.cleanup();
});
test('SDH variant stays selectable and uses the exact source-owned menu row',async()=>{
  const f=fixture({labels:['Arabic','Arabic (SDH)','English','Español']});
  const items=await f.scan();
  await f.select(items[1],'sdh-request');
  await f.clock.tickAsync(1100);
  assert.equal(f.last('xs:subtitleSelected').requestID,'sdh-request');
  assert.equal(f.textTracks.at(-1).label,'Arabic (SDH)');
  assert.equal(f.clicks(),1);
  f.cleanup();
});
test('duplicate language rows preserve distinct source occurrences',async()=>{
  const f=fixture({labels:['English','English','Español']});
  const items=await f.scan();
  assert.deepEqual(items.map(it=>it.label),['English','English','Español']);
  assert.notEqual(items[0].id,items[1].id);
  f.cleanup();
});
test('server reset restores a hidden timing track before a new provider loads',async()=>{
  const f=fixture();const items=await f.scan();await f.select(items[1]);
  await f.clock.tickAsync(1000);
  const track=f.textTracks.at(-1);
  track.mode='showing';
  f.adapter.setDelay(1);
  assert.equal(track.mode,'hidden');
  f.adapter.reset();
  assert.equal(track.mode,'showing');
  f.cleanup();
});
test('Off goes through the source handler and only confirms after cues are cleared',async()=>{
  const f=fixture();const items=await f.scan();await f.select(items[1]);await f.clock.tickAsync(1000);
  await f.select({id:'off'},'off-request');await f.clock.tickAsync(100);
  assert.notEqual(f.last('xs:subtitleSelected').requestID,'off-request');
  await f.clock.tickAsync(1000);assert.equal(f.last('xs:subtitleSelected').id,'off');
  assert.equal(f.textTracks.filter(t=>t.mode!=='disabled').length,0);f.cleanup();
});
test('rapid selections cancel old acknowledgements and use the last requested row',async()=>{
  const f=fixture({loadDelay:700});const items=await f.scan();await f.select(items[0],'old');
  const selecting=f.select(items[1],'new');await f.clock.tickAsync(100);await selecting;await f.clock.tickAsync(1500);
  assert.deepEqual(f.emitted.filter(e=>e.event==='xs:subtitleSelected').map(e=>e.requestID),['new']);f.cleanup();
});
test('another frame cannot act on a subtitle command',async()=>{
  const f=fixture();const items=await f.scan();await f.adapter.select({id:items[1].id,frameID:'frame-B',requestID:'bad'});
  await f.clock.tickAsync(1000);assert.equal(f.clicks(),0);f.cleanup();
});
test('missing or failed subtitle does not produce a false success or leave an endless request',async()=>{
  const f=fixture({fail:true});const items=await f.scan();await f.select(items[1]);await f.clock.tickAsync(18000);
  assert.equal(f.last('xs:subtitleSelected'),undefined);assert.equal(f.last('xs:subtitleSelectionFailed').requestID,'r1');
  assert.equal(f.clicks(),2); // Requested row then the source's Off, no guessed fallback.
  f.cleanup();
});
test('server/source change invalidates catalog IDs and pending results',async()=>{
  const f=fixture();const items=await f.scan();await f.select(items[1]);f.adapter.reset();await f.clock.tickAsync(1000);
  assert.equal(f.last('xs:subtitleSelected'),undefined);await f.select(items[1],'stale');
  assert.equal(f.last('xs:subtitleSelectionFailed').requestID,'stale');
  const next=await f.scan();assert.notEqual(next[1].id,items[1].id);f.cleanup();
});
test('source cue layer stays visible while chrome and menu are hidden',async()=>{
  const f=fixture();await f.scan();f.adapter.tick();
  assert.equal(f.doc.querySelector('#cue').style.opacity,'');
  assert.equal(f.doc.querySelector('#player').hasAttribute('data-xs-source-panel'),false);
  assert.equal(f.doc.querySelector('#menu').getAttribute('data-xs-source-panel'),'1');
  assert.equal(f.doc.querySelector('#cue').style.color,'rgb(255, 255, 255)');f.cleanup();
});
test('custom timing reads the exact source-loaded cues; zero delay restores source rendering',async()=>{
  const f=fixture();const items=await f.scan();await f.select(items[1]);await f.clock.tickAsync(1000);
  f.video.currentTime=4.5;f.adapter.setDelay(-1);assert.equal(f.last('xs:caption').text,'Next'); // − means ahead
  assert.equal(f.last('xs:subtitleTimingStatus').mode,'cues');
  assert.equal(f.doc.querySelector('#cue').style.opacity,'0');
  f.adapter.setDelay(1);assert.equal(f.last('xs:caption').text,'مرحبا'); // + means delayed
  f.adapter.setDelay(0);assert.equal(f.doc.querySelector('#cue').style.opacity,'');assert.equal(f.last('xs:caption').text,'');f.cleanup();
});
test('DOM-only source subtitle selection confirms only after source renderer actually changes',async()=>{
  const f=fixture({domOnly:true});
  const items=await f.scan();
  await f.select(items[1]);
  await f.clock.tickAsync(1100);
  assert.equal(f.last('xs:subtitleSelected').id,items[1].id);
  assert.equal(f.textTracks.length,0);
  f.cleanup();
});
test('DOM-only source: positive subtitle delay changes visible cue timing, not just slider number',async()=>{
  const f=fixture({domOnly:true});
  const items=await f.scan();
  await f.select(items[1]);await f.clock.tickAsync(1100);
  f.video.currentTime=0;
  f.adapter.setDelay(2);
  assert.equal(f.last('xs:subtitleTimingStatus').mode,'buffered');
  assert.equal(f.cue.style.opacity,'0');
  f.video.currentTime=1;f.adapter.tick();
  assert.equal(f.last('xs:caption')?.text ?? '','');
  f.video.currentTime=2.1;f.adapter.tick();
  assert.equal(f.last('xs:caption').text,'Arabic message');
  f.video.currentTime=3;f.cue.textContent='Second dialogue';f.adapter.tick();
  assert.equal(f.last('xs:caption').text,'Arabic message');
  f.video.currentTime=5.1;f.adapter.tick();
  assert.equal(f.last('xs:caption').text,'Second dialogue');
  f.adapter.setDelay(0);
  assert.equal(f.cue.style.opacity,'');
  f.cleanup();
});
test('DOM-only source: impossible negative lookahead must NOT silently pretend to change captions',async()=>{
  const f=fixture({domOnly:true});
  const items=await f.scan();
  await f.select(items[1]);await f.clock.tickAsync(1100);
  f.adapter.setDelay(-1.5);
  assert.equal(f.last('xs:subtitleTimingStatus').mode,'unsupported');
  assert.equal(f.cue.style.opacity,'');
  assert.equal(f.last('xs:caption')?.text ?? '','');
  f.cleanup();
});
test('empty wrapper frames cannot erase the source frame subtitle list',async()=>{
  const f=fixture();f.doc.querySelector('#cc').remove();await f.scan().catch(()=>{});
  assert.equal(f.last('xs:subtitles'),undefined);f.cleanup();
});
test('language-only source row matches the source generic TextTrack label plus language',async()=>{
  const f=fixture({labels:['en','ar'],genericTrackLabel:true});const items=await f.scan();
  await f.select(items[1]);await f.clock.tickAsync(1000);
  assert.equal(f.last('xs:subtitleSelected').id,items[1].id);f.cleanup();
});
test('timing adjustment suppresses and then restores native in-stream cues',async()=>{
  const f=fixture();const items=await f.scan();await f.select(items[1]);await f.clock.tickAsync(1000);
  f.textTracks.at(-1).mode='showing';f.adapter.setDelay(1);
  assert.equal(f.textTracks.at(-1).mode,'hidden');f.adapter.setDelay(0);
  assert.equal(f.textTracks.at(-1).mode,'showing');f.cleanup();
});
test('generated production bridge parses and safely starts before documentElement exists',()=>{
  const swift=fs.readFileSync('FrameNative/FrameXTVPlayerV6.swift','utf8');
  assert(swift.includes('.init(name: "controls", value: "1")'));
  const match=swift.match(/private static let bridgeScript = #"""\n([\s\S]*?)    """#/);
  assert(match);new vm.Script(match[1]);
  assert(match[1].split('\n').every(line=>!line.trim() || line.startsWith('    ')), 'Swift raw multiline string indentation');
  const listeners={};let intervals=0;
  const doc={documentElement:null,body:null,addEventListener:(n,f)=>listeners[n]=f};
  const win={crypto:{randomUUID:()=> 'frame-test'},addEventListener:()=>{},setTimeout:()=>1};
  vm.runInNewContext(match[1],{window:win,document:doc,setInterval:()=>intervals++,setTimeout:()=>1,MutationObserver:class {observe(target){assert(target)}}});
  assert.equal(intervals,1);assert.equal(typeof listeners.DOMContentLoaded,'function');
  assert(!match[1].includes('originalFetch'));assert(!match[1].includes("action:'setSubtitle'"));
});
