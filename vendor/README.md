# ‏הספריות, אצלנו ולא ב-CDN

‏בשורש ולא בתוך app, כי גם הדשבורד ב-admin טוען את supabase-js,
‏והוא הדף שמציג את כל הלידים · שם זה חשוב אפילו יותר.

‏שלושתן נטענו קודם מ-cdn.jsdelivr.net בזמן ריצה. ספרייה שנטענת
מרשת זרה רצה אצל המשתמש עם ההרשאות שלו ורואה כל מה שהוא רואה,
ולכן יום רע אחד אצל ה-CDN הוא יום רע אצלנו. לייבוא ESM אין SRI,
אז הדרך היחידה לנעול גרסה היא להחזיק את הקובץ.

| קובץ | מקור | גרסה |
|---|---|---|
| `supabase.js` | `@supabase/supabase-js` | 2.117.3 |
| `xlsx.js` | `xlsx` (SheetJS) | 0.18.5 |
| `pdf.js` | `pdfjs-dist/build/pdf.min.mjs` | 4.0.379 |
| `pdf.worker.js` | `pdfjs-dist/build/pdf.worker.min.mjs` | 4.0.379 |

‏שתי הראשונות נארזו מחדש ל-ESM לדפדפן עם esbuild, שתי האחרונות
הן הקבצים של החבילה כמות שהם.

## ‏לעדכן גרסה

```sh
npm i @supabase/supabase-js@2 xlsx@0.18.5 pdfjs-dist@4.0.379 esbuild
echo "export { createClient } from '@supabase/supabase-js';" > sb-entry.js
printf "import * as X from 'xlsx';\nexport const read = X.read;\nexport const utils = X.utils;\nexport default X;\n" > xlsx-entry.js
npx esbuild sb-entry.js   --bundle --format=esm --platform=browser --minify --target=es2020 --legal-comments=none --outfile=supabase.js
npx esbuild xlsx-entry.js --bundle --format=esm --platform=browser --minify --target=es2020 --legal-comments=none --define:global=globalThis --outfile=xlsx.js
cp node_modules/pdfjs-dist/build/pdf.min.mjs        pdf.js
cp node_modules/pdfjs-dist/build/pdf.worker.min.mjs pdf.worker.js
```

‏אחרי עדכון · להריץ את חבילות הבדיקה, ובעיקר את ייבוא הקבצים.
