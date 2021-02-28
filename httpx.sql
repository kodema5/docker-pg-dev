-- accesses uvicorn's httpx
-- uvicorn dev:app --host=0.0.0.0 --port=80
--
select not exists (select 1 from pg_language where lanname='plpython3u') as has_no_plpython3u_language
\gset
\if :has_no_plpython3u_language
    create language plpython3u;
\endif


create procedure httpx (
    url text,
    method text default 'POST',

    type text default 'json',
    callback text default null,

    params jsonb default null,
    data jsonb default null,
    json jsonb default null,
    headers jsonb default null,
    cookies jsonb default null,
    files jsonb default null,

    downloads text default null
)
as $$
    from httpx import request
    from json import loads

    p = {
        "url": url,
        "method": method,

        "params": loads(params) if params else None,
        "data": loads(data) if data else None,
        "json": loads(json) if json else None,
        "headers": loads(headers) if headers else None,
        "cookies": loads(cookies) if cookies else None,
        "files": loads(files) if files else None,

        "downloads": downloads if downloads else None,
        "callback": callback if callback else None,
        "type": type
    }

    try:
        r = request(
            'POST',
            'http://0.0.0.0:80/httpx',
            json = p,
        )
    except:
        pass

$$ language plpython3u;


-- httpx_sync locks process (use sparingly)
--
create function httpx_sync (
    url text,
    method text default 'POST',

    params jsonb default null,
    data jsonb default null,
    json jsonb default null,
    headers jsonb default null,
    cookies jsonb default null,
    timeout int default 5 -- set to null to disable
)
returns text
as $$
    from httpx import request
    from json import loads, dumps

    try:
        r = request(
            method,
            url,
            params = loads(params) if params else None,
            json = loads(json) if json else None,
            data = loads(data) if data else None,
            headers = loads(headers) if headers else None,
            cookies = loads(cookies) if cookies else None,
            timeout = timeout
        )

        return r.text

    except Exception as e:
        plpy.warning(str(e))
        return None
$$ language plpython3u;



\if :test

    create table tests.httpx_log (
        ts timestamp with time zone default current_timestamp,
        val jsonb
    );

    create function tests.httpx_callback (x jsonb) returns void as $$
        insert into tests.httpx_log (val) values (x)
    $$ language sql;


    create procedure tests.httpx_log_show_values (title text) as $$
    declare
        r record;
    begin
        raise warning '-------------------------------------------- ';
        raise warning '%',  title;

        for r in select val from tests.httpx_log
        loop
            raise warning '- %', r.val;
        end loop;

        delete from tests.httpx_log;
    end;
    $$ language plpgsql;


    create function tests.test_httpx_simple () returns setof text as $$
    declare
        n int;
        v jsonb;
    begin
        call httpx(
            url := 'https://httpbin.org/post',
            json := jsonb_build_object('foo', array[1,2,3]::int[]),
            callback:= 'api://tests.httpx_callback?from=test_httpx_simple'
        );

        perform pg_sleep(1);

        select count(1) into n
            from tests.httpx_log
            where val->>'from' = 'test_httpx_simple';

        return next ok(n=1, 'can call http and callback');
    end;
    $$ language plpgsql;


    create function tests.test_httpx_get_file () returns setof text as $$
    declare
        n int;
        v jsonb;
        r record;
    begin
        call httpx(
            url := 'http://0.0.0.0:80/example.html',
            method := 'GET',
            type := 'text',
            callback:= 'api://tests.httpx_callback?from=test_httpx_get_file'
        );

        perform pg_sleep(1);

        select val into v
            from tests.httpx_log
            where val->>'from' = 'test_httpx_get_file';

        call tests.httpx_log_show_values('test_httpx_get_file');

        return next ok(v is not null and v->>'text' is not null, 'can get-file');
    end;
    $$ language plpgsql;


    create function tests.test_httpx_downloads () returns setof text as $$
    declare
        n int;
        v jsonb;
        r record;
    begin
        call httpx(
            url := 'http://0.0.0.0:80/example.html',
            method := 'GET',
            downloads := 'a.html',
            type := 'text',
            callback:= 'api://tests.httpx_callback?from=test_httpx_downloads'
        );

        perform pg_sleep(1);

        select count(1) into n
            from tests.httpx_log
            where val->>'from' = 'test_httpx_downloads';

        call tests.httpx_log_show_values('test_httpx_downloads');

        return next ok(n=1, 'can download-files');
    end;
    $$ language plpgsql;

    create function tests.test_httpx_uploads () returns setof text as $$
    declare
        n int;
        v jsonb;
    begin
        call httpx(
            url := 'https://httpbin.org/post',
            files := jsonb_build_object(
                'a-file', 'example.html'
            ),
            callback:= 'api://tests.httpx_callback?from=test_httpx_uploads'
        );

        perform pg_sleep(1);


        select count(1) into n
            from tests.httpx_log
            where val->>'from' = 'test_httpx_uploads';

        call tests.httpx_log_show_values('test_httpx_uploads');

        return next ok(n=1, 'can call http uploads');
    end;
    $$ language plpgsql;

    create function tests.test_httpx_sync () returns setof text as $$
    declare
        a jsonb;
    begin
        a = httpx_sync(
            url := 'http://0.0.0.0:80/echo?a=1',
            json := jsonb_build_object(
                'b', 2
            )
        )::jsonb;

        -- raise warning '----- httpx_sync %', a;

        return next ok(a->>'a' = '1' and a->>'b' = '2', 'can sync http-call');
    end;
    $$ language plpgsql;


\endif

