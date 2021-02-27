
-- pg-dev psql
-- \ir example.sql
-- select * from example.example_log;

-- see example.http for call

drop schema if exists example cascade;
create schema example;

------------------------------------------------------------

create table example.example_log(
    ts timestamp with time zone default current_timestamp,
    by text,
    val jsonb
);


create function example.echo(i jsonb) returns jsonb as $$
declare
    o jsonb = (i || '{"web.echo1":"hello"}'::jsonb) - 'callback';
begin
    insert into example.example_log (by, val) values ('echo1', o);
    return o;
end;
$$ language plpgsql;


create function example.echo2(i jsonb) returns jsonb as $$
declare
    o jsonb = (i || '{"web.echo2":"hello"}'::jsonb) - 'callback';
begin
    insert into example.example_log (by, val) values ('echo2', o);
    return o;
end;
$$ language plpgsql;

