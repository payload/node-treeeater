{ spawn } = require 'child_process'
BufferStream = require 'bufferstream'
EventEmitter = (require 'events').EventEmitter
git_commands = (require 'git-commands').commands

debug_log = (what...) ->
    console.log.apply console.log, ['DEBUG:'].concat (""+x for x in what)

# see CommitsParser to see an example of the usage
# a possible error in usage is a wrong regex at index 0 which results surely in
# a TypeError cause of setting a property of null
class ItemsParser
    constructor: (@regexes) ->
        @item = null
    end: () => @item unless @no_match
    line: (line) =>
        return_item = null
        matched = false
        for [ regex, func ], i in @regexes
            match = line.match regex
            if match
                matched = true
                if i == 0
                    return_item = @item
                    @item = {}
                func.call this, match
        unless matched
            debug_log "ItemsParser.line - unknown line:", line
        return_item

class CommitsParser extends ItemsParser
    constructor: ->
        super [
            [/^commit ([0-9a-z]+)/, (match) ->
                @item.commit = match[1]]
            [/^tree ([0-9a-z]+)/, (match) ->
                @item.tree = match[1]]
            [/^parent ([0-9a-z]+)/, (match) ->
                (@item.parents ?= []).push match[1]]
            [/^author (\S+) (\S+) (\d+) (\S+)/, (match) ->
                [ _, name, email, time, timezone ] = match
                @item.author = { name, email, time, timezone }]
            [/^committer (\S+) (\S+) (\d+) (\S+)/, (match) ->
                [ _, name, email, time, timezone ] = match
                @item.committer = { name, email, time, timezone }]
            [/^\s\s\s\s(.*)/, (match) ->
                (@item.message ?= []).push match[1]]
            [/^:(\S+) (\S+) ([0-9a-z]+) ([0-9a-z]+) (.)\t(.+)/, (match) ->
                [ _, modea, modeb, hasha, hashb, change, path ] = match
                (@item.changes ?= {})[path] = { modea, modeb, hasha, hashb, change }]
            [/^([0-9-]+)\s+([0-9-]+)\s+(.+)/, (match) ->
                [ _, plus, minus, path ] = match
                (@item.numstats ?= {})[path] = { plus, minus }]
            [/^$/, ->]
        ]


class Git
    constructor: () ->
        for cmd in git_commands
            this[cmd] = ((cmd) => (opts..., cb) =>
                @spawn 'git', cmd, opts, cb)(cmd)

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

    # spawn             # mostly like child_process.spawn
    # command: string
    # args: [string]
    # [options]: string
    # [cb]: (string) -> # gets all the text
    # returns: EventEmitter line: string, end
    spawn: (command, opts..., cb) =>
        # optional args
        if typeof cb != 'function'
            opts.push cb
            cb = undefined
        # split into args and filtered options
        args = []
        options = {}
        i = 0 # i am pushing stuff into opts inside the loop, thats why i need i
        while i < opts.length
            arg = opts[i]
            # to mix single strings and arrays in the arguments
            if Array.isArray(arg)
                opts.push.apply opts, arg # thats the pushing i is needed for
            else if typeof arg == 'object'
                # the options filter
                for k in ['cwd', 'env', 'customFds', 'setsid']
                    if arg[k]
                        options[k] = arg[k]
                        delete arg[k]
                args = args.concat @opts2args(arg)
            else if typeof arg is 'string'
                args.push arg
            else unless typeof arg is 'undefined'
                throw Error "wrong arg #{arg} in opts"
            i++
        # spawn and pipe through BufferStream
        buffer = new BufferStream
        debug_log 'spawn:',
            command+' '+args.join(' '),
            ["#{k}: #{v}" for k,v of options]
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

    version: (opts..., cb) =>
        @spawn 'git', '--version', opts, cb

    # commits             # serves commits as parsed from git log
    # [options]: object
    # [cb]: ([object]) -> # gets all the commits
    # returns: EventEmitter commit: object, end
    commits: (opts..., cb) =>
        console.log opts, cb
        if typeof cb != 'function'
            opts.push cb
            cb = undefined
        (opts ?= []).push
            raw: null
            pretty: 'raw'
            numstat: null
            'no-color': null
            'no-abbrev': null
        @parsed_output 'commit', new CommitsParser, cb, => @log opts

class Repo
    constructor: (args) ->
        { @path, @bare } = args if args
        @git = new Git

    commits: (opts..., cb) ->
        @git.commits opts, cb

exports.Git = Git
exports.Repo = Repo

