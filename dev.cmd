@echo off
setlocal EnableDelayedExpansion
rem dev.cmd [cmd]
rem requires
rem     docker
rem     npm install -g nodemon

set PGDEV_IMAGE=pg-dev
if "%PGDEV_NAME%"=="" (
    set PGDEV_NAME=pg-dev
)
if "%PGDEV_PASSWORD%"=="" (
    set PGDEV_PASSWORD=rei
)
if "%PGDEV_PORT%"=="" (
    set PGDEV_PORT=5432
)
if "%PGDEV_HTTP_PORT%"=="" (
    set PGDEV_HTTP_PORT=5000
)
if "%PGDEV_WORKDIR%"=="" (
    set PGDEV_WORKDIR=%cd%
)

set args_all=%*
set arg1=%1
set arg2=%2
call set args=%%args_all:*%1=%%


if [%arg1%]==[build-docker] (
    @echo building %PGDEV_IMAGE%
    docker build -t %PGDEV_IMAGE% .
    docker system prune -f
    goto end
)
if [%arg1%]==[start-docker] (
    @echo starting %PGDEV_NAME% container

    docker run --rm -d ^
        -p %PGDEV_PORT%:5432 ^
        -p %PGDEV_HTTP_PORT%:80 ^
        -v %PGDEV_WORKDIR%:/work ^
        -v %PGDEV_WORKDIR%/.data:/var/lib/postgresql/data ^
        --name %PGDEV_NAME% ^
        -e POSTGRES_PASSWORD=%PGDEV_PASSWORD% ^
        %PGDEV_IMAGE% ^
        -c shared_preload_libraries=pg_cron ^
        -c cron.database_name=postgres
    goto end
)
if [%arg1%]==[stop-docker] (
    @echo stopping %PGDEV_NAME% container

    docker exec -it %PGDEV_NAME% ^
        su - postgres -c ^
        "/usr/lib/postgresql/12/bin/pg_ctl -D /var/lib/postgresql/data stop -m fast"
    rem docker stop %PGDEV_NAME%
    goto end
)


if [%arg1%]==[bash] (
    docker exec -it %PGDEV_NAME% bash %args%
    goto end
)
if [%arg1%]==[python] (
    docker exec -it %PGDEV_NAME% python3 %args%
    goto end
)
if [%arg1%]==[psql] (
    docker exec -it -w /work %PGDEV_NAME% ^
        psql -U postgres -d postgres %args%
    goto end
)


rem runs uvicorn web-server
rem
if [%arg1%]==[serve] (
    @echo starting dev web-server
    @echo POST http://localhost:%PGDEV_HTTP_PORT%/api/web.post HTTP/1.1
    @echo Content-Type: application/json
    @echo.
    docker exec -it -w / %PGDEV_NAME% ^
        uvicorn dev:app --host=0.0.0.0 --port=80
    goto end
)


rem dev.cmd dev (/dir)/file.sql
rem
if [%arg1%]==[watch] (
    goto watch
)
if [%arg1%]==[test-sql] (
    goto test-sql
)
if [%arg1%]==[install-setup-py] (
    goto install-setup-py
)

@echo nothing to-do
goto end


:watch
    @echo.
    @echo -- watching %arg2%

    for /f "tokens=* delims=/" %%a in ("%arg2%") do call set "lastname=%%~nxa"
    set filename=%lastname%
    call set dirname=%%arg2:%lastname%=%%

    set "cmd=dev.cmd test-sql %arg2%"
    set "ext=sql"
    set "ignore="

    set "pathname=%dirname:/=\%"

    if exist %PGDEV_WORKDIR%\%pathname%setup.py (
        @echo -- watching %pathname%setup.py
        set "cmd=dev.cmd install-setup-py %arg2% && %cmd%"
        set "ext=sql,py"
        set "ignore=-i %dirname%build -i %dirname%dist -i %dirname%*.egg_info"
    )

    @echo (Press CTRL+C to quit)
    @echo.
    nodemon -e %ext% %ignore% -x "%cmd%"
    goto end


:test-sql
    @echo.
    for /f "tokens=* delims=/" %%a in ("%arg2%") do call set "lastname=%%~nxa"
    set filename=%lastname%
    call set dirname=%%arg2:%lastname%=%%

    @echo.
    @echo -- testing %dirname%%filename%
    docker exec -t -w /work/%dirname% ^
        %PGDEV_NAME% ^
        psql -P pager=off --quiet -v -v ON_ERROR_STOP=1 ^
        -U postgres -d postgres ^
        -f /dev.sql ^
        -v test_file=%filename%
    goto end


:install-setup-py
    for /f "tokens=* delims=/" %%a in ("%arg2%") do call set "lastname=%%~nxa"
    set filename=%lastname%
    call set dirname=%%arg2:%lastname%=%%

    @echo.
    @echo -- installing %dirname%setup.py
    docker exec -t -w /work/%dirname% ^
        %PGDEV_NAME% ^
        python3 setup.py -q install
    goto end


:end
endlocal