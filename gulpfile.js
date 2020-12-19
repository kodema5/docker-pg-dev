let path = require('path')
let fs = require('fs')
let { series, watch } = require('gulp')


// command line arguments ex: dev [cmd] --foo --bar=123
// argv = ['--foo', '--bar=123']
// Argv = {foo:true, bar:123}
let yargs = require('yargs/yargs')
const { hideBin } = require('yargs/helpers')
const argv = (() => {
    let arr = hideBin(process.argv)

    let n = arr.findIndex(function (t) {
        if (this.skipNext) {
            this.skipNext = false
            return false
        }
        let isFlag = t[0]=='-'
        let hasValue = t.indexOf('=')>=0
        this.skipNext = isFlag && !hasValue
        return !isFlag
    }, {
        skipNext:false
    })
    return arr.slice(n+1)
})();
const Argv = yargs(argv).parse()

// caller dir, /foo> .../dev  -> '/foo'
const initCwd = process.env.INIT_CWD

const rootCwd = path.join(__dirname, '..', '..')

// packs "a \n b \n c" to "a b c"
let packWords = (s) => s.replace(/\s+/g, ' ').trim()


let execSync = require('child_process').execSync
const exec = (s, opt={}) => {
    let o = Object.assign({}, {
        cwd: exports.initCwd,
        stdio:'inherit',
        encoding:'utf8',
    }, opt, {
        env: Object.assign(process.env, opt.env)
    })
    try {
        execSync(packWords(s),o)
    } catch(e) {
    }
}



let dockerImageName = 'pg-dev'
let pgName = process.env.POSTGRES_NAME || Argv.pg_name || 'pg-dev'
let pgUser = process.env.POSTGRES_USER || Argv.pg_user || 'postgres'
let pgPassword = process.env.POSTGRES_PASSWORD || Argv.pg_password || 'rei'

// pg-dev2 maps to 5433 and 8001
let defaultPortIndex = (() => {
    let a = pgName.replace('pg-dev','').match(/^\d$/g)
    return a && (parseInt(a[0]) - 1) || 0
})()

let pgPort = process.env.PGDEV_PORT || Argv.pg_port|| (5432 + defaultPortIndex)
let httpPort = process.env.PGDEV_HTTP_PORT || Argv.pg_http_port || (8000 + defaultPortIndex)

exports.docker_build = (cb) => {
    exec(`docker build -t ${dockerImageName} .`)
    exec(`docker system prune -f`)
    cb()
}

exports.docker_start = (cb) => {
    let cd = initCwd
    let dd = path.join(cd, '.data', pgName)

    exec(`
    docker run --rm -d
        -p ${pgPort}:5432
        -p ${httpPort}:80
        -v ${cd}:/work
        -v ${dd}:/var/lib/postgresql/data
        --name ${pgName}
        -e POSTGRES_PASSWORD=${pgPassword}
        ${dockerImageName}
        -c shared_preload_libraries=pg_cron,pg_partman_bgw
        -c cron.database_name=${pgUser}
        -c cron.pg_partman_bgw.dbname=${pgUser}
    `)
    cb()
}

exports.docker_stop = (cb) => {
    exec(`
    docker exec -it
        ${pgName}
        su - postgres
        -c "/usr/lib/postgresql/12/bin/pg_ctl -D /var/lib/postgresql/data stop -m fast"
    `)
    // exec(`docker stop ${pgName}`)
    cb()
}

exports.bash = (cb) => {
    exec(`docker exec -it ${pgName} bash ${argv}`)
    cb()
}

// gulp --silent migra ^
// --from postgresql://postgres:rei@host.docker.internal:5433/postgres ^
// --to postgresql://postgres:rei@0.0.0.0:5432/postgres
exports.migra = (cb) => {
    let fromDb = Argv.from
    let toDb = Argv.to || `postgresql://${pgUser}:${pgPassword}@0.0.0.0:${pgPort}/${pgUser}`
    try { exec(`docker exec -it ${pgName} migra --unsafe ${fromDb} ${toDb}`) } catch(e) {}
    cb()
}


exports.multicorn = (cb) => {
    let file = Argv.file
    let p = path.resolve(initCwd, file)
    let s = fs.lstatSync(p)
    let isDir = s.isDirectory()
    let f = isDir ? 'setup.py' : path.basename(p)
    let d = isDir ? file : path.dirname(p)

    let notFound = !fs.existsSync(path.resolve(initCwd, d, f))
        || path.extname(f)!=='.py'
    if (notFound) {
        cb()
        return
    }

    let wd = path.relative(initCwd, d)
        .split(path.sep)
        .join('/')
    exec(`
        docker exec -t -w /tmp ${pgName}
        python3 /work/${wd}/${f}
        clean --all install clean --all
    `)
    cb()
}


exports.psql = (cb) => {
    exec(`docker exec -it ${pgName} psql -U ${pgUser} -d ${pgUser} ${argv}`)
    cb()
}

exports.python = (cb) => {
    exec(`docker exec -it ${pgName} python3 ${argv} `)
    cb()
}

exports.test = (cb) => {
    let file = Argv.file
    let p = path.resolve(initCwd, file)
    let s = fs.lstatSync(p)
    let isDir = s.isDirectory()
    let f = isDir ? 'index.sql' : path.basename(p)
    let d = isDir ? file : path.dirname(p)

    let wd = path.relative(initCwd, d)
        .split(path.sep)
        .join('/')

    exec(`
        docker exec -t -w /work/${wd} ${pgName}
        psql -P pager=off --quiet -v -v ON_ERROR_STOP=1
        -U postgres -d postgres ^
        -f /dev.sql ^
        -v test_file=${f}
    `)
    cb()
}

exports.uvicorn = (cb) => {
    exec(`docker exec -it -w / ${pgName} uvicorn dev:app --host=0.0.0.0 --port=${httpPort}`)
    cb()
}

exports.watch = (cb) => {
    let file = Argv.file || '.'
    let p = path.resolve(initCwd, file)
    let s = fs.lstatSync(p)
    let isDir = s.isDirectory()
    let d = isDir ? file : path.dirname(p)

    let wd = path.relative(initCwd, d)
        .split(path.sep)
        .join('/')
    watch(['*.sql', '*.py'], {
        cwd:d
    }, series('test', 'multicorn'))
    cb()
}


exports.default = (cb) => {
    console.log(`pg-dev

for pg and python development

test         - test --file for testing a file
multicorn    - builds multicorn module --file
watch        - watch --file for test and multicorn
migra        - migra --from for migration script
uvicorn      - maps /api/[schema.fn] see dev.py

docker
docker_build - builds pg-dev docker image
docker_start - starts pg-dev instance
docker_stop  - stops pd-dev instance

utils
bash         - bash shell
psql         - psql
python       - python3
    `)
    cb()
}