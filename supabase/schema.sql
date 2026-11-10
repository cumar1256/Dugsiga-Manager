-- Dugsiga Manager production data model for Supabase/PostgreSQL.
-- Provision auth.users and matching user_profiles rows from a trusted admin
-- workflow. Never put the Supabase service-role key in browser code.

create extension if not exists pgcrypto;

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid not null references public.schools(id) on delete cascade,
  role text not null check (role in ('admin','teacher')),
  full_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  grade text not null,
  section text not null default 'A',
  academic_year text not null,
  teacher_id uuid references public.user_profiles(user_id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, academic_year, grade, section),
  unique (id, school_id)
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  full_name text not null,
  grade text not null,
  parent_name text not null default '',
  phone text not null default '',
  enrollment_date date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, school_id)
);

create table if not exists public.class_students (
  school_id uuid not null references public.schools(id) on delete cascade,
  class_id uuid not null,
  student_id uuid not null,
  enrolled_at timestamptz not null default now(),
  ended_at timestamptz,
  primary key (class_id, student_id),
  foreign key (class_id, school_id) references public.classes(id, school_id) on delete cascade,
  foreign key (student_id, school_id) references public.students(id, school_id) on delete cascade
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  class_id uuid not null,
  student_id uuid not null,
  attendance_date date not null,
  status text not null check (status in ('Present','Absent','Late')),
  recorded_by uuid not null references public.user_profiles(user_id),
  recorded_at timestamptz not null default now(),
  constraint attendance_class_school_fk foreign key (class_id, school_id) references public.classes(id, school_id),
  constraint attendance_student_school_fk foreign key (student_id, school_id) references public.students(id, school_id),
  constraint attendance_roster_fk foreign key (class_id, student_id) references public.class_students(class_id, student_id),
  constraint attendance_once_per_student_class_day unique (student_id, class_id, attendance_date)
);

create index if not exists classes_teacher_idx on public.classes(teacher_id, school_id) where is_active;
create index if not exists class_students_student_idx on public.class_students(student_id);
create index if not exists attendance_teacher_lookup_idx on public.attendance(class_id, attendance_date);
create unique index if not exists one_active_class_per_student on public.class_students(student_id) where ended_at is null;

create or replace function public.validate_class_teacher()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.teacher_id is not null and not exists (
    select 1 from public.user_profiles p
    where p.user_id = new.teacher_id and p.school_id = new.school_id
      and p.role = 'teacher' and p.is_active
  ) then
    raise exception 'Class teacher must be an active teacher at the same school';
  end if;
  return new;
end;
$$;
drop trigger if exists validate_class_teacher_before_save on public.classes;
create trigger validate_class_teacher_before_save before insert or update of teacher_id, school_id
  on public.classes for each row execute function public.validate_class_teacher();

create or replace function public.is_school_admin(target_school uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (
  select 1 from public.user_profiles p
  where p.user_id = auth.uid() and p.school_id = target_school
    and p.role = 'admin' and p.is_active
) $$;

create or replace function public.is_assigned_teacher(target_class uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (
  select 1 from public.classes c
  join public.user_profiles p on p.user_id = auth.uid()
  where c.id = target_class and c.teacher_id = auth.uid()
    and c.is_active and p.is_active and p.role = 'teacher'
) $$;

alter table public.schools enable row level security;
alter table public.user_profiles enable row level security;
alter table public.classes enable row level security;
alter table public.students enable row level security;
alter table public.class_students enable row level security;
alter table public.attendance enable row level security;

create policy "school members read own school" on public.schools for select
  using (exists (select 1 from public.user_profiles p where p.user_id = auth.uid() and p.school_id = id and p.is_active));
create policy "admins update own school" on public.schools for update
  using (public.is_school_admin(id)) with check (public.is_school_admin(id));

create policy "users read own profile or admin reads school profiles" on public.user_profiles for select
  using (user_id = auth.uid() or public.is_school_admin(school_id));
create policy "admins manage school profiles" on public.user_profiles for all
  using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));

create policy "admin manages classes; teacher reads assigned classes" on public.classes for select
  using (public.is_school_admin(school_id) or (teacher_id = auth.uid() and is_active));
create policy "admins insert classes" on public.classes for insert
  with check (public.is_school_admin(school_id));
create policy "admins update classes" on public.classes for update
  using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins delete classes" on public.classes for delete
  using (public.is_school_admin(school_id));

create policy "admin reads all school students; teachers read assigned class roster" on public.students for select
  using (public.is_school_admin(school_id) or exists (
    select 1 from public.class_students cs
    where cs.student_id = students.id and cs.school_id = students.school_id
      and public.is_assigned_teacher(cs.class_id)
  ));
create policy "admins manage students" on public.students for all
  using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));

create policy "admin manages rosters; teacher reads assigned rosters" on public.class_students for select
  using (public.is_school_admin(school_id) or (ended_at is null and public.is_assigned_teacher(class_id)));
create policy "admins add students to class rosters" on public.class_students for insert
  with check (public.is_school_admin(school_id));
create policy "admins update class rosters" on public.class_students for update
  using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));
create policy "admins remove class rosters without attendance history" on public.class_students for delete
  using (public.is_school_admin(school_id));

create policy "admin reads all school attendance; teachers read assigned class attendance" on public.attendance for select
  using (public.is_school_admin(school_id) or public.is_assigned_teacher(class_id));
create policy "assigned teacher records their class attendance" on public.attendance for insert
  with check (
    recorded_by = auth.uid() and public.is_assigned_teacher(class_id)
    and exists (select 1 from public.classes c where c.id = class_id and c.school_id = school_id)
    and exists (select 1 from public.class_students cs where cs.class_id = class_id and cs.student_id = student_id and cs.ended_at is null)
  );
create policy "assigned teacher updates class attendance" on public.attendance for update
  using (public.is_assigned_teacher(class_id))
  with check (recorded_by = auth.uid() and public.is_assigned_teacher(class_id)
    and exists (select 1 from public.classes c where c.id = class_id and c.school_id = school_id));
create policy "admins manage attendance" on public.attendance for all
  using (public.is_school_admin(school_id)) with check (public.is_school_admin(school_id));

-- Do not grant anonymous access. Supabase's authenticated role is further
-- constrained by the row-level policies above.
revoke all on public.schools, public.user_profiles, public.classes,
  public.students, public.class_students, public.attendance from anon;
revoke all on function public.is_school_admin(uuid), public.is_assigned_teacher(uuid), public.validate_class_teacher() from public;
grant execute on function public.is_school_admin(uuid), public.is_assigned_teacher(uuid), public.validate_class_teacher() to authenticated;
grant select, update on public.schools to authenticated;
grant select, insert, update, delete on public.user_profiles, public.classes,
  public.students, public.class_students, public.attendance to authenticated;
