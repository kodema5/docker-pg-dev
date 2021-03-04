# can be used as out of process calculation accessed via http
# run uvicorn dev:app --host=0.0.0.0 --port=80

import asyncio
import asyncpg
import aiofiles
import os
import json
import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.staticfiles import StaticFiles
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.background import BackgroundTask
from urllib import parse

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

items = {}

@app.on_event("startup")
async def startup_event():
    items['pool'] = await asyncpg.create_pool(
        min_size=1,
        max_size=10,
        database='postgres',
        password=os.getenv('POSTGRES_PASSWORD'),
        user='postgres')


@app.on_event("shutdown")
async def shutdown_event():
    items['pool'].terminate()

# -----------------------------------------------------------------------------
# serve / static file
#
app.mount("/public", StaticFiles(directory="/work"), name="root")


# -----------------------------------------------------------------------------
# /echo parameters for testing
#
@app.post('/echo')
async def echo_api(req:Request):
    return {
        **({
            'origin': req.client.host if req.client else None
        }),
        **dict(req.headers),
        **dict(req.query_params),
        **(await get_req_json(req))
    }

async def get_req_json(req:Request):
    try:
        return await req.json()
    except:
        return {}

# -----------------------------------------------------------------------------
# httpx calls httpx from pg
#
@app.post('/_/httpx')
async def httpx_exec_api(req:Request):
    p = await req.json()

    if 'callback' in p:
        t = BackgroundTask(httpx_exec, p)
        return JSONResponse(None, background=t)

    return await httpx_exec(p)


async def httpx_exec(p):
    # p.url
    #
    if not ('url' in p):
        return

    # p.uploads=[[name,filename]]
    #
    files = p.get('files', None)
    if files:
        for n in files.keys():
            filename = files.get(n)
            async with aiofiles.open(filename, mode='r') as f:
                r = await f.read()
                files[n] = r

    # call-ajax
    # p.method
    # p.params
    # p.data
    # p.json
    # p.headers
    # p.cookies
    #
    r = httpx.Request(
        p.get('method', 'POST'),
        p['url'],
        params = p.get('params', None),
        data = p.get('data', None),
        json = p.get('json', None),
        headers = p.get('headers', None),
        cookies = p.get('cookies', None),
        files = files
    )

    success = False
    async with httpx.AsyncClient(
        timeout = httpx.Timeout(p.get('timeout', 5.0))
    ) as client:
        try:
            res = await client.send(r)
            success = True
        except Exception as e:
            res = {'error': str(e) }

    # p.downloads
    #
    writeTo = p.get('downloads', None)
    if success and writeTo:
        async with aiofiles.open(writeTo, 'wb') as f:
            await f.write(res.content)
            await f.flush()


    # builds data
    # p.type
    #
    data = dict()
    v = p.get('type', None)
    if success and not writeTo and v == "json":
        try:
            data.update(res.json())
        except Exception as e:
            data.update({'error': 'Failed to parse json'})
    elif success and not writeTo and v == "text":
        data.update({"text": res.text})
    elif not success:
        data.update({"error": res.get('error')})


    # p.callback
    #
    if not 'callback' in p:
        return data

    # call-callback
    #
    await do_callback(p.get('callback',None), data)

# -----------------------------------------------------------------------------
# /schema/{fn} calls {schema.fn}(jsonb) returns jsonb
#
@app.post('/{schema}/{fn}')
async def db_exec_api(schema:str, fn:str, req:Request):
    pg_fn = '.'.join(map(json.dumps, [schema, fn]))
    data = {
        **({
            'origin': req.client.host if req.client else None
        }),
        **dict(req.headers),
        **dict(req.query_params),
        **(await get_req_json(req))
    }

    if not 'callback' in data:
        return await db_exec(pg_fn, data)

    cb = data["callback"]
    task = BackgroundTask(db_exec_callback, pg_fn, data, cb)
    return JSONResponse(None, background=task)


# execute db-call
#
async def db_exec(pg_fn, data):
    pool = items['pool']

    async with pool.acquire() as conn:

        await conn.set_type_codec(
            'jsonb',
            encoder=json.dumps,
            decoder=json.loads,
            schema='pg_catalog'
        )

        return await conn.fetchval(
            f"select {pg_fn}($1::jsonb) as output",
            data
        )


# execute db with callback
#
async def db_exec_callback(pg_fn, data, callback):
    output = await db_exec(pg_fn, data)
    await do_callback(callback, output)


# -----------------------------------------------------------------------------
# process callback=url of data
#
async def do_callback(url, data):
    parsed = parse.urlsplit(url)
    sch = parsed.scheme

    if sch == 'local' or sch == '':
        fn = '.'.join(map(json.dumps, [parsed.netloc, parsed.path.split('/')[1]]))
        await db_exec(fn, {
            **dict(parse.parse_qsl(parsed.query)),
            **data
        })

    elif sch == 'http' or sch == 'https':
        r = httpx.Request('POST', url, json=data)

        async with httpx.AsyncClient() as client:
            try:
                await client.send(r)
            except Exception as e:
                print(e)



# -----------------------------------------------------------------------------
# refs:
#
# https://fastapi.tiangolo.com/
# https://magicstack.github.io/asyncpg/current/usage.html
