// V13_SMART_AUDIO_SYNC — opt-in acoustic alignment.
// Works only with a capturable, authorized media-element audio stream AND
// sufficiently rich timed subtitle cues. No microphone, remote upload, DRM
// bypass, source player replacement, or changes to live VLC playback.
// This is signal-analysis assistance, not neural speech recognition.
function xsSmartSyncEstimate(samples, intervals, currentOffset) {
  if (!Array.isArray(samples) || !Array.isArray(intervals)) return null;
  const usable = samples.filter(s => Number.isFinite(s.t) && Number.isFinite(s.rms));
  const cues = intervals.filter(c => Number.isFinite(c.start) && Number.isFinite(c.end) && c.end > c.start);
  if (usable.length < 120 || cues.length < 5) return null;
  const timespan = usable[usable.length - 1].t - usable[0].t;
  if (timespan < 16) return null;
  const energies = usable.map(s => s.rms).sort((a,b) => a-b);
  const quantile = p => energies[Math.min(energies.length-1, Math.floor(p*(energies.length-1)))];
  const floor=quantile(.18), loud=quantile(.83);
  // Silence or constant music/noise cannot prove a speech/subtitle relationship.
  if (!(loud > floor + .008)) return null;
  const threshold = floor + (loud - floor) * .42;
  const voice = usable.map(s => s.rms > threshold ? 1 : 0);
  const voiceRate=voice.reduce((s,v)=>s+v,0)/voice.length;
  if (voiceRate < .16 || voiceRate > .84) return null;
  // Cue lists are ordered; bounded linear loop is fine for <=60s windows.
  function score(offset) {
    let both=0,a=0,b=0,n=0;
    for (let k=0;k<usable.length;k++) {
      const time=usable[k].t-offset;
      let caption=0;
      for (const cue of cues) {
        if (cue.start>time) break;
        if (cue.start<=time && time<cue.end) {caption=1;break;}
      }
      const speech=voice[k];
      a+=speech;b+=caption;both+=speech*caption;n++;
    }
    const pA=a/n,pB=b/n;
    if (pB<.12||pB>.88) return -1;
    const denom=Math.sqrt(pA*(1-pA)*pB*(1-pB));
    return denom<=0?-1:((both/n)-pA*pB)/denom;
  }
  const baseline=score(Number(currentOffset)||0);
  const grid=[];
  for (let i=-32;i<=32;i++) {
    const offset=i*.25;
    grid.push({offset,quality:score(offset)});
  }
  grid.sort((a,b)=>b.quality-a.quality);
  const best=grid[0];
  const improvement=best.quality-baseline;
  if (!best || best.quality < .60 || improvement < .16 ||
      Math.abs(best.offset-(Number(currentOffset)||0)) < .30) return null;
  return {offset:best.offset, confidence:Math.min(.99,Math.max(0,(best.quality-.45)/.5)),
          correlation:best.quality, improvement, sampleCount:usable.length};
}

function xsSmartCueWindows(video, activeTrack, history, futureSeconds=5) {
  const v=video; if(!v) return [];
  const now=Number(v.currentTime||0);
  const from=now-55,to=now+futureSeconds;
  if (activeTrack && activeTrack.cues && activeTrack.cues.length) {
    const out=[];
    for (const c of Array.from(activeTrack.cues)) {
      if (c.endTime < from || c.startTime > to) continue;
      if (c.endTime>c.startTime) out.push({start:c.startTime,end:c.endTime});
    }
    return out.sort((a,b)=>a.start-b.start);
  }
  const observed=[];
  for(let i=0;i<history.length;i++){
    const current=history[i],next=history[i+1];
    if (!current.text) continue;
    const end=next?next.at:Math.min(now,current.at+5);
    if(end>current.at+.15) observed.push({start:current.at,end});
  }
  return observed.filter(c=>c.end>=from&&c.start<=to).sort((a,b)=>a.start-b.start);
}

let xsSmartSyncBusy=false, xsSmartSyncCancel=null;
function xsSmartCancel() {
  if (xsSmartSyncCancel) xsSmartSyncCancel();
}

async function xsSmartAutoSync() {
  if (xsSmartSyncBusy) return;
  const video=findVideo();
  const epoch=generation;
  if (!video || !active || !Number.isFinite(video.currentTime) || video.paused) {
    send({event:'xs:subtitleAutoSync',phase:'unavailable',
      message:'شغّل الفيديو واختر الترجمة أولاً.'});
    return;
  }
  const capture=video.captureStream || video.mozCaptureStream;
  const AudioContextType=win.AudioContext || win.webkitAudioContext;
  if (typeof capture!=='function' || !AudioContextType) {
    send({event:'xs:subtitleAutoSync',phase:'unavailable',
      message:'هذا السيرفر لا يتيح تحليل الصوت الآمن على جهازك. يمكنك ضبط التوقيت بالأزرار.'});
    return;
  }
  let context=null,source=null,analyser=null,sampleTimer=null,cancelled=false;
  xsSmartSyncBusy=true;
  xsSmartSyncCancel=()=>{ cancelled=true; };
  const samples=[],started=Date.now();
  const fail=(phase,message)=>send({event:'xs:subtitleAutoSync',phase,message});
  try {
    // captureStream returns a separate audio capture stream. Do not call
    // createMediaElementSource(): routing it could mute protected video audio.
    const stream=capture.call(video);
    if (!stream || !stream.getAudioTracks || !stream.getAudioTracks().length) {
      fail('unavailable','سيرفر الفيديو لا يسمح بالوصول للصوت من أجل المزامنة التلقائية.');return;
    }
    context=new AudioContextType();
    source=context.createMediaStreamSource(stream);
    analyser=context.createAnalyser();
    analyser.fftSize=1024;analyser.smoothingTimeConstant=.18;
    source.connect(analyser); // NEVER connect to audio destination.
    if (context.state==='suspended') await context.resume();
    if (context.state!=='running') {
      fail('unavailable','متصفح الآيفون لم يسمح بتحليل صوت الفيديو.');return;
    }
    send({event:'xs:subtitleAutoSync',phase:'running',
      message:'أحلّل الصوت وتوقيت الجمل على الجهاز لمدة 25 ثانية…'});
    const chunk=new Uint8Array(analyser.fftSize);
    let lastTime=-1,seeked=false;
    await new Promise(resolve=>{
      sampleTimer=win.setInterval(()=>{
        if (cancelled||epoch!==generation||disposed||!active||!findVideo()||video.paused) {
          // Pauses may be temporary; stop after a reasonable wall-clock cap.
          if(cancelled||epoch!==generation||disposed||Date.now()-started>50000) resolve();
          return;
        }
        const t=Number(video.currentTime);
        if (lastTime>=0&&(t<lastTime-.7||t>lastTime+2.5)) {seeked=true;resolve();return;}
        lastTime=t;
        // Capture real rendered cue onset/offset for DOM-only players too.
        // This observation never touches the source's audio or caption nodes.
        if (!trackFor(active)) captureSourceCaption(video);
        analyser.getByteTimeDomainData(chunk);
        let power=0;
        for(let i=0;i<chunk.length;i++){const centered=(chunk[i]-128)/128;power+=centered*centered;}
        samples.push({t,rms:Math.sqrt(power/chunk.length)});
        if(samples.length>=270||Date.now()-started>34000) resolve();
      },100);
    });
    if(cancelled||epoch!==generation||disposed) return;
    if(seeked) {fail('unavailable','تم تغيير موضع الفيديو أثناء التحليل. حاول مجدداً.');return;}
    if(samples.length<120) {
      fail('unavailable','ما وصل صوت كافٍ للتحليل. جرّب أثناء مشهد فيه حوار.');return;
    }
    const reference=xsSmartCueWindows(video,trackFor(active),sourceCaptionHistory);
    const answer=xsSmartSyncEstimate(samples,reference,delay);
    if (!answer) {
      fail('low-confidence','ما قدرت أحدد فرق توقيت موثوق. أبقيت الترجمة كما هي.');return;
    }
    // Guard source/episode switch while analyser sampled audio.
    if(epoch!==generation||!active) return;
    const candidate=Math.round(answer.offset*100)/100;
    // The assistant applies alignment only when correlation is strong.
    delay=candidate;
    reportCaption();
    send({event:'xs:subtitleAutoSync',phase:'applied',offset:candidate,
      confidence:answer.confidence,
      message:'تم ضبط الترجمة تلقائياً بعد مطابقة الصوت والتوقيت.'});
  } catch(err) {
    fail('unavailable','سيرفر الفيديو منع تحليل الصوت، لم يتغير توقيت الترجمة.');
  } finally {
    if(sampleTimer!==null) win.clearInterval(sampleTimer);
    try {if(source) source.disconnect();}catch(_){}
    try {if(analyser) analyser.disconnect();}catch(_){}
    try {if(context) await context.close();}catch(_){}
    xsSmartSyncBusy=false;xsSmartSyncCancel=null;
  }
}

if(typeof module!=='undefined' && module.exports){
  module.exports.xsSmartSyncEstimate=xsSmartSyncEstimate;
  module.exports.xsSmartCueWindows=xsSmartCueWindows;
}
