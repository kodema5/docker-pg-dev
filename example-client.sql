select not exists (select 1 from pg_language where lanname='plpython3u') as has_no_plpython3u_language
\gset
\if :has_no_plpython3u_language
    create language plpython3u;
\endif

-- calls univorn dev.py httpx end-point
-- to off-load http-call requests
-- plpython3u does not seem to handle jsonb type
--
create or replace function httpx(
    x jsonb,
    timeout float default 0.000001
) returns text as $$
    import httpx
    import json
    p = json.loads(x)
    try:
        r = httpx.request(
            'POST',
            'http://0.0.0.0:80/httpx',
            json = p,

            # use short read Timeout to ignore response
            #
            timeout = httpx.Timeout(10, read=timeout)
        )

        return r.text
    except:
        return None
$$ language plpython3u;


-- call httpx-service with 10 second timeout wait
--
select to_jsonb(httpx(jsonb_build_object(
    'url', 'https://httpbin.org/post',
    'method', 'POST',
    'json', jsonb_build_object('foo', array[1,2,3]::int[]),

    'callback', 'select $1::jsonb || coalesce($2::jsonb, ''{}''::jsonb)',
    'context', jsonb_build_object('a', 123)
    ), 10.0));

