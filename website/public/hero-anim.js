(function(){
var st=document.getElementById('st'),S=[].slice.call(st.querySelectorAll('.s')),bg=document.getElementById('bg'),wp=document.getElementById('wp'),tmr=document.getElementById('tmr'),ci=0,cur=-1,vis=true,iv,timer;
function wrap(n){[].slice.call(n.childNodes).forEach(function(c){if(c.nodeType==3){var f=document.createDocumentFragment();c.textContent.split('').forEach(function(ch){var x=document.createElement('span');x.className='c';x.style.setProperty('--i',ci++);x.innerHTML=ch==' '?' ':ch;f.appendChild(x)});c.parentNode.replaceChild(f,c)}else if(c.nodeType==1&&c.tagName!='BR')wrap(c)})}
[].forEach.call(st.querySelectorAll('.k'),function(e){ci=0;wrap(e)});
for(var i=0;i<22;i++){var p=document.createElement('i');p.style.cssText='left:'+Math.random()*100+'%;--z:'+(.3+Math.random()*.7)+'cqw;--du:'+(9+Math.random()*10)+'s;--dl:-'+Math.random()*14+'s';bg.appendChild(p)}
[['#5BE3AE','-8cqw','-10cqw'],['#F4B942','60cqw','25cqw']].forEach(function(c){var o=document.createElement('b');o.style.cssText='background:'+c[0]+';left:'+c[1]+';top:'+c[2];bg.appendChild(o)});
function re(e){e.classList.remove('go');void e.offsetWidth;e.classList.add('go')}
function show(n){var prev=S[cur];if(prev){prev.classList.remove('on');prev.classList.add('out');setTimeout(function(){prev.classList.remove('out')},700)}
 cur=n%S.length;var s=S[cur];s.classList.remove('out');void s.offsetWidth;s.classList.add('on');re(wp);clearInterval(iv);
 if(tmr&&s.contains(tmr)){var t0=Date.now();iv=setInterval(function(){var m=Math.min(22,(Date.now()-t0-400)/5000*22);tmr.textContent=('0'+Math.max(0,Math.floor(m))).slice(-2)+':'+('0'+Math.floor((m%1)*60)).slice(-2)},60)}
 timer=setTimeout(tick,(+s.dataset.t-.4)*1000)}
function tick(){if(!vis||document.hidden){timer=setTimeout(tick,500);return}show(cur+1)}
if(window.matchMedia&&matchMedia('(prefers-reduced-motion:reduce)').matches){S[0].classList.add('on');return}
if('IntersectionObserver' in window)new IntersectionObserver(function(e){vis=e[0].isIntersecting}).observe(st);
show(0)})();
