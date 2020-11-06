-- designed for individual file test
-- psql --quiet -v ON_ERROR_STOP=1 -U postgres -d postgres -f /test.sql -v test_file=file-to-test.sql

---------------------------------------------------------------------------
-- install pg-tap https://pgtap.org/

set client_min_messages to warning;
-- \echo '-- test for' :test_file
create extension if not exists pgtap;


---------------------------------------------------------------------------
-- setup tests schema for test functions

drop schema if exists tests cascade;
create schema tests;
\set test true


---------------------------------------------------------------------------
-- save current search_path

create or replace function tests.last(a anyarray)
returns anyelement as $$
    select a[array_upper(a,1)]
$$ language sql immutable strict;

select current_setting('search_path')  as old_search_path,
    tests.last(string_to_array(:'test_file', '/')) as test_filename
\gset


---------------------------------------------------------------------------
-- setup dev schema for default temporary schema

drop schema if exists dev cascade;
create schema dev;
\set dev true
set schema 'dev';


---------------------------------------------------------------------------
-- include combinations of files
-- from -v test_file=..... parameter

\set ON_ERROR_STOP 0
\i :test_file
\i :test_file.sql
\i :test_file/:test_filename.sql
\i :test_file/index.sql
\set ON_ERROR_STOP 1


---------------------------------------------------------------------------
-- set search_path for dev and tests

select set_config('search_path',
    :'old_search_path' || ',dev,tests',
    false) as new_search_path
\gset


---------------------------------------------------------------------------
-- run tests

\set test_pattern :test_pattern
select case
    when :'test_pattern' = ':test_pattern' then '^test'
    else :'test_pattern'
end as test_pattern \gset

set client_min_messages to notice;
select * from runtests('tests'::name, :'test_pattern');
set client_min_messages to warning;


---------------------------------------------------------------------------
-- clean-up tests schema

drop schema if exists tests cascade;

