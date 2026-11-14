-- דף הקישורים · הוספת השאלון כיעד רביעי
--
-- בדף הקישורים נוסף כרטיס לשאלון, והוא יושב ראשון: הביו באינסטגרם
-- מבטיח "שתי דקות ותדעו איפה אתם עומדים", וזה מה שצריך לחכות שם.
--
-- המגבלה על העמודה ועל הפונקציה הכירה ארבעה יעדים בלבד, ולכן כל
-- לחיצה על השאלון הייתה נדחית עם reason=target ולא נספרת. הכרטיס
-- עצמו עובד גם בלי זה, כי הניווט אינו תלוי במדידה, אבל בלי ההרצה
-- הזאת הלחיצות פשוט אינן מגיעות לדשבורד.
--
-- להריץ בעורך ה-SQL של סופאבייס. הרצה חוזרת אינה מזיקה.

alter table public.links_clicks
  drop constraint if exists links_clicks_target_ck;

alter table public.links_clicks
  add constraint links_clicks_target_ck
  check (target in ('open','whatsapp','landing','calculator','quiz'));

create or replace function public.links_click(
  p_target text,
  p_visit  uuid default null,
  p_ref    text default null,
  p_device text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_hour integer;
begin
  if p_target is null
     or p_target not in ('open','whatsapp','landing','calculator','quiz') then
    return jsonb_build_object('ok', false, 'reason', 'target');
  end if;

  -- תקרה על הטבלה עצמה, כדי שסקריפט לא ימלא אותה בלחיצות.
  select count(*) into v_hour from public.links_clicks
   where created_at > now() - interval '1 hour';
  if v_hour >= 1000 then
    return jsonb_build_object('ok', false, 'reason', 'busy');
  end if;

  insert into public.links_clicks (target, visit, ref, device)
  values (p_target, p_visit,
          nullif(left(btrim(coalesce(p_ref, '')), 120), ''),
          case when p_device in ('mobile','desktop') then p_device end)
  on conflict do nothing;

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.links_click(text,uuid,text,text) from public;
grant execute on function public.links_click(text,uuid,text,text) to anon, authenticated;
