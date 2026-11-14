-- integration.sql section 20: renaming on any of profiles / patients / caregivers / doctors reaches the others of the same account.
begin;
insert into auth.users (id, email) values ('a1100000-0000-0000-0000-000000000001', 'ns@t');
insert into patients (id, user_id, full_name) values ('b1100000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001', 'Old');
update profiles set full_name = 'Old' where id = 'a1100000-0000-0000-0000-000000000001';
insert into caregivers (id, user_id, full_name) values ('c1100000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001', 'Old');
do $$
begin
  update patients set full_name = 'New1' where id = 'b1100000-0000-0000-0000-000000000001';
  assert (select full_name from profiles where id = 'a1100000-0000-0000-0000-000000000001') = 'New1', 'patient rename did not reach profile';
  assert (select full_name from caregivers where id = 'c1100000-0000-0000-0000-000000000001') = 'New1', 'patient rename did not reach caregiver';
  update profiles set full_name = 'New2' where id = 'a1100000-0000-0000-0000-000000000001';
  assert (select full_name from patients where id = 'b1100000-0000-0000-0000-000000000001') = 'New2', 'profile rename did not reach patient';
  update caregivers set full_name = 'New3' where id = 'c1100000-0000-0000-0000-000000000001';
  assert (select full_name from patients where id = 'b1100000-0000-0000-0000-000000000001') = 'New3', 'caregiver rename did not reach patient';
  assert (select full_name from profiles where id = 'a1100000-0000-0000-0000-000000000001') = 'New3', 'caregiver rename did not reach profile';
end $$;
rollback;
