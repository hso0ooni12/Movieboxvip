const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { JSDOM } = require('jsdom');
const script = fs.readFileSync('FrameNative/Resources/xstv-cinema.js','utf8');
function setup(html, resumePosition=0) {
  const dom = new JSDOM(html,{url:'https://www.etwatch.net/watch/tv/1396/2/3',runScripts:'outside-only'});
  const {window:w}=dom;const messages=[];
  const close=w.close.bind(w);w.close=()=>{w.dispatchEvent(new w.Event('pagehide'));close()};
  w.webkit={messageHandlers:{xstvVideoStatus:{postMessage:m=>messages.push(m)}}};
  w.__xstvPlaybackConfig={resumePosition};
  for(const v of w.document.querySelectorAll('video')) {
    Object.defineProperty(v,'readyState',{configurable:true,get:()=>4});
    Object.defineProperty(v,'duration',{configurable:true,get:()=>1000});
    Object.defineProperty(v,'paused',{configurable:true,get:()=>false});
    v.getBoundingClientRect=()=>({width:700,height:400});
    v.pause=()=>{};
  }
  w.eval(script);w.document.dispatchEvent(new w.Event('DOMContentLoaded'));
  return {dom,w,messages,video:w.document.querySelector('video')};
}
const markup='<main><div class="player-root"><video></video><div id="captions">ترجمة عربية</div><button aria-label="Fullscreen"><span>expand</span></button><button aria-label="Subtitles">CC</button><button aria-label="Servers">Servers</button></div></main>';
test('fullscreen retains the exact video, caption node and all controls, without reparenting',()=>{
 const {dom,w,video}=setup(markup);const parent=video.parentElement;const captions=w.document.getElementById('captions');
 let nativeFullscreen=0;w.document.querySelector('[aria-label="Fullscreen"]').addEventListener('click',()=>nativeFullscreen++);
 w.document.querySelector('button span').click();
 assert.equal(nativeFullscreen,0);assert(parent.classList.contains('xstv-theater-player'));
 assert.equal(video.parentElement,parent);assert.equal(captions.parentElement,parent);
 assert.equal(parent.querySelector('video'),video);assert.equal(parent.querySelector('#captions'),captions);
 assert.equal(w.__xstvExitTheater(),true);assert(!parent.classList.contains('xstv-theater-player'));dom.window.close();
});
test('source subtitle and server buttons keep receiving exactly one click',()=>{
 const {dom,w}=setup(markup);let subs=0,servers=0;
 const sub=w.document.querySelector('[aria-label="Subtitles"]'),server=w.document.querySelector('[aria-label="Servers"]');
 sub.addEventListener('click',()=>subs++);server.addEventListener('click',()=>servers++);
 sub.click();server.click();assert.equal(subs,1);assert.equal(servers,1);dom.window.close();
});
test('fullscreen does nothing until an actual video or player frame is available',()=>{
 const {dom,w}=setup('<main>Loading</main>');assert.equal(w.__xstvEnterTheater(),false);
 assert(!w.document.documentElement.classList.contains('xstv-cinema-on'));dom.window.close();
});
test('video remains inline and playing alone never forces theater mode',()=>{
 const {dom,w,video}=setup(markup);assert.equal(video.playsInline,true);
 video.currentTime=20;video.dispatchEvent(new w.Event('playing'));
 assert(!w.document.documentElement.classList.contains('xstv-cinema-on'));dom.window.close();
});
test('reports progress only after actual video events, and caps timeupdate traffic',()=>{
 const {dom,w,video,messages}=setup(markup);messages.length=0;
 for(const value of [1,2,3,4,5,6]){video.currentTime=value;video.dispatchEvent(new w.Event('timeupdate'))}
 assert.equal(messages.length,2);assert.equal(messages[1].seconds,6);assert.equal(messages[1].duration,1000);
 assert.equal(messages[0].event,'timeupdate');dom.window.close();
});
test('restores progress once and does not jump backwards on later server/metadata events',()=>{
 const {dom,w,video}=setup(markup,240);assert.equal(video.currentTime,240);
 video.currentTime=310;video.dispatchEvent(new w.Event('loadedmetadata'));
 assert.equal(video.currentTime,310);dom.window.close();
});
test('does not resume past the ending',()=>{
 const {dom,video}=setup(markup,998);assert.equal(video.currentTime,0);dom.window.close();
});
test('duplicate injection cannot install duplicate handlers',()=>{
 const {dom,w,video,messages}=setup(markup);w.eval(script);messages.length=0;
 video.currentTime=50;video.dispatchEvent(new w.Event('playing'));assert.equal(messages.length,1);dom.window.close();
});
test('video and caption tree survive multiple expand/collapse cycles',()=>{
 const {dom,w,video}=setup(markup);for(let i=0;i<8;i++){assert(w.__xstvEnterTheater());assert(w.__xstvExitTheater())}
 assert.equal(w.document.querySelectorAll('video').length,1);assert.equal(w.document.querySelector('video'),video);
 assert.equal(w.document.querySelectorAll('#xstv-cinema-style').length,1);dom.window.close();
});
test('videos created after initial page load are observed',async()=>{
 const {dom,w,messages}=setup('<main></main>');const v=w.document.createElement('video');
 w.document.querySelector('main').append(v);await new Promise(resolve=>setTimeout(resolve,0));
 v.currentTime=15;v.dispatchEvent(new w.Event('playing'));
 assert.equal(v.playsInline,true);assert(messages.some(m=>m.event==='playing'&&m.seconds===15));dom.window.close();
});
