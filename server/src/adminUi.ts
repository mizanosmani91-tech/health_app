/** A tiny phone-friendly page for verifying pharmacies. It holds no data itself: the admin key is typed
 *  in the browser (kept in sessionStorage only) and every call goes to the guarded /admin/* API. */
export const ADMIN_HTML = `<!doctype html><html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ফার্মেসি যাচাই</title><link rel="stylesheet" href="/admin/ui.css"></head><body>
<h1>ফার্মেসি যাচাই</h1>
<div id="login"><input id="key" type="password" placeholder="Admin key" autocomplete="off"><button id="go">ঢুকুন</button></div>
<div id="app" hidden><div class="tabs"><button data-s="pending" class="on">যাচাই বাকি</button><button data-s="verified">যাচাই হয়েছে</button><button data-s="rejected">বাতিল</button></div><div id="list"></div></div>
<script src="/admin/ui.js"></script></body></html>`;

export const ADMIN_CSS = `body{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#f6f5ff;color:#1b1a3a;max-width:640px;margin:auto}
h1{font-size:20px}input,button{font:inherit;padding:10px 14px;border-radius:12px;border:1px solid #cfcaf5}
button{background:#4f43d6;color:#fff;border:0;cursor:pointer}.tabs button{background:#fff;color:#4f43d6;border:1px solid #cfcaf5;margin-right:6px}.tabs .on{background:#4f43d6;color:#fff}
.card{background:#fff;border-radius:16px;padding:14px;margin:12px 0;box-shadow:0 2px 10px #4f43d61a}.card img{max-width:100%;border-radius:10px;margin-top:8px}
.row{margin:4px 0;font-size:14px}.act{display:flex;gap:8px;margin-top:10px}.rej{background:#e5484d}.ok{background:#1f9d6b}.muted{color:#6b6a8a}`;

export const ADMIN_JS = `(function(){
var key=sessionStorage.getItem('ak')||'',status='pending';
var $=function(i){return document.getElementById(i)};
function api(p,o){o=o||{};o.headers=Object.assign({'x-admin-key':key,'content-type':'application/json'},o.headers||{});return fetch(p,o)}
function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e}
async function load(){
  var r=await api('/admin/pharmacies?status='+status);
  if(r.status===401){sessionStorage.removeItem('ak');$('app').hidden=true;$('login').hidden=false;alert('Admin key ভুল');return}
  var rows=await r.json(),l=$('list');l.textContent='';
  if(!rows.length)l.appendChild(el('p','muted','কিছু নেই।'));
  rows.forEach(function(p){
    var c=el('div','card');c.appendChild(el('b','',p.name));
    [['ঠিকানা',p.address],['ফোন',p.phone],['লাইসেন্স নম্বর',p.licenseNo],['মালিক (ইমেইল)',p.ownerEmail]].forEach(function(a){c.appendChild(el('div','row',a[0]+': '+(a[1]||'')))});
    var img=el('img');c.appendChild(img);
    api('/admin/pharmacies/'+p.id+'/license').then(function(x){return x.ok?x.blob():null}).then(function(b){if(b)img.src=URL.createObjectURL(b)});
    var a=el('div','act');
    [['verified','যাচাই করুন','ok'],['rejected','বাতিল','rej']].forEach(function(s){
      if(s[0]===status)return;var b=el('button',s[2],s[1]);
      b.onclick=async function(){if(!confirm(p.name+' — '+s[1]+'?'))return;await api('/admin/pharmacies/'+p.id+'/status',{method:'POST',body:JSON.stringify({status:s[0]})});load()};a.appendChild(b)});
    c.appendChild(a);l.appendChild(c)})}
function show(){$('login').hidden=true;$('app').hidden=false;load()}
$('go').onclick=function(){key=$('key').value.trim();sessionStorage.setItem('ak',key);show()};
document.querySelectorAll('.tabs button').forEach(function(b){b.onclick=function(){status=b.dataset.s;document.querySelectorAll('.tabs button').forEach(function(x){x.classList.toggle('on',x===b)});load()}});
if(key)show();
})();`;
