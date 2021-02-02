# can be used as out of process calculation accessed via http
# run uvicorn dev:app --host=0.0.0.0 --port=80

import asyncio
import asyncpg
import os
import json
import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.staticfiles import StaticFiles
from starlette.requests import Request

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

# /api/{fn} calls {fn}(jsonb, jsonb) returns jsonb
#
#
@app.post('/api/{fn}')
async def exec_func(fn:str, req:Request):
    pool = items['pool']
    pg_fn = '.'.join(map(json.dumps, fn.split('.')))

    async with pool.acquire() as conn:

        await conn.set_type_codec(
            'jsonb',
            encoder=json.dumps,
            decoder=json.loads,
            schema='pg_catalog'
        )

        return await conn.fetchval(
            f"select {pg_fn}($1::jsonb, $2::jsonb) as output",
            await req.json(),
            dict(req.headers)
        )

# http-proxy to export http-tasks outside
#
#
@app.post('/httpx')
async def exec_func(req:Request):
    p = await req.json()

    if not ('url' in p):
        return

    r = httpx.Request(
        p.get('method', 'POST'),
        p['url'],
        params = p.get('params', None),
        data = p.get('data', None),
        json = p.get('json', None),
        headers = p.get('headers', None),
        cookies = p.get('cookies', None)
    )

    async with httpx.AsyncClient() as client:
        res = await client.send(r)

    if not ('callback' in p):
        return

    pool = items['pool']
    async with pool.acquire() as conn:

        await conn.set_type_codec(
            'jsonb',
            encoder=json.dumps,
            decoder=json.loads,
            schema='pg_catalog'
        )

        t = p.get('type', 'json')
        if t == 'json':
            a = res.json()
        else:
            a = res.text

        if ('context' in p):
            x = await conn.fetchval(
                p.get('callback'),
                a,
                p.get('context', None)
            )
        else:
            x = await conn.fetchval(
                p.get('callback'),
                a
            )

        return x


# serve / static file
#
app.mount("/", StaticFiles(directory="/work"), name="root")

# refs:
# https://fastapi.tiangolo.com/
# https://magicstack.github.io/asyncpg/current/usage.html
