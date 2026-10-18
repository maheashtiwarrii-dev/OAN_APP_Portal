--------------------------------------------------------------------------------
-- 112 Wellbeing activities on the volunteering page (Q43, 18 Oct 2026). Re-runnable.
--   Members enrol for marathon events, fitness sessions, yoga classes and meditation classes the same way they
--   sign up for social-cause drives (capacity, waitlist, attendance and hours). Causes now carry a category so the
--   page shows two groups: social causes and wellbeing.
--------------------------------------------------------------------------------
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_tab_columns where table_name = 'OAN_VOLUNTEER_CAUSES' and column_name = 'CATEGORY';
  if l_cnt = 0 then
    execute immediate q'[alter table oan_volunteer_causes add (category varchar2(12 char) default 'CAUSE' not null
                         constraint oan_vc_cat_ck check (category in ('CAUSE','WELLBEING')))]';
  end if;
end;
/

merge into oan_volunteer_causes c
using (select 'MARATHON' code, 'Marathon events' label,
              'Run, walk or volunteer at marathons and charity runs; group training runs before race day.' d, 'fa-trophy' i, 60 o from dual union all
       select 'FITNESS', 'Fitness sessions',
              'Group workouts, walking clubs and outdoor fitness sessions for all levels.', 'fa-heartbeat', 70 from dual union all
       select 'YOGA', 'Yoga classes',
              'Beginner and regular yoga classes led by experienced members and teachers.', 'fa-leaf', 80 from dual union all
       select 'MEDITATION', 'Meditation classes',
              'Guided meditation, breathing and mindfulness sessions, in person or online.', 'fa-moon-o', 90 from dual) s
   on (c.code = s.code)
 when matched then update set c.label = s.label, c.description = s.d, c.icon = s.i, c.sort_order = s.o, c.category = 'WELLBEING'
 when not matched then insert (code, label, description, icon, sort_order, category) values (s.code, s.label, s.d, s.i, s.o, 'WELLBEING');

merge into oan_pd_columns p
using (select 'CATEGORY' column_name from dual) s
   on (p.table_name = 'OAN_VOLUNTEER_CAUSES' and p.column_name = s.column_name)
 when not matched then insert (table_name, column_name, classification, export_flag)
                       values ('OAN_VOLUNTEER_CAUSES', s.column_name, 'NON_PERSONAL', 'N');

-- J-22 keywords and label cover the wellbeing activities too
update oan_lu_codes
   set label = 'Volunteer for a social cause or join a marathon, fitness, yoga or meditation group in my city',
       description = 'volunteer,volunteering,social cause,ngo,charity,educate,nutrition,medical camp,dental,tree,plantation,mother,child welfare,'
                     || 'marathon,run,running,fitness,workout,yoga,meditation,mindfulness,wellbeing'
 where code_type = 'INTENT' and code = 'VOLUNTEERING';
commit;
