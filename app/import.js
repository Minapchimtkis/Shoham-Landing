/* ═══════════════════════════════════════════════════════════════
   ייבוא קבצים ומסמכים · החלק שנוגע במסך
   ═══════════════════════════════════════════════════════════════

   ‏הפענוח עצמו יושב ב-parse.js ואין בו DOM, ולכן הוא נבדק בלי
   דפדפן. כאן נמצא מה שסביבו: קריאת הקובץ, טעינת הספריות, מסך
   האישור, והכתיבה לבסיס.

   ‏הכלל שמסביר את כל המסך הזה: שום שורה לא נכנסת לבסיס בלי
   שאדם ראה אותה. קורא אוטומטי של קובץ בנק שטועה בשקט גרוע
   מקורא שלא קיים, כי אחרי חודש כבר אי אפשר לדעת מה הוא עשה.
*/

import * as P from './parse.js';

/* ‏שתי הספריות נטענות רק כשבאמת בוחרים קובץ מהסוג שלהן. יחד
   הן כשני מגהבייט, ואין שום סיבה שמי שלא ייבא דבר ישלם עליהן. */
/* ‏הנתיבים נגזרים מכתובת הקובץ הזה עצמו ולא מכתובת הדף, כדי
   ‏שהעובד של pdf.js ימצא את עצמו גם אם האפליקציה תוגש מתיקייה
   ‏אחרת יום אחד. */
const V = p => new URL('../vendor/' + p, import.meta.url).href;
const LIB = {
  xlsx:      V('xlsx.js'),
  pdf:       V('pdf.js'),
  pdfWorker: V('pdf.worker.js')
};

const DOC_KINDS = [
  { key: 'loan',      icon: '🏦', label: 'דוח יתרות וסילוקין' },
  { key: 'bill',      icon: '🧾', label: 'חשבון' },
  { key: 'statement', icon: '📄', label: 'דף חשבון' },
  { key: 'other',     icon: '•',  label: 'אחר' }
];

export function mountImport(A) {
  const { sb, S, $, el, show, hide, toast, openSheet, closeSheet,
          fmt, setMoney, toAgorot, isoDate, byId, outCats, inCats } = A;

  const MOVE = '__move';
  let impKind = 'bank';
  let impRows = [];
  let impFile = null;
  let impHash = null;

  /* ─────────────────────────────── עזרים ── */

  const setErr = (node, msg) => {
    if (!msg) { hide(node); node.textContent = ''; return; }
    node.textContent = msg; show(node);
  };

  async function sha256(buf) {
    try {
      const d = await crypto.subtle.digest('SHA-256', buf);
      return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
    } catch { return null; }
  }

  const catIdOf = key => {
    const c = S.cats.find(x => x.key === key && x.household_id === null);
    return c ? c.id : null;
  };

  /* ─────────────────────── קריאת הקובץ לפי סוגו ── */

  async function readFile(file) {
    const name = (file.name || '').toLowerCase();
    const buf = await file.arrayBuffer();
    const today = isoDate(new Date());

    if (name.endsWith('.csv') || file.type === 'text/csv' || name.endsWith('.txt')) {
      const text = P.decodeText(buf);
      return P.rowsFromTable(P.parseCSV(text), impKind, today);
    }

    if (name.endsWith('.xlsx') || name.endsWith('.xls') ||
        (file.type || '').includes('spreadsheet') || (file.type || '').includes('ms-excel')) {
      let XLSX;
      try { XLSX = await import(/* @vite-ignore */ LIB.xlsx); }
      catch {
        return { ok: false, reason: 'no-xlsx', rows: [] };
      }
      const wb = XLSX.read(new Uint8Array(buf), { type: 'array', cellDates: true });
      /* ‏הגיליון הראשון שיש בו שורת כותרות מוכרת, ולא בהכרח
         הראשון: בקבצים של בנקים הגיליון הראשון הוא לפעמים
         עמוד נתוני לקוח. */
      let best = null;
      for (const nm of wb.SheetNames) {
        const rows = XLSX.utils.sheet_to_json(wb.Sheets[nm], { header: 1, raw: true, blankrows: false });
        const r = P.rowsFromTable(rows, impKind, today);
        if (r.ok && (!best || r.rows.length > best.rows.length)) best = r;
      }
      return best || { ok: false, reason: 'no-header', rows: [] };
    }

    if (name.endsWith('.pdf') || file.type === 'application/pdf') {
      let pdfjs;
      try {
        pdfjs = await import(/* @vite-ignore */ LIB.pdf);
        pdfjs.GlobalWorkerOptions.workerSrc = LIB.pdfWorker;
      } catch {
        return { ok: false, reason: 'no-pdf', rows: [] };
      }
      const doc = await pdfjs.getDocument({ data: new Uint8Array(buf) }).promise;
      const lines = [];
      for (let i = 1; i <= doc.numPages; i++) {
        const page = await doc.getPage(i);
        const tc = await page.getTextContent();
        /* ‏ב-PDF אין שורות, יש פריטי טקסט עם מיקום. קיבוץ לפי
           הגובה הוא מה שמחזיר להם את השורה. */
        const byY = new Map();
        for (const it of tc.items) {
          if (!it.str || !it.str.trim()) continue;
          const y = Math.round(it.transform[5]);
          const k = Math.round(y / 3) * 3;
          if (!byY.has(k)) byY.set(k, []);
          byY.get(k).push({ x: it.transform[4], s: it.str });
        }
        for (const k of [...byY.keys()].sort((a, b) => b - a)) {
          lines.push(byY.get(k).sort((a, b) => a.x - b.x).map(o => o.s).join(' '));
        }
      }
      if (!lines.length) return { ok: false, reason: 'pdf-empty', rows: [] };
      return P.rowsFromLines(lines, impKind, today);
    }

    return { ok: false, reason: 'unknown-type', rows: [] };
  }

  const WHY = {
    'no-header': 'לא זיהינו בקובץ טבלה עם תאריך וסכום. אם זה קובץ אקסל, כדאי לבדוק שיש בו שורת כותרות כמו תאריך, תיאור וסכום.',
    'no-xlsx': 'לא הצלחנו לטעון את קורא האקסל. אפשר לשמור את הקובץ כ־CSV ולנסות שוב, וזה גם נקרא מדויק יותר.',
    'no-pdf': 'לא הצלחנו לטעון את קורא ה־PDF. באתר של הבנק יש כפתור ייצוא לאקסל ליד ההורדה ל־PDF, והוא הדרך הבטוחה.',
    'pdf-empty': 'ה־PDF הזה הוא סריקה של תמונה ואין בו טקסט לקרוא. צריך את הקובץ המקורי מהבנק, או ייצוא לאקסל.',
    'no-rows': 'קראנו את הקובץ ולא מצאנו בו שורות של תנועות. אם זה PDF, כדאי לנסות ייצוא לאקסל.',
    'unknown-type': 'את סוג הקובץ הזה אנחנו לא יודעים לקרוא. אקסל, CSV או PDF.'
  };

  /* ──────────────────────────────── מסך הייבוא ── */

  function setKind(k) {
    impKind = k;
    $('impBank').setAttribute('aria-pressed', String(k === 'bank'));
    $('impCredit').setAttribute('aria-pressed', String(k === 'credit'));
    $('impDropSub').textContent = k === 'credit'
      ? 'פירוט החיובים של הכרטיס, אקסל, CSV או PDF'
      : 'דף התנועות של החשבון, אקסל, CSV או PDF';
  }

  function resetImport() {
    impRows = []; impFile = null; impHash = null;
    show($('impPick')); hide($('impReview'));
    setErr($('impErr'), ''); setErr($('impErr2'), '');
    $('impFile').value = '';
    $('impDropTitle').textContent = 'בחירת קובץ';
    setKind('bank');
  }

  async function onFile(file) {
    if (!file) return;
    setErr($('impErr'), '');
    $('impDropTitle').textContent = 'קורא את ' + file.name;

    if (file.size > 15 * 1024 * 1024) {
      setErr($('impErr'), 'הקובץ גדול מ־15 מגה. דף של שלושה חודשים אמור להיות קטן בהרבה.');
      $('impDropTitle').textContent = 'בחירת קובץ';
      return;
    }

    let res;
    try {
      impHash = await sha256(await file.arrayBuffer());
      /* ‏אותו קובץ שהועלה כבר פעם אחת. בלי הבדיקה הזאת אדם
         שמעלה שוב את אותו דף מקבל מאתיים שורות שהוא כבר אישר. */
      if (impHash) {
        const { data } = await sb.from('imports')
          .select('created_at,rows_taken').eq('file_hash', impHash).limit(1);
        if (data && data.length) {
          const when = new Date(data[0].created_at).toLocaleDateString('he-IL');
          setErr($('impErr'), `את הקובץ הזה כבר ייבאתם ב־${when}, ונכנסו ממנו ${data[0].rows_taken} תנועות. אם זה בכוונה, אפשר למחוק את הישן מהתנועות ולנסות שוב.`);
          $('impDropTitle').textContent = 'בחירת קובץ';
          return;
        }
      }
      res = await readFile(file);
    } catch (err) {
      setErr($('impErr'), 'הקובץ לא נקרא. ' + (err && err.message ? '' : '') + 'אם זה PDF, כדאי לנסות ייצוא לאקסל.');
      $('impDropTitle').textContent = 'בחירת קובץ';
      return;
    }

    if (!res.ok || !res.rows.length) {
      setErr($('impErr'), WHY[res.reason] || WHY['no-rows']);
      $('impDropTitle').textContent = 'בחירת קובץ';
      return;
    }

    impFile = file;
    impRows = res.rows;

    /* ‏כפילויות נבדקות מול התנועות שכבר קיימות בטווח התאריכים
       של הקובץ, ולא מול החודש הנוכחי בלבד: דף של שלושה חודשים
       חופף לשלושה חודשים של רישום ידני. */
    const dates = impRows.map(r => r.occurred_on).sort();
    const { data: existing } = await sb.from('transactions')
      .select('occurred_on,amount_agorot,direction,description')
      .gte('occurred_on', dates[0]).lte('occurred_on', dates[dates.length - 1]);
    P.markDuplicates(impRows, (existing || []).map(t => ({ ...t, amount_agorot: Number(t.amount_agorot) })));

    hide($('impPick')); show($('impReview'));
    $('impChargeWrap').classList.toggle('hidden', impKind !== 'credit');
    if (impKind === 'credit' && !$('impCharge').value) $('impCharge').value = isoDate(new Date());
    renderReview();
    window.scrollTo({ top: 0 });
  }

  function renderReview() {
    const box = $('impRows');
    box.textContent = '';

    const cats = [...outCats(), ...inCats()];
    for (const [i, r] of impRows.entries()) {
      const row = el('div', 'ir' + (r.take ? '' : ' off'));

      const cb = el('input');
      cb.type = 'checkbox';
      cb.checked = r.take;
      cb.id = 'ir' + i;
      cb.addEventListener('change', () => {
        r.take = cb.checked;
        row.classList.toggle('off', !r.take);
        updateSum();
      });

      const mid = el('div', 'ir-mid');
      const top = el('div', 'ir-top');
      const lab = el('label', 'ir-desc', r.description || 'תנועה בלי תיאור');
      lab.htmlFor = cb.id;
      const amt = el('span', 'ir-amt money' + (r.direction === 'in' ? ' in' : ''));
      setMoney(amt, r.amount_agorot);
      if (r.direction === 'in') amt.prepend(document.createTextNode('+'));
      top.append(lab, amt);

      const sub = el('div', 'ir-sub');
      sub.append(el('span', null, new Date(r.occurred_on + 'T12:00:00')
        .toLocaleDateString('he-IL', { day: 'numeric', month: 'numeric' })));

      /* ‏ההעברה היא אפשרות בתוך בורר הקטגוריה ולא פקד נוסף: היא
         ממילא התשובה לשאלה "לאיזה סעיף זה שייך", והתשובה היא
         לאף אחד. פקד נפרד לכל שורה היה מכפיל את המסך. */
      const sel = el('select');
      sel.setAttribute('aria-label', 'קטגוריה עבור ' + (r.description || 'התנועה'));
      const moveOpt = el('option', null, '⇄ העברה, לא הוצאה');
      moveOpt.value = MOVE;
      sel.append(moveOpt);
      for (const c of cats) {
        const o = el('option', null, (c.icon || '•') + ' ' + c.label);
        o.value = c.id;
        sel.append(o);
      }
      if (r.move) sel.value = MOVE;
      else {
        const hit = cats.find(c => c.key === r.cat) ||
                    cats.find(c => c.key === (r.direction === 'in' ? 'other_in' : 'other'));
        if (hit) sel.value = hit.id;
      }
      r.catId = sel.value;
      const syncMove = () => {
        r.catId = sel.value;
        r.move = sel.value === MOVE;
        row.classList.toggle('moved', r.move);
        updateSum();
      };
      sel.addEventListener('change', syncMove);
      sub.append(sel);
      if (r.move) row.classList.add('moved');

      if (r.installment_total)
        sub.append(el('span', 'ir-inst', `תשלום ${r.installment_no} מתוך ${r.installment_total}`));
      if (r.dup) sub.append(el('span', 'ir-dup', 'כבר קיים'));

      mid.append(top, sub);
      row.append(cb, mid);
      box.append(row);
    }
    updateSum();
  }

  function updateSum() {
    const taken = impRows.filter(r => r.take);
    const out = taken.filter(r => r.direction === 'out' && !r.move).reduce((s, r) => s + r.amount_agorot, 0);
    const inn = taken.filter(r => r.direction === 'in' && !r.move).reduce((s, r) => s + r.amount_agorot, 0);
    const mov = taken.filter(r => r.move).reduce((s, r) => s + r.amount_agorot, 0);
    const dups = impRows.filter(r => r.dup).length;

    const box = $('impSum');
    box.textContent = '';
    const line = el('p');
    line.append(document.createTextNode('נקראו '));
    line.append(el('b', null, String(impRows.length)));
    line.append(document.createTextNode(' שורות, מסומנות '));
    line.append(el('b', null, String(taken.length)));
    line.append(document.createTextNode('.'));
    box.append(line);

    const l2 = el('p');
    l2.append(document.createTextNode('יוצא ' + fmt(out)));
    if (inn) l2.append(document.createTextNode(' · נכנס ' + fmt(inn)));
    if (mov) l2.append(document.createTextNode(' · ' + fmt(mov) + ' בהעברות'));
    box.append(l2);

    if (dups) {
      const l3 = el('p', 'warn', `${dups} ${dups === 1 ? 'שורה כבר קיימת' : 'שורות כבר קיימות'} אצלכם, והן לא מסומנות.`);
      box.append(l3);
    }
    $('impGo').textContent = taken.length ? `ייבוא ${taken.length} תנועות` : 'לא סומן כלום';
    $('impGo').disabled = !taken.length;
  }

  async function doImport() {
    setErr($('impErr2'), '');
    const taken = impRows.filter(r => r.take);
    if (!taken.length) return;

    const btn = $('impGo');
    btn.disabled = true; btn.textContent = 'מייבא...';
    try {
      const charged = impKind === 'credit' ? ($('impCharge').value || null) : null;

      const { data: imp, error: e1 } = await sb.from('imports').insert({
        household_id: S.hh, source: 'file', kind: impKind,
        file_name: impFile ? impFile.name.slice(0, 120) : null,
        file_hash: impHash,
        rows_total: impRows.length, rows_taken: taken.length,
        charged_on: charged, created_by: S.user.id
      }).select().single();
      if (e1) throw e1;

      const rows = taken.map(r => ({
        household_id: S.hh,
        occurred_on: r.occurred_on,
        amount_agorot: r.amount_agorot,
        direction: r.direction,
        category_id: r.move ? null : (r.catId && r.catId !== MOVE ? r.catId : catIdOf(r.cat)) || null,
        is_transfer: !!r.move,
        description: r.description,
        source: 'import',
        import_id: imp.id,
        installment_no: r.installment_no,
        installment_total: r.installment_total,
        charged_on: r.charged_on || charged,
        created_by: S.user.id
      }));

      /* ‏בבקשות של מאות שורות, חבילה אחת גדולה היא בקשה אחת
         שנופלת כולה. מאה בכל פעם. */
      for (let i = 0; i < rows.length; i += 100) {
        const { error } = await sb.from('transactions').insert(rows.slice(i, i + 100));
        if (error) throw error;
      }

      /* ‏דף של שלושה חודשים נוחת בשלושה חודשים, ומי שמסתכל על
         אוקטובר ומייבא את אפריל רואה מסך שלא השתנה בכלום וחושב
         שהייבוא נכשל. עוברים לחודש שקיבל הכי הרבה שורות. */
      const byMonth = new Map();
      for (const r of taken) {
        const k = r.occurred_on.slice(0, 7);
        byMonth.set(k, (byMonth.get(k) || 0) + 1);
      }
      const here = A.monthKeyOf(S.month).slice(0, 7);
      if (!byMonth.has(here) && byMonth.size) {
        const top = [...byMonth.entries()].sort((a, b) => b[1] - a[1])[0][0];
        A.setMonth(new Date(+top.slice(0, 4), +top.slice(5, 7) - 1, 1));
      }

      const names = [...byMonth.keys()].sort().reverse()
        .map(k => A.monthName(new Date(+k.slice(0, 4), +k.slice(5, 7) - 1, 1)));
      toast(`נכנסו ${taken.length} תנועות${names.length === 1 ? ' ל' + names[0]
            : names.length === 2 ? ' ל' + names[0] + ' ול' + names[1]
            : ' ב' + names.length + ' חודשים'}.`);

      resetImport();
      await A.reload();
      A.goTab('home');
    } catch (err) {
      setErr($('impErr2'), A.human(err));
    } finally {
      btn.disabled = false;
      updateSum();
    }
  }

  /* ─────────────────────────────────── מסמכים ── */

  let docKind = 'bill';
  let docFile = null;
  let docOpenRow = null;

  async function renderDocs() {
    const box = $('docsList');
    box.textContent = '';
    const { data, error } = await sb.from('documents')
      .select('*').order('created_at', { ascending: false });
    if (error) {
      box.append(el('p', 'note', A.human(error)));
      return;
    }
    if (!data || !data.length) {
      const e = el('div', 'empty');
      e.append(el('h2', null, 'עוד אין כאן מסמכים'));
      e.append(el('p', null, 'דוח יתרות וסילוקין מהבנק, חשבון חשמל, ארנונה. כל נייר שתרצו למצוא בלי לחפש במיילים.'));
      box.append(e);
      return;
    }
    for (const d of data) {
      const k = DOC_KINDS.find(x => x.key === d.kind) || DOC_KINDS[3];
      const row = el('button', 'doc');
      row.type = 'button';
      const ic = el('span', 'doc-ico', k.icon); ic.setAttribute('aria-hidden', 'true');
      const mid = el('div', 'doc-mid');
      mid.append(el('div', 't', d.title));
      const bits = [k.label];
      if (d.provider) bits.push(d.provider);
      if (d.due_on) bits.push(new Date(d.due_on + 'T12:00:00').toLocaleDateString('he-IL'));
      mid.append(el('div', 's', bits.join(' · ')));
      row.append(ic, mid);
      if (d.amount_agorot) {
        const a = el('span', 'doc-amt money');
        setMoney(a, Number(d.amount_agorot));
        row.append(a);
      }
      row.setAttribute('aria-label', `${d.title}, ${bits.join(', ')}`);
      row.addEventListener('click', () => openDocView(d));
      box.append(row);
    }
  }

  function openDocSheet() {
    docFile = null;
    docKind = 'bill';
    $('docName').value = ''; $('docProvider').value = '';
    $('docAmount').value = ''; $('docDue').value = '';
    $('docFile').value = '';
    $('docDropTitle').textContent = 'בחירת קובץ';
    setErr($('docErr'), '');

    const box = $('docKinds');
    box.textContent = '';
    for (const k of DOC_KINDS) {
      const b = el('button', 'chip', `${k.icon} ${k.label}`);
      b.type = 'button';
      b.setAttribute('aria-pressed', String(k.key === docKind));
      b.addEventListener('click', () => {
        docKind = k.key;
        for (const o of box.children) o.setAttribute('aria-pressed', 'false');
        b.setAttribute('aria-pressed', 'true');
        if (!$('docName').value) $('docName').value = k.label;
      });
      box.append(b);
    }
    openSheet($('docSheet'));
  }

  async function saveDoc() {
    setErr($('docErr'), '');
    const title = $('docName').value.trim();
    if (!title) { setErr($('docErr'), 'צריך שם למסמך.'); $('docName').focus(); return; }
    if (docFile && docFile.size > 15 * 1024 * 1024) {
      setErr($('docErr'), 'הקובץ גדול מ־15 מגה.'); return;
    }

    const btn = $('docSave');
    btn.disabled = true; btn.textContent = 'שומר...';
    try {
      let path = null;
      if (docFile) {
        /* ‏התיקייה הראשונה בנתיב היא מזהה משק הבית, וזאת גם
           ההרשאה: המדיניות על הקבצים נגזרת ממנה. */
        const safe = docFile.name.replace(/[^\w.֐-׿-]+/g, '_').slice(-60);
        path = `${S.hh}/${Date.now()}-${safe}`;
        const { error } = await sb.storage.from('docs')
          .upload(path, docFile, { contentType: docFile.type || 'application/octet-stream', upsert: false });
        if (error) throw error;
      }

      const { error } = await sb.from('documents').insert({
        household_id: S.hh,
        kind: docKind,
        title: title.slice(0, 160),
        provider: $('docProvider').value.trim().slice(0, 80) || null,
        amount_agorot: toAgorot($('docAmount').value) || null,
        due_on: $('docDue').value || null,
        period: $('docDue').value ? $('docDue').value.slice(0, 8) + '01' : null,
        storage_path: path,
        mime: docFile ? docFile.type : null,
        size_bytes: docFile ? docFile.size : null,
        created_by: S.user.id
      });
      if (error) throw error;

      closeSheet();
      toast('המסמך נשמר.');
      renderDocs();
    } catch (err) {
      setErr($('docErr'), A.human(err));
    } finally {
      btn.disabled = false; btn.textContent = 'שמירה';
    }
  }

  function openDocView(d) {
    docOpenRow = d;
    const k = DOC_KINDS.find(x => x.key === d.kind) || DOC_KINDS[3];
    $('docViewTitle').textContent = d.title;
    const bits = [k.label];
    if (d.provider) bits.push(d.provider);
    if (d.amount_agorot) bits.push(fmt(Number(d.amount_agorot)));
    if (d.due_on) bits.push(new Date(d.due_on + 'T12:00:00').toLocaleDateString('he-IL'));
    $('docViewSub').textContent = bits.join(' · ') + '.';
    $('docOpen').disabled = !d.storage_path;
    /* ‏הפיכה להוצאה היא רק לחשבון שיש בו סכום ושעוד לא הפך
       לתנועה. בלי זה אותו חשבון נספר פעמיים. */
    $('docToTx').classList.toggle('hidden', !(d.amount_agorot && !d.transaction_id));
    openSheet($('docView'));
  }

  async function openDocFile() {
    const d = docOpenRow;
    if (!d || !d.storage_path) return;
    const { data, error } = await sb.storage.from('docs').createSignedUrl(d.storage_path, 60);
    if (error || !data) { toast(A.human(error)); return; }
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  async function docToTx() {
    const d = docOpenRow;
    closeSheet();
    if (!d || !d.amount_agorot) return;
    const cat = catIdOf(P.guessCategory([d.title, d.provider].filter(Boolean).join(' '))) || catIdOf('other');
    const on = d.due_on || d.period || isoDate(new Date());
    const { data, error } = await sb.from('transactions').insert({
      household_id: S.hh, occurred_on: on,
      amount_agorot: Number(d.amount_agorot), direction: 'out',
      category_id: cat, description: [d.provider, d.title].filter(Boolean)[0] || d.title,
      source: 'import', created_by: S.user.id
    }).select().single();
    if (error) { toast(A.human(error)); return; }
    await sb.from('documents').update({ transaction_id: data.id }).eq('id', d.id);
    toast('נוסף כהוצאה.');
    await A.reload();
    renderDocs();
  }

  async function deleteDoc() {
    const d = docOpenRow;
    closeSheet();
    if (!d) return;
    if (d.storage_path) await sb.storage.from('docs').remove([d.storage_path]);
    const { error } = await sb.from('documents').delete().eq('id', d.id);
    if (error) { toast(A.human(error)); return; }
    toast('נמחק.');
    renderDocs();
  }

  /* ─────────────────────────────────── חיווט ── */

  $('impBank').addEventListener('click', () => setKind('bank'));
  $('impCredit').addEventListener('click', () => setKind('credit'));
  $('impFile').addEventListener('change', e => onFile(e.target.files[0]));
  $('impCancel').addEventListener('click', resetImport);
  $('impGo').addEventListener('click', doImport);
  $('impAll').addEventListener('click', () => { for (const r of impRows) r.take = true; renderReview(); });
  $('impNone').addEventListener('click', () => { for (const r of impRows) r.take = false; renderReview(); });
  $('impNoDup').addEventListener('click', () => { for (const r of impRows) r.take = !r.dup; renderReview(); });

  const drop = $('impDrop');
  for (const ev of ['dragenter', 'dragover']) drop.addEventListener(ev, e => {
    e.preventDefault(); drop.classList.add('over');
  });
  for (const ev of ['dragleave', 'drop']) drop.addEventListener(ev, e => {
    e.preventDefault(); drop.classList.remove('over');
  });
  drop.addEventListener('drop', e => {
    const f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
    if (f) onFile(f);
  });

  $('docFile').addEventListener('change', e => {
    docFile = e.target.files[0] || null;
    $('docDropTitle').textContent = docFile ? docFile.name : 'בחירת קובץ';
    if (docFile && !$('docName').value) $('docName').value = docFile.name.replace(/\.[^.]+$/, '').slice(0, 160);
  });
  $('docAdd').addEventListener('click', openDocSheet);
  $('docCancel').addEventListener('click', closeSheet);
  $('docSave').addEventListener('click', saveDoc);
  $('docClose').addEventListener('click', closeSheet);
  $('docOpen').addEventListener('click', openDocFile);
  $('docToTx').addEventListener('click', docToTx);
  $('docDelete').addEventListener('click', deleteDoc);

  return {
    openImport() { resetImport(); },
    openDocs() { renderDocs(); }
  };
}
