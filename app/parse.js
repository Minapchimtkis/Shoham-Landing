/* ═══════════════════════════════════════════════════════════════
   קריאת קבצים · החלק שאינו נוגע במסך
   ═══════════════════════════════════════════════════════════════

   ‏כאן יושב כל מה שהופך קובץ של בנק או של חברת אשראי לשורות.
   אין בקובץ הזה DOM ואין בו רשת, ולכן אפשר לבדוק אותו ישירות,
   בלי דפדפן ובלי להעמיד פנים.

   ‏שלוש עובדות על קבצים ישראליים שמסבירות כמעט כל שורה כאן:

   1. ‏הם לא תמיד UTF-8. בנקים מייצאים קובץ בקידוד windows-1255,
      ואם קוראים אותו כ-UTF-8 מקבלים ג'יבריש במקום עברית.

   2. ‏מינוס בא אחרי המספר ולא לפניו. "45.90-" הוא מינוס ארבעים
      וחמישה. זה מה שאקסל בעברית מייצא.

   3. ‏סימן הסכום אומר דברים הפוכים בשני הקבצים: בעו"ש שלילי זה
      כסף שיצא, ובפירוט אשראי חיובי זה כסף שיצא. קריאה של פירוט
      אשראי לפי כללי העו"ש הופכת כל הוצאה להכנסה.
*/

/* ───────────────────────────────────────────── קידוד ── */

/* ‏מנחש קידוד ומחזיר טקסט. הסימן U+FFFD הוא מה שהדפדפן שם
   במקום בית שאינו UTF-8 תקין, ולכן נוכחותו היא ההוכחה שזה לא
   היה UTF-8 מלכתחילה. */
export function decodeText(buf) {
  const bytes = new Uint8Array(buf);
  // ‏סימן סדר בתים, אם יש
  if (bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF)
    return new TextDecoder('utf-8').decode(bytes.subarray(3));

  const utf8 = new TextDecoder('utf-8').decode(bytes);
  if (!utf8.includes('�')) return utf8;

  for (const enc of ['windows-1255', 'iso-8859-8']) {
    try {
      const alt = new TextDecoder(enc).decode(bytes);
      if (!alt.includes('�')) return alt;
    } catch {}
  }
  return utf8;
}

/* ─────────────────────────────────────────────── CSV ── */

/* ‏מנתח אמיתי ולא split על פסיק: בתיאור של בית עסק יש פסיקים,
   והם עטופים במרכאות. split היה שובר כל שורה כזאת לשתיים. */
export function parseCSV(text, delim) {
  const d = delim || sniffDelim(text);
  const rows = [];
  let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') {
        if (text[i + 1] === '"') { cell += '"'; i++; }
        else q = false;
      } else cell += c;
      continue;
    }
    if (c === '"') { q = true; continue; }
    if (c === d) { row.push(cell); cell = ''; continue; }
    if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(cell); cell = '';
      if (row.some(x => x.trim() !== '')) rows.push(row);
      row = [];
      continue;
    }
    cell += c;
  }
  row.push(cell);
  if (row.some(x => x.trim() !== '')) rows.push(row);
  return rows.map(r => r.map(c => c.trim()));
}

function sniffDelim(text) {
  const head = text.slice(0, 4000);
  const counts = [[',', 0], [';', 0], ['\t', 0], ['|', 0]];
  for (const pair of counts) pair[1] = head.split(pair[0]).length - 1;
  counts.sort((a, b) => b[1] - a[1]);
  return counts[0][1] > 0 ? counts[0][0] : ',';
}

/* ────────────────────────────────────── תאריך וסכום ── */

const pad2 = n => String(n).padStart(2, '0');

/* ‏בארץ היום קודם לחודש, תמיד. 03/04 הוא השלישי באפריל ולא
   הרביעי במרץ, ומערכת שמנחשת כאן טועה בשליש מהשנה. */
export function parseDate(v, today) {
  if (v == null) return null;
  if (v instanceof Date && !isNaN(v)) return isoLocal(v);
  const s = String(v).trim();
  if (!s) return null;

  let m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/);
  if (m) return mk(+m[1], +m[2], +m[3]);

  m = s.match(/(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})/);
  if (m) {
    let y = +m[3];
    if (y < 100) y += y < 70 ? 2000 : 1900;
    return mk(y, +m[2], +m[1]);
  }

  /* ‏פירוטי אשראי כותבים לפעמים יום וחודש בלבד, בלי שנה. השנה
     נלקחת מהיום, ואם זה מפיל את התאריך קדימה הוא שייך לשנה
     שעברה: פירוט שמופק בינואר מכיל את דצמבר. */
  m = s.match(/^(\d{1,2})[-/.](\d{1,2})$/);
  if (m) {
    const now = today ? new Date(today) : new Date();
    let y = now.getFullYear();
    const guess = mk(y, +m[2], +m[1]);
    if (guess && new Date(guess) - now > 45 * 86400000) return mk(y - 1, +m[2], +m[1]);
    return guess;
  }
  return null;

  function mk(y, mo, d) {
    if (!(y >= 1990 && y <= 2100) || !(mo >= 1 && mo <= 12) || !(d >= 1 && d <= 31)) return null;
    const dt = new Date(y, mo - 1, d);
    if (dt.getMonth() !== mo - 1 || dt.getDate() !== d) return null;
    return `${y}-${pad2(mo)}-${pad2(d)}`;
  }
}

export const isoLocal = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;

/* ‏מחזיר אגורות שלמות, עם הסימן. null כשאין כאן מספר בכלל. */
export function parseAmount(v) {
  if (v == null || v === '') return null;
  if (typeof v === 'number') return isFinite(v) ? Math.round(v * 100) : null;

  let s = String(v).trim();
  if (!s) return null;

  // ‏סימני כיווניות שנדבקים למספרים שנחתכו מ-PDF בעברית
  s = s.replace(/[‎‏‪-‮⁦-⁩]/g, '');
  s = s.replace(/[₪\s]/g, '').replace(/ש"ח|שח|NIS|ILS/gi, '');
  if (!s) return null;

  let neg = false;
  if (/^\(.*\)$/.test(s)) { neg = true; s = s.slice(1, -1); }
  // ‏מינוס בסוף, כפי שאקסל בעברית מייצא
  if (/-$/.test(s)) { neg = true; s = s.slice(0, -1); }
  if (/^[-−–]/.test(s)) { neg = true; s = s.slice(1); }

  s = s.replace(/,/g, '');
  if (!/^\d+(\.\d+)?$/.test(s)) return null;
  const n = Math.round(parseFloat(s) * 100);
  if (!isFinite(n)) return null;
  return neg ? -n : n;
}

/* ───────────────────────────────────── זיהוי עמודות ── */

const HEAD = {
  date:    ['תאריך עסקה','תאריך העסקה','ת. עסקה','תאריך ערך','תאריך חיוב','תאריך','מועד','date','transaction date'],
  date2:   ['תאריך חיוב','מועד חיוב','תאריך ערך'],
  desc:    ['שם בית עסק','בית העסק','בית עסק','תיאור פעולה','תיאור העסקה','תיאור','פירוט','פרטים','אסמכתא ותיאור','description','merchant','details'],
  amount:  ['סכום חיוב','סכום החיוב','סכום העסקה','סכום בש"ח','סכום בשח','סכום','amount','charge'],
  debit:   ['חובה','חיוב','משיכה','בחובה'],
  credit:  ['זכות','הפקדה','זיכוי','בזכות'],
  balance: ['יתרה','יתרה בחשבון','balance'],
  inst:    ['תשלומים','מספר תשלום','פירוט תשלומים','תשלום']
};

const norm = s => String(s == null ? '' : s)
  .replace(/[‎‏]/g, '').replace(/["'`]/g, '').replace(/\s+/g, ' ').trim().toLowerCase();

/* ‏מחזיר מיפוי של שם שדה למספר עמודה, או null אם זו אינה
   שורת כותרות. דרושות לפחות שתיים, כי שורת נתונים אחת יכולה
   במקרה להכיל את המילה "סכום". */
export function mapHeader(cells) {
  const map = {};
  const used = new Set();
  for (const [field, words] of Object.entries(HEAD)) {
    let best = -1, bestLen = 0;
    cells.forEach((c, i) => {
      if (used.has(i)) return;
      const n = norm(c);
      if (!n) return;
      for (const w of words) {
        const wn = norm(w);
        if (n === wn || n.startsWith(wn) || n.includes(wn)) {
          if (wn.length > bestLen) { best = i; bestLen = wn.length; }
        }
      }
    });
    if (best >= 0) { map[field] = best; used.add(best); }
  }
  const hasDate = map.date != null || map.date2 != null;
  const hasMoney = map.amount != null || map.debit != null || map.credit != null;
  if (!hasDate || !hasMoney) return null;
  return map;
}

/* ‏מוצא את שורת הכותרות. בקבצים של בנקים יש מעליה שורות של
   שם לקוח, מספר חשבון ותקופה, ולכן היא כמעט אף פעם לא הראשונה. */
export function findHeader(rows) {
  const limit = Math.min(rows.length, 30);
  for (let i = 0; i < limit; i++) {
    const map = mapHeader(rows[i]);
    if (map) return { index: i, map };
  }
  return null;
}

/* ──────────────────────────────────────── תשלומים ── */

/* ‏קנייה ב-12 תשלומים מופיעה בפירוט כסכום חודשי. אפליקציה
   שלא יודעת את זה סופרת אותה כהוצאה קבועה ומשקרת למשתמש. */
export function parseInstallment(s) {
  const t = String(s == null ? '' : s).replace(/[‎‏]/g, '');
  let m = t.match(/תשלום\s*(\d{1,2})\s*(?:מתוך|מ-|מ|\/)\s*(\d{1,2})/);
  if (!m) m = t.match(/(\d{1,2})\s*מתוך\s*(\d{1,2})/);
  if (!m) m = t.match(/\b(\d{1,2})\s*\/\s*(\d{1,2})\b/);
  if (!m) return null;
  const no = +m[1], total = +m[2];
  if (!(total > 1 && no >= 1 && no <= total && total <= 60)) return null;
  return { no, total };
}

/* ──────────────────────────────────────── קטגוריות ── */

/* ‏ניחוש, לא קביעה. כל שורה מוצגת לאישור, ולכן עדיף לנחש
   ולטעות מאשר להשאיר הכל ב"כל השאר" ולהעביר למשתמש את כל
   העבודה. סדר הבדיקה חשוב: "דלק" לפני "דלק תעשיות". */
const RULES = [
  ['housing',   ['חברת חשמל','חשמל','מקורות','מי ','תאגיד המים','מים','ארנונה','עירי','מועצה מקומית','ועד בית','גז','סופרגז','אמישראגז','פזגז','דור גז','משכנתא','שכר דירה','שכירות','בזק','הוט','hot','yes','פרטנר','סלקום','פלאפון','גולן טלקום','רמי לוי תקשורת','019','012','מועצה אזורית','ביטוח דירה','ארנונה']],
  ['food',      ['שופרסל','רמי לוי','ויקטורי','יוחננוף','אושר עד','טיב טעם','מגה','יינות ביתן','סטופ מרקט','am:pm','ampm','סופר','מכולת','מרכול','קפה','קפית','ארומה','לנדוור','קופיקס','מסעד','פיצה','בורגר','מקדונלד','סושי','wolt','וולט','10bis','תן ביס','תן-ביס','מאפ','קונדיטור','בשר','ירקות','שוק']],
  ['transport', ['פז ','פז,','דלק','סונול','דור אלון','ten ','טן ','יעד','רב קו','רב-קו','הופ און','פנגו','pango','סלופארק','cellopark','חניון','מוסך','טסט','רישוי','ביטוח רכב','gett','גט','uber','אובר','רכבת','אגד','דן','מטרופולין','סופרבוס','צמיג']],
  ['debt',      ['הלוואה','החזר הלוואה','ריבית','עמלת','עמלה','משיכת יתר','מינוס','כרטיס אשראי','חיוב כרטיס','ישראכרט','כאל','מקס','אמריקן אקספרס','לאומי קארד']],
  ['fun',       ['נטפליקס','netflix','ספוטיפיי','spotify','דיסני','disney','youtube','יוטיוב','סינמה','יס פלנט','רב חן','לב סינמה','הוט סינמה','תיאטרון','הופע','כרטיס','מלון','נופש','טיסה','אל על','ויז אייר','booking','airbnb','חדר כושר','הולמס פלייס','גו אקטיב','איקאה','קסטרו','זara','h&m','fox','טרמינל','steam','playstation','xbox','apple.com','google play']],
  ['other',     []]
];

export function guessCategory(desc) {
  const t = norm(desc);
  if (!t) return 'other';
  for (const [key, words] of RULES) {
    for (const w of words) {
      if (w && t.includes(norm(w))) return key;
    }
  }
  return 'other';
}

/* ────────────────────────────── מטבלה לשורות תנועה ── */

/* kind: 'bank' או 'credit'. זה מה שקובע מה המשמעות של הסימן. */
export function rowsFromTable(rows, kind, today) {
  const found = findHeader(rows);
  if (!found) return { ok: false, reason: 'no-header', rows: [] };
  const { index, map } = found;
  const out = [];
  let skipped = 0;

  for (let i = index + 1; i < rows.length; i++) {
    const r = rows[i];
    if (!r || !r.length) continue;

    const rawDate = map.date != null ? r[map.date] : r[map.date2];
    const on = parseDate(rawDate, today);
    if (!on) { skipped++; continue; }

    let signed = null;
    if (map.debit != null || map.credit != null) {
      const d = parseAmount(map.debit  != null ? r[map.debit]  : null);
      const c = parseAmount(map.credit != null ? r[map.credit] : null);
      if (d) signed = -Math.abs(d);
      else if (c) signed = Math.abs(c);
      else if (map.amount != null) signed = parseAmount(r[map.amount]);
    } else {
      signed = parseAmount(r[map.amount]);
    }
    if (signed == null || signed === 0) { skipped++; continue; }

    /* ‏בעו"ש שלילי הוא כסף שיצא. בפירוט אשראי כל שורה היא חיוב,
       ולכן חיובי הוא כסף שיצא וזיכוי הוא השלילי. */
    const outward = kind === 'credit' ? signed > 0 : signed < 0;

    const desc = (map.desc != null ? String(r[map.desc] || '') : '').trim();
    const instSrc = (map.inst != null ? String(r[map.inst] || '') : '') + ' ' + desc;
    const inst = parseInstallment(instSrc);

    out.push({
      occurred_on: on,
      charged_on: map.date2 != null && map.date != null ? parseDate(r[map.date2], today) : null,
      amount_agorot: Math.abs(signed),
      direction: outward ? 'out' : 'in',
      description: desc.slice(0, 80) || null,
      cat: outward ? guessCategory(desc) : 'salary',
      installment_no: inst ? inst.no : null,
      installment_total: inst ? inst.total : null,
      take: true
    });
  }
  return { ok: true, rows: out, skipped, headerAt: index, map };
}

/* ────────────────────────────── משורות טקסט, ל-PDF ── */

/* ‏ב-PDF אין עמודות, יש שורות. לכן כאן מחפשים בכל שורה תאריך
   ומספר, ומה שביניהם הוא התיאור. זה גס, והוא נכון רק בחלק
   מהקבצים, ולכן הכל עובר דרך מסך אישור. */
const DATE_RE = /(\d{1,2}[-/.]\d{1,2}(?:[-/.]\d{2,4})?)/;
const MONEY_RE = /(?:^|\s)(-?[\d,]+\.\d{2}-?|\(\s*[\d,]+\.\d{2}\s*\))(?=\s|$)/g;

export function rowsFromLines(lines, kind, today) {
  const out = [];
  for (const raw of lines) {
    const line = String(raw || '').replace(/[‎‏‪-‮]/g, ' ').trim();
    if (line.length < 8) continue;

    const dm = line.match(DATE_RE);
    if (!dm) continue;
    const on = parseDate(dm[1], today);
    if (!on) continue;

    const monies = [...line.matchAll(MONEY_RE)].map(m => m[1]);
    if (!monies.length) continue;

    /* ‏בשורה של עו"ש המספר האחרון הוא היתרה ולא הסכום. כשיש
       שניים או יותר, הסכום הוא זה שלפני האחרון. */
    const pick = monies.length >= 2 ? monies[monies.length - 2] : monies[0];
    const signed = parseAmount(pick);
    if (signed == null || signed === 0) continue;

    let desc = line.replace(dm[1], ' ');
    for (const m of monies) desc = desc.replace(m, ' ');
    desc = desc.replace(/\s{2,}/g, ' ').replace(/^[\s|·.-]+|[\s|·.-]+$/g, '').trim();

    const outward = kind === 'credit' ? signed > 0 : signed < 0;
    const inst = parseInstallment(line);

    out.push({
      occurred_on: on,
      charged_on: null,
      amount_agorot: Math.abs(signed),
      direction: outward ? 'out' : 'in',
      description: desc.slice(0, 80) || null,
      cat: outward ? guessCategory(desc) : 'salary',
      installment_no: inst ? inst.no : null,
      installment_total: inst ? inst.total : null,
      take: true
    });
  }
  return { ok: out.length > 0, rows: out, reason: out.length ? null : 'no-rows' };
}

/* ────────────────────────────────────────── כפילויות ── */

export const dupKey = t =>
  [t.occurred_on, t.amount_agorot, t.direction,
   String(t.description || '').replace(/\s+/g, ' ').trim().slice(0, 24)].join('|');

/* ‏מסמן שורות שכבר קיימות. גם בתוך הקובץ עצמו, כי פירוט אשראי
   מכיל לפעמים את אותה עסקה פעמיים כשהיא פוצלה. */
export function markDuplicates(rows, existing) {
  const seen = new Set((existing || []).map(dupKey));
  for (const r of rows) {
    const k = dupKey(r);
    r.dup = seen.has(k);
    if (r.dup) r.take = false;
    seen.add(k);
  }
  return rows;
}
