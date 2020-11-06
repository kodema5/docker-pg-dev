
-- > "dev watch /example.sql"
-- > "dev web"
-- see example.http for call

drop schema if exists web cascade;
create schema web;

create type web.input_t as (
    a int
);

create type web.output_t as (
    b int,
    hello text
);

-- this is an internal function
create function web.post(i web.input_t) returns web.output_t as $$
declare
    o web.output_t;
begin
    o.b = i.a + 100;
    o.hello = 'world';
    return o;
end;
$$ language plpgsql;


-- pg is polymorphic
create function web.post(
    body jsonb,                 -- request json body
    headers jsonb default null  -- for future (ex: authentication)
) returns jsonb as $$
    select to_jsonb(web.post(jsonb_populate_record(null::web.input_t, body)))
        || coalesce(headers, '{}'::jsonb);             -- just combine for now
$$ language sql;

\if :test
-- "\if :test" indicates if run by dev.sql

-- add tests.test_ for unit-testing
--
create function tests.test_post () returns setof text as $$
declare
    a jsonb;
    b jsonb;
begin
    a = '{'
        '"a":1,'
        '"c":3' -- extra field will be ignored
    '}'::jsonb;

    b = web.post(a);
    -- raise warning '---%', b::text;

    return next ok((b ->> 'b')::int = 101, 'returns b = a + 100');
    return next ok(b ->> 'hello' is not null, 'says hello too');
end;
$$ language plpgsql;

\endif

-- see https://www.postgresql.org/docs/12/functions-json.html