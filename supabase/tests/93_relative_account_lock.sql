-- integration.sql #18: a contact the patient added stops being theirs to change once an account is attached to it (user_id set by
-- Admin). Before, the patient could still rename it, change its phone or delete the caregivers row of a real relative account.
-- Users: PU patient of P1, CG caregiver account. KIN = a contact PU added, later attached by Admin to CG's account.
begin;
insert into auth.users (id, email) values
  ('e7000000-0000-0000-0000-0000000000e7', 'pu5@t'), ('e8000000-0000-0000-0000-0000000000e8', 'cg5@t');
update profiles set is_active = true where id in ('e7000000-0000-0000-0000-0000000000e7', 'e8000000-0000-0000-0000-0000000000e8');
insert into user_roles (user_id, role) values
  ('e7000000-0000-0000-0000-0000000000e7', 'patient'), ('e8000000-0000-0000-0000-0000000000e8', 'caregiver');
insert into patients (id, user_id, full_name) values ('f7000000-0000-0000-0000-0000000000f7', 'e7000000-0000-0000-0000-0000000000e7', 'P1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e7000000-0000-0000-0000-0000000000e7"}', true);
select set_config('t.kin', save_my_relative(null, 'KIN', 'ลูก', '0899990005')::text, true);
reset role;
-- Admin attaches CG's account to the contact (the relative now signs in and sees P1)
update caregivers set user_id = 'e8000000-0000-0000-0000-0000000000e8' where id = current_setting('t.kin')::uuid;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e7000000-0000-0000-0000-0000000000e7"}', true);
do $$
declare r uuid := current_setting('t.kin')::uuid;
begin
  assert (select count(*) from list_my_relatives() where id = r) = 1, 'attached relative missing from the list';
  assert not (select editable from list_my_relatives() where id = r), 'attached relative still editable';
  begin perform save_my_relative(r, 'x', 'y', '1'); raise exception 'patient edited a relative account row';
  exception when insufficient_privilege then null; end;
  begin perform delete_my_relative(r); raise exception 'patient deleted a relative account row';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$
begin
  assert (select full_name || '|' || phone from caregivers where id = current_setting('t.kin')::uuid) = 'KIN|0899990005', 'row changed';
end $$;
rollback;
