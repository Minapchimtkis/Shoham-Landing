/* ═══════════════════════════════════════════════════════════════
   כמה יש לי · הלוגיקה
   ═══════════════════════════════════════════════════════════════

   ‏שלוש החלטות שמסבירות כמעט כל שורה בקובץ:

   1. ‏כסף הוא מספר שלם באגורות, מהקלדה ועד למסך. שום חישוב אינו
      נוגע בנקודה עשרונית, כי 0.1 + 0.2 אינו 0.3 וזה הבאג שאי אפשר
      לתקן אחרי שיש נתונים.

   2. ‏חודש הוא אובייקט Date של ה-1 בחודש בשעון המקומי. אין מחרוזות
      חודש, ואין toISOString, שמזיז את התאריך לאחור בכל שעון שמוקדם
      מ-UTC ולכן גם בשלנו.

   3. ‏המסך נגזר מהמצב, והמצב נגזר מהבסיס. אין שום מקום שבו המסך
      מתעדכן בלי שהנתון עבר קודם. זה מה שמונע את המצב שבו המספר על
      המסך נכון והנתון בבסיס לא.
*/

/* ‏הספרייה יושבת אצלנו ולא ב-CDN. ספרייה שנטענת מרשת זרה רצה
   ‏אצל המשתמש עם ההרשאות שלו ורואה כל מה שהוא רואה, ולייבוא ESM
   ‏אין SRI · אין דרך לומר "רק הקובץ הזה ולא אחר". ראה app/vendor. */
import { createClient } from './vendor/supabase.js';
import { mountImport } from './import.js';

/* ‏אותו פרויקט ואותו מפתח פרסום כמו בשאר הדפים. אין כאן סוד:
   המפתח הזה נועד לרוץ בדפדפן, והוא לבדו אינו מאפשר דבר. מה שמגן
   על הנתונים הוא אבטחת השורות בבסיס, שבה כל גישה נגזרת מחברות
   במשק הבית ומשום מקום אחר. */
const SUPABASE_URL = 'https://vplqocqmlquajwwnyeby.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_R8cgR0cpcFP4RdTyS7IGWQ_925TH_KY';

/* ‏נקרא לפני יצירת הלקוח, כי detectSessionInUrl מנקה את הכתובת
   ‏ברגע שהוא קם. הסימן הוא פרמטר משלנו ולא ה-hash של Supabase,
   ‏כי ה-hash משתנה בין זרימת הטוקן לזרימת ה-PKCE והפרמטר שלנו
   ‏שורד את שתיהן. בלי הסימן הזה מי שחוזר מהמייל נכנס ישר
   ‏לאפליקציה · עם סשן תקף, ובלי שהחליף סיסמה. */
const FROM_MAIL_RESET = new URLSearchParams(location.search).get('mode') === 'reset';

const sb = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

/* ‏עשרה תווים ולא שמונה. זה החשבון שמחזיק דוח יתרות וסילוקין,
   ‏וכל תו נוסף שווה יותר מכל כלל "אות גדולה וסימן" שרק גורם
   ‏לאנשים לבחור Password1!. את הבדיקה מול סיסמאות שדלפו עושה
   ‏Supabase עצמו, בהגדרה בפרויקט. */
const MIN_PASS = 10;

/* ‏סיסמה שהיא האימייל, או רק ספרות, היא לא סיסמה. שתי הבדיקות
   ‏האלה תופסות את רוב מה שאנשים באמת מקלידים. */
function passProblem(pass, email) {
  if (pass.length < MIN_PASS) return `הסיסמה צריכה להיות באורך ${MIN_PASS} תווים לפחות.`;
  if (/^\d+$/.test(pass)) return 'סיסמה שכולה ספרות קלה מדי לניחוש. כדאי להוסיף מילה.';
  const local = (email || '').split('@')[0].toLowerCase();
  if (local.length >= 4 && pass.toLowerCase().includes(local))
    return 'הסיסמה מכילה את האימייל שלכם. כדאי משהו אחר.';
  return null;
}

/* ───────────────────────────────────────────────── עזרים ── */

const $  = id => document.getElementById(id);
const el = (tag, cls, txt) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (txt != null) n.textContent = txt;
  return n;
};
const show = n => n && n.classList.remove('hidden');
const hide = n => n && n.classList.add('hidden');

/* ‏כסף פנימה. מקבל מה שאדם מקליד ומחזיר אגורות שלמות.
   הפסיק הוא מפריד אלפים ולא נקודה עשרונית, כי כך כותבים כאן. */
function toAgorot(raw) {
  const s = String(raw == null ? '' : raw).replace(/[\s‏‎₪,]/g, '');
  if (!s || !/^\d*\.?\d*$/.test(s)) return null;
  const n = parseFloat(s);
  if (!isFinite(n) || n < 0) return null;
  // ‏עיגול ולא חיתוך: 45.995 הוא 46 שקל ולא 45.99.
  return Math.round(n * 100);
}

/* ‏כסף החוצה. אגורות מוצגות רק כשהן אינן אפס, כי ".00" בסוף כל
   מספר על המסך הוא רעש בארבעה תווים. */
function fmtNum(ag) {
  const n = Math.abs(Math.round(ag || 0));
  const sh = Math.floor(n / 100), ar = n % 100;
  let s = sh.toLocaleString('en-US');
  if (ar) s += '.' + String(ar).padStart(2, '0');
  return s;
}
function fmt(ag, withSign) {
  return (withSign && (ag || 0) < 0 ? '−' : '') + '₪' + fmtNum(ag);
}

/* ‏הש"ח אינו חלק מהמספר, הוא סימן לידו.
   ‏הסריף טעון עם הספרות בלבד, ולכן הש"ח נופל ל-Heebo. במשקל של
   המספר הוא יוצא בלוק כבד שמתחרה בו. כאן הוא נכתב בנפרד, קטן
   ושקט, והספרה נשארת הדבר שרואים. */
function setMoney(node, ag, withSign) {
  node.textContent = '';
  if (withSign && (ag || 0) < 0) node.append(document.createTextNode('−'));
  node.append(el('span', 'cur', '₪'), document.createTextNode(fmtNum(ag)));
  return node;
}
function moneyEl(ag, cls) {
  return setMoney(el('span', 'money' + (cls ? ' ' + cls : '')), ag);
}

const DAY = 86400000;
const pad2 = n => String(n).padStart(2, '0');
/* ‏תאריך מקומי. toISOString היה מחזיר כאן את היום הקודם בכל
   תאריך שנוצר לפני 02:00 או 03:00 בבוקר. */
const isoDate  = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const monthOf  = d => new Date(d.getFullYear(), d.getMonth(), 1);
const monthKey = d => isoDate(monthOf(d));
const addMonths = (d, k) => new Date(d.getFullYear(), d.getMonth() + k, 1);
const daysInMonth = d => new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
const sameMonth = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();

/* ───────────────────────────────────────── תקופה ──
   ‏יש מי שמנהל תקציב מהעשירי עד העשירי, כי כך הכרטיס שלו מחייב.
   מבחינת יועץ זאת לא המסגרת הנכונה, ובוודאי לא לשנה: תקופה כזאת
   זוחלת, ושנה כזאת אינה שנים עשר חודשים שלמים.

   ‏לכן הבחירה חלה על מקום אחד בלבד · החלון שדרכו רואים תנועות.
   התקציב נשאר מקובע לחודש הקלנדרי שבו התקופה נפתחת, ומכאן שסיכום
   השנה הוא קלנדרי מעצם המבנה ולא בזכות תנאי שמישהו זכר לכתוב. */

const atNoon = iso => new Date(iso + 'T12:00:00');

function periodRange(anchor) {
  const c = S.cycle || 1;
  if (c === 1) {
    return { from: monthKey(anchor),
             to: isoDate(new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0)) };
  }
  return { from: isoDate(new Date(anchor.getFullYear(), anchor.getMonth(), c)),
           to:   isoDate(new Date(anchor.getFullYear(), anchor.getMonth() + 1, c - 1)) };
}

/* ‏חודש העוגן של התקופה שהיום נמצא בה. ב-5 באוקטובר עם מחזור
   שמתחיל בעשירי, התקופה הפעילה היא זו שנפתחה ב-10 בספטמבר. */
function currentAnchor(d) {
  const now = d || new Date();
  const c = S.cycle || 1;
  return now.getDate() >= c ? monthOf(now) : addMonths(monthOf(now), -1);
}

const inCurrentPeriod = () => monthKey(S.month) === monthKey(currentAnchor());

function daysInPeriod(anchor) {
  const { from, to } = periodRange(anchor);
  return Math.round((atNoon(to) - atNoon(from)) / DAY) + 1;
}

/* ‏באיזה יום בתוך התקופה אנחנו. אחד הוא היום הראשון שלה. */
function dayOfPeriod(anchor, d) {
  const { from } = periodRange(anchor);
  return Math.round((atNoon(isoDate(d || new Date())) - atNoon(from)) / DAY) + 1;
}

const MFMT = new Intl.DateTimeFormat('he-IL', { month: 'long' });
function monthName(d) {
  const now = new Date();
  const m = MFMT.format(d);
  return d.getFullYear() === now.getFullYear() ? m : `${m} ${d.getFullYear()}`;
}
const SHORT = new Intl.DateTimeFormat('he-IL', { day: 'numeric', month: 'numeric' });
function periodLabel(anchor) {
  if ((S.cycle || 1) === 1) return monthName(anchor);
  const { from, to } = periodRange(anchor);
  return `${SHORT.format(atNoon(from))} עד ${SHORT.format(atNoon(to))}`;
}

const DFMT = new Intl.DateTimeFormat('he-IL', { weekday: 'long', day: 'numeric', month: 'long' });
function dayName(iso) {
  const d = new Date(iso + 'T12:00:00');
  const today = new Date(), yest = new Date(Date.now() - DAY);
  if (isoDate(today) === iso) return 'היום';
  if (isoDate(yest)  === iso) return 'אתמול';
  return DFMT.format(d);
}

function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.add('on');
  clearTimeout(t._t);
  t._t = setTimeout(() => t.classList.remove('on'), 2400);
  // ‏נאמר בנפרד, כדי שמי שמקשיב ישמע גם אחרי שההודעה דהתה
  $('say').textContent = msg;
}

function setErr(node, msg) {
  if (!msg) { hide(node); node.textContent = ''; return; }
  node.textContent = msg;
  show(node);
}

/* ‏מה שבסיס הנתונים מחזיר אינו מה שאדם צריך לקרוא. כל שגיאה
   שאין לה תרגום מקבלת נוסח אחד שאומר מה לעשות ולא מה נשבר. */
function human(error) {
  const m = String(error?.message || error || '').toLowerCase();
  if (m.includes('invalid login')) return 'האימייל או הסיסמה אינם נכונים.';
  if (m.includes('already registered') || m.includes('already been registered'))
    return 'כבר יש חשבון עם האימייל הזה. אפשר להיכנס איתו.';
  if (m.includes('password') && m.includes('6'))  return `הסיסמה צריכה להיות באורך ${MIN_PASS} תווים לפחות.`;
  if (m.includes('pwned') || m.includes('compromised') || m.includes('leaked'))
    return 'הסיסמה הזאת מופיעה בדליפות ידועות. כדאי לבחור אחרת.';
  if (m.includes('weak') || m.includes('password should'))
    return `הסיסמה קצרה או פשוטה מדי. ${MIN_PASS} תווים לפחות.`;
  if (m.includes('same password') || m.includes('should be different'))
    return 'זאת הסיסמה הקודמת. צריך לבחור אחת חדשה.';
  if (m.includes('email') && m.includes('invalid')) return 'כתובת האימייל אינה תקינה.';
  if (m.includes('email not confirmed')) return 'החשבון עוד לא אושר. יש לפתוח את הקישור שנשלח במייל.';
  if (m.includes('rate limit') || m.includes('too many'))
    return 'יותר מדי ניסיונות. כדאי לנסות שוב בעוד דקה.';
  if (m.includes('relation') && m.includes('does not exist'))
    return 'מסד הנתונים של האפליקציה עוד לא הוקם. יש להריץ את המיגרציה.';
  if (m.includes('failed to fetch') || m.includes('network'))
    return 'אין חיבור לרשת כרגע. הנתונים לא אבדו, רק לא נשמרו עוד.';
  return 'משהו לא עבד. כדאי לנסות שוב.';
}

/* ───────────────────────────────────────────────── המצב ── */

const S = {
  user: null,
  recovery: false,          // ‏באמצע החלפת סיסמה · לא נכנסים לאפליקציה
  hh: null,
  profile: null,
  month: monthOf(new Date()),
  cats: [],                 // כל הקטגוריות הגלויות
  budgets: new Map(),       // category_id → agorot
  txs: [],                  // תנועות החודש הנבחר
  prevTxs: null,            // החודש שלפניו, לצורך ההשוואה בלבד
  reflections: [],
  tab: 'home',
  cycle: 1,
  filterCat: null,
  txFilter: 'all',
  hist: null,
  mode: 'signup',
  asked: false,             // לא שואלים יותר מפעם אחת בביקור
  lastLeft: null
};

const byId  = id => S.cats.find(c => c.id === id);
const outCats = () => S.cats.filter(c => c.kind === 'expense' && !c.archived)
                            .sort((a, b) => a.sort - b.sort || a.label.localeCompare(b.label, 'he'));
const inCats  = () => S.cats.filter(c => c.kind === 'income'  && !c.archived)
                            .sort((a, b) => a.sort - b.sort);

const planned   = id => S.budgets.get(id) || 0;
const plannedOut = () => outCats().reduce((s, c) => s + planned(c.id), 0);
const plannedIn  = () => inCats().reduce((s, c) => s + planned(c.id), 0);
/* ‏העברה אינה הוצאה. מי שמעביר אלפיים לחיסכון לא הוציא אלפיים,
   הוא העביר אותם לכיס אחר, ואפליקציה שסופרת את זה כהוצאה משקרת
   במספר הגדול שהוא כל האפליקציה. כל ספירה כאן מדלגת עליהן. */
const real = t => !t.is_transfer;
const spentIn = id => S.txs.reduce((s, t) =>
  s + (real(t) && t.direction === 'out' && t.category_id === id ? t.amount_agorot : 0), 0);
const spentAll = () => S.txs.reduce((s, t) => s + (real(t) && t.direction === 'out' ? t.amount_agorot : 0), 0);
const gotAll   = () => S.txs.reduce((s, t) => s + (real(t) && t.direction === 'in'  ? t.amount_agorot : 0), 0);
const movedAll = () => S.txs.reduce((s, t) => s + (t.is_transfer ? t.amount_agorot : 0), 0);

/* ‏המספר של האפליקציה.
   ‏כשיש תכנון, התשובה היא מה שנשאר ממנו.
   ‏כשאין, "נשאר מהתכנון" חסר משמעות, ואז התשובה נמדדת בכסף
   אמיתי: מה שנכנס בפועל פחות מה שיצא. חודש שיובא מדף בנק הוא
   בדיוק המקרה הזה, ובלי זה הוא היה מוצג כחריגה של כל ההוצאות
   שבו דווקא בחודש שנכנסה בו משכורת מלאה. */
function leftToSpend() {
  const p = plannedOut();
  if (p > 0) return p - spentAll();
  return (gotAll() || plannedIn()) - spentAll();
}

/* ─────────────────────────────────────────── גלונים ── */

let openEl = null, lastFocus = null;

function openSheet(node) {
  if (openEl) closeSheet();
  lastFocus = document.activeElement;
  openEl = node;
  show($('scrim')); show(node);
  // ‏פריים אחד לפני שמדליקים את המחלקה, אחרת הדפדפן מצייר את
  // המצב הסופי ישר ואין מעבר.
  requestAnimationFrame(() => {
    $('scrim').classList.add('on');
    node.classList.add('on');
  });
  document.body.style.overflow = 'hidden';
  const first = node.querySelector('input:not([type=hidden]),button,select,textarea,[href]');
  if (first) setTimeout(() => first.focus({ preventScroll: true }), 60);
}

function closeSheet() {
  if (!openEl) return;
  const node = openEl;
  openEl = null;
  node.classList.remove('on');
  $('scrim').classList.remove('on');
  document.body.style.overflow = '';
  setTimeout(() => { hide(node); hide($('scrim')); }, 240);
  if (lastFocus && lastFocus.isConnected) lastFocus.focus({ preventScroll: true });
}

/* ‏מלכודת טאב. בלעדיה הטאב יוצא מתוך הגלון אל הדף שמאחוריו,
   שמוסתר מהעין אבל לא מהמקלדת. */
document.addEventListener('keydown', e => {
  if (!openEl) return;
  if (e.key === 'Escape') { e.preventDefault(); closeSheet(); return; }
  if (e.key !== 'Tab') return;
  const f = [...openEl.querySelectorAll('input:not([type=hidden]),button,select,textarea,[href]')]
    .filter(n => !n.disabled && n.offsetParent !== null);
  if (!f.length) return;
  const first = f[0], last = f[f.length - 1];
  if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
  else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
});

$('scrim').addEventListener('click', closeSheet);

/* ─────────────────────────────────────── מסכים ראשיים ── */

function stage(name) {
  for (const id of ['boot', 'gate', 'setup', 'app']) {
    id === name ? show($(id)) : hide($(id));
  }
  $('boot').removeAttribute('aria-busy');
}

/* ‏ייבוא ומסמכים אינם לשוניות בניווט אלא מסכים שנפתחים מתוך
   ההגדרות. הם מסמנים את ההגדרות כמקום שממנו הגיעו, ומסתירים
   את בורר החודש, שאין לו שם משמעות. */
const SUB = { import: 'set', docs: 'set', sum: 'set', goals: 'set', year: 'set', assets: 'set' };

function tab(name) {
  S.tab = name;
  const map = { home: 'scHome', tx: 'scTx', budget: 'scBudget', set: 'scSet',
                import: 'scImport', docs: 'scDocs', sum: 'scSum', goals: 'scGoals',
                year: 'scYear', assets: 'scAssets' };
  for (const [k, v] of Object.entries(map)) k === name ? show($(v)) : hide($(v));

  const current = SUB[name] || name;
  for (const b of document.querySelectorAll('.nav button[data-tab]')) {
    b.dataset.tab === current ? b.setAttribute('aria-current', 'page')
                              : b.removeAttribute('aria-current');
  }
  document.querySelector('.topbar').classList.toggle('hidden', !!SUB[name]);

  if (name === 'tx') renderTx();
  if (name === 'budget') renderBudget();
  if (name === 'set') renderSet();
  if (name === 'import') IMP.openImport();
  if (name === 'docs') IMP.openDocs();
  if (name === 'sum') renderSum();
  if (name === 'goals') renderGoals();
  if (name === 'year') renderYear();
  if (name === 'assets') renderAssets();
  window.scrollTo({ top: 0 });
}

/* ═════════════════════════════════════ כניסה והרשמה ══ */

function authMode(mode) {
  S.mode = mode;
  const signup = mode === 'signup';
  $('authBtn').textContent        = signup ? 'פתיחת חשבון' : 'כניסה';
  $('authSwitchText').textContent = signup ? 'יש לכם כבר חשבון?' : 'עוד אין לכם חשבון?';
  $('authToggle').textContent     = signup ? 'כניסה' : 'פתיחת חשבון';
  $('authPass').setAttribute('autocomplete', signup ? 'new-password' : 'current-password');
  /* ‏בכניסה מקלידים סיסמה קיימת, ולכן מספר התווים הנדרש אינו
     ‏רלוונטי שם · הוא רק נראה כמו דרישה שהמשתמש כבר לא יכול
     ‏לעמוד בה אם החשבון שלו ישן. */
  $('authPass').placeholder = signup ? `לפחות ${MIN_PASS} תווים` : 'הסיסמה שלכם';
  if (signup) $('authPass').setAttribute('minlength', MIN_PASS);
  else        $('authPass').removeAttribute('minlength');
  $('authLegal').classList.toggle('hidden', !signup);
  $('forgotLine').classList.toggle('hidden', signup);
  setErr($('authErr'), '');
}

$('authToggle').addEventListener('click', () => authMode(S.mode === 'signup' ? 'login' : 'signup'));

$('authForm').addEventListener('submit', async e => {
  e.preventDefault();
  setErr($('authErr'), '');
  const email = $('authEmail').value.trim();
  const pass  = $('authPass').value;

  if (!email || !email.includes('@')) {
    setErr($('authErr'), 'צריך כתובת אימייל תקינה.');
    $('authEmail').focus(); return;
  }
  /* ‏רק בהרשמה. בכניסה סיסמה קיימת וקצרה היא עניין של השרת,
     ‏וחסימה מקומית שלה רק מונעת ממי שיש לו חשבון ישן להיכנס. */
  if (S.mode === 'signup') {
    const bad = passProblem(pass, email);
    if (bad) { setErr($('authErr'), bad); $('authPass').focus(); return; }
  }

  const btn = $('authBtn');
  btn.disabled = true;
  btn.textContent = S.mode === 'signup' ? 'פותח חשבון...' : 'נכנס...';

  try {
    if (S.mode === 'signup') {
      const { data, error } = await sb.auth.signUp({
        email, password: pass,
        options: { emailRedirectTo: window.location.origin + '/app/' }
      });
      if (error) throw error;

      /* ‏שני עולמות, ואי אפשר לדעת מראש באיזה מהם אנחנו: אם אישור
         אימייל כבוי בפרויקט, ההרשמה מחזירה מפתח גישה ואפשר להיכנס
         מיד. אם הוא דלוק, היא מחזירה משתמש בלי מפתח, ואז הדבר
         היחיד שאפשר לעשות הוא להגיד לו לפתוח את המייל. */
      if (data.session) { await enter(data.session.user); return; }

      /* ‏משתמש שכבר קיים מוחזר כאן בלי שגיאה ועם רשימת זהויות
         ריקה. בלי הבדיקה הזאת הוא היה מקבל "שלחנו מייל" לנצח. */
      if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
        authMode('login');
        setErr($('authErr'), 'כבר יש חשבון עם האימייל הזה. אפשר להיכנס איתו.');
        return;
      }
      $('sentHead').textContent = 'שלחנו לכם מייל';
      $('sentMail').textContent = email;
      $('sentWhy').textContent =
        'ולחצו על הקישור כדי לאשר את החשבון. אחר כך חוזרים לכאן ונכנסים.';
      gateScreen('sent');
      return;
    }

    const { data, error } = await sb.auth.signInWithPassword({ email, password: pass });
    if (error) throw error;
    await enter(data.user);

  } catch (err) {
    setErr($('authErr'), human(err));
  } finally {
    btn.disabled = false;
    /* ‏כאן היה authMode, והוא מנקה את הודעת השגיאה בסופו. כלומר
       כל שגיאה שהגיעה מהשרת נכתבה ונמחקה באותו רגע, ומי שהקליד
       סיסמה שגויה ראה טופס שלא קרה בו כלום. רק התווית חוזרת. */
    btn.textContent = S.mode === 'signup' ? 'פתיחת חשבון' : 'כניסה';
  }
});

$('sentBack').addEventListener('click', () => {
  gateScreen('main');
  authMode('login');
});

/* ════════════════════════════════════ איפוס סיסמה ══ */

/* ‏ארבעה מסכים בתוך השער, ואחד מהם גלוי בכל רגע. */
function gateScreen(which) {
  for (const [k, id] of [['main','gateMain'], ['sent','gateSent'],
                         ['forgot','gateForgot'], ['new','gateNew']]) {
    $(id).classList.toggle('hidden', k !== which);
  }
}

$('authForgot').addEventListener('click', () => {
  $('forgotEmail').value = $('authEmail').value.trim();
  setErr($('forgotErr'), '');
  gateScreen('forgot');
  $('forgotEmail').focus();
});

$('forgotBack').addEventListener('click', () => gateScreen('main'));

/* ‏השהיה מקומית, כדי שלחיצה חוזרת לא תיתקל בחסימת הקצב של
   ‏השרת ותחזיר שגיאה שנראית כאילו משהו שבור. לפי כתובת ולא
   ‏גלובלית · מי שהקליד את האימייל בטעות צריך לתקן ולשלוח מיד,
   ‏ולא לחכות דקה בגלל שגיאת הקלדה. */
const sentAt = new Map();

$('forgotForm').addEventListener('submit', async e => {
  e.preventDefault();
  setErr($('forgotErr'), '');
  const email = $('forgotEmail').value.trim();
  if (!email || !email.includes('@')) {
    setErr($('forgotErr'), 'צריך כתובת אימייל תקינה.');
    $('forgotEmail').focus(); return;
  }
  const key = email.toLowerCase();
  const wait = Math.ceil((60000 - (Date.now() - (sentAt.get(key) || 0))) / 1000);
  if (wait > 0) {
    setErr($('forgotErr'), `כבר שלחנו. אפשר לנסות שוב בעוד ${wait} שניות.`);
    return;
  }

  const btn = $('forgotBtn');
  btn.disabled = true;
  btn.textContent = 'שולח...';
  try {
    /* ‏הכתובת שחוזרים אליה נושאת סימן משלנו, כדי שהאפליקציה
       ‏תדע שזאת חזרה מאיפוס ולא כניסה רגילה. */
    await sb.auth.resetPasswordForEmail(email, {
      redirectTo: location.origin + location.pathname + '?mode=reset'
    });
    sentAt.set(key, Date.now());
  } catch {}
  finally {
    btn.disabled = false;
    btn.textContent = 'שליחת קישור';
  }

  /* ‏אותו מסך בדיוק גם אם אין חשבון כזה. אחרת הטופס הזה הופך
     ‏לכלי שבודק אילו כתובות רשומות אצלנו. */
  $('sentHead').textContent = 'שלחנו לכם קישור';
  $('sentMail').textContent = email;
  $('sentWhy').textContent =
    'אם יש חשבון עם הכתובת הזאת, הקישור לבחירת סיסמה חדשה כבר בדרך. הוא תקף לשעה.';
  gateScreen('sent');
});

/* ‏החזרה מהקישור. המשתמש כבר מחובר כאן, ולכן שני הדברים
   ‏החשובים הם לא להכניס אותו פנימה לפני שהחליף, ולנתק אחר כך
   ‏כל מכשיר אחר שעוד מחזיק סשן ישן. */
function openNewPass(msg) {
  S.recovery = true;
  stage('gate');
  gateScreen('new');
  setErr($('newErr'), msg || '');
  $('newPass').focus();
}

$('newForm').addEventListener('submit', async e => {
  e.preventDefault();
  setErr($('newErr'), '');
  const a = $('newPass').value, b = $('newPass2').value;

  const bad = passProblem(a, '');
  if (bad) { setErr($('newErr'), bad); $('newPass').focus(); return; }
  if (a !== b) {
    setErr($('newErr'), 'שתי הסיסמאות אינן זהות.');
    $('newPass2').focus(); return;
  }

  const btn = $('newBtn');
  btn.disabled = true;
  btn.textContent = 'שומר...';
  try {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) throw new Error('recovery expired');

    const { error } = await sb.auth.updateUser({ password: a });
    if (error) throw error;

    /* ‏מי שאיפס סיסמה עשה את זה לרוב כי משהו הדאיג אותו. כל סשן
       ‏אחר שנשאר פתוח במכשיר אחר נסגר כאן. אם גרסת הספרייה לא
       ‏מכירה את ה-scope הזה, לא נורא · הסיסמה כבר הוחלפה. */
    try { await sb.auth.signOut({ scope: 'others' }); } catch {}

    S.recovery = false;
    history.replaceState(null, '', location.pathname);
    const { data: { user } } = await sb.auth.getUser();
    if (user) { await enter(user); toast('הסיסמה הוחלפה.'); return; }
    throw new Error('no user');

  } catch (err) {
    const m = String(err?.message || '').toLowerCase();
    if (m.includes('expired') || m.includes('no user') || m.includes('session')) {
      setErr($('newErr'), 'הקישור כבר לא תקף. אפשר לבקש קישור חדש ממסך הכניסה.');
    } else {
      setErr($('newErr'), human(err));
    }
  } finally {
    btn.disabled = false;
    btn.textContent = 'שמירה וכניסה';
  }
});

$('setOut').addEventListener('click', async () => {
  await sb.auth.signOut();
  location.reload();
});

/* ═══════════════════════════════════════════ ההקמה ══ */

/* ‏שש קטגוריות, לא שלוש עשרה. רשימה ארוכה בהקמה הראשונה היא
   הדרך הבטוחה לכך שאיש לא ימלא אותה. */
const SETUP_ROWS = [
  { key: 'housing',   icon: '🏠', label: 'דיור',    hint: 'שכירות או משכנתא, ארנונה, חשמל, ועד' },
  { key: 'food',      icon: '🛒', label: 'מזון',    hint: 'סופר, שוק, אוכל בחוץ' },
  { key: 'transport', icon: '🚗', label: 'תחבורה',  hint: 'דלק, ביטוח, רב קו' },
  { key: 'debt',      icon: '🏦', label: 'החזרים',  hint: 'הלוואות, מינוס, כרטיס' },
  { key: 'fun',       icon: '🎬', label: 'בילויים', hint: 'מסעדות, חופשות, מנויים' },
  { key: 'other',     icon: '•',  label: 'כל השאר', hint: 'מה שלא נכנס למעלה' }
];

function buildSetup() {
  const box = $('setupCats');
  box.textContent = '';
  for (const r of SETUP_ROWS) {
    const row = el('div', 'num-row');
    const ic = el('span', 'ico', r.icon); ic.setAttribute('aria-hidden', 'true');
    const lab = el('label', 'nm', r.label);
    lab.htmlFor = 's_' + r.key;
    lab.append(el('small', null, r.hint));
    const wrap = el('span', 'amt');
    const inp = el('input');
    inp.id = 's_' + r.key;
    inp.type = 'text'; inp.inputMode = 'decimal';
    inp.autocomplete = 'off'; inp.placeholder = '0';
    inp.dataset.key = r.key;
    wrap.append(inp);
    row.append(ic, lab, wrap);
    box.append(row);
  }
  $('setup').addEventListener('input', setupLive);

  /* ‏הסרגל התחתון קבוע במקומו ולכן הוא מכסה את השורה האחרונה.
     הרמז שבתוכו מתחלף לפי מה שהוקלד, ולכן גם הגובה שלו מתחלף,
     ומספר קבוע בגיליון הסגנון היה נכון רק לאחד הנוסחים. נמדד. */
  const bar = document.querySelector('.setup-bar');
  const fit = () => { $('setup').style.paddingBottom = (bar.offsetHeight + 26) + 'px'; };
  if (window.ResizeObserver) new ResizeObserver(fit).observe(bar);
  fit();

  setupLive();
}

function setupNumbers() {
  const income = toAgorot($('s_income').value) || 0;
  let out = 0;
  const budget = {};
  for (const r of SETUP_ROWS) {
    const v = toAgorot($('s_' + r.key).value) || 0;
    if (v > 0) budget[r.key] = v;
    out += v;
  }
  return { income, out, budget };
}

/* ‏הקורא החי. הוא הסיבה שההקמה היא מסך אחד ולא שישה שלבים: כל
   מספר שנכנס מזיז מספר אחד למטה, ואז מילוי טופס הופך למשחק. */
function setupLive() {
  const { income, out } = setupNumbers();
  const left = income - out;
  const v = $('setupLeft');
  setMoney(v, left, true);
  v.classList.toggle('over', left < 0);

  if (!income) {
    $('setupLeftLabel').textContent = 'נשאר לתכנן';
    $('setupHint').textContent = 'מתחילים מההכנסה.';
  } else if (left > 0) {
    $('setupLeftLabel').textContent = 'נשאר לתכנן';
    $('setupHint').textContent = 'זה מה שעוד לא שובץ לשום מקום. אם הוא נשאר ככה, הוא ההפרש שלכם בסוף החודש.';
  } else if (left === 0) {
    $('setupLeftLabel').textContent = 'הכול משובץ';
    $('setupHint').textContent = 'כל שקל שנכנס יש לו מקום. זה תכנון מדויק, ואין בו מרווח.';
  } else {
    $('setupLeftLabel').textContent = 'חסר';
    $('setupHint').textContent = 'התכנון גדול מההכנסה. זה לא תקלה בטופס, זה מה שקורה בפועל אצל רבים, ובדיוק בשביל זה אנחנו כאן.';
  }
}

$('setupBtn').addEventListener('click', async () => {
  setErr($('setupErr'), '');
  const { income, out, budget } = setupNumbers();

  if (!income && !out) {
    setErr($('setupErr'), 'צריך לפחות מספר אחד כדי להתחיל. ההכנסה היא המקום הטבעי.');
    $('s_income').focus(); return;
  }

  const btn = $('setupBtn');
  btn.disabled = true; btn.textContent = 'מקים...';
  try {
    const name = $('s_name').value.trim();
    const { data, error } = await sb.rpc('setup_household', {
      p_name: name || null, p_income: income, p_budget: budget
    });
    if (error) throw error;
    S.hh = data;
    await loadAll();
    stage('app');
    tab('home');
    toast('הכול מוכן. ברוכים הבאים.');
  } catch (err) {
    setErr($('setupErr'), human(err));
  } finally {
    btn.disabled = false; btn.textContent = 'סיימתי, קחו אותי לפנים';
  }
});

/* ═══════════════════════════════════════ טעינת נתונים ══ */

async function findHousehold() {
  const { data, error } = await sb.from('household_members')
    .select('household_id').limit(1);
  if (error) throw error;
  return data && data.length ? data[0].household_id : null;
}

async function loadAll() {
  /* ‏התקציב נשמר תחת החודש הקלנדרי. התנועות נקראות לפי החלון
     שהמשתמש בחר. זאת כל ההפרדה. */
  const m0 = monthKey(S.month);
  const { from: p0, to: p1 } = periodRange(S.month);

  const [cats, buds, txs, refl, prof, hh] = await Promise.all([
    sb.from('categories').select('*').eq('archived', false),
    sb.from('budgets').select('category_id,planned_agorot').eq('month', m0),
    sb.from('transactions').select('*').gte('occurred_on', p0).lte('occurred_on', p1)
      .order('occurred_on', { ascending: false }).order('created_at', { ascending: false }),
    sb.from('reflections').select('*').eq('month', m0),
    sb.from('profiles').select('display_name').limit(1),
    sb.from('households').select('cycle_start').limit(1)
  ]);

  for (const r of [cats, buds, txs, prof]) if (r.error) throw r.error;

  S.cats = cats.data || [];
  S.budgets = new Map((buds.data || []).map(b => [b.category_id, Number(b.planned_agorot)]));
  S.txs = (txs.data || []).map(t => ({ ...t, amount_agorot: Number(t.amount_agorot) }));
  /* ‏טבלת ההשתקפויות היא שכבת הנשמה, ולא שכבת הכסף. אם המיגרציה
     שלה עוד לא רצה, האפליקציה עובדת בלעדיה במקום ליפול. */
  S.reflections = refl.error ? [] : (refl.data || []);
  S.profile = (prof.data && prof.data[0]) || null;
  /* ‏העמודה הזאת נוספה אחרי שהיו כבר משקי בית. אם המיגרציה עוד
     לא רצה, הראשון בחודש הוא מה שהיה תמיד. */
  S.cycle = (!hh.error && hh.data && hh.data[0] && hh.data[0].cycle_start) || 1;
  S.prevTxs = null;

  renderHome();
}

/* ‏החודש שלפני, ורק בשביל ההשוואה. נטען אחרי הציור הראשון כדי
   שהמסך לא יחכה לשאילתה שהוא לא צריך בשביל המספר הגדול. */
async function loadPrev() {
  if (S.prevTxs) return S.prevTxs;
  const p = addMonths(S.month, -1);
  const { from: a, to: b } = periodRange(p);
  const { data, error } = await sb.from('transactions')
    .select('amount_agorot,direction,category_id,occurred_on')
    .gte('occurred_on', a).lte('occurred_on', b);
  S.prevTxs = error ? [] : (data || []).map(t => ({ ...t, amount_agorot: Number(t.amount_agorot) }));
  return S.prevTxs;
}

/* ═══════════════════════════════════════════ הבית ══ */

function renderHome() {
  $('monthLabel').textContent = periodLabel(S.month);

  const now = new Date();
  const current = inCurrentPeriod();
  const dim = daysInPeriod(S.month);
  const daysLeft = current ? (dim - dayOfPeriod(S.month, now) + 1) : 0;

  const left = leftToSpend();
  const over = left < 0;

  /* ‏כשחרגנו, השאלה משתנה יחד עם התשובה. אפליקציה שמראה מספר
     שלילי מתחת לכיתוב "כמה יש לי" נותנת תשובה לא נכונה לשאלה
     שהיא עצמה שאלה. */
  $('heroQ').textContent = over ? 'כמה חרגתי?' : 'כמה יש לי?';
  const a = $('heroA');
  setMoney(a, left);
  a.setAttribute('aria-label', (over ? 'חרגתם ב' : 'נשאר לכם ') + fmt(left));
  a.classList.toggle('over', over);

  if (S.lastLeft !== null && S.lastLeft !== left) {
    a.classList.remove('bump');
    void a.offsetWidth;          // הפעלה מחדש של האנימציה
    a.classList.add('bump');
  }
  S.lastLeft = left;

  /* ‏שתי שורות ולא שלוש אריחים: מה הוצאתי מתוך מה תכננתי, וכמה
     מותר לי היום. "מותר היום" הוא מה שנשאר חלקי הימים שנותרו,
     והוא מתקן את עצמו: כל הוצאה היום מקטינה את מה שנשאר ולכן
     גם אותו. */
  const sub = $('heroSub');
  sub.textContent = '';
  const line = (...nodes) => { const d = el('div'); d.append(...nodes); sub.append(d); };
  const strong = v => { const b = el('b', 'money'); setMoney(b, v); return b; };

  if (!plannedOut() && !plannedIn()) {
    if (spentAll() || gotAll()) {
      line(document.createTextNode('הוצאתי '), strong(spentAll()));
      line(document.createTextNode('אין תקציב לחודש הזה, אז זה מה שנכנס פחות מה שיצא.'));
    } else {
      line(document.createTextNode('עוד אין תקציב לחודש הזה. אפשר לבנות אותו בלשונית התקציב.'));
    }
  } else {
    const spent = spentAll(), plan = plannedOut();
    line(document.createTextNode('הוצאתי '), strong(spent),
         ...(plan ? [document.createTextNode(' מתוך '), strong(plan)] : []));

    if (current && daysLeft > 0) {
      if (over) {
        line(document.createTextNode('מעל התכנון. נשארו '),
             el('b', null, String(daysLeft)),
             document.createTextNode(daysLeft === 1 ? ' יום' : ' ימים'));
      } else {
        line(document.createTextNode('מותר לי היום '),
             strong(Math.floor(left / daysLeft / 100) * 100),
             document.createTextNode(` · עוד ${daysLeft} ${daysLeft === 1 ? 'יום' : 'ימים'}`));
      }
    } else if (!current) {
      line(document.createTextNode(over ? 'החודש נגמר מעל התכנון.' : 'החודש נגמר, ועמדתם בתכנון.'));
    }
  }

  /* ‏"נכנסו 18,500 מתוך 18,500 שתוכננו" הוא אותו מספר פעמיים,
     ושורה מודגשת שאינה אומרת כלום מתחרה במספר הגדול. ההכנסה
     נאמרת רק כשהיא שונה ממה שתוכנן, כי אז זה מידע. */
  const got = gotAll(), pin = plannedIn(), moved = movedAll();
  const offPlan = pin > 0 && Math.abs(got - pin) / pin >= 0.02;
  if (got > 0 && pin > 0 && offPlan)
    line(document.createTextNode(got > pin ? 'נכנסו ' : 'נכנסו רק '), strong(got),
         document.createTextNode(' מתוך '), strong(pin), document.createTextNode(' שתוכננו'));
  else if (got > 0 && !pin)
    line(document.createTextNode('נכנסו החודש '), strong(got));
  if (moved > 0) line(document.createTextNode('ועוד '), strong(moved),
                      document.createTextNode(' בהעברות, שאינן הוצאה'));

  renderRows(current, dim, now);
  renderInsight();
}

function renderRows(current, dim, now) {
  const box = $('homeRows');
  box.textContent = '';

  const rows = outCats()
    .map(c => ({ c, p: planned(c.id), s: spentIn(c.id) }))
    .filter(r => r.p > 0 || r.s > 0);

  if (!rows.length) {
    const e = el('div', 'empty');
    e.append(el('h2', null, 'עוד לא רשמתם כלום'));
    e.append(el('p', null, 'כל הוצאה שתוסיפו תופיע כאן, והמספר למעלה יזוז. אפשר להתחיל מההוצאה האחרונה שאתם זוכרים.'));
    const b = el('button', 'btn', 'הוספת ההוצאה הראשונה');
    b.type = 'button';
    b.addEventListener('click', () => openAdd());
    e.append(b);
    box.append(e);
    return;
  }

  const frag = document.createDocumentFragment();
  for (const { c, p, s } of rows) {
    const over = p > 0 && s > p;
    const row = el('button', 'row');
    row.type = 'button';
    row.setAttribute('aria-label',
      p > 0 ? `${c.label}. יצא ${fmt(s)} מתוך ${fmt(p)} שתוכננו${over ? '. חריגה' : ''}`
            : `${c.label}. יצא ${fmt(s)}, לא תוכנן`);

    const top = el('div', 'row-top');
    const ic = el('span', 'row-ico', c.icon || '•'); ic.setAttribute('aria-hidden', 'true');
    const nm = el('span', 'row-nm', c.label);
    const val = moneyEl(s, 'row-val' + (over ? ' over' : '') + (s === 0 ? ' zero' : ''));
    const of = el('span', 'row-of');
    if (p > 0) { of.append(document.createTextNode('מתוך ')); of.append(moneyEl(p)); }
    top.append(ic, nm, val, of);

    const bar = el('div', 'bar' + (over ? ' over' : ''));
    bar.setAttribute('aria-hidden', 'true');
    const fill = el('i');
    /* ‏בחריגה הפס כולו הוא מה שיצא, והקטע המלא הוא החלק שמעבר
       לתכנון. כך חריגה של שישה אחוזים נראית אחרת מחריגה של
       שבעים, ולא שתיהן כפס מלא זהה. */
    const pct = over ? Math.max(4, Math.round((s - p) / s * 100))
              : p > 0 ? Math.min(100, Math.round(s / p * 100))
              : (s > 0 ? 100 : 0);
    fill.style.width = pct + '%';
    if (over) fill.classList.add('over');
    else if (!p) fill.classList.add('none');
    bar.append(fill);

    /* ‏הסימן של היום בתוך התקופה. בלעדיו "ארבעים אחוז מהתקציב"
       הוא לא מידע: ארבעים אחוז ביום העשירי הוא בעיה, וביום
       העשרים ושמונה הוא מצוין. */
    if (current && p > 0 && !over) {
      const t = el('span', 'today');
      t.style.right = Math.round(dayOfPeriod(S.month, now) / dim * 100) + '%';
      bar.append(t);
    }

    row.append(top, bar);
    row.addEventListener('click', () => { S.filterCat = c.id; tab('tx'); });
    frag.append(row);
  }
  box.append(frag);
}

/* ═══════════════════════════════════ ארבעת המנגנונים ══ */

/* ── 1. הרצף ──
   ‏הוא נספר על ימים שבהם הסתכלתם, ולא על חודשים שבהם לא חרגתם.
   השד השני בדף של שוהם הוא פחד להסתכל בחשבון, ולכן הדבר היחיד
   שהאפליקציה מתגמלת הוא ההסתכלות. רצף של התנהגות מושלמת נשבר
   פעם אחת ואז מפסיקים לנסות. */
const LS = {
  get(k, d) { try { const v = localStorage.getItem('kyl.' + k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem('kyl.' + k, JSON.stringify(v)); } catch {} }
};

function touchStreak() {
  const today = isoDate(new Date());
  const s = LS.get('streak', { last: '', n: 0, best: 0 });
  if (s.last === today) return s;
  const yest = isoDate(new Date(Date.now() - DAY));
  s.n = s.last === yest ? s.n + 1 : 1;
  s.last = today;
  s.best = Math.max(s.best || 0, s.n);
  LS.set('streak', s);
  return s;
}

function renderStreak(s) {
  const btn = $('streakBtn');
  if (!s || s.n < 2) { hide(btn); return; }
  $('streakText').textContent = `${s.n} ימים`;
  btn.setAttribute('aria-label', `${s.n} ימים ברצף שהסתכלתם. השיא שלכם ${s.best}.`);
  show(btn);
}

$('streakBtn').addEventListener('click', () => {
  const s = LS.get('streak', { n: 0, best: 0 });
  toast(`${s.n} ימים ברצף שהסתכלתם. השיא ${s.best}.`);
  LS.set('streakNote', 1);
});

/* ── 2. שואלים, לא נוזפים ──
   ‏קטגוריה חרגה. הדבר שאפליקציות עושות כאן הוא נורה אדומה, והדבר
   שהיא גורמת הוא שמפסיקים לפתוח אותן. לכן: שאלה אחת, בלי שיפוט,
   ועם אפשרות לא לענות. */
const ASK_CHIPS = ['הוצאה חד פעמית', 'תכננתי נמוך מדי', 'פשוט הוצאתי יותר', 'לא יודע'];
let askCtx = null;

function haveReflection(kind, catId) {
  return S.reflections.some(r => r.kind === kind &&
    (catId ? r.category_id === catId : !r.category_id));
}

function openAsk(kind, cat) {
  askCtx = { kind, cat };
  if (kind === 'overspend') {
    $('askTitle').textContent = 'שאלה אחת';
    $('askSub').textContent =
      `${cat.label} עבר את התכנון. זה קורה לכולם, ואין כאן ציון. רק שווה לדעת למה, כי זה מה שמשנה את החודש הבא.`;
    $('askLbl').textContent = 'מה היה הסיפור?';
  } else {
    const prev = addMonths(S.month, -1);
    $('askTitle').textContent = `${monthName(prev)} נגמר`;
    $('askSub').textContent =
      'שאלה אחת לפני שממשיכים. אין תשובה נכונה, ואף אחד לא קורא את זה חוץ מכם.';
    $('askLbl').textContent = 'מה הדבר האחד שהייתם עושים אחרת?';
  }
  const box = $('askChips');
  box.textContent = '';
  const chips = kind === 'overspend' ? ASK_CHIPS
    : ['להוציא פחות על בילויים', 'לרשום בזמן', 'לתכנן אחרת', 'שום דבר, היה בסדר'];
  for (const c of chips) {
    const b = el('button', 'chip', c);
    b.type = 'button';
    b.setAttribute('aria-pressed', 'false');
    b.addEventListener('click', () => {
      for (const o of box.children) o.setAttribute('aria-pressed', 'false');
      b.setAttribute('aria-pressed', 'true');
    });
    box.append(b);
  }
  $('askText').value = '';
  openSheet($('askSheet'));
}

async function saveAsk(skipped) {
  const ctx = askCtx;
  closeSheet();
  if (!ctx) return;
  const chosen = [...$('askChips').children].find(b => b.getAttribute('aria-pressed') === 'true');
  const row = {
    household_id: S.hh,
    kind: ctx.kind,
    month: monthKey(ctx.kind === 'month_end' ? addMonths(S.month, -1) : S.month),
    category_id: ctx.cat ? ctx.cat.id : null,
    choice: skipped ? 'skipped' : (chosen ? chosen.textContent : null),
    note: skipped ? null : ($('askText').value.trim() || null),
    created_by: S.user.id
  };
  askCtx = null;
  /* ‏נרשם מקומית לפני הנסיעה לשרת, כדי שלא נשאל שוב את אותה
     שאלה אם הכתיבה נכשלה או אם הטבלה עוד לא קיימת. */
  S.reflections.push(row);
  const { error } = await sb.from('reflections').upsert(row, {
    onConflict: ctx.cat ? 'household_id,kind,month,category_id' : undefined
  });
  if (!error && !skipped) toast('נרשם. תודה.');
  renderInsight();
}

$('askSave').addEventListener('click', () => saveAsk(false));
$('askSkip').addEventListener('click', () => saveAsk(true));

/* ‏מופעל אחרי שהמסך התיישב, פעם אחת בביקור, ולא מיד אחרי ההקמה. */
function maybeAsk() {
  if (S.asked || openEl) return;
  for (const c of outCats()) {
    const p = planned(c.id), s = spentIn(c.id);
    if (p > 0 && s > p && !haveReflection('overspend', c.id)) {
      S.asked = true;
      setTimeout(() => { if (!openEl && S.tab === 'home') openAsk('overspend', c); }, 900);
      return;
    }
  }
}

/* ── 3 ו-4. השדים, ושאלת סוף החודש ──
   ‏כל כלל כאן נגזר מנתון אמיתי. אין כאן משפטי עידוד כלליים שלא
   מסתכלים על כלום, חוץ מהשורה האחרונה, שמוצגת רק כשאין לאפליקציה
   שום דבר אמיתי להגיד. */
const LINES = [
  ['הכסף לא נעלם, הוא עובר', 'כל שקל שיצא החודש הלך למקום מסוים. ברגע שרואים לאן, ההחלטה הבאה כבר אחרת.'],
  ['תקציב הוא לא דיאטה', 'הוא לא נשבר כשחורגים. הוא נשבר כשמפסיקים להסתכל.'],
  ['הסכום הקטן הוא לא קטן', 'שלושים שקל ביום הם תשע מאות בחודש. אף אחד לא מרגיש את זה בזמן אמת.'],
  ['החודש הבא מתחיל היום', 'מה שאתם רושמים עכשיו הוא מה שתוכלו להשוות אליו בעוד שלושים יום.']
];

/* ── ‏כללי אצבע · בועת ענן פעם בשבוע ──
   ‏אלה היחידים במסך הבית שאינם נגזרים מהכסף של המשתמש, ולכן הם
   גם היחידים שמסומנים בפירוש כידע כללי ונראים אחרת: בועה עם זנב,
   ולא הכרטיס של התובנות. הם גם אחרונים בתור · אזהרת חריגה או
   הוצאה חריגה תמיד קודמת להם, כי היא על הכסף עצמו.
   ‏אין כאן המלצת השקעה, שום מוצר ושום מסלול. */
const RULES = [
  ['כלל אצבע', 'כרית ביטחון, לא יותר מזה',
   '‏שלושה עד שישה חודשי מחיה בצד, וזה כל הסיפור. לא כדי להתעשר, אלא כדי שאם משהו נופל, לא צריך הלוואה כדי לקום.'],
  ['כלל אצבע', 'תקציב שאי אפשר לעמוד בו הוא לא תקציב',
   '‏אם תכננתם מאתיים שקל לאוכל בחוץ ואתם מוציאים שמונה מאות, הבעיה היא בתכנון. תקציב ריאלי נראה פחות מרשים ומחזיק הרבה יותר זמן.'],
  ['כלל אצבע', 'עדיף בינוני לאורך זמן',
   '‏חודש אחד מושלם שווה פחות מחצי שנה של בסדר. מי שממשיך לרשום גם בחודש שהשתבש הוא זה שרואה שינוי אמיתי.'],
  ['כלל אצבע', 'תשאירו מקום לכיף',
   '‏תקציב בלי שום הנאה בתוכו נשבר תוך שבועיים. שימו סעיף לדברים שאתם אוהבים, בסכום שאתם בוחרים, ותיהנו ממנו בלי אשמה.'],
  ['טיפ קטן', 'המוצר, או הכסף?',
   '‏רגע לפני קנייה: אם היו מציעים לכם עכשיו את המוצר או את הסכום במזומן, מה הייתם לוקחים? אם בחרתם בכסף, כנראה לא כל כך רציתם את המוצר.'],
  ['טיפ קטן', 'כמה שעות עבודה זה?',
   '‏תרגמו את המחיר לשעות עבודה לפני שקונים. חולצה בשלוש מאות שקל היא לא מספר על תווית, היא יום עבודה שלם, ופתאום ההחלטה נעשית כמעט לבד.'],
  ['טיפ קטן', 'מזומן מרגישים אחרת',
   '‏בחרו סעיף אחד שקשה לכם בו במיוחד, ושלמו עליו החודש במזומן בלבד. כשרואים את השטרות יוצאים מהארנק, פתאום סופרים.'],
  ['טיפ קטן', 'לכסף שנשאר יש המשך',
   '‏כסף שלא יוצא היום לא עומד במקום, הוא ממשיך לעבוד בשקט. אין צורך לחשב כמה בדיוק · מספיק לזכור שמה שנשאר בצד היום שווה יותר בעוד כמה שנים.']
];

/* ‏פעם בשבוע, בלי לחזור על כלל עד שנגמר הסבב, ואותו כלל כל היום
   כדי שהוא לא יתחלף מתחת לאצבע בכל רישום. */
function weeklyRule(today) {
  const st = LS.get('rule', { at: '', i: -1, seen: [] });
  if (st.at === today) return RULES[st.i] || null;
  if (st.at && new Date(today) - new Date(st.at) < 7 * DAY) return null;
  let seen = (Array.isArray(st.seen) ? st.seen : []).filter(i => i >= 0 && i < RULES.length);
  let pool = RULES.map((_, i) => i).filter(i => !seen.includes(i));
  if (!pool.length) { seen = []; pool = RULES.map((_, i) => i); }
  const i = pool[Math.floor(Math.random() * pool.length)];
  LS.set('rule', { at: today, i, seen: [...seen, i] });
  return RULES[i];
}

async function renderInsight() {
  const box = $('homeInsight');
  const card = (title, text, acts, opt) => {
    box.textContent = '';
    const d = el('div', 'insight' + (opt && opt.cls ? ' ' + opt.cls : ''));
    if (opt && opt.kick) d.append(el('span', 'kick', opt.kick));
    d.append(el('h3', null, title));
    d.append(el('p', null, text));
    if (acts && acts.length) {
      const row = el('div', 'acts');
      for (const [label, fn] of acts) {
        const b = el('button', null, label);
        b.type = 'button';
        b.addEventListener('click', fn);
        row.append(b);
      }
      d.append(row);
    }
    box.append(d);
  };

  const now = new Date();
  const current = inCurrentPeriod();

  /* ‏שאלת סוף החודש. בחמשת הימים הראשונים של התקופה, ורק אם
     היה בקודמת משהו להסתכל עליו. */
  if (current && dayOfPeriod(S.month, now) <= 5 && !haveReflection('month_end', null)) {
    const prev = await loadPrev();
    if (prev.length >= 3) {
      card(`${monthName(addMonths(S.month, -1))} נגמר`,
        'שאלה אחת לפני שממשיכים. חודש שנגמר בלי להסתכל עליו הוא חודש שלא לימד כלום.',
        [['לשאלה', () => openAsk('month_end', null)]]);
      return;
    }
  }

  /* ‏אזהרה לפני החריגה ולא אחריה, ופעם אחת לכל קטגוריה בחודש.
     התנאי אינו "עברת שמונים אחוז" אלא "הקצב שלך מקדים את
     החודש": שמונים אחוז בעשרים ושמונה בחודש הוא בסדר גמור,
     ושמונים אחוז בעשירי הוא מה ששווה לדעת עליו עכשיו. */
  if (current) {
    const pace = dayOfPeriod(S.month, now) / daysInPeriod(S.month);
    for (const c of outCats()) {
      const p = planned(c.id), used = spentIn(c.id);
      if (p <= 0 || used <= 0 || used > p) continue;
      const share = used / p;
      const seen = LS.get('warn.' + monthKey(S.month), {});
      if (seen[c.id]) continue;
      if (share >= 0.75 && share - pace >= 0.25) {
        seen[c.id] = 1;
        LS.set('warn.' + monthKey(S.month), seen);
        const leftCat = p - used;
        card(`${c.label}: נשארו ${fmt(leftCat)} ל־${daysInPeriod(S.month) - dayOfPeriod(S.month, now)} ימים`,
          `השתמשתם ב־${Math.round(share * 100)}% מהתכנון, והחודש רק ב־${Math.round(pace * 100)}%. זאת לא נזיפה, זה הזמן שבו עוד אפשר להחליט.`,
          [['לתנועות', () => { S.filterCat = c.id; tab('tx'); }]]);
        return;
      }
    }
  }

  /* ‏השד השלישי: אנחנו חוזרים על הדפוסים. הכלל הזה מחפש דפוס
     אמיתי בין שני חודשים ואומר אותו בשמו. */
  if (S.txs.length >= 4) {
    const prev = await loadPrev();
    if (prev.length >= 4) {
      let worst = null;
      for (const c of outCats()) {
        const nowS = spentIn(c.id);
        const prevS = prev.reduce((s, t) =>
          s + (t.direction === 'out' && t.category_id === c.id ? t.amount_agorot : 0), 0);
        if (prevS < 10000 || nowS <= prevS) continue;
        const rise = (nowS - prevS) / prevS;
        if (rise >= 0.25 && nowS - prevS >= 15000) {
          if (!worst || nowS - prevS > worst.delta) {
            worst = { c, delta: nowS - prevS, pct: Math.round(rise * 100) };
          }
        }
      }
      if (worst) {
        card(`${worst.c.label} עלה ב־${worst.pct}% מול ${monthName(addMonths(S.month, -1))}`,
          `זה ${fmt(worst.delta)} יותר. פעם אחת זה מקריות, פעמיים זה דפוס. שווה להסתכל על התנועות ולראות מה השתנה.`,
          [['לתנועות', () => { S.filterCat = worst.c.id; tab('tx'); }]]);
        return;
      }
    }
  }

  /* ‏הוצאה חריגה ביחס להרגל, ולא ביחס לסכום קבוע. 400 שקל הם
     חריגה אצל אחד ושגרה אצל אחר, ולכן ההשוואה היא לחציון של
     ההוצאות שלו עצמו. חציון ולא ממוצע, כי ממוצע נגרר דווקא
     אחרי החריגה שמחפשים. */
  if (S.txs.length >= 5) {
    const prevRows = await loadPrev();
    const both = [...S.txs, ...prevRows].filter(t => t.direction === 'out' && !t.is_transfer);
    /* ‏הוצאה שחוזרת כל חודש באותו סכום אינה חריגה, היא הדבר הכי
       קבוע שיש. בלי ההחרגה הזאת שכר הדירה נתפס כ"פי 31 מהרגיל"
       בכל חודש מחדש, כי החציון נגרר אחרי המון הוצאות קטנות. */
    const steady = new Set(recurring(both).map(r => r.key));
    const oneOff = both.filter(t => !steady.has(normDesc(t.description)));
    const pool = oneOff.map(t => t.amount_agorot).sort((a, b) => a - b);
    if (pool.length >= 6) {
      const med = pool[Math.floor(pool.length / 2)];
      const big = S.txs
        .filter(t => t.direction === 'out' && !t.is_transfer && !steady.has(normDesc(t.description)))
        .sort((a, b) => b.amount_agorot - a.amount_agorot)[0];
      if (big && med > 0 && big.amount_agorot >= med * 4 && big.amount_agorot >= 25000) {
        const c = byId(big.category_id);
        card(`${fmt(big.amount_agorot)} ב${c ? c.label : 'תנועה אחת'}, פי ${Math.round(big.amount_agorot / med)} מהרגיל אצלכם`,
          `${big.description || 'התנועה הזאת'} גדולה בהרבה מכל השאר החודש. אם היא מתוכננת, הכול בסדר. אם לא, זה הדבר שכדאי להסתכל עליו לפני כל השאר.`,
          [['לתנועות', () => { S.filterCat = big.category_id; tab('tx'); }]]);
        return;
      }
    }
  }

  /* ‏הנזילות הקטנות. אף אחד לא מרגיש אותן בזמן אמת, ולכן האפליקציה
     היא זו שצריכה להרגיש אותן בשבילו. */
  const small = S.txs.filter(t => t.direction === 'out' && t.amount_agorot <= 5000);
  const smallSum = small.reduce((s, t) => s + t.amount_agorot, 0);
  if (small.length >= 8 && smallSum >= 25000) {
    card(`${small.length} תנועות קטנות, ויחד ${fmt(smallSum)}`,
      'כל אחת מהן נראתה כמו כלום. ביחד הן קטגוריה שלמה שלא תכננתם.',
      [['לתנועות', () => { S.filterCat = null; tab('tx'); }]]);
    return;
  }

  /* ‏חור ברישום. לא נזיפה, הזמנה. */
  if (current && S.txs.length) {
    const last = S.txs.reduce((m, t) => t.occurred_on > m ? t.occurred_on : m, '0000-00-00');
    const gap = Math.floor((now - new Date(last + 'T12:00:00')) / DAY);
    if (gap >= 4) {
      card(`${gap} ימים בלי רישום`,
        'לא נורא, וזה לא מחייב לשחזר הכול. מספיק להוסיף את מה שאתם זוכרים, והמספר למעלה יחזור להיות נכון.',
        [['להוסיף עכשיו', () => openAdd()]]);
      return;
    }
  }

  /* ‏השד הראשון: "זה לא בשבילי". הרגע שבו אפשר להראות שזה כן. */
  if (!current || dayOfPeriod(S.month, now) >= dayBeforeEnd()) {
    const planned_ = outCats().filter(c => planned(c.id) > 0);
    if (planned_.length >= 3 && planned_.every(c => spentIn(c.id) <= planned(c.id))) {
      card('עמדתם בכל הקטגוריות', 'זה לא מקריות ולא מזל. זה מה שקורה כשמסתכלים. "זה לא בשבילי" הוא השד הראשון, וזה בדיוק הדבר שסותר אותו.');
      return;
    }
  }

  /* ‏השד השני: פחד להסתכל בחשבון. מוצג פעם אחת, כשיש כבר רצף
     שמוכיח שהוא נשבר. */
  const st = LS.get('streak', { n: 0 });
  if (st.n >= 3 && !LS.get('streakNote', 0)) {
    LS.set('streakNote', 1);
    card(`${st.n} ימים ברצף שהסתכלתם`,
      'הרצף הזה לא נספר על חודשים מושלמים, אלא על ימים שבהם פתחתם את זה. פחד להסתכל בחשבון הוא השד שעולה הכי הרבה כסף, והדבר הזה למעלה הוא ההוכחה שהוא כבר לא אצלכם.');
    return;
  }

  const rule = weeklyRule(isoDate(now));
  if (rule) {
    card(rule[1], rule[2], null, { cls: 'cloud', kick: rule[0] });
    return;
  }

  const [t, p] = LINES[new Date().getDate() % LINES.length];
  card(t, p);
}

function dayBeforeEnd() { return daysInPeriod(S.month) - 2; }

/* ═══════════════════════════════════════════ תנועות ══ */

/* ‏חיפוש על מה שכבר בזיכרון. חודש של תנועות הוא מאות שורות,
   ולכן אין שום סיבה לנסוע לשרת בשביל כל אות. */
function matches(t, q) {
  if (!q) return true;
  const c = byId(t.category_id);
  const hay = [t.description || '', c ? c.label : '', t.is_transfer ? 'העברה' : '']
    .join(' ').toLowerCase();
  if (hay.includes(q)) return true;
  // ‏מספר בשאילתה מחפש בסכום, כי "כמה זה היה" הוא איך שזוכרים
  if (/^[\d.,]+$/.test(q)) return fmtNum(t.amount_agorot).replace(/,/g, '').includes(q.replace(/,/g, ''));
  return false;
}

const TX_FILTERS = [
  { key: 'all',  label: 'הכל',    test: () => true },
  { key: 'out',  label: 'הוצאות', test: t => t.direction === 'out' && !t.is_transfer },
  { key: 'in',   label: 'הכנסות', test: t => t.direction === 'in' && !t.is_transfer },
  { key: 'move', label: 'העברות', test: t => !!t.is_transfer }
];

function renderTx() {
  const box = $('txList');
  box.textContent = '';

  const q = ($('txSearch').value || '').trim().toLowerCase();
  const f = TX_FILTERS.find(x => x.key === S.txFilter) || TX_FILTERS[0];

  const chips = $('txFilters');
  chips.textContent = '';
  for (const o of TX_FILTERS) {
    const n = S.txs.filter(o.test).length;
    if (o.key !== 'all' && !n) continue;
    const b = el('button', 'chip chip-quiet', o.label);
    b.type = 'button';
    b.setAttribute('aria-pressed', String(o.key === f.key));
    b.addEventListener('click', () => { S.txFilter = o.key; renderTx(); });
    chips.append(b);
  }

  let rows = S.txs.filter(t => f.test(t) && matches(t, q));
  if (S.filterCat) {
    const c = byId(S.filterCat);
    rows = rows.filter(t => t.category_id === S.filterCat);
    const b = el('button', 'chip', `${c ? c.label : 'קטגוריה'} ✕`);
    b.type = 'button';
    b.setAttribute('aria-pressed', 'true');
    b.setAttribute('aria-label', `מסונן לפי ${c ? c.label : 'קטגוריה'}. לחיצה מבטלת את הסינון`);
    b.addEventListener('click', () => { S.filterCat = null; renderTx(); });
    chips.append(b);
  }

  if (!rows.length) {
    const e = el('div', 'empty');
    if (q) {
      e.append(el('h2', null, 'לא נמצא כלום'));
      e.append(el('p', null, `אין תנועה שמתאימה ל"${q}" בחודש הזה. אפשר לנסות חודש אחר מלמעלה.`));
      box.append(e);
      return;
    }
    e.append(el('h2', null, S.filterCat ? 'אין תנועות בקטגוריה הזאת' : 'החודש הזה עוד ריק'));
    e.append(el('p', null, S.filterCat
      ? 'אף תנועה לא נרשמה כאן בחודש הזה.'
      : 'כל מה שתוסיפו יופיע כאן, לפי ימים, מהחדש לישן.'));
    const b = el('button', 'btn', 'הוספת תנועה');
    b.type = 'button';
    b.addEventListener('click', () => openAdd());
    e.append(b);
    if (!S.filterCat) {
      const imp = el('button', 'btn-quiet', 'או ייבוא קובץ מהבנק');
      imp.type = 'button';
      imp.style.marginTop = '12px';
      imp.addEventListener('click', () => tab('import'));
      const wrap = el('div');
      wrap.append(imp);
      e.append(wrap);
    }
    box.append(e);
    /* ‏דוגמה, לא הסבר. ברגע הזה אדם לא יודע איך נראית תנועה
       אצלו, ומסך שאומר "אין כאן כלום" לא מלמד אותו. */
    if (!S.filterCat) box.append(exampleTx());
    return;
  }

  /* ‏מקובצות לפי יום. אדם זוכר "ביום חמישי" ולא "ב-14 בחודש",
     ולכן הכותרת היא שם היום. */
  /* ‏נבנה בשבר מסמך ומוכנס פעם אחת. שלוש מאות הכנסות נפרדות
     לתוך המסמך החי מבטלות את הפריסה שלוש מאות פעמים. */
  const frag = document.createDocumentFragment();
  let day = null;
  for (const t of rows) {
    if (t.occurred_on !== day) {
      day = t.occurred_on;
      const sum = rows.filter(r => r.occurred_on === day && r.direction === 'out' && !r.is_transfer)
                      .reduce((s, r) => s + r.amount_agorot, 0);
      const h = el('h2', 'sec-h', dayName(day) + (sum ? ' · ' + fmt(sum) : ''));
      frag.append(h);
    }
    const c = byId(t.category_id);
    const row = el('button', 'tx');
    row.type = 'button';

    const ic = el('span', 'tx-ico', t.is_transfer ? '⇄' : ((c && c.icon) || '•'));
    ic.setAttribute('aria-hidden', 'true');
    const mid = el('div', 'tx-mid');
    mid.append(el('div', 't', t.description || (c ? c.label : 'תנועה')));
    const sub = el('div', 's');
    sub.textContent = t.is_transfer ? 'העברה, לא נספרת כהוצאה'
                    : (t.description && c ? c.label : (t.source === 'import' ? 'מיובא' : ''));
    if (t.installment_no && t.installment_total) {
      const tag = el('span', 'tag', `תשלום ${t.installment_no} מתוך ${t.installment_total}`);
      sub.append(tag);
    }
    mid.append(sub);
    const amt = el('span', 'tx-amt money' + (t.direction === 'in' ? ' in' : '') + (t.is_transfer ? ' moved' : ''));
    setMoney(amt, t.amount_agorot);
    if (t.direction === 'in' && !t.is_transfer) amt.prepend(document.createTextNode('+'));

    row.setAttribute('aria-label',
      `${t.description || (c ? c.label : 'תנועה')}, ${t.direction === 'in' ? 'הכנסה' : 'הוצאה'} ${fmt(t.amount_agorot)}, ${dayName(t.occurred_on)}`);
    row.append(ic, mid, amt);
    row.addEventListener('click', () => openTx(t));
    frag.append(row);
  }
  box.append(frag);
}

let txCtx = null;
function openTx(t) {
  txCtx = t;
  const c = byId(t.category_id);
  $('txSheetTitle').textContent = t.description || (c ? c.label : 'תנועה');
  $('txSheetSub').textContent =
    `${t.is_transfer ? 'העברה' : t.direction === 'in' ? 'הכנסה' : 'הוצאה'} של ${fmt(t.amount_agorot)}` +
    `${c && !t.is_transfer ? ', ' + c.label : ''}, ${dayName(t.occurred_on)}.` +
    (t.is_transfer ? ' היא לא נספרת כהוצאה.' : '');
  openSheet($('txSheet'));
}
$('txClose').addEventListener('click', closeSheet);
$('txEdit').addEventListener('click', () => {
  const t = txCtx;
  closeSheet();
  if (t) setTimeout(() => openAdd(t), 260);
});

$('txDelete').addEventListener('click', async () => {
  const t = txCtx;
  closeSheet();
  if (!t) return;
  const { error } = await sb.from('transactions').delete().eq('id', t.id);
  if (error) { toast(human(error)); return; }
  S.txs = S.txs.filter(x => x.id !== t.id);
  renderHome(); renderTx();
  toast('נמחק.');
});

/* ═════════════════════════════════════ הוספת תנועה ══ */

let addDir = 'out';      // out | in | move
let editId = null;       // תנועה שנערכת, או null

function setDir(d) {
  addDir = d;
  for (const [id, k] of [['dirOut','out'], ['dirIn','in'], ['dirMove','move']])
    $(id).setAttribute('aria-pressed', String(d === k));

  const T = {
    out:  ['מה הוצאתם?', 'סכום, קטגוריה, וזה הכל. התיאור הוא לכם, לא לנו.'],
    in:   ['מה נכנס?',   'משכורת, החזר, מתנה. כל שקל שנכנס ולא תוכנן.'],
    move: ['לאן העברתם?', 'העברה לחיסכון או בין חשבונות. היא נרשמת, והיא לא נספרת כהוצאה.']
  };
  $('addTitle').textContent = editId ? 'עריכת תנועה' : T[d][0];
  $('addSub').textContent = T[d][1];
  /* ‏להעברה אין קטגוריה: היא לא שייכת לשום סעיף בתקציב, כי היא
     לא יצאה מהתקציב. */
  $('catField').classList.toggle('hidden', d === 'move');
  if (d !== 'move') fillAddCats();
}
$('dirOut').addEventListener('click', () => setDir('out'));
$('dirIn').addEventListener('click', () => setDir('in'));
$('dirMove').addEventListener('click', () => setDir('move'));

let addCat = null;
function fillAddCats() {
  const box = $('txCats');
  box.textContent = '';
  const list = addDir === 'out' ? outCats() : inCats();
  if (!list.some(c => c.id === addCat)) addCat = list.length ? list[0].id : null;
  for (const c of list) {
    const b = el('button', 'chip', `${c.icon || '•'} ${c.label}`);
    b.type = 'button';
    b.setAttribute('aria-pressed', String(c.id === addCat));
    b.addEventListener('click', () => {
      addCat = c.id;
      for (const o of box.children) o.setAttribute('aria-pressed', 'false');
      b.setAttribute('aria-pressed', 'true');
    });
    box.append(b);
  }
}

/* ‏מקבל תנועה לעריכה, או כלום לתנועה חדשה. כל מי שקורא לה
   כמאזין חייב לעטוף: מאזין מקבל את אירוע הלחיצה כארגומנט
   ראשון, והוא היה נכנס לכאן בתור "התנועה שנערכת". */
function openAdd(t) {
  editId = t ? t.id : null;
  /* ‏הקטגוריה האחרונה שנבחרה חוזרת מעצמה. רוב ההוצאות של אדם
     נופלות על אותן שתיים או שלוש, ובחירה מחדש בכל פעם היא
     הנגיעה שהופכת רישום של שתי שניות לרישום של חמש. */
  if (!t) addCat = LS.get('lastCat', null) || addCat;
  setDir(t ? (t.is_transfer ? 'move' : t.direction) : 'out');

  $('txAmount').value = t ? (t.amount_agorot / 100).toString() : '';
  $('txDesc').value = t ? (t.description || '') : '';
  if (t && t.category_id) { addCat = t.category_id; fillAddCats(); }

  /* ‏ברירת המחדל היא היום, אלא אם מסתכלים על חודש שעבר. תנועה
     שנרשמת לחודש שלא מסתכלים עליו פשוט נעלמת מהעיניים. */
  const now = new Date();
  const { from, to } = periodRange(S.month);
  $('txDate').value = t ? t.occurred_on : (inCurrentPeriod() ? isoDate(now) : to);
  $('txDate').min = from;
  $('txDate').max = to;
  $('addSave').textContent = t ? 'שמירה' : 'הוספה';
  setErr($('addErr'), '');
  openSheet($('addSheet'));
  /* ‏המיקוד נכנס לסכום ולא לכפתור הראשון: זה השדה היחיד שתמיד
     ממלאים, ובלעדיו כל רישום מתחיל בנגיעה מיותרת. */
  setTimeout(() => $('txAmount').focus({ preventScroll: true }), 120);
}

/* ‏אנטר בשדה הסכום שומר. שתי שניות, כפי שהוא ביקש. */
$('txAmount').addEventListener('keydown', e => {
  if (e.key === 'Enter') { e.preventDefault(); $('addSave').click(); }
});
$('addBtn').addEventListener('click', () => openAdd());
$('addCancel').addEventListener('click', closeSheet);

$('addSave').addEventListener('click', async () => {
  setErr($('addErr'), '');
  const ag = toAgorot($('txAmount').value);
  if (!ag) {
    setErr($('addErr'), 'צריך סכום גדול מאפס.');
    $('txAmount').focus(); return;
  }
  const move = addDir === 'move';
  if (!move && !addCat) { setErr($('addErr'), 'צריך לבחור קטגוריה.'); return; }
  const on = $('txDate').value;
  if (!on) { setErr($('addErr'), 'צריך תאריך.'); return; }

  const btn = $('addSave');
  const was = editId;
  btn.disabled = true; btn.textContent = was ? 'שומר...' : 'מוסיף...';
  try {
    const row = {
      occurred_on: on,
      amount_agorot: ag,
      direction: move ? 'out' : addDir,
      is_transfer: move,
      category_id: move ? null : addCat,
      description: $('txDesc').value.trim() || null
    };

    if (was) {
      const { error } = await sb.from('transactions').update(row).eq('id', was);
      if (error) throw error;
      const i = S.txs.findIndex(x => x.id === was);
      if (i >= 0) S.txs[i] = { ...S.txs[i], ...row };
    } else {
      const { data, error } = await sb.from('transactions')
        .insert({ ...row, household_id: S.hh, source: 'manual', created_by: S.user.id })
        .select().single();
      if (error) throw error;
      /* ‏נכנס לרשימה במקום הנכון לפי תאריך, במקום טעינה מחדש של
         כל החודש בשביל שורה אחת. */
      S.txs.push({ ...data, amount_agorot: Number(data.amount_agorot) });
    }

    S.txs.sort((a, b) => b.occurred_on.localeCompare(a.occurred_on) ||
                         String(b.created_at).localeCompare(String(a.created_at)));
    if (!move && addCat) LS.set('lastCat', addCat);
    editId = null;
    closeSheet();
    renderHome();
    if (S.tab === 'tx') renderTx();
    toast(was ? 'עודכן.' : move ? 'הועבר.' : addDir === 'out' ? 'נרשם.' : 'נכנס.');
    if (!was) { S.asked = false; maybeAsk(); }
  } catch (err) {
    setErr($('addErr'), human(err));
  } finally {
    btn.disabled = false; btn.textContent = editId ? 'שמירה' : 'הוספה';
  }
});

/* ═══════════════════════════════════════════ תקציב ══ */

function renderBudget() {
  const box = $('budgetRows');
  box.textContent = '';
  setErr($('budgetErr'), '');

  const group = (title, list) => {
    if (!list.length) return;
    const g = el('div', 'setup-group');
    g.append(el('h2', null, title));
    for (const c of list) {
      const row = el('div', 'num-row');
      const ic = el('span', 'ico', c.icon || '•'); ic.setAttribute('aria-hidden', 'true');
      const lab = el('label', 'nm', c.label);
      lab.htmlFor = 'b_' + c.id;
      const sp = spentIn(c.id);
      if (c.kind === 'expense' && sp > 0) lab.append(el('small', null, `יצא עד כה ${fmt(sp)}`));
      const wrap = el('span', 'amt');
      const inp = el('input');
      inp.id = 'b_' + c.id;
      inp.type = 'text'; inp.inputMode = 'decimal'; inp.autocomplete = 'off';
      inp.placeholder = '0';
      inp.dataset.cat = c.id;
      const p = planned(c.id);
      inp.value = p ? (p / 100).toString() : '';
      wrap.append(inp);
      row.append(ic, lab, wrap);
      g.append(row);
    }
    box.append(g);
  };

  group('מה נכנס', inCats());
  group('מה יוצא', outCats());
  budgetLive();
}

function budgetNumbers() {
  const out = {}, inc = {};
  for (const inp of $('budgetRows').querySelectorAll('input[data-cat]')) {
    const c = byId(inp.dataset.cat);
    if (!c) continue;
    (c.kind === 'income' ? inc : out)[c.id] = toAgorot(inp.value) || 0;
  }
  const sumOut = Object.values(out).reduce((a, b) => a + b, 0);
  const sumIn  = Object.values(inc).reduce((a, b) => a + b, 0);
  return { out, inc, sumOut, sumIn };
}

function budgetLive() {
  const { sumOut, sumIn } = budgetNumbers();
  setMoney($('budgetTotal'), sumOut);
  const left = sumIn - sumOut;
  if (!sumIn) {
    $('budgetHint').textContent = 'בלי הכנסה אין למה להשוות את התכנון.';
  } else if (left > 0) {
    $('budgetHint').textContent = `${fmt(left)} מההכנסה עוד לא שובצו לשום מקום.`;
  } else if (left === 0) {
    $('budgetHint').textContent = 'כל שקל שנכנס יש לו מקום.';
  } else {
    $('budgetHint').textContent = `התכנון גדול מההכנסה ב${fmt(left)}.`;
  }
}
$('budgetRows').addEventListener('input', budgetLive);

$('budgetSave').addEventListener('click', async () => {
  setErr($('budgetErr'), '');
  const { out, inc } = budgetNumbers();
  const all = { ...inc, ...out };
  const m = monthKey(S.month);
  const rows = Object.entries(all).map(([category_id, planned_agorot]) =>
    ({ household_id: S.hh, month: m, category_id, planned_agorot }));

  const btn = $('budgetSave');
  btn.disabled = true; btn.textContent = 'שומר...';
  try {
    const { error } = await sb.from('budgets')
      .upsert(rows, { onConflict: 'household_id,month,category_id' });
    if (error) throw error;
    S.budgets = new Map(Object.entries(all).map(([k, v]) => [k, v]));
    renderHome();
    toast('התקציב נשמר.');
  } catch (err) {
    setErr($('budgetErr'), human(err));
  } finally {
    btn.disabled = false; btn.textContent = 'שמירת התקציב';
  }
});

/* ───────────────────────────────────── קטגוריה חדשה ── */

const ICONS = ['🏠','🛒','🚗','🏦','🎬','👶','🐾','💊','👕','✈️','📚','🎁','💡','☕','🏋️','•'];
let newIcon = ICONS[0];

$('catAddBtn').addEventListener('click', () => {
  $('catName').value = '';
  newIcon = ICONS[0];
  const box = $('catIcons');
  box.textContent = '';
  for (const ic of ICONS) {
    const b = el('button', 'chip chip-quiet', ic);
    b.type = 'button';
    b.setAttribute('aria-pressed', String(ic === newIcon));
    b.setAttribute('aria-label', 'סמל ' + ic);
    b.addEventListener('click', () => {
      newIcon = ic;
      for (const o of box.children) o.setAttribute('aria-pressed', 'false');
      b.setAttribute('aria-pressed', 'true');
    });
    box.append(b);
  }
  setErr($('catErr'), '');
  openSheet($('catSheet'));
});
$('catCancel').addEventListener('click', closeSheet);

$('catSave').addEventListener('click', async () => {
  setErr($('catErr'), '');
  const label = $('catName').value.trim();
  if (!label) { setErr($('catErr'), 'צריך שם לקטגוריה.'); $('catName').focus(); return; }
  if (S.cats.some(c => c.label === label)) {
    setErr($('catErr'), 'כבר יש קטגוריה בשם הזה.'); return;
  }
  const btn = $('catSave');
  btn.disabled = true; btn.textContent = 'מוסיף...';
  try {
    const { data, error } = await sb.from('categories').insert({
      household_id: S.hh, label, icon: newIcon, kind: 'expense', sort: 90
    }).select().single();
    if (error) throw error;
    S.cats.push(data);
    closeSheet();
    renderBudget();
    toast('הקטגוריה נוספה.');
  } catch (err) {
    setErr($('catErr'), human(err));
  } finally {
    btn.disabled = false; btn.textContent = 'הוספה';
  }
});

/* ═══════════════════════════════════════ בחירת חודש ══ */

$('monthBtn').addEventListener('click', () => {
  const box = $('monthChips');
  box.textContent = '';
  const now = currentAnchor();
  for (let i = 0; i < 7; i++) {
    const m = addMonths(now, -i);
    const b = el('button', 'chip', monthName(m));
    b.type = 'button';
    if ((S.cycle || 1) !== 1) b.append(el('small', null, ' · ' + periodLabel(m)));
    b.setAttribute('aria-pressed', String(sameMonth(m, S.month)));
    b.addEventListener('click', async () => {
      closeSheet();
      if (sameMonth(m, S.month)) return;
      S.month = m;
      S.filterCat = null;
      S.lastLeft = null;
      $('monthLabel').textContent = periodLabel(m);
      try { await loadAll(); } catch (err) { toast(human(err)); }
      if (S.tab === 'tx') renderTx();
      if (S.tab === 'budget') renderBudget();
    });
    box.append(b);
  }
  openSheet($('monthSheet'));
});
$('monthClose').addEventListener('click', closeSheet);

/* ═══════════════════════════════════ דוגמה למצב ריק ══ */

/* ‏שלוש שורות שנראות כמו תנועות אמיתיות, מעומעמות ובלי מגע.
   הן עונות על השאלה שהמסך הריק משאיר פתוחה: איך זה ייראה. */
function exampleTx() {
  const box = el('div', 'eg');
  box.append(el('h3', null, 'ככה זה ייראה'));
  const demo = [
    ['🛒', 'שופרסל', 'מזון', 24900],
    ['☕', 'קפה עם מיכל', 'בילויים', 1800],
    ['🚗', 'דלק', 'תחבורה', 25000]
  ];
  for (const [icon, desc, cat, ag] of demo) {
    const row = el('div', 'tx');
    const ic = el('span', 'tx-ico', icon); ic.setAttribute('aria-hidden', 'true');
    const mid = el('div', 'tx-mid');
    mid.append(el('div', 't', desc), el('div', 's', cat));
    const amt = el('span', 'tx-amt money');
    setMoney(amt, ag);
    row.append(ic, mid, amt);
    box.append(row);
  }
  box.setAttribute('aria-hidden', 'true');
  return box;
}

/* ═══════════════════════════════════════ היסטוריה ══ */

/* ‏ארבעה חודשים אחורה, פעם אחת, לשימוש הסיכום וזיהוי המנויים.
   נטען רק כשנכנסים למסך שצריך אותו. */
async function loadHistory(months) {
  const n = months || 4;
  if (S.hist && S.hist.n >= n && S.hist.anchor === monthKey(S.month)) return S.hist.rows;
  const from = periodRange(addMonths(S.month, -(n - 1))).from;
  const to = periodRange(S.month).to;
  const { data, error } = await sb.from('transactions')
    .select('occurred_on,amount_agorot,direction,category_id,description,is_transfer')
    .gte('occurred_on', from).lte('occurred_on', to);
  const rows = error ? [] : (data || []).map(t => ({ ...t, amount_agorot: Number(t.amount_agorot) }));
  S.hist = { n, anchor: monthKey(S.month), rows };
  return rows;
}

/* ═════════════════════════════════ מה חוזר כל חודש ══ */

/* ‏"לאן הכסף נעלם" הוא כמעט תמיד הדברים שחוזרים. הם קטנים, הם
   לא מורגשים, ואף אחד לא סוכם אותם.

   ‏הזיהוי הוא לפי התיאור בלי המספרים שבו, כי פירוט אשראי מוסיף
   לכל שורה אסמכתא משתנה, ולפי סכום דומה בחודשים שונים. פעמיים
   באותו חודש אינן מנוי, הן שתי קניות. */
function normDesc(d) {
  return String(d || '')
    .replace(/[‎‏]/g, '')
    .replace(/\d+/g, ' ')
    .replace(/[^֐-׿a-zA-Z ]/g, ' ')
    .replace(/\s+/g, ' ').trim().toLowerCase()
    .split(' ').slice(0, 3).join(' ');
}

function recurring(rows) {
  const g = new Map();
  for (const t of rows) {
    if (t.direction !== 'out' || t.is_transfer) continue;
    const k = normDesc(t.description);
    if (k.length < 3) continue;
    if (!g.has(k)) g.set(k, []);
    g.get(k).push(t);
  }
  const out = [];
  for (const [k, list] of g) {
    const months = new Set(list.map(t => t.occurred_on.slice(0, 7)));
    if (months.size < 2) continue;
    const amounts = list.map(t => t.amount_agorot).sort((a, b) => a - b);
    const mid = amounts[Math.floor(amounts.length / 2)];
    // ‏סכום שמשתנה בחצי אינו מנוי, הוא מקום שקונים בו הרבה
    const steady = amounts.every(a => Math.abs(a - mid) <= mid * 0.2);
    if (!steady) continue;
    out.push({ key: k, label: list[list.length - 1].description || k,
               amount: mid, months: months.size, total: list.reduce((s, t) => s + t.amount_agorot, 0) });
  }
  return out.sort((a, b) => b.amount - a.amount);
}

/* ═══════════════════════════════════ סיכום החודש ══ */

async function renderSum() {
  const box = $('sumBody');
  box.textContent = '';
  $('sumTitle').textContent = 'הסיכום של ' + monthName(S.month);

  const spent = spentAll(), got = gotAll(), plan = plannedOut(), moved = movedAll();

  if (!S.txs.length) {
    const e = el('div', 'empty');
    e.append(el('h2', null, 'אין מה לסכם עדיין'));
    e.append(el('p', null, 'בחודש הזה לא נרשמה אף תנועה. אחרי כמה רישומים יהיה כאן מה לראות.'));
    box.append(e);
    return;
  }

  /* ── המספר, ומה הוא אומר ── */
  const head = el('div', 'sum-block');
  const big = el('div', 'sum-big');
  const v = el('span', 'v money'); setMoney(v, spent);
  big.append(v, el('span', 'k', plan ? 'יצאו מתוך ' + fmt(plan) : 'יצאו החודש'));
  head.append(big);
  if (got) head.append(el('p', 'note', `נכנסו ${fmt(got)}, ונשארו ${fmt(got - spent)}.`));
  if (moved) head.append(el('p', 'note', `ועוד ${fmt(moved)} בהעברות, שאינן הוצאה.`));
  box.append(head);

  /* ── לאן הכסף הלך ── */
  const rows = outCats()
    .map(c => ({ c, s: spentIn(c.id) }))
    .filter(r => r.s > 0)
    .sort((a, b) => b.s - a.s);

  if (rows.length) {
    const blk = el('div', 'sum-block');
    blk.append(el('h2', null, 'לאן הכסף הלך'));
    const max = rows[0].s;
    for (const { c, s: amt } of rows) {
      const row = el('div', 'sum-row');
      row.append(el('span', 'nm', (c.icon || '•') + ' ' + c.label));
      const track = el('div', 'track'); track.setAttribute('aria-hidden', 'true');
      const fill = el('i');
      fill.style.width = Math.max(3, Math.round(amt / max * 100)) + '%';
      track.append(fill);
      const vv = el('span', 'vv money'); setMoney(vv, amt);
      const wrap = el('span');
      wrap.append(vv, el('span', 'pct', Math.round(amt / spent * 100) + '%'));
      row.append(track, wrap);
      row.setAttribute('aria-label', `${c.label}, ${fmt(amt)}, ${Math.round(amt / spent * 100)} אחוז מההוצאות`);
      blk.append(row);
    }
    box.append(blk);
  }

  /* ── מה השתנה מול החודש שעבר ── */
  const prev = await loadPrev();
  if (prev.length) {
    const deltas = outCats().map(c => {
      const now = spentIn(c.id);
      const was = prev.reduce((s, t) =>
        s + (!t.is_transfer && t.direction === 'out' && t.category_id === c.id ? t.amount_agorot : 0), 0);
      return { c, now, was, d: now - was };
    }).filter(x => Math.abs(x.d) >= 5000 && (x.now || x.was))
      .sort((a, b) => Math.abs(b.d) - Math.abs(a.d)).slice(0, 5);

    if (deltas.length) {
      const blk = el('div', 'sum-block');
      blk.append(el('h2', null, 'מה השתנה מול ' + monthName(addMonths(S.month, -1))));
      for (const x of deltas) {
        const row = el('div', 'sum-row');
        row.append(el('span', 'nm', (x.c.icon || '•') + ' ' + x.c.label));
        row.append(el('span'));
        const d = el('span', 'delta ' + (x.d > 0 ? 'up' : 'down'),
                     (x.d > 0 ? '+' : '−') + fmt(Math.abs(x.d)).replace('₪', '₪'));
        row.append(d);
        row.setAttribute('aria-label',
          `${x.c.label}, ${x.d > 0 ? 'עלה ב' : 'ירד ב'}${fmt(Math.abs(x.d))} מול החודש הקודם`);
        blk.append(row);
      }
      box.append(blk);
    }
  }

  /* ── מה חוזר כל חודש ── */
  const hist = await loadHistory(4);
  const rec = recurring(hist).slice(0, 8);
  if (rec.length) {
    const blk = el('div', 'sum-block');
    blk.append(el('h2', null, 'חוזר כל חודש'));
    const sum = rec.reduce((s, r) => s + r.amount, 0);
    blk.append(el('p', 'note',
      `${rec.length} ${rec.length === 1 ? 'דבר חוזר' : 'דברים חוזרים'}, יחד ${fmt(sum)} בחודש. זה ${fmt(sum * 12)} בשנה.`));
    for (const r of rec) {
      const row = el('div', 'sum-row');
      row.append(el('span', 'nm', r.label.slice(0, 26)));
      row.append(el('span'));
      const vv = el('span', 'vv money'); setMoney(vv, r.amount);
      const wrap = el('span');
      wrap.append(vv, el('span', 'pct', `${r.months} חודשים`));
      row.append(wrap);
      blk.append(row);
    }
    box.append(blk);
  }

  /* ── ההזמנה. בסוף, ואחרי שהמסך כבר נתן משהו ── */
  const cta = el('a', 'cta');
  cta.href = '../#contact';
  cta.target = '_blank';
  cta.rel = 'noopener';
  cta.append(el('strong', null, 'רוצים להבין את התמונה לעומק?'));
  const sp = el('span');
  sp.append(document.createTextNode('המספרים כאן אומרים מה קרה. למה זה קורה, ומה לעשות עם זה, זאת כבר שיחה. '));
  sp.append(el('span', 'go', 'לדבר עם שוהם'));
  cta.append(sp);
  box.append(cta);
}

/* ═════════════════════════════════ חסכונות ונכסים ══ */

/* ‏ספר חשבונות שני, ובכוונה אינו נוגע בתנועות. תנועות עונות על
   "כמה הוצאתי החודש", נכסים עונים על "כמה יש לי בכלל", ואלה שתי
   שאלות שונות.

   ‏הכלל שחל על כל המסך הזה: הוא ממפה ואינו ממליץ. אין כאן דירוג
   בין סוגי נכסים, אין "כדאי" ואין "עדיף", ואין שום משפט שאפשר
   לקרוא כהמלצת השקעה. גם מנוע התובנות של האפליקציה אינו מגיע
   לכאן. */

const ASSET_KINDS = [
  { key: 'bank_savings', icon: '🏦', label: 'חיסכון בבנק',   group: 'savings' },
  { key: 'deposit',      icon: '💰', label: 'פיקדון',         group: 'savings' },
  { key: 'cash',         icon: '💵', label: 'מזומן',          group: 'savings' },
  { key: 'portfolio',    icon: '📊', label: 'תיק השקעות',     group: 'invest'  },
  { key: 'crypto',       icon: '₿',  label: 'קריפטו',         group: 'invest'  },
  { key: 'mutual_fund',  icon: '📋', label: 'קרן נאמנות',     group: 'invest'  },
  { key: 'study_fund',   icon: '📈', label: 'קרן השתלמות',    group: 'retire'  },
  { key: 'provident',    icon: '🏦', label: 'קופת גמל',       group: 'retire'  },
  { key: 'pension',      icon: '👴', label: 'פנסיה',          group: 'retire'  },
  { key: 'realestate',   icon: '🏠', label: 'נדל"ן',          group: 'estate'  },
  { key: 'other',        icon: '➕', label: 'אחר',            group: 'other'   }
];

const ASSET_GROUPS = [
  { key: 'savings', label: 'חסכונות' },
  { key: 'invest',  label: 'השקעות' },
  { key: 'retire',  label: 'פנסיה והשתלמות' },
  { key: 'estate',  label: 'נדל"ן' },
  { key: 'other',   label: 'אחר' }
];

/* ‏התחייבות נשאלת רק איפה שיש לה משמעות. */
const ASKS_LIABILITY = new Set(['realestate', 'other']);
const kindOf = k => ASSET_KINDS.find(x => x.key === k) || ASSET_KINDS[ASSET_KINDS.length - 1];

let assetRows = [];
let assetEdit = null;
let assetKind = 'bank_savings';

/* ‏מתי עודכן. בלי זה המסך מתחיל להיראות כאילו המספרים חיים,
   והם לא: הם מה שאדם הקליד ביום מסוים. */
function updatedAgo(iso) {
  if (!iso) return '';
  const d = Math.floor((Date.now() - new Date(iso)) / DAY);
  if (d <= 0) return 'עודכן היום';
  if (d === 1) return 'עודכן אתמול';
  if (d < 31) return `עודכן לפני ${d} ימים`;
  const m = Math.round(d / 30.4);
  if (m < 12) return `עודכן לפני ${m} ${m === 1 ? 'חודש' : 'חודשים'}`;
  return 'עודכן לפני יותר משנה';
}

const assetWorth = a => Number(a.amount_agorot) - Number(a.liability_agorot || 0);

async function renderAssets() {
  const box = $('assetsBody');
  const { data, error } = await sb.from('assets')
    .select('*').eq('archived', false).order('created_at', { ascending: true });
  box.textContent = '';
  if (error) { box.append(el('p', 'note', human(error))); return; }

  assetRows = (data || []).map(a => ({ ...a,
    amount_agorot: Number(a.amount_agorot),
    liability_agorot: Number(a.liability_agorot || 0) }));

  if (!assetRows.length) {
    const e = el('div', 'empty');
    e.append(el('h2', null, 'עוד לא מיפינו כלום'));
    e.append(el('p', null, 'חיסכון בבנק, קרן השתלמות, פנסיה, דירה. כל מקום שיש בו כסף שלכם ואינו העובר ושב. אחרי שניים שלושה פריטים כבר רואים תמונה.'));
    box.append(e);
    return;
  }

  const total = assetRows.reduce((s, a) => s + Number(a.amount_agorot), 0);
  const debts = assetRows.reduce((s, a) => s + Number(a.liability_agorot || 0), 0);
  const worth = total - debts;

  /* ── המספר, והבטחה להסביר אותו ── */
  const head = el('button', 'worth');
  head.type = 'button';
  head.append(el('span', 'k', 'השווי הפיננסי שלי'));
  const v = el('span', 'v money' + (worth < 0 ? ' neg' : ''));
  setMoney(v, worth, true);
  head.append(v);
  const how = el('span', 'how');
  how.append(document.createTextNode('ממה זה מורכב'));
  const sv = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  sv.setAttribute('viewBox', '0 0 24 24'); sv.setAttribute('aria-hidden', 'true');
  const pa = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  pa.setAttribute('d', 'M14.5 6l-6 6 6 6'); pa.setAttribute('fill', 'none');
  pa.setAttribute('stroke', 'currentColor'); pa.setAttribute('stroke-width', '2.4');
  pa.setAttribute('stroke-linecap', 'round'); pa.setAttribute('stroke-linejoin', 'round');
  sv.append(pa); how.append(sv);
  head.append(how);
  head.setAttribute('aria-label',
    `השווי הפיננסי שלכם ${fmt(worth)}. לחיצה מראה ממה הוא מורכב.`);
  head.addEventListener('click', openWorth);
  box.append(head);

  if (debts) {
    box.append(el('p', 'note',
      `סך הנכסים ${fmt(total)}, ומתוכם ${fmt(debts)} עוד לא שלכם.`));
  }

  /* ── לפי סוגים ── */
  for (const g of ASSET_GROUPS) {
    const keys = ASSET_KINDS.filter(k => k.group === g.key).map(k => k.key);
    const list = assetRows.filter(a => keys.includes(a.kind));
    if (!list.length) continue;

    const wrap = el('div', 'ag');
    const h = el('h2');
    h.append(el('span', null, g.label));
    const tv = el('span', 't money'); setMoney(tv, list.reduce((s, a) => s + assetWorth(a), 0), true);
    h.append(tv);
    wrap.append(h);

    for (const a of list) {
      const k = kindOf(a.kind);
      const row = el('button', 'asset');
      row.type = 'button';
      const ic = el('span', 'asset-ico', k.icon); ic.setAttribute('aria-hidden', 'true');
      const mid = el('div', 'asset-mid');
      mid.append(el('div', 't', a.name));
      const bits = [k.label];
      if (a.note) bits.push(a.note);
      bits.push(updatedAgo(a.updated_at || a.created_at));
      mid.append(el('div', 's', bits.filter(Boolean).join(' · ')));

      const end = el('div', 'asset-end');
      const money = el('span', 'v money' + (assetWorth(a) < 0 ? ' over' : ''));
      setMoney(money, assetWorth(a), true);
      end.append(money);
      /* ‏בנדל"ן המספר הגדול הוא ההון העצמי, והשווי נאמר מתחתיו
         בנפרד. שני המספרים האלה אינם אותו דבר, ואסור שייראו כך. */
      if (a.liability_agorot > 0) {
        end.append(el('span', 'sub', `שווי ${fmt(a.amount_agorot)}, משכנתא ${fmt(a.liability_agorot)}`));
      }
      row.append(ic, mid, end);
      row.setAttribute('aria-label', a.liability_agorot > 0
        ? `${a.name}, ${k.label}. שווי ${fmt(a.amount_agorot)}, יתרת הלוואה ${fmt(a.liability_agorot)}, הון עצמי ${fmt(assetWorth(a))}`
        : `${a.name}, ${k.label}, ${fmt(a.amount_agorot)}`);
      row.addEventListener('click', () => openAsset(a));
      wrap.append(row);
    }
    box.append(wrap);
  }
}

/* ‏ממה מורכב השווי. הוא מבטיח הסבר, ולכן הוא מראה את החשבון
   עצמו ולא גרסה מעוגלת שלו. */
function openWorth() {
  const body = $('worthBody');
  body.textContent = '';
  const line = (k, val, cls) => {
    const r = el('div', 'worth-row' + (cls ? ' ' + cls : ''));
    r.append(el('span', 'k', k));
    const v = el('span', 'v money' + (cls === 'minus' ? ' minus' : ''));
    setMoney(v, val, true);
    r.append(v);
    body.append(r);
  };

  for (const g of ASSET_GROUPS) {
    const keys = ASSET_KINDS.filter(k => k.group === g.key).map(k => k.key);
    const list = assetRows.filter(a => keys.includes(a.kind));
    if (!list.length) continue;
    line(g.label, list.reduce((s, a) => s + Number(a.amount_agorot), 0));
  }

  const debts = assetRows.reduce((s, a) => s + Number(a.liability_agorot || 0), 0);
  if (debts) {
    const r = el('div', 'worth-row');
    r.append(el('span', 'k', 'פחות הלוואות על הנכסים'));
    const v = el('span', 'v money minus');
    setMoney(v, debts);
    v.prepend(document.createTextNode('−'));
    r.append(v);
    body.append(r);
  }

  const total = assetRows.reduce((s, a) => s + assetWorth(a), 0);
  line('השווי הפיננסי שלי', total, 'total');
  openSheet($('worthSheet'));
}
$('worthClose').addEventListener('click', closeSheet);

/* ─────────────────────────── הטופס ── */

function assetEquityLine() {
  if (!ASKS_LIABILITY.has(assetKind)) { $('assetEquity').textContent = ''; return; }
  const v = toAgorot($('assetAmount').value) || 0;
  const l = toAgorot($('assetLiab').value) || 0;
  $('assetEquity').textContent = (v || l)
    ? `ההון העצמי שלכם בנכס הוא ${fmt(v - l, true)}, כלומר השווי פחות יתרת ההלוואה.`
    : '';
}

function setAssetKind(k) {
  assetKind = k;
  for (const b of $('assetKinds').children)
    b.setAttribute('aria-pressed', String(b.dataset.kind === k));
  const estate = k === 'realestate';
  $('assetAmountLbl').textContent = estate ? 'שווי הנכס היום' : 'כמה יש שם';
  $('assetLiabWrap').classList.toggle('hidden', !ASKS_LIABILITY.has(k));
  assetEquityLine();
}

function openAsset(a) {
  assetEdit = a || null;
  $('assetTitle').textContent = a ? 'עדכון' : 'חיסכון או נכס חדש';
  $('assetName').value = a ? a.name : '';
  $('assetAmount').value = a ? (Number(a.amount_agorot) / 100).toString() : '';
  $('assetLiab').value = a && a.liability_agorot ? (Number(a.liability_agorot) / 100).toString() : '';
  $('assetNote').value = a && a.note ? a.note : '';
  $('assetDelRow').classList.toggle('hidden', !a);

  const box = $('assetKinds');
  box.textContent = '';
  for (const k of ASSET_KINDS) {
    const b = el('button', 'chip', `${k.icon} ${k.label}`);
    b.type = 'button';
    b.dataset.kind = k.key;
    b.addEventListener('click', () => setAssetKind(k.key));
    box.append(b);
  }
  setAssetKind(a ? a.kind : 'bank_savings');
  setErr($('assetErr'), '');
  openSheet($('assetSheet'));
}

$('assetAdd').addEventListener('click', () => openAsset(null));
$('assetCancel').addEventListener('click', closeSheet);
$('assetAmount').addEventListener('input', assetEquityLine);
$('assetLiab').addEventListener('input', assetEquityLine);

$('assetSave').addEventListener('click', async () => {
  setErr($('assetErr'), '');
  const name = $('assetName').value.trim();
  const amount = toAgorot($('assetAmount').value);
  if (!name) { setErr($('assetErr'), 'צריך שם, כדי שתדעו מה זה כשתחזרו.'); $('assetName').focus(); return; }
  if (amount == null) { setErr($('assetErr'), 'צריך סכום. אם אתם לא יודעים בדיוק, מספר בערך מספיק.'); $('assetAmount').focus(); return; }
  const liab = ASKS_LIABILITY.has(assetKind) ? (toAgorot($('assetLiab').value) || 0) : 0;

  const btn = $('assetSave');
  btn.disabled = true; btn.textContent = 'שומר...';
  try {
    const row = {
      kind: assetKind, name: name.slice(0, 60),
      amount_agorot: amount, liability_agorot: liab,
      note: $('assetNote').value.trim().slice(0, 300) || null,
      updated_at: new Date().toISOString()
    };
    const { error } = assetEdit
      ? await sb.from('assets').update(row).eq('id', assetEdit.id)
      : await sb.from('assets').insert({ ...row, household_id: S.hh, created_by: S.user.id });
    if (error) throw error;
    closeSheet();
    toast(assetEdit ? 'עודכן.' : 'נוסף.');
    renderAssets();
  } catch (err) {
    setErr($('assetErr'), human(err));
  } finally {
    btn.disabled = false; btn.textContent = 'שמירה';
  }
});

$('assetDelete').addEventListener('click', async () => {
  const a = assetEdit;
  closeSheet();
  if (!a) return;
  const { error } = await sb.from('assets').delete().eq('id', a.id);
  if (error) { toast(human(error)); return; }
  toast('נמחק.');
  renderAssets();
});

/* ═══════════════════════════════════════ סיכום שנה ══ */

/* ‏תמיד קלנדרי, מינואר עד דצמבר, בלי קשר ליום שבו המשתמש בחר
   לפתוח את החודש התקציבי שלו. חודש של עשירי עד עשירי זוחל, שנה
   כזאת אינה שנים עשר חודשים שלמים, ואי אפשר להשוות בה ינואר
   לינואר. זאת הסיבה שהחלון שהמשתמש בוחר חל על התצוגה היומיומית
   בלבד ולא מגיע לכאן. */

let yearPicked = null;

async function renderYear() {
  const now = new Date();
  const thisYear = now.getFullYear();
  if (!yearPicked) yearPicked = thisYear;

  const chips = $('yearPick');
  chips.textContent = '';
  for (const y of [thisYear, thisYear - 1, thisYear - 2]) {
    const b = el('button', 'chip', String(y));
    b.type = 'button';
    b.setAttribute('aria-pressed', String(y === yearPicked));
    b.addEventListener('click', () => { yearPicked = y; renderYear(); });
    chips.append(b);
  }

  const box = $('yearBody');
  box.textContent = '';
  box.append(el('p', 'note', 'טוען...'));

  const from = `${yearPicked}-01-01`, to = `${yearPicked}-12-31`;
  const { data, error } = await sb.from('transactions')
    .select('occurred_on,amount_agorot,direction,category_id,description,is_transfer')
    .gte('occurred_on', from).lte('occurred_on', to);
  if (error) { box.textContent = ''; box.append(el('p', 'note', human(error))); return; }

  const rows = (data || []).map(t => ({ ...t, amount_agorot: Number(t.amount_agorot) }));
  const spend = rows.filter(t => t.direction === 'out' && !t.is_transfer);
  const income = rows.filter(t => t.direction === 'in' && !t.is_transfer);
  const moved = rows.filter(t => t.is_transfer);

  box.textContent = '';
  $('yearTitle').textContent = 'סיכום ' + yearPicked;

  if (!rows.length) {
    const e = el('div', 'empty');
    e.append(el('h2', null, 'אין נתונים ל' + yearPicked));
    e.append(el('p', null, 'בשנה הזאת לא נרשמה אף תנועה. אפשר לייבא דפי בנק אחורה, והשנה תתמלא מעצמה.'));
    const b = el('button', 'btn', 'לייבוא קובץ');
    b.type = 'button';
    b.addEventListener('click', () => tab('import'));
    e.append(b);
    box.append(e);
    return;
  }

  const sum = a => a.reduce((s, t) => s + t.amount_agorot, 0);
  const totalOut = sum(spend), totalIn = sum(income), totalMoved = sum(moved);
  const kept = totalIn - totalOut;

  /* ── המספר של השנה ── */
  const head = el('div', 'sum-block');
  const big = el('div', 'sum-big');
  const v = el('span', 'v money' + (kept < 0 ? ' over' : ''));
  setMoney(v, kept, true);
  big.append(v, el('span', 'k', kept >= 0 ? 'נשארו אצלכם השנה' : 'חסרו השנה'));
  head.append(big);

  const l = el('p', 'note');
  l.append(document.createTextNode('נכנסו ' + fmt(totalIn) + ' · יצאו ' + fmt(totalOut)));
  head.append(l);
  if (totalMoved) head.append(el('p', 'note', 'ועוד ' + fmt(totalMoved) + ' בהעברות, שאינן הוצאה.'));

  const months = new Set(rows.map(t => t.occurred_on.slice(0, 7))).size;
  if (months) head.append(el('p', 'note',
    `ממוצע של ${fmt(Math.round(totalOut / months))} לחודש, על פני ${months} ${months === 1 ? 'חודש' : 'חודשים'} עם רישום.`));
  box.append(head);

  /* ── שנים עשר חודשים, הגרף היחיד שבאמת עוזר ── */
  const perMonth = Array.from({ length: 12 }, (_, i) => ({
    i, out: sum(spend.filter(t => +t.occurred_on.slice(5, 7) === i + 1)),
    in: sum(income.filter(t => +t.occurred_on.slice(5, 7) === i + 1))
  }));
  const maxM = Math.max(...perMonth.map(m => m.out), 1);

  const blk = el('div', 'sum-block');
  blk.append(el('h2', null, 'חודש אחרי חודש'));
  for (const m of perMonth) {
    if (!m.out && !m.in) continue;
    const row = el('div', 'sum-row');
    row.append(el('span', 'nm', MFMT.format(new Date(yearPicked, m.i, 1))));
    const track = el('div', 'track'); track.setAttribute('aria-hidden', 'true');
    const fill = el('i');
    fill.style.width = Math.max(3, Math.round(m.out / maxM * 100)) + '%';
    track.append(fill);
    const vv = el('span', 'vv money'); setMoney(vv, m.out);
    row.append(track, vv);
    row.setAttribute('aria-label',
      `${MFMT.format(new Date(yearPicked, m.i, 1))}, יצאו ${fmt(m.out)}`);
    blk.append(row);
  }
  box.append(blk);

  const active = perMonth.filter(m => m.out > 0);
  if (active.length >= 2) {
    const hi = active.reduce((a, b) => a.out > b.out ? a : b);
    const lo = active.reduce((a, b) => a.out < b.out ? a : b);
    const note = el('p', 'note');
    note.textContent =
      `הכי יקר היה ${MFMT.format(new Date(yearPicked, hi.i, 1))} עם ${fmt(hi.out)}, ` +
      `והכי זול ${MFMT.format(new Date(yearPicked, lo.i, 1))} עם ${fmt(lo.out)}. ` +
      `ההפרש ביניהם הוא ${fmt(hi.out - lo.out)}.`;
    box.append(note);
  }

  /* ── לאן הלך הכסף בשנה ── */
  const byCat = outCats()
    .map(c => ({ c, s: sum(spend.filter(t => t.category_id === c.id)) }))
    .filter(x => x.s > 0).sort((a, b) => b.s - a.s);
  if (byCat.length) {
    const b2 = el('div', 'sum-block');
    b2.append(el('h2', null, 'לאן הכסף הלך בשנה'));
    const max = byCat[0].s;
    for (const { c, s: amt } of byCat) {
      const row = el('div', 'sum-row');
      row.append(el('span', 'nm', (c.icon || '•') + ' ' + c.label));
      const track = el('div', 'track'); track.setAttribute('aria-hidden', 'true');
      const fill = el('i');
      fill.style.width = Math.max(3, Math.round(amt / max * 100)) + '%';
      track.append(fill);
      const vv = el('span', 'vv money'); setMoney(vv, amt);
      const wrap = el('span');
      wrap.append(vv, el('span', 'pct', Math.round(amt / totalOut * 100) + '%'));
      row.append(track, wrap);
      row.setAttribute('aria-label', `${c.label}, ${fmt(amt)}, ${Math.round(amt / totalOut * 100)} אחוז מהוצאות השנה`);
      b2.append(row);
    }
    box.append(b2);
  }

  /* ── מה חזר כל חודש, ומה הוא עלה בשנה ── */
  const rec = recurring(spend).slice(0, 8);
  if (rec.length) {
    const b3 = el('div', 'sum-block');
    b3.append(el('h2', null, 'מה חזר לאורך השנה'));
    const tot = rec.reduce((s, r) => s + r.total, 0);
    b3.append(el('p', 'note',
      `${rec.length} ${rec.length === 1 ? 'דבר חוזר' : 'דברים חוזרים'}, ויחד ${fmt(tot)} לאורך השנה.`));
    for (const r of rec) {
      const row = el('div', 'sum-row');
      row.append(el('span', 'nm', r.label.slice(0, 26)));
      row.append(el('span'));
      const vv = el('span', 'vv money'); setMoney(vv, r.total);
      const wrap = el('span');
      wrap.append(vv, el('span', 'pct', `${r.months} חודשים`));
      row.append(wrap);
      b3.append(row);
    }
    box.append(b3);
  }

  /* ── המטרות, אם יש ── */
  const { data: goals } = await sb.from('goals').select('*').eq('archived', false);
  if (goals && goals.length) {
    const b4 = el('div', 'sum-block');
    b4.append(el('h2', null, 'המטרות'));
    for (const g of goals) {
      const target = Number(g.target_agorot), saved = Number(g.saved_agorot);
      const row = el('div', 'sum-row');
      row.append(el('span', 'nm', g.title));
      const track = el('div', 'track'); track.setAttribute('aria-hidden', 'true');
      const fill = el('i');
      fill.style.width = Math.min(100, Math.round(saved / target * 100)) + '%';
      track.append(fill);
      const wrap = el('span');
      const vv = el('span', 'vv money'); setMoney(vv, saved);
      wrap.append(vv, el('span', 'pct', Math.round(saved / target * 100) + '%'));
      row.append(track, wrap);
      b4.append(row);
    }
    box.append(b4);
  }

  /* ‏מי שבחר חלון שאינו קלנדרי צריך לדעת שכאן הוא לא חל. */
  if ((S.cycle || 1) !== 1) {
    const n = el('div', 'insight');
    n.append(el('h3', null, 'הסיכום הזה קלנדרי'));
    n.append(el('p', null,
      `ביום יום אתם מסתכלים מה־${S.cycle} עד ה־${S.cycle}, וזה בסדר לראות מה הכרטיס עומד לחייב. ` +
      'שנה נמדדת מהראשון בינואר עד השלושים ואחד בדצמבר, אחרת היא לא שנים עשר חודשים שלמים ואי אפשר להשוות בה ינואר לינואר.'));
    box.append(n);
  }

  const cta = el('a', 'cta');
  cta.href = '../#contact';
  cta.target = '_blank'; cta.rel = 'noopener';
  cta.append(el('strong', null, 'שנה שלמה במספרים. מה עושים איתה?'));
  const sp = el('span');
  sp.append(document.createTextNode('זה מה שקרה. לאן זה הולך, וכמה מזה אפשר לשנות, זאת כבר שיחה. '));
  sp.append(el('span', 'go', 'לדבר עם שוהם'));
  cta.append(sp);
  box.append(cta);
}

/* ══════════════════════════ מתי מתחיל החודש התקציבי ══ */

const CYCLE_DAYS = [1, 2, 5, 10, 15, 20, 25];
let cyclePick = 1;

function cycleLabel(c) {
  return c === 1 ? 'בראשון בחודש' : `ב־${c} בחודש, כמו מועד החיוב בכרטיס`;
}

$('setCycle').addEventListener('click', () => {
  cyclePick = S.cycle || 1;
  const box = $('cycleChips');
  box.textContent = '';
  for (const c of CYCLE_DAYS) {
    const b = el('button', 'chip', c === 1 ? 'הראשון' : 'ה־' + c);
    b.type = 'button';
    b.setAttribute('aria-pressed', String(c === cyclePick));
    b.addEventListener('click', () => {
      cyclePick = c;
      for (const o of box.children) o.setAttribute('aria-pressed', 'false');
      b.setAttribute('aria-pressed', 'true');
      $('cycleWarn').classList.toggle('hidden', false);
    });
    box.append(b);
  }
  setErr($('cycleErr'), '');
  openSheet($('cycleSheet'));
});
$('cycleCancel').addEventListener('click', closeSheet);

$('cycleSave').addEventListener('click', async () => {
  setErr($('cycleErr'), '');
  const btn = $('cycleSave');
  btn.disabled = true; btn.textContent = 'שומר...';
  try {
    const { error } = await sb.from('households')
      .update({ cycle_start: cyclePick }).eq('id', S.hh);
    if (error) throw error;
    S.cycle = cyclePick;
    /* ‏נשארים על אותו חודש עוגן ולא קופצים ל"עכשיו". התקציב
       שמור תחת החודש הקלנדרי, ולכן הוא לא זז; מה שזז הוא רק
       טווח הימים שנספרים. קפיצה לחודש אחר כאן הייתה נראית
       למשתמש כאילו התקציב שלו נעלם ברגע ששינה הגדרה. */
    S.lastLeft = null;
    S.hist = null;
    closeSheet();
    await loadAll();
    renderSet();
    toast(cyclePick === 1 ? 'החודש מתחיל בראשון.' : `החודש מתחיל ב־${cyclePick}.`);
  } catch (err) {
    setErr($('cycleErr'), human(err));
  } finally {
    btn.disabled = false; btn.textContent = 'שמירה';
  }
});

/* ═══════════════════════════════════════════ מטרות ══ */

let goalEdit = null;

async function renderGoals() {
  const box = $('goalsList');
  box.textContent = '';
  const { data, error } = await sb.from('goals')
    .select('*').eq('archived', false).order('created_at', { ascending: true });
  if (error) { box.append(el('p', 'note', human(error))); return; }

  if (!data || !data.length) {
    const e = el('div', 'empty');
    e.append(el('h2', null, 'עוד אין מטרה'));
    e.append(el('p', null, 'קרן חירום של שלוש משכורות, טיול, דירה. מטרה אחת שיש לה סכום ותאריך שווה יותר משבע כוונות.'));
    box.append(e);
    return;
  }

  for (const g of data) {
    const target = Number(g.target_agorot), saved = Number(g.saved_agorot);
    const pct = Math.min(100, Math.round(saved / target * 100));
    const done = saved >= target;
    const row = el('button', 'goal' + (done ? ' goal-done' : ''));
    row.type = 'button';

    const top = el('div', 'goal-top');
    top.append(el('span', 'goal-nm', g.title));
    const v = el('span', 'goal-v money'); setMoney(v, saved);
    const of = el('span', 'row-of');
    of.append(document.createTextNode('מתוך '));
    const ofv = el('span', 'money'); setMoney(ofv, target); of.append(ofv);
    top.append(v, of);

    const track = el('div', 'bar'); track.setAttribute('aria-hidden', 'true');
    const fill = el('i'); fill.style.width = pct + '%'; track.append(fill);

    const sub = el('div', 'goal-sub');
    sub.append(el('span', null, pct + '%'));
    /* ‏כמה להפריש כל חודש כדי להגיע בזמן. זה המספר היחיד שהופך
       מטרה ממשאלה לתוכנית. */
    if (g.target_date && !done) {
      const left = target - saved;
      const months = Math.max(1, Math.round(
        (new Date(g.target_date) - new Date()) / (30.4 * DAY)));
      sub.append(el('span', null,
        months > 0 ? `${fmt(Math.ceil(left / months / 100) * 100)} בחודש עד ${new Date(g.target_date + 'T12:00:00').toLocaleDateString('he-IL', { month: 'long', year: 'numeric' })}`
                   : 'היעד עבר'));
    } else if (done) {
      sub.append(el('span', null, 'הגעתם'));
    }

    row.append(top, track, sub);
    row.setAttribute('aria-label', `${g.title}, נחסכו ${fmt(saved)} מתוך ${fmt(target)}, ${pct} אחוז`);
    row.addEventListener('click', () => openGoal(g));
    box.append(row);
  }
}

function openGoal(g) {
  goalEdit = g || null;
  $('goalTitle').textContent = g ? 'המטרה' : 'מטרה חדשה';
  $('goalName').value = g ? g.title : '';
  $('goalTarget').value = g ? (Number(g.target_agorot) / 100).toString() : '';
  $('goalSaved').value = g ? (Number(g.saved_agorot) / 100).toString() : '';
  $('goalDate').value = g && g.target_date ? g.target_date : '';
  $('goalDelRow').classList.toggle('hidden', !g);
  setErr($('goalErr'), '');
  openSheet($('goalSheet'));
}

$('goalAdd').addEventListener('click', () => openGoal(null));
$('goalCancel').addEventListener('click', closeSheet);

$('goalSave').addEventListener('click', async () => {
  setErr($('goalErr'), '');
  const title = $('goalName').value.trim();
  const target = toAgorot($('goalTarget').value);
  const saved = toAgorot($('goalSaved').value) || 0;
  if (!title) { setErr($('goalErr'), 'צריך שם למטרה.'); $('goalName').focus(); return; }
  if (!target) { setErr($('goalErr'), 'צריך סכום יעד גדול מאפס.'); $('goalTarget').focus(); return; }
  if (saved > target) { setErr($('goalErr'), 'כבר יש יותר מהיעד. אולי כדאי להעלות את היעד.'); return; }

  const btn = $('goalSave');
  btn.disabled = true; btn.textContent = 'שומר...';
  try {
    const row = { title: title.slice(0, 60), target_agorot: target, saved_agorot: saved,
                  target_date: $('goalDate').value || null, updated_at: new Date().toISOString() };
    const { error } = goalEdit
      ? await sb.from('goals').update(row).eq('id', goalEdit.id)
      : await sb.from('goals').insert({ ...row, household_id: S.hh, created_by: S.user.id });
    if (error) throw error;
    closeSheet();
    toast(goalEdit ? 'עודכן.' : 'נשמר.');
    renderGoals();
  } catch (err) {
    setErr($('goalErr'), human(err));
  } finally {
    btn.disabled = false; btn.textContent = 'שמירה';
  }
});

$('goalDelete').addEventListener('click', async () => {
  const g = goalEdit;
  closeSheet();
  if (!g) return;
  const { error } = await sb.from('goals').delete().eq('id', g.id);
  if (error) { toast(human(error)); return; }
  toast('נמחק.');
  renderGoals();
});

/* ═══════════════════════════════════════════ הגדרות ══ */

function renderSet() {
  $('setEmail').textContent = S.user?.email || '';
  $('setName').textContent  = S.profile?.display_name || 'לא הוגדר';
  $('cycleNow').textContent = cycleLabel(S.cycle || 1);
}

$('setNameBtn').addEventListener('click', () => {
  $('nameInput').value = S.profile?.display_name || '';
  openSheet($('nameSheet'));
});
$('nameCancel').addEventListener('click', closeSheet);

$('nameSave').addEventListener('click', async () => {
  const name = $('nameInput').value.trim();
  closeSheet();
  const { error } = await sb.from('profiles')
    .upsert({ user_id: S.user.id, display_name: name || null }, { onConflict: 'user_id' });
  if (error) { toast(human(error)); return; }
  S.profile = { display_name: name || null };
  renderSet();
  toast('נשמר.');
});

/* ‏הנתונים הם שלהם, ולכן הם צריכים להיות מסוגלים לקחת אותם
   ולעזוב. BOM בתחילת הקובץ, אחרת אקסל בעברית פותח אותו כג'יבריש. */
$('setExport').addEventListener('click', async () => {
  toast('מכין את הקובץ...');
  const { data, error } = await sb.from('transactions')
    .select('occurred_on,direction,amount_agorot,category_id,description,source,installment_no,installment_total,charged_on')
    .order('occurred_on', { ascending: false });
  if (error) { toast(human(error)); return; }

  const head = ['תאריך', 'סוג', 'סכום', 'קטגוריה', 'תיאור', 'מקור', 'תשלום', 'מתוך', 'מועד חיוב'];
  const q = v => {
    const s = String(v == null ? '' : v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const lines = [head.join(',')];
  for (const t of (data || [])) {
    const c = byId(t.category_id);
    lines.push([
      t.occurred_on,
      t.direction === 'in' ? 'הכנסה' : 'הוצאה',
      (Number(t.amount_agorot) / 100).toFixed(2),
      c ? c.label : '',
      t.description || '',
      t.source === 'import' ? 'מיובא' : 'הוקלד',
      t.installment_no || '',
      t.installment_total || '',
      t.charged_on || ''
    ].map(q).join(','));
  }

  const blob = new Blob(['﻿' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `כמה-יש-לי-${isoDate(new Date())}.csv`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
  toast(`${(data || []).length} תנועות ירדו אליכם.`);
});

/* ‏מחיקה היא מחיקה. שתי לחיצות ולא אישור של הדפדפן, כי חלון
   אישור נלחץ בלי לקרוא אותו. */
let wipeArmed = 0;
$('setWipe').addEventListener('click', async () => {
  const k = $('setWipe').querySelector('.k');
  if (Date.now() - wipeArmed > 6000) {
    wipeArmed = Date.now();
    k.textContent = 'עוד לחיצה אחת מוחקת הכול, בלי דרך חזרה';
    setTimeout(() => {
      if (Date.now() - wipeArmed >= 6000) {
        k.textContent = '';
        k.append(document.createTextNode('מחיקת כל הנתונים'));
        k.append(el('small', null, 'משק הבית, התקציב וכל התנועות'));
      }
    }, 6200);
    return;
  }
  wipeArmed = 0;
  const { error } = await sb.from('households').delete().eq('id', S.hh);
  if (error) { toast(human(error)); return; }
  toast('נמחק.');
  setTimeout(() => location.reload(), 900);
});

/* ═══════════════════════════════════════════ הפעלה ══ */

/* ‏מודול הייבוא מקבל את מה שהוא צריך במקום לייבא מכאן: ייבוא
   הדדי בין שני קבצים הוא מעגל, והוא נשבר בדיוק בסדר שבו קשה
   לשחזר אותו. */
const IMP = mountImport({
  sb, S, $, el, show, hide, toast, openSheet, closeSheet,
  fmt, setMoney, toAgorot, isoDate, byId, outCats, inCats, human,
  goTab: tab,
  monthName, monthKeyOf: monthKey,
  setMonth: m => { S.month = m; S.lastLeft = null; $('monthLabel').textContent = periodLabel(m); },
  reload: async () => { try { await loadAll(); } catch (err) { toast(human(err)); } }
});

/* ‏קליק וואטסאפ נספר, כדי שהמקור החדש הזה לא ייעלם לו מהמדידה
   שכבר יש לו. הרשומה היא חותמת זמן והמילה app, בלי שום פרט מזהה.

   ‏fetch גולמי ולא דרך הלקוח, כי keepalive הוא מה שמאפשר לבקשה
   להסתיים אחרי שהדפדפן כבר עזב לוואטסאפ. והיא לעולם לא מעכבת
   את המעבר: הקישור ממשיך כרגיל גם אם היא נכשלת. */
$('setWa').addEventListener('click', () => {
  try {
    fetch(SUPABASE_URL + '/rest/v1/rpc/wa_click', {
      method: 'POST', keepalive: true,
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_PUBLISHABLE_KEY,
        'Authorization': 'Bearer ' + SUPABASE_PUBLISHABLE_KEY
      },
      body: JSON.stringify({ p_page: 'app' })
    }).catch(() => {});
  } catch {}
});

$('setImport').addEventListener('click', () => tab('import'));
$('setDocs').addEventListener('click', () => tab('docs'));
$('setSum').addEventListener('click', () => tab('sum'));
$('setYear').addEventListener('click', () => tab('year'));
$('setAssets').addEventListener('click', () => tab('assets'));
$('assetsBack').addEventListener('click', () => tab('set'));
$('yearBack').addEventListener('click', () => tab('set'));
$('setGoals').addEventListener('click', () => tab('goals'));
$('importBack').addEventListener('click', () => tab('set'));
$('docsBack').addEventListener('click', () => tab('set'));
$('sumBack').addEventListener('click', () => tab('set'));
$('goalsBack').addEventListener('click', () => tab('set'));

/* ‏חיפוש בהקלדה, בלי השהיה: הכל כבר בזיכרון. */
$('txSearch').addEventListener('input', () => renderTx());
$('txSearch').addEventListener('search', () => renderTx());

for (const b of document.querySelectorAll('.nav button[data-tab]')) {
  b.addEventListener('click', () => {
    if (b.dataset.tab !== 'tx') S.filterCat = null;
    tab(b.dataset.tab);
  });
}

async function enter(user) {
  S.user = user;
  try {
    S.hh = await findHousehold();
  } catch (err) {
    /* ‏אם הטבלאות עוד לא קיימות, זה המקום היחיד שבו זה מתגלה,
       ולכן זה המקום שבו צריך להגיד את זה בבירור. */
    stage('gate');
    gateScreen('main');
    setErr($('authErr'), human(err));
    return;
  }

  if (!S.hh) {
    stage('setup');
    buildSetup();
    $('s_income').focus({ preventScroll: true });
    return;
  }

  try {
    /* ‏יום תחילת המחזור נקרא לפני הכל: הוא קובע איזו תקופה היא
       "עכשיו", ובלעדיו הטעינה הראשונה הייתה מביאה את החלון
       הלא נכון ומתקנת את עצמה אחר כך על המסך. */
    const { data: h } = await sb.from('households').select('cycle_start').limit(1);
    S.cycle = (h && h[0] && h[0].cycle_start) || 1;
    S.month = currentAnchor();
    await loadAll();
  } catch (err) {
    stage('gate');
    setErr($('authErr'), human(err));
    return;
  }

  stage('app');
  tab('home');
  renderStreak(touchStreak());
  renderInsight();
  maybeAsk();
}

/* ‏מי שחזר מקישור האישור במייל מגיע לכאן עם מפתח בכתובת.
   detectSessionInUrl קורא אותו, והמאזין הזה הוא מה שמכניס אותו
   פנימה בלי שיצטרך להתחבר שוב. */
sb.auth.onAuthStateChange((event, session) => {
  if (event === 'PASSWORD_RECOVERY') { openNewPass(); return; }
  /* ‏באמצע החלפת סיסמה אין כניסה לאפליקציה, גם אם יש סשן תקף. */
  if (S.recovery) return;
  if (event === 'SIGNED_IN' && session?.user && !S.user) enter(session.user);
  if (event === 'SIGNED_OUT') location.reload();
});

(async function boot() {
  try {
    const { data: { session } } = await sb.auth.getSession();

    /* ‏חזרה מקישור האיפוס. הסשן קיים, אבל המסך הוא החלפת סיסמה
       ‏ולא הבית · ואם הקישור פג, אומרים את זה במקום לזרוק החוצה. */
    if (FROM_MAIL_RESET) {
      openNewPass(session ? '' : 'הקישור כבר לא תקף. אפשר לבקש קישור חדש ממסך הכניסה.');
      if (!session) { gateScreen('new'); }
      return;
    }

    if (session?.user) { await enter(session.user); return; }
  } catch {}
  stage('gate');
  authMode('signup');
})();
