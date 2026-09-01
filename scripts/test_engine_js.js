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
  querySelectorAll(sel) { return this.els.filter(el => matches(el, sel)); },
};
const window = { location: { href: 'https://utatar.com/build?id=34' } };
const document = {
  title: 'عصر التتار5',
  body: null,
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
const inp12 = t('input', { name: 'tf[12]', type: 'tel' });
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
if (inp11.value !== '500') throw new Error('FAIL tf[11] value, got ' + inp11.value);
if (inp14.value !== '87') throw new Error('FAIL tf[14] value 87, got ' + inp14.value);
if (!trainForm.children.find(c => c.clicked)) throw new Error('FAIL submit button not clicked');

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
const mapScanJS = extractStatic('mapScanJS');
const mv = JSON.parse(eval(mapScanJS));
console.log('MAP:', JSON.stringify(mv));
if (!mv.length) throw new Error('FAIL map scan found nothing');
const v = mv.find(x => x.vid === '998877');
if (!v || v.x !== 7 || v.player.indexOf('علي') < 0) throw new Error('FAIL map village parse');

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
  t('input', { name: 'c', type: 'radio', value: '1' }),
  t('input', { name: 'c', type: 'radio', value: '2' }),
  t('input', { name: 'c', type: 'radio', value: '3' }),
  t('button', { type: 'submit' }, [], 'إرسال'),
]);
const xi = sendForm.children.find(c => c.getAttribute('name') === 'x');
const yi = sendForm.children.find(c => c.getAttribute('name') === 'y');
xi.value = ''; yi.value = '';
axeInp.value = ''; scoutInp.value = '';
const sendJS = extractFunc('sendTroopsJS')
  .split('\\(x)').join('12').split('\\(y)').join('34')
  .replace('var pairs=\\(arr);', 'var pairs=[[14,3]];')
  .replace('var modeVals=\\(mv);', 'var modeVals=[3,4,2];');
const scoutRes = JSON.parse(eval(sendJS));
console.log('SCOUT:', JSON.stringify(scoutRes));
if (!scoutRes.sent) throw new Error('FAIL scout send: ' + scoutRes.message);
if (scoutInp.value !== '3') throw new Error('FAIL scout value 3, got ' + scoutInp.value);
if (axeInp.value) throw new Error('FAIL axe must stay empty');
if (xi.value !== '12' || yi.value !== '34') throw new Error('FAIL coords not filled: ' + xi.value + ',' + yi.value);
const radios = sendForm.querySelectorAll('input[name="c"]');
const raidClicked = radios.find(r => r.clicked);
if (!raidClicked || raidClicked.getAttribute('value') !== '3') {
  console.log('DBG radios found:', radios.length, radios.map(r => ({v: r.getAttribute('value'), val: r.value, clicked: r.clicked})));
  console.log('DBG modeVals line:', (sendJS.split('\n').find(l => l.includes('modeVals')) || '').trim());
  throw new Error('FAIL raid radio value 3 not clicked');
}
if (!sendForm.children.find(c => c.clicked)) throw new Error('FAIL send button not clicked');

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

console.log('\nALL JS TESTS PASSED ✅');
