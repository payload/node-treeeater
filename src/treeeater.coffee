{ spawn } = require 'child_process'
BufferStream = require 'bufferstream'
EventEmitter = (require 'events').EventEmitter
git_commands = (require 'git-commands').commands
Path = require 'path'

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
    constructor: () -> @regexes = regexes
    regexes = [
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
        [/^:(\S+) (\S+) ([0-9a-z]+) ([0-9a-z]+) (.+)\t(.+)/, (match) ->
            [ _, modea, modeb, shaa, shab, status, path ] = match
            (@item.changes ?= {})[path] = { modea, modeb, shaa, shab, status }]
        [/^([0-9-]+)\s+([0-9-]+)\s+(.+)/, (match) ->
            [ _, plus, minus, path ] = match
            (@item.numstats ?= {})[path] = { plus, minus }]
        [/^$/, ->]
    ]

class TreeParser extends ItemsParser
    constructor: () -> @regexes = regexes
    regexes = [
        [/^(\S+) (\S+) (\S+)\s+(\S+)\s+(.+)/, (match) ->
            [ _, mode, type, sha, size, path ] = match
            @item = { mode, type, sha, size, path }]]

class DiffsParser extends ItemsParser
    constructor: () -> @regexes = regexes
    set_by_list: (names..., match) ->
        for name, i in names
            @item[name] = match[i] if name
    regexes = [
        [/^diff (.+) a\/(.+) b\/(.+)/, (match) ->
            @set_by_list null, 'type', 'src', 'dst', match]
        [/^@.*/, (match) ->
            (@item.chunks ?= []).push { head: match[0], lines: [] }]
        [/^[ -+](.*)/, (match) ->
            # "?" is a fix for "+++"/"---" lines in the header
            @item.chunks?[-1..][0].lines.push match[1]]
        [//, ->]
    ]

class Git
    constructor: (@opts...) ->
        for cmd in git_commands
            func = cmd.replace /-/g, '_'
            this[func] = ((cmd) => (opts..., cb) =>
                [opts, cb] = @opts_cb opts, cb
                @spawn 'git', c: 'color.ui=never', cmd, opts, cb)(cmd)

    parsed_output: (name, parser, cb, call) =>
        ee = new EventEmitter
        lines = call()
        lines.on 'line', (l) ->
            item = parser.line l
            (ee.emit name, item) if item
        lines.on 'close', ->
            item = parser.end()
            (ee.emit name, item) if item
            ee.emit 'close'
        if cb
            items = []
            ee.on name, (item) -> items.push item
            ee.on 'close', -> cb items
        ee

    opts2args: (opts) =>
        args = []
        for k,v of opts
            if k.length > 1
                if v != null
                    args.push "--#{k}=#{v}"
                else
                    args.push "--#{k}"
            else if k.length == 1
                if v != null
                    args.push "-#{k}"
                    args.push "#{v}"
                else
                    args.push "-#{k}"
            else args.push "--"
        args

    # spawn             # mostly like child_process.spawn
    # command: string
    # opts: [...]       # command options and special options like
                        # documented in child_process.spawn#options
                        # or { chunked: true } to disable line splits
    # [cb]: (string) -> # gets all the text
    # returns: EventEmitter line: string, end
    spawn: (command, opts..., cb) =>
        [opts, cb] = @opts_cb opts, cb
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
                # the options filter for special options (below is here)
                for k in ['cwd', 'env', 'customFds', 'setsid', 'chunked']
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
        # output
        if options.chunked
            if cb
                buffer.on 'close', () -> cb buffer.buffer
            else
                buffer.disable()
        else
            if cb
                buffer.on 'close', () -> cb buffer.buffer.toString()
            else
                buffer.split '\n', (l,t) -> buffer.emit 'line', l.toString()
        buffer

    opts_cb: (opts, cb) =>
        opts = @opts[0..].concat(opts or [])
        if typeof cb != 'function'
            opts.push cb
            cb = undefined
        [opts, cb]

    version: (opts..., cb) =>
        [opts, cb] = @opts_cb opts, cb
        @spawn 'git', '--version', opts, cb

    # commits             # serves commits as parsed from git log
    # [cb]: ([object]) -> # gets all the commits
    # returns: EventEmitter commit: object, end
    commits: (opts..., cb) =>
        [opts, cb] = @opts_cb opts, cb
        @parsed_output 'commit', new CommitsParser, cb, =>
            @log opts,
                raw: null
                pretty: 'raw'
                numstat: null
                'no-color': null
                'no-abbrev': null

    # tree # opts should contain a revision like HEAD
    # [cb]: ([object]) -> # gets all the tree objects
    # returns: EventEmitter tree: object, end
    tree: (opts..., cb) =>
        [opts, cb] = @opts_cb opts, cb
        @parsed_output 'tree', new TreeParser, cb, =>
            @ls_tree '-l', '-r', '-t', opts

    # tree_hierachy
    # transforms the output of @tree into a correct tree hierachy
    tree_hierachy: (trees) =>
        trees = trees[0..]
        path_tree_map = {}
        hierachy = []
        n = trees.length * 2
        while trees.length
            obj = trees.pop()
            if obj.type == 'tree'
                # so you can array-iterate of a tree object to get its contents
                tree = []
                tree[k] = v for k, v of obj
                obj = tree
                # a tree is put into path_tree_map for easy lookup
                path_tree_map[tree.path] = tree
            dirname = Path.dirname obj.path
            if dirname == '.' # push into root directory
                hierachy.push obj
            else if dirname of path_tree_map # push into some directory
                path_tree_map[dirname].push obj
            else # queue it back so the needed directory is there next time
                trees = [obj].concat trees
            # if the needed directory is not there next time,
            # we are in an infinite loop, so we through an error after we have
            # seen too much ^^
            if !(n -= 1) and trees.length
                throw "#{Path.dirname(trees[0].path)} missing #{n} #{trees.length}"
        hierachy

    # cat                # cats the content of an blob as a Buffer
    # path: string
    # [revision]: string # defaults to HEAD
    cat: (treeish, opts..., cb) =>
        if typeof treeish == 'string'
            path = treeish
            revision = 'HEAD'
        else for k, v of treeish
            path = v
            revision = k
        [ opts, cb ] = @opts_cb opts, cb
        @cat_file '-p', "#{revision}:#{path}", chunked: true, cb

    diffs: (opts..., cb) =>
        [opts, cb] = @opts_cb opts, cb
        @parsed_output 'diff', new DiffsParser, cb, =>
            # TODO when the parser supports it: --full-index
            @diff 'no-color': null, opts

module.exports = Git

