// ==== JS unit tests: extract scripts from GameEngine.swift and run them on fixture pages ====
const fs = require('fs');
const path = require('path');

const swift = fs.readFileSync(path.join(__dirname, '..', 'UtatarApp', 'UtatarApp', 'GameEngine.swift'), 'utf8');

// Extract a triple-quoted Swift string into JS text (unescaping \\ -> \)
function extractStatic(name) {
  const marker = `static let ${name} = """`;
  let i = swift.indexOf(marker);
  if (i < 0) throw new Error('marker not found: ' + name);
  let a = swift.indexOf('"""', i + marker.length - 3 + 3); // closing of opening quote is same; find end
  // find closing """
  const start = i + marker.length;
  const end = swift.indexOf('"""', start);
  let body = swift.slice(start, end);
  // unescape: Swift \\ -> \ and \" -> " ; \(...) interpolation handled separately below
  body = body.replace(/\\\\/g, '\\').replace(/\\"/g, '"');
  return body;
}
function extractFunc(name) {
  let marker = `static func ${name}`;
  let i = swift.indexOf(marker);
  if (i < 0) { marker = `static let ${name}`; i = swift.indexOf(marker); }
  if (i < 0) throw new Error('func not found: ' + name);
  const start = swift.indexOf('"""', i);
  const end = swift.indexOf('"""', start + 3);
  let body = swift.slice(start + 3, end);
  body = body.replace(/\\\\/g, '\\').replace(/\\"/g, '"');
  return body;
}

// --- Minimal DOM emulation (enough for our scripts) ---
class Element {
  constructor(tag, attrs = {}, children = [], text = '') {
    this.tagName = tag.toUpperCase();
    this.attrs = attrs;
    this.children = children;
    this._text = text;
    this.parentElement = null;
    this.clicked = false;
    this.submitted = false;
    this.style = {};
  }
  get className() { return this.attrs.class || ''; }
  get id() { return this.attrs.id || ''; }
  get textContent() {
    if (this.children.length === 0) return this._text;
    return this.children.map(c => c.textContent).join('');
  }
  getAttribute(n) { const v = this.attrs[n]; return v === undefined ? null : v; }
  setAttribute(n, v) { this.attrs[n] = String(v); }
  get rect() { return this.attrs.__rect || { top: 5, width: 40 }; }
  getBoundingClientRect() { return this.rect; }
  * walk() {
    for (const c of this.children) { yield c; yield* c.walk(); }
  }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  querySelectorAll(sel) {
    const sels = sel.split(',').map(x => x.trim());
    const out = [];
    for (const el of this.walk()) {
      if (sels.some(s => matches(el, s))) out.push(el);
    }
    return out;
  }
  contains(other) { let e = other; while (e) { if (e === this) return true; e = e.parentElement; } return false; }
  appendChild(c) { this.children.push(c); c.parentElement = this; H.register(c); return c; }
  closest(selList) {
    let e = this.parentElement;
    while (e) {
      for (const sel of selList.split(',')) {
        if (matches(e, sel.trim())) return e;
      }
      e = e.parentElement;
    }
    return null;
  }
  click() { this.clicked = true; if (this.onclickHandler) this.onclickHandler(); }
  get value() {
    if (this._value !== undefined) return String(this._value);
    return this.getAttribute('value') || '';
  }
  set value(v) { this._value = String(v); }
  dispatchEvent(ev) { return true; }
  requestSubmit() { this.submitted = true; }
}
function matches(el, sel) {
  sel = sel.trim();
  // tag#id.c1.c2 / tag / #id / .cls / tag[attr*="v"] / tag[attr^="v"] / tag[attr] / *
  let m = sel.match(/^([a-z]+)(.*)$/i);
  let tag = m ? m[1].toLowerCase() : '*';
  let rest = m ? m[2] : sel;
  if (tag !== '*' && el.tagName.toLowerCase() !== tag) return false;
  // split rest into tokens
  const tokens = rest.match(/(\.[A-Za-z0-9_-]+|#[A-Za-z0-9_-]+|\[(?:"[^"]*"|'[^']*'|[^\]])*\])/g) || [];
  for (const t of tokens) {
    if (t.startsWith('.')) {
      if (!(' ' + el.className + ' ').includes(' ' + t.slice(1) + ' ')) return false;
    } else if (t.startsWith('#')) {
      if (el.id !== t.slice(1)) return false;
    } else {
      const am = t.match(/\[([a-z-]+)([*^]?)="([^\"]*)"\]/) || t.match(/\[([a-z-]+)\]/);
      if (!am) return false;
      const val = el.getAttribute(am[1]);
      if (am.length === 2) { if (val === null) return false; }
      else if (am[2] === '*') { if (!val || !val.includes(am[3])) return false; }
      else if (am[2] === '^') { if (!val || !val.startsWith(am[3])) return false; }
      else { if (val !== am[3]) return false; }
    }
  }
  return true;
}
// global document emulation
const H = {
  forms: [],
  els: [],
  register(el) { this.els.push(el); return el; },
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
  querySelectorAll(sel) {
    const sels = sel.split(',').map(x => x.trim());
    return this.els.filter(el => sels.some(ss => matches(el, ss)));
  },
};
const window = { location: { href: 'https://utatar.com/build?id=34', pathname: '/build', search: '?id=34' } };
const location = window.location;
const document = {
  title: 'عصر التتار5',
  body: null,
  documentElement: { scrollTop: 0 },
  _listeners: [],
  addEventListener(type, fn) { this._listeners.push({ type, fn }); },
  createElement: tag => t(tag, {}),   // created elements auto-register globally (H)
  querySelector: s => H.querySelector(s),
  querySelectorAll: s => {
    const sels = s.split(',').map(x => x.trim());
    return H.els.filter(el => sels.some(ss => matches(el, ss)));
  },
};

function t(tag, attrs = {}, children = [], text = "") {
  const el = new Element(tag, attrs, children, text);
  for (const c of children) c.parentElement = el;
  return H.register(el);
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

// sessionStorage shim (recorder hook persists arm/post across pages)
const _store = {};
const sessionStorage = {
  setItem: (k, v) => { _store[k] = String(v); },
  getItem: k => (k in _store ? _store[k] : null),
  removeItem: k => { delete _store[k]; },
};
const fire = (type, target) => {
  const ev = new Event(type);
  ev.target = target;
  document._listeners.filter(l => l.type === type).forEach(l => l.fn(ev));
};

// --- Browser globals the scripts rely on ---
class Event { constructor(type, opts) { this.type = type; this.bubbles = !!(opts && opts.bubbles); } }
const HTMLInputElement = { prototype: {} };
Object.defineProperty(HTMLInputElement.prototype, 'value', {
  get() { return this._value || ''; },
  set(v) { this._value = String(v); },
  configurable: true,
});

// ==== Fake game page (based on the user's real diagnostics) ====
// top resource bar (custom engine: plain <b> numbers)
const bar = t('div', { id: 'stockBar' }, [
  t('b', {}, [], '3,559,545'),
  t('b', {}, [], '11,381,973'),
  t('b', {}, [], '18,204,576'),
  t('b', {}, [], '30,346,503'),
].map(x => { x.attrs.__rect = { top: 78, width: 80 }; return x; }));
document.body = bar;

// training form (build?id=34 with tf[11..14])
const inp11 = t('input', { name: 'tf[11]', type: 'tel' });
const inp12 = t('input', { name: 'tf[12]', type: 'tel', max: '0' });   // اللعبة بتقول: مش متاح خالص
const inp14 = t('input', { name: 'tf[14]', type: 'tel', max: '87' });
const row11 = t('tr', {}, [
  t('td', {}, [t('img', { src: 'img/u/u11.gif', title: 'مقاتل بهراوة' })]),
  t('td', { class: 'val' }, [], '737'),
  t('td', {}, [inp11]),
]);
const row12 = t('tr', {}, [
  t('td', {}, [t('img', { src: 'img/u/u12.gif', title: 'مقاتل برمح' })]),
  t('td', { class: 'val' }, [], '862'),
  t('td', {}, [inp12]),
]);
const row14 = t('tr', {}, [
  t('td', {}, [t('img', { src: 'img/u/u14.gif', title: 'الكشاف' })]),
  t('td', { class: 'val' }, [], '281'),
  t('td', {}, [inp14]),
]);
const trainForm = t('form', { action: 'build?id=34' }, [
  row11, row12, row14,
  t('button', { type: 'submit' }, [], 'تدريب'),
]);
const maxLink11 = t('a', { href: '#', onclick: 'document.snd[\"tf[11]\"].value=200; return false;' }, [], '200');
maxLink11.attrs.__rect = { top: 500, width: 30 };   // بعيد عن شريط الموارد في المسح
const villageLink = t('a', { href: 'karte?d=12345', title: 'قرية (5|8) اللاعب أحمد السكان 45' }, [], 'قرية');

// ==== Run resourcesJS ====
const resourcesJS = extractStatic('resourcesJS');
let res = JSON.parse(eval(resourcesJS));
console.log('RESOURCES:', JSON.stringify(res.resources));
if (res.resources.wood !== 3559545) throw new Error('FAIL resources wood');
if (res.resources.crop !== 30346503) throw new Error('FAIL resources crop');

// ==== Run trainableJS ====
const trainableJS = extractStatic('trainableJS');
let tr = JSON.parse(eval(trainableJS));
console.log('TRAINABLE:', JSON.stringify(tr.units.map(u => ({ i: u.input, uid: u.uid, n: u.name, max: u.max }))));
if (tr.units.length !== 3) throw new Error('FAIL expected 3 trainable, got ' + tr.units.length);
const u11 = tr.units.find(u => u.input === 'tf[11]');
if (!u11 || u11.uid !== 11 || u11.name !== 'مقاتل بهراوة') throw new Error('FAIL tf[11] identity');
const u14 = tr.units.find(u => u.input === 'tf[14]');
if (!u14 || u14.max !== 87) throw new Error('FAIL tf[14] max=87');

// ==== Run trainManyJS (fill 500 for tf[11]) ====
const pairs = JSON.stringify([['tf[11]', 500], ['tf[14]', 87]]);
const trainJS = extractFunc('trainManyJS').replace('var sels=\\(arr);', 'var sels=' + pairs + ';');
let trr = JSON.parse(eval(trainJS));
console.log('TRAIN RESULT:', JSON.stringify(trr));
if (!trr.ok) throw new Error('FAIL training submit: ' + trr.message);
if (inp11.value !== '200') throw new Error('FAIL tf[11] capped to 200, got ' + inp11.value);
if (inp14.value !== '87') throw new Error('FAIL tf[14] value 87, got ' + inp14.value);
if (!trainForm.children.find(c => c.clicked)) throw new Error('FAIL submit button not clicked');

// ==== typed-million semantics: 1000000 gets capped to what resources allow (87) ====
const pairsMil = JSON.stringify([['tf[14]', 1000000]]);
const milJS = extractFunc('trainManyJS').replace('var sels=\\(arr);', 'var sels=' + pairsMil + ';');
const mil = JSON.parse(eval(milJS));
console.log('MILLION:', JSON.stringify(mil));
if (inp14.value !== '87') throw new Error('FAIL million not capped to 87, got ' + inp14.value);
console.log('MILLION CAP ✓ (1000000 -> 87)');

// ==== zero-afford: a type with no cap is SKIPPED and nothing is submitted ====
trainForm.children.forEach(c => { c.clicked = false; c.submitted = false; });
inp12.value = '';
const noneJS = extractFunc('trainManyJS').replace('var sels=\\(arr);', 'var sels=' + JSON.stringify([['tf[12]', 5000]]) + ';');
const none = JSON.parse(eval(noneJS));
console.log('NO AFFORD:', JSON.stringify(none));
if (none.ok !== false || none.message.indexOf('مش كفاية') < 0) throw new Error('FAIL zero-afford must refuse: ' + none.message);
if (inp12.value !== '') throw new Error('FAIL zero-afford must not fill');
if (trainForm.children.find(c => c.clicked)) throw new Error('FAIL zero-afford must not submit');

// ==== Run homeTroopsJS ====
const homeTroopsJS = extractStatic('homeTroopsJS');
const homeRes = JSON.parse(eval(homeTroopsJS));
console.log('HOME:', JSON.stringify(homeRes));
const h11 = homeRes.find(x => x.id === 11);
if (!h11 || h11.count !== 737) throw new Error('FAIL home u11=737, got ' + JSON.stringify(homeRes));

// ==== Run mapScanJS on fake map ====
const mapTile = t('div', { onclick: "go('karte?d=998877')" , title: 'قرية (7|9) اللاعب علي' }, []);
// mapScan looks for area[href*=karte], div[onclick*=d=], a[href*=karte]
const mapA = t('a', { href: 'karte?d=998877', title: 'قرية (7|9) اللاعب علي السكان 120' }, [], 'قرية علي');
// real-game map cells: dorf3?id= links with EMPTY titles
const cellA = t('a', { href: 'dorf3?id=867966' });
const cellB = t('area', { href: 'dorf3?id=867967', title: '' });
const mapScanJS = extractStatic('mapScanJS');
const mv = JSON.parse(eval(mapScanJS));
console.log('MAP:', JSON.stringify(mv));
if (!mv.length) throw new Error('FAIL map scan found nothing');
const v = mv.find(x => x.vid === '998877');
if (!v || v.x !== 7 || v.player.indexOf('علي') < 0) throw new Error('FAIL map village parse');
const cA = mv.find(x => x.vid === '867966');
if (!cA) throw new Error('FAIL dorf3 cell 867966 not harvested');
if (!mv.find(x => x.vid === '867967')) throw new Error('FAIL dorf3 area cell not harvested');

// ==== Run scoutSendJS(count=3) on a send form ====
// form with t-inputs + x/y (like a2b send page)
const scoutInp = t('input', { name: 'tf[14]', type: 'tel', max: '18' });
const axeInp = t('input', { name: 'tf[11]', type: 'tel', max: '100' });
const sendForm = t('form', { action: 'a2b' }, [
  t('tr', {}, [
    t('td', {}, [t('img', { src: 'img/u/u11.gif', title: 'مقاتل بهراوة' })]),
    t('td', {}, [axeInp]),
  ]),
  t('tr', {}, [
    t('td', {}, [t('img', { src: 'img/u/u14.gif', title: 'الكشاف' })]),
    t('td', {}, [scoutInp]),
  ]),
  t('input', { name: 'x' }),
  t('input', { name: 'y' }),
  t('label', {}, [t('input', { name: 'c', type: 'radio', value: '2' }), t('span', {}, [], 'تعزيز')]),
  t('label', {}, [t('input', { name: 'c', type: 'radio', value: '3' }), t('span', {}, [], 'هجوم عادي')]),
  t('label', {}, [t('input', { name: 'c', type: 'radio', value: '4' }), t('span', {}, [], 'نهب')]),
  t('button', { type: 'submit' }, [], 'إرسال'),
]);
const xi = sendForm.children.find(c => c.getAttribute('name') === 'x');
const yi = sendForm.children.find(c => c.getAttribute('name') === 'y');
xi.value = ''; yi.value = '';
axeInp.value = ''; scoutInp.value = '';
const sendJS = extractFunc('sendTroopsJS')
  .split('\\(x)').join('12').split('\\(y)').join('34')
  .replace('var pairs=\\(arr);', 'var pairs=[[14,3],[16,5]];')
  .replace('var modeVals=\\(mv);', 'var modeVals=[4,3];')
  .split('\\(rx)').join('"\\u0646\\u0647\\u0628|raid"');
const scoutRes = JSON.parse(eval(sendJS));
console.log('SCOUT:', JSON.stringify(scoutRes));
if (!scoutRes.sent) throw new Error('FAIL scout send: ' + scoutRes.message);
if (scoutInp.value !== '3') throw new Error('FAIL scout value 3, got ' + scoutInp.value);
if (axeInp.value) throw new Error('FAIL axe must stay empty');
if (xi.value !== '12' || yi.value !== '34') throw new Error('FAIL coords not filled: ' + xi.value + ',' + yi.value);
// unit NOT in the form (u16 حصان) must be INJECTED as hidden t16 — server reads any field anywhere
const inj = sendForm.children.find(c => c.getAttribute && c.getAttribute('name') === 't16' && c.value === '5');
if (!inj) throw new Error('FAIL hidden injection t16=5 missing');
console.log('INJECT ✓ t16=5 hidden field created');
const radios = sendForm.querySelectorAll('input[name="c"]');
const raidClicked = radios.find(r => r.clicked);
if (!raidClicked || raidClicked.getAttribute('value') !== '4') {
  console.log('DBG radios found:', radios.length, radios.map(r => ({v: r.getAttribute('value'), val: r.value, clicked: r.clicked})));
  console.log('DBG modeVals line:', (sendJS.split('\n').find(l => l.includes('modeVals')) || '').trim());
  throw new Error('FAIL raid radio value 4 (نهب) not clicked');
}
if (!sendForm.children.find(c => c.clicked)) throw new Error('FAIL send button not clicked');
// twin fields: plain t14 + positional t4 must exist with the scout value
const twin14 = sendForm.children.find(c => c.getAttribute && c.getAttribute('name') === 't14' && c.value === '3');
const twin4 = sendForm.children.find(c => c.getAttribute && c.getAttribute('name') === 't4' && c.value === '3');
const s1 = sendForm.children.find(c => c.getAttribute && c.getAttribute('name') === 's1');
if (!twin14) throw new Error('FAIL twin t14 missing');
if (!twin4) throw new Error('FAIL positional twin t4 missing');
if (!s1 || s1.value !== 'ok') throw new Error('FAIL s1=ok hidden missing');
console.log('TWINS: t14=3 + t4=3 + s1=ok ✓');

// ==== findBarracksLinkJS: finds the barracks link by Arabic name on a dorf2-like page ====
const bImg = t('img', { src: 'img/34.gif', title: 'الثكنة مستوى 10' });
t('a', { href: 'build?id=34' }, [bImg]);
const sImg = t('img', { src: 'img/20.gif', title: 'الإسطبل مستوى 3' });
t('a', { href: 'build?id=20' }, [sImg]);
const barracksJS = extractFunc('findBarracksLinkJS');
const barr = JSON.parse(eval(barracksJS));
console.log('BARRACKS:', JSON.stringify(barr));
if (barr.href !== 'https://utatar.com/build?id=34') throw new Error('FAIL barracks link, got ' + barr.href);

// ==== trainBlindJS: fills every tf[..] input with count (capped by max) and submits ====
inp11.value = ''; inp12.value = ''; inp14.value = '';
const blindJS = extractFunc('trainBlindJS').split('\\(count)').join('500');
const blindRes = JSON.parse(eval(blindJS));
console.log('BLIND:', JSON.stringify(blindRes));
if (!blindRes.ok) throw new Error('FAIL trainBlind: ' + blindRes.message);
if (inp11.value !== '500') throw new Error('FAIL blind tf[11]=500, got ' + inp11.value);
if (inp14.value !== '87') throw new Error('FAIL blind tf[14] capped to 87, got ' + inp14.value);
const tPlain11 = trainForm.children.find(c => c.getAttribute && c.getAttribute('name') === 't11' && c.value === '500');
const ft = trainForm.children.find(c => c.getAttribute && c.getAttribute('name') === 'ft');
const idh = trainForm.children.find(c => c.getAttribute && c.getAttribute('name') === 'id');
if (!tPlain11) throw new Error('FAIL train twin t11 missing');
if (!ft || ft.value !== 't1') throw new Error('FAIL ft=t1 missing');
if (!idh) throw new Error('FAIL id hidden missing');
console.log('TRAIN TWINS: t11=500 + ft=t1 + id ✓');

// ==== farmListsJS + launchFarmKickJS: raid list ground truth (farmlist.tpl) ====
const farmForm = t('form', { action: 'build.php?id=39&t=99&action=startRaid' }, [
  t('input', { type: 'hidden', name: 'action', value: 'startRaid' }),
  t('input', { type: 'hidden', name: 'a', value: 'c35' }),
  t('input', { type: 'hidden', name: 'sort', value: 'distance' }),
  t('input', { type: 'hidden', name: 'tribe', value: '2' }),
  t('input', { type: 'hidden', name: 'direction', value: 'asc' }),
  t('input', { type: 'hidden', name: 'lid', value: '7' }),
  t('input', { type: 'checkbox', class: 'markSlot', name: 'slot101' }),
  t('input', { type: 'checkbox', class: 'markSlot', name: 'slot102' }),
]);
const farmRow = t('tr', { class: 'slotRow' }, [ farmForm.children[6] ]);
const fl = JSON.parse(eval(extractFunc('farmListsJS')));
console.log('FARM LISTS:', JSON.stringify(fl));
if (fl.lists.length !== 1 || fl.lists[0].lid !== '7' || fl.lists[0].tribe !== '2') throw new Error('FAIL farm list parse: ' + JSON.stringify(fl));

// launch: native form submit (identical to user press; no fetch = no logout risk)
farmForm.submitted = false;
farmForm.requestSubmit = function() { this.submitted = true; };
const resFarm = JSON.parse(eval(extractFunc('launchFarmKickJS')));
console.log('FARM LAUNCH:', JSON.stringify(resFarm));
if (resFarm.ok !== true) throw new Error('FAIL farm launch: ' + resFarm.message);
if (!farmForm.submitted) throw new Error('FAIL farm form was NOT natively submitted');
const marks2 = farmForm.querySelectorAll('input.markSlot');
if (!marks2[0].checked) throw new Error('FAIL farm bot must auto-check the first slot');
console.log('FARM LAUNCH ✓ (native submit, first slot auto-checked, no fetch/logout risk)');

// ==== readVillageInfoJS: parses player/coords from a dorf3-style info page ====
const vbody = t('body', {}, [
  t('div', {}, [], 'قرية الحصن — اللاعب: قيس السكان: 45 (12|34)'),
]);
document.body = vbody;
const vinfoJS = extractFunc('readVillageInfoJS');
const vinfo = JSON.parse(eval(vinfoJS));
console.log('VILLAGE INFO:', JSON.stringify(vinfo));
if (String(vinfo.player).indexOf('قيس') < 0) throw new Error('FAIL village player parse: ' + vinfo.player);
if (vinfo.x !== 12 || vinfo.y !== 34) throw new Error('FAIL village coords: ' + vinfo.x + ',' + vinfo.y);

// ==== pageRecordJS: radio VALUES are now dumped (ground truth for c) ====
const recJS = extractFunc('pageRecordJS');
const recOut = eval(recJS);
if (recOut.indexOf('/radio=3') < 0) throw new Error('FAIL radio value not in record: ' + recOut.split('\n').find(l => l.startsWith('F0')));
console.log('RECORD F0:', (recOut.match(/F0[^"]*/) || ['?'])[0]);

// trainBlind beacon: after submit the form "left the page" (emulator has no body-contains)
setTimeout(async () => {
  const st = String(window.__utatarTrainCheck || 'none');
  console.log('TRAINCHECK:', st);
  if (st !== 'gone') throw new Error('FAIL train beacon state: ' + st);

  // ==== trainViaFetch: hidden GET+POST, zero navigation ====
  // fake barracks HTML: three cap formats the game uses
  const barrackHtml = [
    // واقعي: onclick بعلامات &quot; (كده اللعبة بتكتبه فعلاً)
    '<tr><td>مقاتل بهراوة</td><td><input name="tf[11]" type="tel"><a href="#" onclick="document.snd[&quot;tf[11]&quot;].value=1234; return false;">1,234</a></td></tr>',
    '<tr><td>مقاتل برمح</td><td><input name="tf[12]" type="tel"><a href="#" onclick="document.snd.tf12.value=567; return false;">567</a></td></tr>',
    '<tr><td>مقاتل بفأس</td><td><input name="tf[13]" type="tel" max="89"></td></tr>',
    // الكشاف: مفيش أي حد ظاهر غير صندوق رقم بعد الحقل
    '<tr><td>الكشاف</td><td><input name="tf[14]" type="tel"> الكمية <b>305</b> / <span>0</span></td></tr>',
  ].join('');
  const calls = [];
  const fetch = function(url, opts) {
    calls.push({ url: url, opts: opts || {} });
    if (calls.length === 1) return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(barrackHtml) });
    return Promise.resolve({ ok: true, status: 200, redirected: true });
  };
  window.__utatarFetchTrain = 'pending';
  const kickJS = extractFunc('kickFetchTrainJS')
    .split('\\(path)').join('"build?id=34"')
    .split('\\(pairs)').join('[[11,1000000],[12,200],[13,500],[14,9999]]');
  eval(kickJS);
  await sleep(60);
  const res = JSON.parse(String(window.__utatarFetchTrain));
  console.log('FETCH TRAIN:', JSON.stringify(res));
  if (res.ok !== true) throw new Error('FAIL fetch train: ' + res.message);
  if (res.message.indexOf('u11=1234/1234') < 0) throw new Error('FAIL cap u11: ' + res.message);
  if (res.message.indexOf('u14=305') < 0) throw new Error('FAIL text-box cap u14: ' + res.message);
  const post = calls[1];
  if (!post || post.url !== 'build.php') throw new Error('FAIL POST url: ' + (post && post.url));
  if (post.opts.method !== 'POST') throw new Error('FAIL POST method');
  const body = post.opts.body;
  for (const piece of ['t11=1234', 'tf%5B11%5D=1234', 't12=200', 't13=89', 't14=305', 'ft=t1', 'id=34', 's1=ok']) {
    if (body.indexOf(piece) < 0) throw new Error('FAIL body missing ' + piece + ' in ' + body);
  }
  if (calls[0].url !== 'build.php?id=34') throw new Error('FAIL GET url: ' + calls[0].url);
  console.log('HIDDEN TRAIN ✓ (u11:1234 from &quot;onclick, u12:200<567, u13:89 attr, u14:305 from row text)');

  // ==== trainReplay: EXACT recorded body, amounts capped, unknown/zero types SKIPPED ====
  calls.length = 0;
  window.__utatarFetchTrain = 'pending';
  // recorded press (what the real form would submit — all four, zeros included)
  const savedBody = 'tf%5B11%5D=0&tf%5B12%5D=0&tf%5B13%5D=0&tf%5B14%5D=0&id=34';
  const kickR = extractFunc('kickReplayTrainJS')
    .split('\\(savedUrl)').join('build?id=34')
    .split('\\(savedBody)').join(savedBody)
    .split('\\(pairs)').join('[[11,1000000],[13,500],[16,777]]');   // u16 = stable unit NOT in the recorded body
  eval(kickR);
  await sleep(60);
  const resR = JSON.parse(String(window.__utatarFetchTrain));
  console.log('REPLAY:', JSON.stringify(resR));
  if (resR.ok !== true) throw new Error('FAIL replay: ' + resR.message);
  const postR = calls[1];
  if (!postR || postR.url !== 'build?id=34') throw new Error('FAIL replay POST url: ' + (postR && postR.url));
  const rb = postR.opts.body;
  // capped recorded fields
  if (rb.indexOf('tf%5B11%5D=1234') < 0) throw new Error('FAIL replay u11 cap: ' + rb);
  if (rb.indexOf('tf%5B13%5D=89') < 0) throw new Error('FAIL replay u13 cap: ' + rb);
  // id preserved exactly
  if (rb.indexOf('id=34') < 0) throw new Error('FAIL replay id kept: ' + rb);
  // u16 (stable, cap unknown on barracks page) appended RAW — server rejects that type alone if over
  if (rb.indexOf('tf%5B16%5D=777') < 0) throw new Error('FAIL replay u16 append: ' + rb);
  // known over-cap capped, never raw
  if (rb.indexOf('=1000000') >= 0) throw new Error('FAIL replay over-cap leaked: ' + rb);
  if (resR.message.indexOf('u11=1234/1234') < 0) throw new Error('FAIL replay report: ' + resR.message);
  if (resR.message.indexOf('u16=777?') < 0) throw new Error('FAIL replay u16 report: ' + resR.message);
  console.log('REPLAY ✓ (exact fields, capped, stable unit appended raw)');

  // hook: serialization logic sanity (pure function part)
  console.log('ALL SUBMIT-REPLAY TESTS DONE');

  // ==== RECORDER (التسجيل باختيارات): a2b retreat form + farm startRaid form ====
  eval(extractFunc('recSubmitHookJS'));
  const a2bForm = t('form', { action: 'a2b.php' }, [
    t('input', { type: 'hidden', name: 'timestamp', value: '1725270000' }),
    t('input', { type: 'hidden', name: 'timestamp_checksum', value: 'abc123' }),
    t('input', { type: 'text', name: 'x', value: '10' }),
    t('input', { type: 'text', name: 'y', value: '20' }),
    t('input', { type: 'radio', name: 'c', value: '2' }),
    t('input', { type: 'radio', name: 'c', value: '4' }),
    t('input', { type: 'text', name: 't14', value: '5' }),
    t('input', { type: 'submit', name: 's1', value: 'ok' }),
  ]);
  a2bForm.querySelectorAll('input[name="c"]')[1].checked = true;  // c=4 نهب
  sessionStorage.setItem('utatarRecArm', '1');
  sessionStorage.setItem('utatarRecArmAt', String(Date.now()));
  fire('click', a2bForm.querySelector('input[name="s1"]'));
  fire('submit', a2bForm);
  const recRaw = sessionStorage.getItem('utatarRecPost');
  if (!recRaw) throw new Error('FAIL recorder: retreat submit not captured');
  const rec = JSON.parse(recRaw);
  if (rec.url !== 'a2b.php') throw new Error('FAIL recorder url: ' + rec.url);
  for (const piece of ['x=10', 'y=20', 'c=4', 't14=5', 's1=ok', 'timestamp_checksum=abc123']) {
    if (rec.body.indexOf(piece) < 0) throw new Error('FAIL recorder body missing ' + piece + ' in ' + rec.body);
  }
  if (rec.body.indexOf('c=2') >= 0) throw new Error('FAIL recorder captured unchecked radio');
  if (sessionStorage.getItem('utatarRecArm') !== '0') throw new Error('FAIL recorder arm not consumed');
  const rr = JSON.parse(eval(extractFunc('readRecordingJS')));
  if (rr.has !== true || rr.body !== rec.body) throw new Error('FAIL readRecording: ' + JSON.stringify(rr));
  const rr2 = JSON.parse(eval(extractFunc('readRecordingJS')));
  if (rr2.has !== false) throw new Error('FAIL recording not consumed');
  // farm form recording (no submit button click — hidden fields only)
  sessionStorage.setItem('utatarRecArm', '1');
  fire('submit', farmForm);
  const fr = JSON.parse(sessionStorage.getItem('utatarRecPost'));
  for (const piece of ['action=startRaid', 'a=c35', 'lid=7', 'tribe=2', 'slot101=']) {
    if (fr.body.indexOf(piece) < 0) throw new Error('FAIL farm rec body missing ' + piece + ' in ' + fr.body);
  }
  // unarmed submits are ignored
  sessionStorage.removeItem('utatarRecPost');
  sessionStorage.setItem('utatarRecArm', '0');
  fire('submit', a2bForm);
  if (sessionStorage.getItem('utatarRecPost')) throw new Error('FAIL recorder captured while unarmed');
  console.log('RECORDER ✓ (retreat a2b with x/y/c=4/s1 + farm startRaid; arm consumed; unarmed ignored)');

  console.log('\nALL JS TESTS PASSED ✅');
}, 4600);
