{ spawn } = require 'child_process'
BufferStream = require 'bufferstream'

debug_log = (what) ->
    console.log 'DEBUG:', "#{what}"

class CommitsParser
    re =
        commit   : /commit ([0-9a-z]+)/
        tree     : /tree ([0-9a-z]+)/
        parent   : /parent ([0-9a-z]+)/
        author   : /author (\S+) (\S+) (\d+) (\S+)/
        committer: /committer (\S+) (\S+) (\d+) (\S+)/
        message  : /\s\s\s\s(.*)/
        change   : /:(\S+) (\S+) ([0-9a-z]+) ([0-9a-z]+) (.)\t(.+)/
        numstat  : /([0-9-]+)\s+([0-9-]+)\s+(.+)/

    constructor: (@oncommit) ->
        @commit = null

    line: (line, end) =>
        return @oncommit?(@commit) if end and @commit != null
        if match = line.match re.commit
            @oncommit?(@commit) if @commit != null
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
            debug_log line

class Git
    commits: (options, cb) =>
        # cb = (commit) ->
        if typeof options is 'function' and not cb?
            cb = options
            options = {}
        opts =
            raw: null
            pretty: 'raw'
            numstat: null
            'no-abbrev': null
        (opts[k]=v) for k, v of options
        @log opts, new CommitsParser(cb).line

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

    log: (options, cb) =>
        # cb = (line) ->
        if typeof options is 'function' and not cb?
            cb = options
            options = {}
        args = 'log --no-color'.split(' ').concat @opts2args(options)
        @call 'git', args, cb

    call: (command, args, options..., cb) =>
        # cb = (line, end) ->
        buffer = new BufferStream
        child = spawn command, args, options[0] or {}
        child.stderr.on 'data', debug_log
        process.once 'exit', child.kill
        child.on 'exit', () ->
            process.removeListener 'exit', child.kill
            delete child
        child.stdout.pipe buffer
        buffer.split '\n', (l,t) ->
            cb "#{l}", false
        buffer.on 'end', -> cb null, true

class Repo
    constructor: (@path) ->

exports.Git = Git

