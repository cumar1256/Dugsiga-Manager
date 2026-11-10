-- Additive upgrade for an existing Dugsiga Manager Supabase project.
-- Apply schema.sql first. Existing students, attendance, classes, and payment
-- rows are kept; all new financial and academic records are additive.

create table if not exists public.education_levels (
  id text primary key check (id in ('primary','secondary')),
  name text not null,
  name_so text not null
);
insert into public.education_levels(id,name,name_so) values
  ('primary','Primary School','Dugsi Hoose'),('secondary','Secondary School','Dugsi Sare')
on conflict (id) do nothing;

alter table public.classes add column if not exists education_level_id text references public.education_levels(id);
alter table public.classes add column if not exists shift text not null default 'Morning';
alter table public.classes add column if not exists capacity integer not null default 40 check (capacity > 0);
alter table public.classes add column if not exists status text not null default 'Active' check (status in ('Active','Inactive'));
update public.classes set education_level_id=case when grade ~* '^(form|f[1-4])' or grade ~* '^grade ([9]|1[0-2])$' then 'secondary' else 'primary' end where education_level_id is null;
alter table public.classes alter column education_level_id set not null;

alter table public.students add column if not exists registration_date date not null default current_date;
alter table public.students add column if not exists attendance_start_date date not null default current_date;
alter table public.students add column if not exists monthly_fee numeric(12,2) not null default 0 check (monthly_fee >= 0);
alter table public.students add column if not exists shift text not null default 'Morning';
alter table public.students add column if not exists enrollment_status text not null default 'Active' check (enrollment_status in ('Active','Inactive','Graduated','Completed Primary'));
alter table public.students add column if not exists education_level_id text references public.education_levels(id);
alter table public.students add column if not exists current_class_id uuid;
alter table public.students add column if not exists graduated_at date;
alter table public.students add column if not exists archived_at timestamptz;
alter table public.students add column if not exists archived_enrollment_status text;
update public.students set registration_date=enrollment_date where registration_date is distinct from enrollment_date;
update public.students set attendance_start_date=registration_date where attendance_start_date is distinct from registration_date;
update public.students set enrollment_status=case when is_active then 'Active' else 'Inactive' end where enrollment_status is null or enrollment_status='Active' and not is_active;
update public.students set enrollment_status=case when is_active then 'Active' else 'Inactive' end;
update public.students set enrollment_status=case when is_active then 'Active' else 'Inactive' end;
update public.students s set education_level_id=c.education_level_id,current_class_id=c.id from public.class_students cs join public.classes c on c.id=cs.class_id where cs.student_id=s.id and cs.ended_at is null and s.current_class_id is null;
alter table public.students add constraint students_current_class_fk foreign key (current_class_id) references public.classes(id) on delete set null;

create table if not exists public.teachers (
  user_id uuid primary key references public.user_profiles(user_id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  teacher_number text not null,
  phone text not null default '',
  email text not null default '',
  education_level_id text not null references public.education_levels(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id,teacher_number),
  unique (user_id,school_id)
);

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  education_level_id text not null references public.education_levels(id),
  name text not null,
  name_so text not null default '',
  is_active boolean not null default true,
  unique (school_id,education_level_id,name),
  unique (id,school_id)
);
insert into public.subjects(school_id,education_level_id,name,name_so)
select schools.id, catalog.level, catalog.name, catalog.name_so
from public.schools cross join (values
 ('primary','Mathematics','Xisaab'),('primary','Somali Language','Af-Soomaali'),('primary','English Language','Ingiriisi'),('primary','Islamic Studies & Tarbiya','Diin iyo Tarbiya'),('primary','Arabic Language','Carabi'),('primary','Science','Saynis'),('primary','Technology','Teknoolojiyad'),('primary','Social Studies','Cilmiga Bulshada'),
 ('secondary','Mathematics','Xisaab'),('secondary','Somali Language','Af-Soomaali'),('secondary','English Language','Ingiriisi'),('secondary','Physics','Fiisigis'),('secondary','Chemistry','Kiimiko'),('secondary','Biology','Bayooloji'),('secondary','Technology','Teknoolojiyad'),('secondary','History','Taariikh'),('secondary','Islamic Studies & Tarbiya','Diin iyo Tarbiya'),('secondary','Arabic Language','Carabi'),('secondary','Geography','Juqraafi'),('secondary','Business Studies','Ganacsi')
) as catalog(level,name,name_so)
on conflict (school_id,education_level_id,name) do nothing;

create table if not exists public.teacher_class_assignments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  teacher_id uuid not null references public.teachers(user_id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  assigned_by uuid not null references public.user_profiles(user_id),
  assigned_at timestamptz not null default now(),
  unique (teacher_id,class_id),
  foreign key (teacher_id,school_id) references public.teachers(user_id,school_id) on delete cascade,
  foreign key (class_id,school_id) references public.classes(id,school_id) on delete cascade
);

create table if not exists public.teacher_subject_assignments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  teacher_id uuid not null references public.teachers(user_id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  class_id uuid references public.classes(id) on delete cascade,
  assigned_by uuid not null references public.user_profiles(user_id),
  unique (teacher_id,subject_id,class_id),
  foreign key (teacher_id,school_id) references public.teachers(user_id,school_id) on delete cascade,
  foreign key (subject_id,school_id) references public.subjects(id,school_id) on delete cascade,
  foreign key (class_id,school_id) references public.classes(id,school_id) on delete cascade
);

create table if not exists public.academic_years (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  start_date date not null,
  end_date date not null,
  is_active boolean not null default false,
  is_closed boolean not null default false,
  check (end_date > start_date),
  unique (school_id,name)
);
create unique index if not exists one_active_academic_year_per_school on public.academic_years(school_id) where is_active;
alter table public.classes add column if not exists academic_year_id uuid references public.academic_years(id);
with normalized_years as (
  select distinct school_id,regexp_replace(academic_year,'[^0-9]','/','g') as normalized_name
  from public.classes where academic_year ~ '^[0-9]{4}[^0-9][0-9]{4}$'
)
insert into public.academic_years(school_id,name,start_date,end_date,is_active)
select school_id,normalized_name,
  make_date(split_part(normalized_name,'/',1)::integer,9,1),
  make_date(split_part(normalized_name,'/',1)::integer+1,6,30),
  current_date between make_date(split_part(normalized_name,'/',1)::integer,9,1) and make_date(split_part(normalized_name,'/',1)::integer+1,6,30)
from normalized_years
on conflict (school_id,name) do nothing;
update public.classes c set academic_year_id=y.id from public.academic_years y where y.school_id=c.school_id and y.name=regexp_replace(c.academic_year,'[^0-9]','/','g') and c.academic_year_id is null;
create table if not exists public.fee_settings (
  school_id uuid primary key references public.schools(id) on delete cascade,
  default_monthly_fee numeric(12,2) not null default 0 check (default_monthly_fee >= 0),
  due_day integer not null default 10 check (due_day between 1 and 28),
  updated_at timestamptz not null default now()
);

create table if not exists public.fee_records (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete restrict,
  billing_month smallint not null check (billing_month between 1 and 12),
  billing_year integer not null check (billing_year between 2000 and 2200),
  amount_due numeric(12,2) not null check (amount_due >= 0),
  amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0 and amount_paid <= amount_due),
  outstanding_balance numeric(12,2) generated always as (amount_due - amount_paid) stored,
  payment_status text not null default 'Unpaid' check (payment_status in ('Paid','Unpaid','Partial Payment','Overdue')),
  due_date date not null,
  created_at timestamptz not null default now(),
  academic_year_id uuid references public.academic_years(id),
  unique (student_id,billing_year,billing_month),
  unique (id,student_id,school_id),
  foreign key (student_id,school_id) references public.students(id,school_id) on delete restrict
);

create table if not exists public.fee_payments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete restrict,
  fee_record_id uuid not null references public.fee_records(id) on delete restrict,
  amount_paid numeric(12,2) not null check (amount_paid > 0),
  payment_date timestamptz not null default now(),
  payment_method text not null,
  recorded_by uuid not null references public.user_profiles(user_id),
  notes text not null default '',
  receipt_number text not null,
  created_at timestamptz not null default now(),
  unique (school_id,receipt_number),
  foreign key (student_id,school_id) references public.students(id,school_id) on delete restrict,
  foreign key (fee_record_id,student_id,school_id) references public.fee_records(id,student_id,school_id) on delete restrict
);

create table if not exists public.student_academic_history (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete restrict,
  academic_year_id uuid references public.academic_years(id),
  class_id uuid references public.classes(id) on delete restrict,
  class_name_snapshot text not null,
  status text not null check (status in ('Current','Completed','Promoted','Repeating','Graduated','Completed Primary','Transferred')),
  recorded_at timestamptz not null default now(),
  unique (student_id,academic_year_id,class_id)
);

create table if not exists public.student_promotions (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete restrict,
  source_year_id uuid not null references public.academic_years(id),
  target_year_id uuid not null references public.academic_years(id),
  from_class_id uuid not null references public.classes(id) on delete restrict,
  to_class_id uuid references public.classes(id) on delete restrict,
  result text not null check (result in ('Promoted','Repeating','Graduated','Completed Primary')),
  promoted_at timestamptz not null default now(),
  unique (student_id,source_year_id)
);

alter table public.attendance add column if not exists teacher_id uuid references public.teachers(user_id);
alter table public.attendance drop constraint if exists attendance_status_check;
alter table public.attendance add constraint attendance_status_check check (status in ('Present','Absent','Late','Excused'));
create unique index if not exists attendance_unique_class_student_date on public.attendance(student_id,class_id,attendance_date);
insert into public.teachers(user_id,school_id,teacher_number,phone,email,education_level_id,is_active)
select p.user_id,p.school_id,'T-'||upper(substr(replace(p.user_id::text,'-',''),1,8)),'','',
  coalesce((select c.education_level_id from public.classes c where c.teacher_id=p.user_id order by c.created_at limit 1),'primary'),p.is_active
from public.user_profiles p where p.role='teacher'
on conflict (user_id) do nothing;
insert into public.teacher_class_assignments(school_id,teacher_id,class_id,assigned_by)
select c.school_id,c.teacher_id,c.id,c.teacher_id from public.classes c join public.teachers t on t.user_id=c.teacher_id
where c.teacher_id is not null and t.education_level_id=c.education_level_id
on conflict (teacher_id,class_id) do nothing;
update public.attendance a set teacher_id=a.recorded_by where exists(select 1 from public.teachers t where t.user_id=a.recorded_by) and a.teacher_id is null;
insert into public.student_academic_history(school_id,student_id,academic_year_id,class_id,class_name_snapshot,status)
select cs.school_id,cs.student_id,c.academic_year_id,c.id,c.name,'Current' from public.class_students cs join public.classes c on c.id=cs.class_id
where cs.ended_at is null and c.academic_year_id is not null
on conflict (student_id,academic_year_id,class_id) do nothing;

create or replace function public.is_assigned_teacher(target_class uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.teacher_class_assignments a
    join public.teachers t on t.user_id=a.teacher_id and t.is_active
    join public.user_profiles p on p.user_id=a.teacher_id and p.is_active and p.role='teacher'
    where a.class_id=target_class and a.teacher_id=auth.uid()
  )
$$;

create or replace function public.validate_teacher_assignment()
returns trigger language plpgsql security definer set search_path=public
as $$
declare class_level text; teacher_level text; teacher_active boolean;
begin
  select education_level_id into class_level from public.classes where id=new.class_id and school_id=new.school_id;
  select education_level_id,is_active into teacher_level,teacher_active from public.teachers where user_id=new.teacher_id and school_id=new.school_id;
  if class_level is null or teacher_level is null or not teacher_active or class_level<>teacher_level then
    raise exception 'Teacher and class must be active and belong to the same education level and school';
  end if;
  return new;
end;
$$;
drop trigger if exists validate_teacher_class_before_save on public.teacher_class_assignments;
create trigger validate_teacher_class_before_save before insert or update on public.teacher_class_assignments
  for each row execute function public.validate_teacher_assignment();

create or replace function public.validate_teacher_subject_assignment()
returns trigger language plpgsql security definer set search_path=public
as $$
declare subject_level text; teacher_level text; assigned_class boolean;
begin
  select education_level_id into subject_level from public.subjects where id=new.subject_id and school_id=new.school_id;
  select education_level_id into teacher_level from public.teachers where user_id=new.teacher_id and school_id=new.school_id;
  if subject_level is null or teacher_level is null or subject_level<>teacher_level then
    raise exception 'Subject and teacher education levels must match';
  end if;
  if new.class_id is not null then
    select exists(select 1 from public.teacher_class_assignments where teacher_id=new.teacher_id and class_id=new.class_id and school_id=new.school_id) into assigned_class;
    if not assigned_class then raise exception 'Teacher must be assigned to class before class subjects'; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists validate_teacher_subject_before_save on public.teacher_subject_assignments;
create trigger validate_teacher_subject_before_save before insert or update on public.teacher_subject_assignments
  for each row execute function public.validate_teacher_subject_assignment();

create or replace function public.validate_attendance_eligibility()
returns trigger language plpgsql security definer set search_path=public
as $$
declare student_registration date;
begin
  select registration_date into student_registration from public.students where id=new.student_id and school_id=new.school_id;
  if student_registration is null then raise exception 'Student does not belong to this school'; end if;
  if student_registration > new.attendance_date then raise exception 'Attendance date cannot be before student registration'; end if;
  if not exists(select 1 from public.class_students cs where cs.class_id=new.class_id and cs.student_id=new.student_id and cs.school_id=new.school_id and cs.ended_at is null) then raise exception 'Student is not an active member of this class'; end if;
  if new.recorded_by<>auth.uid() then raise exception 'recorded_by must match the signed-in user'; end if;
  if exists(select 1 from public.teachers t where t.user_id=auth.uid()) and not public.is_assigned_teacher(new.class_id) then raise exception 'Teacher is not assigned to this class'; end if;
  if exists(select 1 from public.teachers t where t.user_id=auth.uid()) then new.teacher_id:=auth.uid(); end if;
  return new;
end;
$$;
drop trigger if exists attendance_eligibility_before_save on public.attendance;
create trigger attendance_eligibility_before_save before insert or update on public.attendance
  for each row execute function public.validate_attendance_eligibility();

create or replace function public.update_fee_status()
returns trigger language plpgsql set search_path=public
as $$
begin
  if new.amount_paid >= new.amount_due and new.amount_due > 0 then new.payment_status:='Paid';
  elsif new.amount_paid > 0 then new.payment_status:='Partial Payment';
  elsif new.due_date < current_date then new.payment_status:='Overdue';
  else new.payment_status:='Unpaid'; end if;
  return new;
end;
$$;
drop trigger if exists fee_status_before_save on public.fee_records;
create trigger fee_status_before_save before insert or update of amount_due,amount_paid,due_date on public.fee_records
  for each row execute function public.update_fee_status();

create or replace function public.record_fee_payment(
  p_fee_id uuid,p_amount numeric,p_method text,p_notes text default ''
) returns public.fee_payments language plpgsql security definer set search_path=public,auth
as $$
declare f public.fee_records; payment public.fee_payments; receipt text;
begin
  select * into f from public.fee_records where id=p_fee_id for update;
  if not found then raise exception 'Fee record not found'; end if;
  if not public.is_school_admin(f.school_id) then raise exception 'Only an authorized school administrator may record fees'; end if;
  if p_amount<=0 or p_amount>f.outstanding_balance then raise exception 'Payment must be greater than zero and cannot exceed the outstanding balance'; end if;
  receipt:='RCP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  insert into public.fee_payments(school_id,student_id,fee_record_id,amount_paid,payment_method,recorded_by,notes,receipt_number)
  values(f.school_id,f.student_id,f.id,p_amount,p_method,auth.uid(),coalesce(p_notes,''),receipt) returning * into payment;
  update public.fee_records set amount_paid=amount_paid+p_amount where id=f.id;
  return payment;
end;
$$;

create or replace function public.generate_monthly_fee_records(target_month date default date_trunc('month',current_date)::date)
returns integer language plpgsql security definer set search_path=public
as $$
declare school record; month_start date; added integer:=0; affected integer:=0; student record;
begin
  for school in select s.id,coalesce(fs.default_monthly_fee,0) as default_fee,coalesce(fs.due_day,10) as due_day from public.schools s left join public.fee_settings fs on fs.school_id=s.id loop
    for student in select st.id,st.registration_date,coalesce(nullif(st.monthly_fee,0),school.default_fee) as monthly_fee
      from public.students st where st.school_id=school.id and st.is_active and st.enrollment_status='Active' loop
      month_start:=date_trunc('month',student.registration_date)::date;
      while month_start<=date_trunc('month',target_month)::date loop
        insert into public.fee_records(school_id,student_id,billing_month,billing_year,amount_due,due_date,academic_year_id)
        select school.id,student.id,extract(month from month_start)::smallint,extract(year from month_start)::integer,
          student.monthly_fee,greatest(make_date(extract(year from month_start)::integer,extract(month from month_start)::integer,least(school.due_day,28)),student.registration_date),
          (select ay.id from public.academic_years ay where ay.school_id=school.id and month_start between ay.start_date and ay.end_date limit 1)
        where month_start + interval '1 month - 1 day' >= student.registration_date
        on conflict (student_id,billing_year,billing_month) do nothing;
        get diagnostics affected = row_count; added:=added+affected;
        month_start:=(month_start+interval '1 month')::date;
      end loop;
    end loop;
  end loop;
  return added;
end;
$$;

create or replace function public.refresh_overdue_fee_status()
returns integer language plpgsql security definer set search_path=public
as $$ declare changed integer; begin
  update public.fee_records set payment_status='Overdue' where amount_paid=0 and due_date<current_date and payment_status='Unpaid';
  get diagnostics changed=row_count; return changed;
end $$;

create or replace function public.apply_student_promotions(
  p_source_year uuid,p_target_year uuid,p_decisions jsonb
) returns jsonb language plpgsql security invoker set search_path=public
as $$
declare decision jsonb; sid uuid; destination uuid; result_status text; from_class public.classes; to_class public.classes; student public.students; done_count integer:=0; repeat_count integer:=0; graduate_count integer:=0; school uuid;
begin
  if jsonb_typeof(p_decisions)<>'array' then raise exception 'Promotion decisions must be a JSON array'; end if;
  select school_id into school from public.academic_years where id=p_source_year;
  if school is null or not public.is_school_admin(school) then raise exception 'Only an administrator can apply promotions'; end if;
  if not exists(select 1 from public.academic_years where id=p_target_year and school_id=school) then raise exception 'Target academic year must belong to the same school'; end if;
  for decision in select value from jsonb_array_elements(p_decisions) loop
    sid:=(decision->>'student_id')::uuid;result_status:=decision->>'result';destination:=nullif(decision->>'destination_class_id','')::uuid;
    select st.* into student from public.students st where st.id=sid and st.school_id=school for update;
    if not found or student.enrollment_status<>'Active' then raise exception 'Student is not eligible for promotion'; end if;
    if exists(select 1 from public.student_promotions sp where sp.student_id=sid and sp.source_year_id=p_source_year) then raise exception 'Student already has a decision for this academic year'; end if;
    select c.* into from_class from public.class_students cs join public.classes c on c.id=cs.class_id where cs.student_id=sid and cs.school_id=school and cs.ended_at is null and c.academic_year_id=p_source_year for update;
    if not found then raise exception 'Student has no active class in the source year'; end if;
    if result_status='Repeating' then
      insert into public.student_promotions(school_id,student_id,source_year_id,target_year_id,from_class_id,result) values(school,sid,p_source_year,p_target_year,from_class.id,'Repeating');
      insert into public.student_academic_history(school_id,student_id,academic_year_id,class_id,class_name_snapshot,status) values(school,sid,p_source_year,from_class.id,from_class.name,'Repeating') on conflict (student_id,academic_year_id,class_id) do update set status='Repeating';
      repeat_count:=repeat_count+1;continue;
    elsif result_status in ('Graduated','Completed Primary') then
      if (result_status='Graduated' and not (from_class.education_level_id='secondary' and from_class.grade ~* '^(form 4|f4)$')) or (result_status='Completed Primary' and not (from_class.education_level_id='primary' and from_class.grade='Grade 8')) then raise exception 'Graduation decision does not match the final class level';end if;
      insert into public.student_promotions(school_id,student_id,source_year_id,target_year_id,from_class_id,result) values(school,sid,p_source_year,p_target_year,from_class.id,result_status);
      insert into public.student_academic_history(school_id,student_id,academic_year_id,class_id,class_name_snapshot,status) values(school,sid,p_source_year,from_class.id,from_class.name,result_status) on conflict (student_id,academic_year_id,class_id) do update set status=excluded.status;
      update public.class_students set ended_at=now() where class_id=from_class.id and student_id=sid and ended_at is null;
      update public.students set current_class_id=null,enrollment_status=result_status,is_active=false,graduated_at=case when result_status='Graduated' then current_date else null end where id=sid;
      graduate_count:=graduate_count+1;continue;
    elsif result_status<>'Promoted' then raise exception 'Unsupported promotion decision';end if;
    if destination is null then raise exception 'Choose a destination class for promoted students';end if;
    select * into to_class from public.classes where id=destination and school_id=school and academic_year_id=p_target_year and education_level_id=from_class.education_level_id and is_active for update;
    if not found then raise exception 'Destination class must be active and at the same education level';end if;
    insert into public.student_promotions(school_id,student_id,source_year_id,target_year_id,from_class_id,to_class_id,result) values(school,sid,p_source_year,p_target_year,from_class.id,to_class.id,'Promoted');
    insert into public.student_academic_history(school_id,student_id,academic_year_id,class_id,class_name_snapshot,status) values(school,sid,p_source_year,from_class.id,from_class.name,'Completed') on conflict (student_id,academic_year_id,class_id) do update set status='Completed';
    update public.class_students set ended_at=now() where class_id=from_class.id and student_id=sid and ended_at is null;
    insert into public.class_students(school_id,class_id,student_id) values(school,to_class.id,sid);
    update public.students set current_class_id=to_class.id,grade=to_class.grade,education_level_id=to_class.education_level_id,shift=to_class.shift where id=sid;
    insert into public.student_academic_history(school_id,student_id,academic_year_id,class_id,class_name_snapshot,status) values(school,sid,p_target_year,to_class.id,to_class.name,'Current');
    done_count:=done_count+1;
  end loop;
  return jsonb_build_object('promoted',done_count,'repeating',repeat_count,'graduated',graduate_count);
end;
$$;

alter table public.education_levels enable row level security;
alter table public.teachers enable row level security;
alter table public.subjects enable row level security;
alter table public.teacher_class_assignments enable row level security;
alter table public.teacher_subject_assignments enable row level security;
alter table public.academic_years enable row level security;
alter table public.fee_settings enable row level security;
alter table public.fee_records enable row level security;
alter table public.fee_payments enable row level security;
alter table public.student_academic_history enable row level security;
alter table public.student_promotions enable row level security;

drop policy if exists "admin manages classes; teacher reads assigned classes" on public.classes;
create policy "admin manages classes; teacher reads assigned classes" on public.classes for select
  using (public.is_school_admin(school_id) or (is_active and exists(select 1 from public.teacher_class_assignments a where a.class_id=classes.id and a.teacher_id=auth.uid())));
drop policy if exists "admin reads all school students; teachers read assigned class roster" on public.students;
create policy "admin reads all school students; teachers read assigned class roster" on public.students for select
  using (public.is_school_admin(school_id) or exists (
    select 1 from public.class_students cs where cs.student_id=students.id and cs.school_id=students.school_id
      and cs.ended_at is null and public.is_assigned_teacher(cs.class_id)
  ));
drop policy if exists "assigned teacher records their class attendance" on public.attendance;
create policy "assigned teacher records their class attendance" on public.attendance for insert
  with check (recorded_by=auth.uid() and public.is_assigned_teacher(class_id)
    and exists(select 1 from public.classes c where c.id=class_id and c.school_id=attendance.school_id)
    and exists(select 1 from public.class_students cs where cs.class_id=attendance.class_id and cs.student_id=attendance.student_id and cs.school_id=attendance.school_id and cs.ended_at is null));

create policy "authenticated users read level catalogue" on public.education_levels for select to authenticated using (true);
create policy "admins manage teachers; teacher reads own row" on public.teachers for select using (user_id=auth.uid() or public.is_school_admin(school_id));
create policy "admins create or update teachers" on public.teachers for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins manage subjects; teachers read assigned subjects" on public.subjects for select using (public.is_school_admin(school_id) or exists(select 1 from public.teacher_subject_assignments tsa where tsa.subject_id=subjects.id and tsa.teacher_id=auth.uid()));
create policy "admins write subjects" on public.subjects for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admin and assigned teacher read class assignments" on public.teacher_class_assignments for select using (public.is_school_admin(school_id) or teacher_id=auth.uid());
create policy "admins manage class assignments" on public.teacher_class_assignments for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admin and assigned teacher read subject assignments" on public.teacher_subject_assignments for select using (public.is_school_admin(school_id) or teacher_id=auth.uid());
create policy "admins manage subject assignments" on public.teacher_subject_assignments for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins manage academic years" on public.academic_years for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins access fee settings" on public.fee_settings for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins access fees" on public.fee_records for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins access payment transactions" on public.fee_payments for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins read academic history" on public.student_academic_history for select using (public.is_school_admin(school_id));
create policy "admins manage academic history" on public.student_academic_history for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins manage promotion history" on public.student_promotions for all using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));

grant select on public.education_levels to authenticated;
grant select,insert,update,delete on public.teachers,public.subjects,public.teacher_class_assignments,public.teacher_subject_assignments,public.academic_years,public.fee_settings,public.fee_records,public.fee_payments,public.student_academic_history,public.student_promotions to authenticated;
revoke execute on function public.generate_monthly_fee_records(date),public.refresh_overdue_fee_status() from public,anon,authenticated;
grant execute on function public.record_fee_payment(uuid,numeric,text,text),public.apply_student_promotions(uuid,uuid,jsonb) to authenticated;

-- Admin-only student lifecycle operations. Each function runs atomically in
-- PostgreSQL; permanent deletion removes only records linked to this student.
create or replace function public.archive_student(p_student_id uuid)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare student public.students; school uuid;
begin
  select * into student from public.students where id=p_student_id for update;
  if not found then return false; end if;
  school:=student.school_id;
  if not public.is_school_admin(school) then raise exception 'Only a school administrator may archive students'; end if;
  update public.students set archived_enrollment_status=coalesce(archived_enrollment_status,enrollment_status),
    archived_at=coalesce(archived_at,now()),is_active=false,enrollment_status='Inactive'
    where id=p_student_id and school_id=school;
  update public.class_students set ended_at=coalesce(ended_at,now()) where student_id=p_student_id and school_id=school and ended_at is null;
  return true;
end;
$$;

create or replace function public.restore_student(p_student_id uuid)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare student public.students; school uuid;
begin
  select * into student from public.students where id=p_student_id for update;
  if not found then return false; end if;
  school:=student.school_id;
  if not public.is_school_admin(school) then raise exception 'Only a school administrator may restore students'; end if;
  if student.archived_at is null then return false; end if;
  update public.students set archived_at=null,is_active=(coalesce(archived_enrollment_status,'Active')='Active'),
    enrollment_status=coalesce(archived_enrollment_status,'Active'),archived_enrollment_status=null
    where id=p_student_id and school_id=school;
  update public.class_students set ended_at=null where student_id=p_student_id and school_id=school
    and class_id=student.current_class_id and ended_at is not null;
  return true;
end;
$$;

create or replace function public.permanently_delete_student(p_student_id uuid)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare school uuid;
begin
  select school_id into school from public.students where id=p_student_id for update;
  if not found then return false; end if;
  if not public.is_school_admin(school) then raise exception 'Only a school administrator may permanently delete students'; end if;
  delete from public.fee_payments where student_id=p_student_id and school_id=school;
  delete from public.fee_records where student_id=p_student_id and school_id=school;
  delete from public.student_promotions where student_id=p_student_id and school_id=school;
  delete from public.student_academic_history where student_id=p_student_id and school_id=school;
  delete from public.attendance where student_id=p_student_id and school_id=school;
  delete from public.class_students where student_id=p_student_id and school_id=school;
  delete from public.students where id=p_student_id and school_id=school;
  return found;
end;
$$;
revoke execute on function public.archive_student(uuid),public.restore_student(uuid),public.permanently_delete_student(uuid) from public,anon;
grant execute on function public.archive_student(uuid),public.restore_student(uuid),public.permanently_delete_student(uuid) to authenticated;

-- Supabase projects with pg_cron enabled can run these as unattended jobs.
create extension if not exists pg_cron with schema extensions;
select cron.unschedule(jobid) from cron.job where jobname in ('dugsiga-monthly-fees','dugsiga-overdue-fees');
select cron.schedule('dugsiga-monthly-fees','0 2 1 * *','select public.generate_monthly_fee_records(date_trunc(''month'',current_date)::date)');
select cron.schedule('dugsiga-overdue-fees','10 2 * * *','select public.refresh_overdue_fee_status()');
