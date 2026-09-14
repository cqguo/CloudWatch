// A bounded, offline DOM subset. Unsupported browser APIs must fail visibly.
(() => {
'use strict';
let nextID=1, nodes=new Map(), timers=new Map(), nextTimer=1, clock=0;
const resourceRequests=[];
class Event {
 constructor(type,options={}) {this.type=type;this.bubbles=!!options.bubbles;this.defaultPrevented=false;}
 preventDefault(){this.defaultPrevented=true;} stopPropagation(){this.stopped=true;}
}
class EventTarget {
 constructor(){this.listeners={};}
 addEventListener(type,fn){(this.listeners[type] ||= []).push(fn);}
 removeEventListener(type,fn){this.listeners[type]=(this.listeners[type]||[]).filter(x=>x!==fn);}
 dispatchEvent(event){event.target ||= this;event.currentTarget=this;
  if(typeof this['on'+event.type]==='function') this['on'+event.type](event);
  for(const fn of [...(this.listeners[event.type]||[])]) fn.call(this,event);
  if(event.bubbles&&!event.stopped&&this.parentNode)this.parentNode.dispatchEvent(event);
  return !event.defaultPrevented;
 }
}
function simpleMatch(el,s){
 if(s==='*')return el.nodeType===1;
 if(!/^[\w*-]*(?:[.#][\w-]+)*$/.test(s))throw Error('Unsupported CSS selector: '+s);
 let tag=s.match(/^[\w*-]+/)?.[0];
 if(tag&&tag!=='*'&&el.tagName!==tag.toUpperCase())return false;
 for(const bit of s.match(/[.#][\w-]+/g)||[]){if(bit[0]==='#' ? el.id!==bit.slice(1) : !el.className.split(/\s+/).includes(bit.slice(1)))return false;}
 return el.nodeType===1;
}
function matches(el,selector){return selector.split(',').some(part=>{
 const seq=part.trim().split(/\s+/);let i=seq.length-1,p=el;
 if(!simpleMatch(p,seq[i--]))return false;
 while(i>=0){p=p.parentNode;while(p&&!simpleMatch(p,seq[i]))p=p.parentNode;if(!p)return false;i--;}
 return true;
});}
class Node extends EventTarget {
 constructor(tag,text=''){super();this.uid=nextID++;nodes.set(this.uid,this);this.nodeName=tag.toUpperCase();this.nodeType=tag==='#text'?3:1;this.childNodes=[];this.parentNode=null;this._text=text;this.attributes={};this.style={};this.value='';this.width=300;this.height=150;this.hidden=false;this.disabled=false;}
 get tagName(){return this.nodeName;} get children(){return this.childNodes.filter(n=>n.nodeType===1);}
 get firstChild(){return this.childNodes[0]||null;} get lastChild(){return this.childNodes.at(-1)||null;}
 get parentElement(){return this.parentNode;} get ownerDocument(){return globalThis.document;}
 get id(){return this.getAttribute('id')||'';} set id(v){this.setAttribute('id',v);}
 get className(){return this.getAttribute('class')||'';} set className(v){this.setAttribute('class',v);}
 get classList(){let el=this;return {add(...xs){el.className=[...new Set([...el.className.split(/\s+/).filter(Boolean),...xs])].join(' ');},remove(...xs){el.className=el.className.split(/\s+/).filter(x=>!xs.includes(x)).join(' ');},contains(x){return el.className.split(/\s+/).includes(x);}};}
 get textContent(){return this.nodeType===3?this._text:this.childNodes.map(n=>n.textContent).join('');}
 set textContent(v){for(const n of this.childNodes)n.parentNode=null;this.childNodes=[];if(this.nodeType===3)this._text=String(v);else if(String(v))this.appendChild(new Node('#text',String(v)));}
 get innerText(){return this.textContent;} set innerText(v){this.textContent=v;}
 set innerHTML(html){for(const n of this.childNodes)n.parentNode=null;this.childNodes=[];const tree=__parseHTML(String(html));if(tree.error)throw Error(tree.error);for(const n of tree.children)this.appendChild(hydrate(n));}
 get innerHTML(){throw Error('innerHTML serialization is not implemented');}
 appendChild(node){if(node===this||node.contains(this))throw Error('HierarchyRequestError');if(node.parentNode)node.parentNode.removeChild(node);this.childNodes.push(node);node.parentNode=this;return node;}
 removeChild(node){let i=this.childNodes.indexOf(node);if(i<0)throw Error('NotFoundError');this.childNodes.splice(i,1);node.parentNode=null;return node;}
 contains(node){return node===this||this.childNodes.some(n=>n.contains(node));}
 setAttribute(k,v){k=String(k).toLowerCase();this.attributes[k]=String(v);if(k==='style'){for(const bit of String(v).split(';')){const i=bit.indexOf(':');if(i>0)this.style[bit.slice(0,i).trim()]=bit.slice(i+1).trim();}}if(k==='hidden')this.hidden=true;}
 getAttribute(k){return this.attributes[String(k).toLowerCase()]??null;} hasAttribute(k){return this.getAttribute(k)!==null;}
 removeAttribute(k){delete this.attributes[k];if(k==='hidden')this.hidden=false;}
 get src(){return this.getAttribute('src')||'';} set src(v){this.setAttribute('src',v);if(this.tagName==='IMG')setTimeout(()=>this.dispatchEvent(new Event('error')),0);}
 querySelectorAll(selector){let out=[];function visit(n){for(const c of n.children){if(matches(c,selector))out.push(c);visit(c);}}visit(this);return out;}
 querySelector(s){return this.querySelectorAll(s)[0]||null;}
 getElementsByTagName(s){return this.querySelectorAll(s);} getElementsByClassName(s){return this.querySelectorAll('.'+s.trim().split(/\s+/).join('.'));}
 click(){if(!this.disabled)this.dispatchEvent(new Event('click',{bubbles:true}));}
 getContext(kind){if(this.tagName!=='CANVAS'||kind!=='2d')throw Error('Unsupported canvas context');return this.context ||= new CanvasRenderingContext2D(this);}
}
class CanvasRenderingContext2D {
 constructor(canvas){this.canvas=canvas;this.fillStyle='#000000';this.strokeStyle='#000000';this.lineWidth=1;this.commands=[];}
 push(v){if(this.commands.length>=20000)throw Error('Canvas command limit exceeded');this.commands.push(v);}
 fillRect(x,y,w,h){this.push({kind:'fill',x,y,w,h,color:this.fillStyle});}
 strokeRect(x,y,w,h){this.push({kind:'stroke',x,y,w,h,color:this.strokeStyle,lineWidth:this.lineWidth});}
 clearRect(x,y,w,h){if(x===0&&y===0&&w>=this.canvas.width&&h>=this.canvas.height)this.commands=[];else throw Error('Partial canvas clear is unsupported');}
}
function hydrate(raw){const n=new Node(raw.tag,raw.text||'');for(const[k,v]of Object.entries(raw.attributes||{}))n.setAttribute(k,v);for(const child of raw.children||[])n.appendChild(hydrate(child));return n;}
const document=new EventTarget();
Object.assign(document,{nodeType:9,readyState:'loading',createElement:tag=>new Node(tag),createTextNode:text=>new Node('#text',text),createEvent:()=>new Event(''),getElementById:id=>[document.documentElement,...document.documentElement.querySelectorAll('*')].find(n=>n.id===id)||null,querySelector:s=>document.documentElement.querySelector(s),querySelectorAll:s=>document.documentElement.querySelectorAll(s),getElementsByTagName:s=>document.documentElement.querySelectorAll(s)});
Object.defineProperty(document,'cookie',{get(){throw Error('Cookie storage is not implemented in this offline prototype');},set(v){throw Error('Cookie storage is not implemented in this offline prototype');}});
Object.assign(globalThis,{window:globalThis,self:globalThis,top:globalThis,parent:globalThis,document,Node,HTMLElement:Node,Event,CanvasRenderingContext2D,devicePixelRatio:1,navigator:{userAgent:'CloudWatch Offline Prototype',language:'zh-CN'},console:{log(){},warn(){},error(){}}});
const windowEvents=new EventTarget();globalThis.addEventListener=windowEvents.addEventListener.bind(windowEvents);globalThis.removeEventListener=windowEvents.removeEventListener.bind(windowEvents);
globalThis.setTimeout=(fn,delay=0,...args)=>{if(typeof fn!=='function')throw Error('String timer is unsupported');let id=nextTimer++;timers.set(id,{fn:()=>fn(...args),at:clock+Math.max(0,Number(delay)||0)});return id;};
globalThis.clearTimeout=id=>timers.delete(id);
globalThis.fetch=(url,options={})=>new Promise((resolve,reject)=>{const id=resourceRequests.length;resourceRequests.push({id,url:String(url),method:options.method||'GET',body:options.body||null,resolve,reject,done:false});});
globalThis.__requests=()=>resourceRequests.filter(r=>!r.done).map(({id,url,method,body})=>({id,url,method,body}));
globalThis.__respond=(id,status,body)=>{let r=resourceRequests[id];if(!r||r.done)throw Error('Unknown request');r.done=true;r.resolve({status,ok:status>=200&&status<300,text:()=>Promise.resolve(body),json:()=>Promise.resolve(JSON.parse(body))});};
globalThis.__failRequest=id=>{let r=resourceRequests[id];r.done=true;r.reject(Error('Resource unavailable in offline archive'));};
globalThis.__load=(tree,url)=>{nodes.clear();timers.clear();document.documentElement=hydrate(tree);document.body=document.documentElement.querySelector('body');document.head=document.documentElement.querySelector('head');globalThis.location={href:url,protocol:url.split(':')[0]+':',host:url.split('/')[2]||'',pathname:'/',hash:''};document.location=location;};
globalThis.__ready=()=>{document.readyState='interactive';document.dispatchEvent(new Event('DOMContentLoaded'));document.readyState='complete';windowEvents.dispatchEvent(new Event('load'));};
globalThis.__advance=ms=>{clock+=ms;let count=0;for(;;){let hit=[...timers].find(([id,t])=>t.at<=clock);if(!hit)break;if(++count>100)throw Error('Timer budget exceeded');timers.delete(hit[0]);hit[1].fn();}};
globalThis.__click=uid=>{let n=nodes.get(uid);if(!n||!document.documentElement.contains(n))throw Error('Stale element');n.click();};
globalThis.__snapshot=()=>{let out=[];function walk(n){if(n.hidden||n.style.display==='none'||n.style.visibility==='hidden'||['HEAD','SCRIPT','STYLE','NOSCRIPT'].includes(n.tagName))return;
 const clickable=n.tagName==='BUTTON'||n.tagName==='A'||typeof n.onclick==='function'||n.listeners.click?.length;
 if(n.tagName==='CANVAS'){out.push({id:n.uid,kind:'canvas',text:'',width:n.width,height:n.height,commands:n.context?.commands||[]});return;}
 if(clickable){out.push({id:n.uid,kind:'button',text:n.textContent,disabled:n.disabled});return;}
 if(n.nodeType===3&&n.textContent.trim())out.push({id:n.uid,kind:'text',text:n.textContent.trim()});
 for(const c of n.childNodes)walk(c);
 }walk(document.body||document.documentElement);return JSON.stringify(out);};
})();
