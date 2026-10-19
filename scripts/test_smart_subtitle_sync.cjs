const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {xsSmartSyncEstimate,xsSmartCueWindows}=require('./xs_smart_subtitle_sync.js');

function synthetic(offset) {
  const intervals=[];
  for(let t=1;t<38;t+=4) intervals.push({start:t,end:t+1.7});
  const samples=[];
  for(let i=0;i<420;i++){
    const t=i/10;
    const speech=intervals.some(c=>t>=c.start+offset&&t<c.end+offset);
    const ripple=(i%7)*.001;
    samples.push({t,rms:(speech?.52:.025)+ripple});
  }
  return {samples,intervals};
}
test('auto-sync genuinely estimates positive subtitle lateness via independent acoustic samples',()=>{
  const {samples,intervals}=synthetic(1.5);
  const result=xsSmartSyncEstimate(samples,intervals,0);
  assert.ok(result,'expected high-confidence alignment');
  assert.equal(result.offset,1.5);
  assert.ok(result.confidence>=.8);
});
test('auto-sync genuinely estimates negative subtitle lead from audio timing',()=>{
  const {samples,intervals}=synthetic(-1.25);
  const result=xsSmartSyncEstimate(samples,intervals,0);
  assert.ok(result);
  assert.equal(result.offset,-1.25);
});
test('current correct caption alignment must not be shifted on false automatic estimate',()=>{
  const {samples,intervals}=synthetic(0);
  assert.equal(xsSmartSyncEstimate(samples,intervals,0),null);
});
test('music/constant-energy sources do not cause fabricated corrections',()=>{
  const {intervals}=synthetic(0);
  const samples=Array.from({length:400},(_,i)=>({t:i/10,rms:.3}));
  assert.equal(xsSmartSyncEstimate(samples,intervals,0),null);
});
test('short or insufficient caption tracks do not get auto-adjusted',()=>{
  const {samples,intervals}=synthetic(1);
  assert.equal(xsSmartSyncEstimate(samples.slice(0,20),intervals,0),null);
  assert.equal(xsSmartSyncEstimate(samples,intervals.slice(0,3),0),null);
});
test('caption windows preserve source-owned cue timestamps, including gaps',()=>{
  const track={cues:[
    {startTime:10,endTime:12},
    {startTime:14,endTime:15.5},
    {startTime:18,endTime:20}
  ]};
  assert.deepEqual(xsSmartCueWindows({currentTime:25},track,[]),[
    {start:10,end:12},{start:14,end:15.5},{start:18,end:20}
  ]);
});
test('feature is opt-in and reports unsupported media capture without touching playback',async()=>{
  const messages=[];
  const video={currentTime:15,paused:false};
  const sandbox={findVideo:()=>video,active:{id:'subtitle1'},generation:0,
    win:{},disposed:false,send:payload=>messages.push(payload)};
  const code=fs.readFileSync(require.resolve('./xs_smart_subtitle_sync.js'),'utf8');
  await vm.runInNewContext(code+'\nxsSmartAutoSync();',sandbox);
  assert.equal(messages[0].phase,'unavailable');
  assert.equal(messages[0].event,'xs:subtitleAutoSync');
  assert.equal(typeof video.captureStream,'undefined');
  assert.ok(!/\.createMediaElementSource\s*\(/.test(code),'must never reroute or mute the video element');
  assert.ok(!code.includes('getUserMedia('),'must never activate a microphone');
  assert.ok(!code.includes('fetch('),'must not upload voice samples');
});
