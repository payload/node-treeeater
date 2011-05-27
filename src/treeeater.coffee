{ spawn } = require 'child_process'
BufferStream = require 'bufferstream'
EventEmitter = (require 'events').EventEmitter

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

    version: (cb) =>
        @spawn 'git', ['--version'], {}, cb

class Repo
    constructor: (args) ->
        { @path, @bare } = args if args
        @git = new Git

    commits: (options, cb) ->
        @git.commits options, cb

exports.Git = Git
exports.Repo = Repo

