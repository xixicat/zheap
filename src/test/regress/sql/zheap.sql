--
-- Test cases for ZHeap
--
set client_min_messages = warning;
--
-- 1. Test for storage engine
--

-- Normal heap
CREATE TABLE t1_heap
(
 a int
);
\d+ t1_heap;

-- Zheap heap
CREATE TABLE t1_zheap
(
 a int
) USING zheap;
\d+ t1_zheap;

DROP TABLE t1_heap;
DROP TABLE t1_zheap;

--
-- 2. Test for Index Scan on zheap
--
set enable_seqscan to false;
set enable_indexonlyscan to false;
set enable_indexscan to true;
set enable_bitmapscan to false;

create table btree_zheap_tbl(id int4, t text) USING zheap WITH (autovacuum_enabled=false) ;
insert into btree_zheap_tbl
  select g, g::text || '_' ||
            (select string_agg(md5(i::text), '_') from generate_series(1, 50) i)
			from generate_series(1, 100) g;
create index btree_zheap_idx on btree_zheap_tbl (id);

-- check the plan with index scan
explain (costs false) select * from btree_zheap_tbl where id=1;
select id from btree_zheap_tbl where id=1;

-- update a non-key column and delete a row
update btree_zheap_tbl set t='modified' where id=1;
select * from btree_zheap_tbl where id = 1;
delete from btree_zheap_tbl where id=2;
select * from btree_zheap_tbl where id = 2;

drop table btree_zheap_tbl;


--
--3. Test for aggregate nodes
--
CREATE TABLE aggtest_zheap
(
 a int,
 b int
) USING zheap;
INSERT INTO aggtest_zheap SELECT g,g FROM generate_series(1,1000) g;

SELECT sum(a) AS sum_198 FROM aggtest_zheap;
SELECT max(aggtest_zheap.a) AS max_3 FROM aggtest_zheap;
SELECT stddev_pop(b) FROM aggtest_zheap;
SELECT stddev_samp(b) FROM aggtest_zheap;
SELECT var_pop(b) FROM aggtest_zheap;
SELECT var_samp(b) FROM aggtest_zheap;
SELECT stddev_pop(b::numeric) FROM aggtest_zheap;
SELECT stddev_samp(b::numeric) FROM aggtest_zheap;
SELECT var_pop(b::numeric) FROM aggtest_zheap;
SELECT var_samp(b::numeric) FROM aggtest_zheap;

DROP TABLE aggtest_zheap;
set client_min_messages = notice;

--
--4. Test for PRIMARY KEY on zheap tables.
--
CREATE TABLE pkey_test_zheap
(
 a int PRIMARY KEY,
 b int
) USING zheap;

-- should run suucessfully.
INSERT INTO pkey_test_zheap VALUES (10, 30);

-- should error out, primary key doesn't allow NULL value.
INSERT INTO pkey_test_zheap(b) VALUES (30);

-- should error out, primary key doesn't allow duplicate value.
INSERT INTO pkey_test_zheap VALUES (10, 30);

SELECT * FROM pkey_test_zheap;

DROP TABLE pkey_test_zheap;

--
-- 5.1. Test of non-inlace-update where new update goes to new page.
--
CREATE TABLE update_test_zheap(c1 int,c2 char(1000),c3 varchar(10));
INSERT INTO update_test_zheap VALUES(generate_series(1,7), 'aaa', 'aaa');
UPDATE update_test_zheap SET c3 = 'bbbb' WHERE c1=1;

-- verify the update
SELECT c3 FROM update_test_zheap WHERE c1=1;
DROP TABLE update_test_zheap;

--
-- 5.2. Test of non-inlace-update on same page and for index key updates.
--
set enable_indexonlyscan to false;
set enable_bitmapscan to false;
CREATE TABLE update_test_zheap(c1 int PRIMARY KEY, c2 int);
INSERT INTO update_test_zheap VALUES(generate_series(1,7), 1);
UPDATE update_test_zheap SET c2 = 100 WHERE c1 = 1;
UPDATE update_test_zheap SET c2 = 101 WHERE c1 = 2;

-- verify the update
SELECT c2 FROM update_test_zheap WHERE c1 IN (1,2);
DROP TABLE update_test_zheap;

--
-- 6. Test for bitmap heap scan - taken from bitmapops.sql
--

CREATE TABLE bmscantest (a int, b int, t text) USING zheap;

INSERT INTO bmscantest
  SELECT (r%53), (r%59), 'foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo'
  FROM generate_series(1,70000) r;

CREATE INDEX i_bmtest_a ON bmscantest(a);
CREATE INDEX i_bmtest_b ON bmscantest(b);

-- We want to use bitmapscans. With default settings, the planner currently
-- chooses a bitmap scan for the queries below anyway, but let's make sure.
set enable_indexscan=false;
set enable_seqscan=false;

-- Lower work_mem to trigger use of lossy bitmaps
set work_mem = 64;


-- Test bitmap-and.
SELECT count(*) FROM bmscantest WHERE a = 1 AND b = 1;

-- Test bitmap-or.
SELECT count(*) FROM bmscantest WHERE a = 1 OR b = 1;


-- clean up
DROP TABLE bmscantest;

--
-- 7. Test page pruning after a non-inplace-update
--
CREATE TABLE update_test_zheap(c1 int,c2 char(1000),c3 varchar(10))
							   USING zheap;
INSERT INTO update_test_zheap VALUES(generate_series(1,7), 'aaa', 'aaa');
UPDATE update_test_zheap SET c3 = 'bbbbb' WHERE c1=1;

SELECT c1 from update_test_zheap ORDER BY c1;

UPDATE update_test_zheap SET c3 = 'bbbbb' WHERE c1 = 2;

-- record c1 = 2 should come before c1 = 1 because prune should have
-- reclaimed space of moved c1 = 1 and hence new c1 = 2 will be inserted
-- in same page.
SELECT c1 from update_test_zheap ORDER BY c1;

-- update last record c1 = 2 such that it can be inplace extended.
UPDATE update_test_zheap SET c3 = 'cccccc' WHERE c1 = 2;
SELECT c1 from update_test_zheap ORDER BY c1;

-- update another record in the page to force pruning.
UPDATE update_test_zheap SET c3 = 'bbbbb' WHERE c1 = 7;
SELECT c1 from update_test_zheap ORDER BY c1;

DROP TABLE update_test_zheap;

--
-- 8. verify basic cursor fetch.
--
CREATE TABLE cursor_zheap
(
	a int
) USING zheap;

INSERT INTO cursor_zheap SELECT * FROM generate_series(1, 5);

SELECT * FROM cursor_zheap;

BEGIN;
	DECLARE cur1 SCROLL CURSOR FOR SELECT * FROM cursor_zheap;
	FETCH 2 in cur1;
	FETCH BACKWARD 2 in cur1;
END;

CREATE MATERIALIZED VIEW mvtest_mv AS SELECT * FROM cursor_zheap;

DROP MATERIALIZED VIEW mvtest_mv;
DROP TABLE cursor_zheap;

-------------------------------------------
-- Test cases for commit/rollback in SPI --
-------------------------------------------

CREATE TABLE test1 (a int, b text) USING zheap;
CREATE TABLE test2 (x int);
INSERT INTO test2 VALUES (0), (1), (2), (3), (4);

TRUNCATE test1;

DO LANGUAGE plpgsql $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM test2 ORDER BY x LOOP
        INSERT INTO test1 (a) VALUES (r.x);
        COMMIT;
    END LOOP;
END;
$$;

SELECT * FROM test1 order by a, b;

-- error in cursor loop with commit
TRUNCATE test1;

DO LANGUAGE plpgsql $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM test2 ORDER BY x LOOP
        INSERT INTO test1 (a) VALUES (12/(r.x-2));
        COMMIT;
    END LOOP;
END;
$$;

SELECT * FROM test1 order by a, b;

-- rollback inside cursor loop
TRUNCATE test1;

DO LANGUAGE plpgsql $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM test2 ORDER BY x LOOP
        INSERT INTO test1 (a) VALUES (r.x);
        ROLLBACK;
    END LOOP;
END;
$$;

SELECT * FROM test1 order by a, b;

-- first commit then rollback inside cursor loop
TRUNCATE test1;

DO LANGUAGE plpgsql $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM test2 ORDER BY x LOOP
        INSERT INTO test1 (a) VALUES (r.x);
        IF r.x % 2 = 0 THEN
            COMMIT;
        ELSE
            ROLLBACK;
        END IF;
    END LOOP;
END;
$$;

SELECT * FROM test1 order by a, b;

SELECT * FROM pg_cursors;

-- commit/rollback with begin exception case
-- should throw error
TRUNCATE test1;

DO LANGUAGE plpgsql $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM test2 ORDER BY x LOOP
        INSERT INTO test1 (a) VALUES (r.x);
        IF r.x % 2 = 0 THEN
            COMMIT;
        ELSE
            ROLLBACK;
        END IF;
    END LOOP;
EXCEPTION WHEN OTHERS THEN
	RAISE NOTICE '% %', SQLERRM, SQLSTATE;
END;
$$;

SELECT * FROM test1 order by a, b;
SELECT * FROM test2 order by x;

DROP TABLE test1;
DROP TABLE test2;

-- rollback of toast table insertion
CREATE TABLE ctoast (key int primary key, val text) USING zheap;
CREATE OR REPLACE FUNCTION ctoast_large_val() RETURNS TEXT LANGUAGE SQL AS
'select array_agg(md5(g::text))::text from generate_series(1, 256) g';
BEGIN;
INSERT INTO ctoast (key, val) VALUES (1, ctoast_large_val());
ROLLBACK;
DROP TABLE ctoast;
DROP FUNCTION ctoast_large_val;

-- check that new relations have no relfrozenxid/relminmxid and that
-- that's not changed by VACUUM, VACUUM FULL and CLUSTER

-- new relation
CREATE TABLE testvacuum(id serial) USING zheap;
SELECT relfrozenxid, relminmxid FROM pg_class WHERE oid = 'testvacuum'::regclass;
INSERT INTO testvacuum DEFAULT VALUES;
SELECT relfrozenxid, relminmxid FROM pg_class WHERE oid = 'testvacuum'::regclass;

-- plain VACUUM
VACUUM testvacuum;
SELECT relfrozenxid, relminmxid FROM pg_class WHERE oid = 'testvacuum'::regclass;

-- VACUUM FULL
VACUUM FULL testvacuum;
SELECT relfrozenxid, relminmxid FROM pg_class WHERE oid = 'testvacuum'::regclass;

-- CLUSTER
CREATE INDEX testvacuum_id ON testvacuum(id);
CLUSTER testvacuum USING testvacuum_id;
SELECT relfrozenxid, relminmxid FROM pg_class WHERE oid = 'testvacuum'::regclass;

-- and that there's still content after this ordeal
SELECT * FROM testvacuum ORDER BY id;

-- Test multi insert
CREATE TABLE test_multi_insert(id int) USING zheap;
INSERT INTO test_multi_insert SELECT generate_series(1,10);
DELETE FROM test_multi_insert WHERE id%2=0;
VACUUM test_multi_insert;
BEGIN;
COPY test_multi_insert FROM STDIN;
11
12
13
14
15
\.
SELECT * FROM test_multi_insert ORDER BY 1;
ROLLBACK;
SELECT * FROM test_multi_insert ORDER BY 1;
DROP TABLE test_multi_insert;
