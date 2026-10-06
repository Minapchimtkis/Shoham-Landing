-- ═══════════════════════════════════════════════════════════════
--  אפליקציית התקציב, שלב שלישי: המסמכים
-- ═══════════════════════════════════════════════════════════════
--
-- ‏לא כל קובץ שאדם מעלה הוא רשימת תנועות.
--
--   ‏דף עו"ש ופירוט אשראי הם רשימות. הם נקראים, מוצגים לאישור,
--   והופכים לשורות ב-transactions. הם לא נשמרים כאן.
--
--   ‏דוח יתרות וסילוקין וחשבון של חשמל הם מסמכים. יש בהם מספר
--   אחד או שניים שחשובים, והשאר הוא נייר שרוצים שיהיה שמור.
--   הם נשמרים כאן, עם מה שחולץ מהם.
--
-- ‏הקובץ עצמו יושב ב-Storage ולא בטבלה. דוח סילוקין הוא מאות
-- קילובייטים, וטבלה שמחזיקה אותם הופכת כל שאילתה עליה לאיטית
-- גם כשלא ביקשו את הקובץ.
--
-- להרצה בעורך ה-SQL של Supabase, אחרי שני הקבצים שלפניו.
-- הרצה חוזרת אינה מזיקה.

create table if not exists public.documents(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,

  -- ‏loan הוא דוח יתרות וסילוקין, bill הוא חשבון של ספק,
  -- statement הוא דף שנשמר כאסמכתא, other הוא כל השאר.
  kind         text not null default 'other'
               check (kind in ('loan','bill','statement','other')),

  title        text not null,
  provider     text,                      -- חברת חשמל, מזרחי טפחות
  period       date,                      -- לאיזה חודש המסמך שייך

  -- ‏שני המספרים שנשלפים כמעט מכל מסמך: כמה, ועד מתי. השאר
  -- יושב ב-data, כי מה שיש בדוח סילוקין אינו מה שיש בחשבון מים
  -- ועמודה לכל שדה אפשרי הייתה טבלה עם ארבעים עמודות ריקות.
  amount_agorot bigint check (amount_agorot is null or amount_agorot >= 0),
  due_on       date,
  data         jsonb not null default '{}'::jsonb,

  -- ‏הנתיב ב-Storage. תמיד מתחיל במזהה משק הבית, כי מדיניות
  -- הגישה לקבצים נגזרת מהתיקייה הראשונה בנתיב.
  storage_path text,
  mime         text,
  size_bytes   integer check (size_bytes is null or size_bytes >= 0),

  -- ‏כשחשבון הופך להוצאה, הקשר נשמר. בלעדיו אותו חשבון נכנס
  -- פעמיים: פעם מהקובץ ופעם מדף העו"ש.
  transaction_id uuid references public.transactions(id) on delete set null,

  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),

  constraint documents_title_len check (length(btrim(title)) between 1 and 160),
  constraint documents_provider_len check (provider is null or length(provider) <= 80)
);

create index if not exists documents_hh_idx on public.documents (household_id, created_at desc);
create index if not exists documents_kind_idx on public.documents (household_id, kind, period desc);

alter table public.documents enable row level security;
drop policy if exists doc_rw on public.documents;
create policy doc_rw on public.documents for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.documents from anon;
grant select, insert, update, delete on table public.documents to authenticated;

-- ────────────────────────────────────────── מקור הייבוא ──
-- ‏כדי שאפשר יהיה לבטל ייבוא שלם אחרי שהתברר שהוא היה הקובץ
-- הלא נכון, ולדעת מה כבר נקרא כדי לא לקרוא אותו פעמיים.
create table if not exists public.imports(
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  source       text not null default 'file'
               check (source in ('file','manual')),
  kind         text not null default 'bank'
               check (kind in ('bank','credit','other')),
  file_name    text,
  -- ‏טביעת אצבע של הקובץ. אותו קובץ שמועלה שוב מזוהה לפני
  -- שמציגים למשתמש מאתיים שורות שהוא כבר אישר פעם אחת.
  file_hash    text,
  rows_total   integer not null default 0 check (rows_total >= 0),
  rows_taken   integer not null default 0 check (rows_taken >= 0),
  charged_on   date,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists imports_hh_idx on public.imports (household_id, created_at desc);
create unique index if not exists imports_hash_idx
  on public.imports (household_id, file_hash) where file_hash is not null;

alter table public.imports enable row level security;
drop policy if exists imp_rw on public.imports;
create policy imp_rw on public.imports for all to authenticated
  using (public.is_member(household_id))
  with check (public.is_member(household_id));

revoke all on table public.imports from anon;
grant select, insert, update, delete on table public.imports to authenticated;

-- ‏כל תנועה יודעת מאיזה ייבוא היא הגיעה. מחיקת הייבוא משאירה
-- את התנועות ומנתקת אותן, כי מחיקה של היסטוריה כלכלית בגלל
-- ניקיון של רשומת ייבוא היא לא מה שמישהו התכוון אליו.
alter table public.transactions
  add column if not exists import_id uuid references public.imports(id) on delete set null;

create index if not exists tx_import_idx on public.transactions (import_id)
  where import_id is not null;

-- ───────────────────────────────────── הקבצים עצמם ──
-- ‏דלי פרטי. בלי הדלי הזה אין איפה לשמור את הקובץ, ואם הוא
-- נוצר ציבורי, כל מי שמנחש נתיב מוריד דוח סילוקין של מישהו.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('docs', 'docs', false, 15728640,
        array['application/pdf','image/jpeg','image/png','image/webp',
              'text/csv','application/vnd.ms-excel',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ‏התיקייה הראשונה בנתיב היא מזהה משק הבית, ולכן היא גם
-- ההרשאה. קובץ בנתיב של משק בית אחר אינו נראה ואינו נכתב.
drop policy if exists docs_read   on storage.objects;
drop policy if exists docs_write  on storage.objects;
drop policy if exists docs_update on storage.objects;
drop policy if exists docs_delete on storage.objects;

create policy docs_read on storage.objects for select to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_write on storage.objects for insert to authenticated
  with check (bucket_id = 'docs'
              and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_update on storage.objects for update to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid))
  with check (bucket_id = 'docs'
              and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));

create policy docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'docs'
         and public.is_member(nullif((storage.foldername(name))[1], '')::uuid));
