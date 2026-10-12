-- ops/ios-rig/seed.sql - the rig's world. Run ONCE by up.sh, as the cluster's superuser, against
-- a freshly migrated, empty throwaway database. Fixed UUIDs on purpose: a driven test refers to
-- a door by name, and the log of a walk reads better with ids a human can tell apart.
--
--   Rig Reinigung GmbH  (one company workspace)
--     Rig Haus Alpha     a0000000-...-a1
--        Stiege 1        a1000000-...-01   VERIFIED     (the ordinary door)
--        Keller          a1000000-...-02   UNVERIFIED   (verified_at NULL: 422 zone_unverified)
--        Dachboden       a1000000-...-03   VERIFIED     (rig.sh zone-deactivate flips it later;
--                                                        also the SECOND door of building A for
--                                                        the same-building rule)
--     Rig Haus Beta      b0000000-...-b1
--        Haupteingang    b1000000-...-01   VERIFIED
--   Workers  Anna Rig, Bernd Rig (two people, one phone: P3)    Operator  Olga Operator
--
-- Everything time-relative (planned assignments, open shifts) is NOT here: rig.sh builds it with
-- `rig.sh schedule-set` / `rig.sh reset-data`, because "tomorrow 22:00" depends on the day the
-- rig comes up.
\set ON_ERROR_STOP on

WITH t AS (
  INSERT INTO tenants (name, locale) VALUES ('Rig Reinigung GmbH', 'de') RETURNING id
)
SELECT id AS tenant FROM t \gset

INSERT INTO locations (id, tenant_id, slug, name, address, active) VALUES
  ('a0000000-0000-4000-8000-0000000000a1', :tenant, 'rig-haus-alpha', 'Rig Haus Alpha', 'Alphagasse 1, 1010 Wien', true),
  ('b0000000-0000-4000-8000-0000000000b1', :tenant, 'rig-haus-beta',  'Rig Haus Beta',  'Betastrasse 2, 1020 Wien', true);

INSERT INTO zones (id, tenant_id, location_id, name, verified_at, active) VALUES
  ('a1000000-0000-4000-8000-000000000001', :tenant, 'a0000000-0000-4000-8000-0000000000a1', 'Stiege 1',     now(), true),
  ('a1000000-0000-4000-8000-000000000002', :tenant, 'a0000000-0000-4000-8000-0000000000a1', 'Keller',       NULL,  true),
  ('a1000000-0000-4000-8000-000000000003', :tenant, 'a0000000-0000-4000-8000-0000000000a1', 'Dachboden',    now(), true),
  ('b1000000-0000-4000-8000-000000000001', :tenant, 'b0000000-0000-4000-8000-0000000000b1', 'Haupteingang', now(), true);

INSERT INTO workers (tenant_id, name, hourly_rate_cents, active) VALUES
  (:tenant, 'Anna Rig',  1500, true),
  (:tenant, 'Bernd Rig', 1500, true);

INSERT INTO operators (tenant_id, name, active) VALUES (:tenant, 'Olga Operator', true);

SELECT 'tenant=' || :tenant;
