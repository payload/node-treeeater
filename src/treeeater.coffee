{ spawn } = require 'child_process'
BufferStream = require 'bufferstream'
EventEmitter = (require 'events').EventEmitter

debug_log = (what...) ->
    console.log.apply console.log, ['DEBUG:'].concat what

class CommitsParser
    re =
        commit   : /^commit ([0-9a-z]+)/
        tree     : /^tree ([0-9a-z]+)/
        parent   : /^parent ([0-9a-z]+)/
        author   : /^author (\S+) (\S+) (\d+) (\S+)/
        committer: /^committer (\S+) (\S+) (\d+) (\S+)/
        message  : /^\s\s\s\s(.*)/
        change   : /^:(\S+) (\S+) ([0-9a-z]+) ([0-9a-z]+) (.)\t(.+)/
        numstat  : /^([0-9-]+)\s+([0-9-]+)\s+(.+)/

    constructor: () -> @commit = null

    end: () => @commit

    line: (line) =>
        #debug_log "CommitsParser.line:", line
        ret = null
        if match = line.match re.commit
            ret = @commit
            @commit =
                parents : []
                message : []
                changes : {}
                numstats: {}
            @commit.commit = match[1]
        else if match = line.match re.tree
            @commit.tree = match[1]
        else if match = line.match re.parent
            @commit.parents.push match[1]
        else if match = line.match re.author
            [ _, name, email, time, timezone ] = match
            @commit.author = { name, email, time, timezone }
        else if match = line.match re.committer
            [ _, name, email, time, timezone ] = match
            @commit.committer = { name, email, time, timezone }
        else if match = line.match re.message
            @commit.message.push match[1]
        else if match = line.match re.change
            [ _, modea, modeb, hasha, hashb, change, path ] = match
            @commit.changes[path] = { modea, modeb, hasha, hashb, change }
        else if match = line.match re.numstat
            [ _, plus, minus, path ] = match
            @commit.numstats[path] = { plus, minus }
        else if line
            debug_log "CommitsParser.line - unknown line:", line
        ret

class Git
    # commits             # serves commits as parsed from git log
    # [options]: object
    # [cb]: ([object]) -> # gets all the commits
    # returns: EventEmitter commit: object, end
    commits: (options, cb) =>
        options or= {}
        if typeof options is 'function' and not cb?
            cb = options
            options = {}
        opts =
            raw: null
            pretty: 'raw'
            numstat: null
            'no-color': null
            'no-abbrev': null
        (opts[k]=v) for k, v of options
        @parsed_output 'commit', new CommitsParser, cb, => @call 'log', opts

    parsed_output: (name, parser, cb, call) =>
        ee = new EventEmitter
        lines = call()
        lines.on 'line', (l) ->
            item = parser.line l
            (ee.emit name, item) if item
        lines.on 'end', ->
            item = parser.end()
            (ee.emit name, item) if item
            ee.emit 'end'
        if cb
            items = []
            ee.on name, (item) -> items.push item
            ee.on 'end', -> cb items
        ee

    opts2args: (opts) =>
        args = for k,v of opts
            if k.length > 1
                if v != null
                    "--#{k}=#{v}"
                else
                    "--#{k}"
            else if k.length == 1
                if v != null
                    "-#{k} #{n}"
                else
                    "-#{k}"
            else "--"

    # call              # calls git
    # cmd: string       # which git command
    # [options]: object # which maps somehow to the shell or spawn options
    # [cb]: (string) -> # gets all the text
    # return: EventEmitter line: string, end
    call: (cmd, options, cb) =>
        # optional args
        options or= {}
        if typeof options is 'function' and not cb?
            cb = options
            options = {}
        args = [cmd].concat @opts2args(options)
        @spawn 'git', args, cb

    # spawn             # mostly like child_process.spawn
    # command: string
    # args: [string]
    # [options]: string
    # [cb]: (string) -> # gets all the text
    # returns: EventEmitter line: string, end
    spawn: (command, args, options, cb) =>
        # optional args
        options or= {}
        if typeof options == 'function'
            cb = options
            options = {}
        # spawn and pipe through BufferStream
        buffer = new BufferStream
        debug_log 'spawn:', command, args
        child = spawn command, args, options
        child.stderr.on 'data', debug_log
        process.once 'exit', child.kill
        child.on 'exit', () ->
            process.removeListener 'exit', child.kill
            delete child
        child.stdout.pipe buffer
        # output via EventEmitter
        ee = new EventEmitter
        buffer.split '\n', (l,t) -> ee.emit 'line', "#{l}"
        buffer.on 'end', -> ee.emit 'end'
        # optional output via callback
        if cb
            text = []
            ee.on 'line', (l) -> text.push l
            ee.on 'end', -> cb text.join("\n")
        ee

class Repo
    constructor: (args) ->
        { @path, @bare } = args if args
        @git = new Git

    commits: (options, cb) ->
        @git.commits options, cb

exports.Git = Git
exports.Repo = Repo

