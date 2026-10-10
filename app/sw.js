/* ‏עובד השירות של "כמה יש לי".
   ═══════════════════════════════════════════════════════════════

   ‏מה הוא עושה: מאפשר לאפליקציה להיפתח בלי רשת. היא מותקנת על
   ‏מסך הבית ונראית כמו אפליקציה, ועד היום פתיחה בלי קליטה הראתה
   ‏מסך שבור · זה ההבדל הגדול ביותר בין "אתר" ל"אפליקציה" בתחושה
   ‏של מי שמשתמש.

   ‏מה הוא לא עושה: הוא לא שומר שום נתון פיננסי. הוא נוגע רק
   ‏בקבצי המעטפת · HTML, CSS, JS והספריות. כל בקשה אל מסד הנתונים
   ‏עוברת דרכו בלי שייגע בה.

   ─────────────────────────────────────────────────────────────
   ‏האסטרטגיה: רשת קודם, מטמון כגיבוי.

   ‏קאש קודם היה מהיר יותר, והוא גם הדרך הקלה ביותר להקפיא גרסה
   ‏ישנה אצל אנשים שכבר מותקנת להם האפליקציה · בלי דרך לתקן את
   ‏זה מרחוק. באפליקציה פיננסית שמעדכנים בה חוקי חישוב, זה סיכון
   ‏שאינו שווה את מאית השנייה.

   ‏לכן: מחובר לרשת · תמיד הגרסה החיה. בלי רשת · מה שנשמר בפעם
   ‏האחרונה. גרסה חדשה תופסת מיד, בלי לחכות לסגירת הלשוניות. */

const CACHE = 'kyl-shell-v1';

/* ‏מה נשמר מראש. רק מה שבלעדיו המסך אינו מסך. */
const SHELL = [
  './',
  './index.html',
  './app.css',
  './app.js',
  './import.js',
  './parse.js',
  './app.webmanifest',
  '../vendor/supabase.js'
];

self.addEventListener('install', e => {
  /* ‏קובץ אחד שנופל לא מפיל את ההתקנה · addAll הוא הכל או כלום,
     ‏ואז גרסה אחת חסרה משאירה את המשתמש בלי מטמון בכלל. */
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await Promise.all(SHELL.map(u => c.add(u).catch(() => {})));
    self.skipWaiting();
  })());
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;

  /* ‏רק GET, ורק מהמקור שלנו. כל מה שהולך אל Supabase · נתונים,
     ‏התחברות, מסמכים · עובר ישר ואינו נשמר לעולם. */
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  e.respondWith((async () => {
    try {
      const fresh = await fetch(req);
      /* ‏רק תשובות תקינות נשמרות. שגיאת שרת שנשמרת היא שגיאה
         ‏שתוגש שוב ושוב גם אחרי שהיא תוקנה. */
      if (fresh && fresh.ok && fresh.type === 'basic') {
        const c = await caches.open(CACHE);
        c.put(req, fresh.clone());
      }
      return fresh;
    } catch {
      const hit = await caches.match(req);
      if (hit) return hit;
      /* ‏ניווט בלי רשת ובלי התאמה · מגישים את המעטפת, והאפליקציה
         ‏עצמה תגיד שאין חיבור בשפה שלה. */
      if (req.mode === 'navigate') {
        const shell = await caches.match('./index.html');
        if (shell) return shell;
      }
      throw new Error('offline');
    }
  })());
});
