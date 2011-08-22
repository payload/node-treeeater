{ spawn } = require 'child_process'
Stream = (require 'stream').Stream
BufferStream = require 'bufferstream'
#EventEmitter = (require 'events').EventEmitter
{ Stream } = require 'stream'
git_commands = (require './git-commands.js').commands
Path = require 'path'

# see NiceGit and Git below ^^

debug_log = (what...) ->
    console.log 'DEBUG:', (""+x for x in what).join(' ')

obj_merge = (objs...) ->
    o = {}
    for obj in objs
        for k,v of obj
            o[k] = v
    o

split_args_options_cb = (opts) =>
    # split into args, filtered options and a callback
    if typeof opts[-1..][0] is 'function'
        cb = opts.pop()
    args = []
    options = {}
    special = ['cwd', 'env', 'customFds', 'setsid', 'buffer', 'parser',
        'json', 'onstderr', 'onchild_exit']
    for x in opts
        if typeof x == 'object'
            filtered = {}
            for k, v of x
                if k in special
                    options[k] = v
                else
                    filtered[k] = v
            args.push filtered
        else args.push x
    { args, options, cb }

# these provides the git commands which you know from the cmd line
class RawGit
    commands: (cmd.replace /-/g, '_' for cmd in git_commands)

    # every git command is called like git.status args..., options
    constructor: () ->
        for func in @commands
            this[func] = do (func) => (args..., options) =>
                @spawn 'git', { c: 'color.ui=never' }, func.replace(/_/g, '-'),
                    args..., options

    # this is an internal and is used to convert every option you give to
    # a function into a command line option
    #
    # key: value → --key=value
    # key: null  → --key
    # if key is only one character
    # k: value   → -k value
    # k: null    → -k
    # if key is an empty string
    # '': null   → --
    obj2cmdline: (obj) =>
        args = []
        for k,v of obj
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

    args2cmdline: (args) =>
        cmdline = []
        for arg in args
            if typeof arg is 'object'
                cmdline = cmdline.concat @obj2cmdline(arg)
            else
                cmdline.push "#{arg}"
        cmdline

    # spawn             # mostly like child_process.spawn
    # command: string
    # args: [...]       # args which get translated to cmdline args
    # options: object   # holds special options for child_process.spawn#options
                        # and RawGit related special options
    spawn: (command, args..., options) =>
        # t0 = (new Date()).getTime()
        args = @args2cmdline args
        spawn_cmd = command+' '+args.join(' ')+'  #'+
            [" #{k}: #{v}" for k,v of options]
        debug_log 'spawn:', spawn_cmd
        buffer = new BufferStream size:'flexible'
        # spawn and pipe through BufferStream
        child = spawn command, args, options
        child.stdout.pipe buffer
        child.stderr.on 'data', options.onstderr or debug_log
        @exit_handling child, options
        buf = @output buffer, options
        #buf.on 'close', -> console.log((new Date()).getTime() - t0)
        buf

    exit_handling: (child, options) =>
        p = exiting: false
        onprocess_exit = ->
            p.exiting = true
            child.kill()
        process.once 'exit', onprocess_exit
        child.on 'exit', () ->
            process.removeListener 'exit', onprocess_exit
            delete child
            if !p.exiting
                options.onchild_exit?()

    # returns an event emitter which outputs via 'data'
    # * raw data       # Buffer
    # * parsed objects # parser specific type, if options.parser
    # * both as JSON   # String, if options.json
    # * JSON as Buffer # Buffer, if options.json and .buffered
    output: (buffer, options) =>
        { parser, json, buffered } = options
        parser = new Parsers[parser] if typeof parser is 'string'
        maybe_buffered = (x) => if buffered then new Buffer(x) else x
        ee = new Stream
        if parser
            buffer.on 'close', -> parser.end()
            parser.on 'item', (x) ->
                x = JSON.stringify(x) if json or buffered
                x = maybe_buffered x
                ee.emit 'data', x
            parser.on 'end', -> ee.emit 'end'
            buffer.split parser.splitter, (x,t) -> parser.chunk x
        else
            buffer.on 'data', (x) ->
                x = maybe_buffered '"'+x.toString()+'"' if json
                ee.emit 'data', x
            buffer.on 'end', -> ee.emit 'end'
            buffer.disable()
            buffer.setSize('none')
        ee

class NiceGit extends RawGit
    # version # returns the git version string
    # args... # git --version args...
    version: (args..., options) =>
        @spawn 'git', '--version', args..., options

    # commits             # serves commits as parsed from git log
    # args...             # git log args...
    commits: (args..., options) =>
        myargs =
            raw: null
            pretty: 'raw'
            numstat: null
            'no-color': null
            'no-abbrev': null
        @log args..., myargs, obj_merge(options, parser: 'commit')

    # tree                # args should contain a revision like HEAD
    # args...             # git ls-tree args...
    trees: (args..., options) =>
        @ls_tree '-l', '-r', '-t', args..., obj_merge(options, parser: 'tree')

    # tree_hierachy
    # transforms the output of @tree into a correct tree hierachy
    # * the returned tree and sub-trees are array-iterable to get inside objects
    # * the returned tree and sub-trees have .contents which
    #   map a basename to an object
    # * the returned tree has a .all which map the full paths of all objects
    #   and sub-objects to the object
    tree_hierachy: (trees) =>
        trees = trees[0..]
        path_tree_map = {}
        hierachy = []
        hierachy.contents = {}
        hierachy.all = {}
        n = trees.length * 2
        while trees.length
            obj = trees.pop()
            if obj.type == 'tree'
                # so you can array-iterate of a tree object to get its contents
                tree = []
                tree.contents = {}
                tree[k] = v for k, v of obj
                obj = tree
                # a tree is put into path_tree_map for easy lookup
                path_tree_map[tree.path] = tree
            # easy access to dir- and basename
            obj.dirname = Path.dirname obj.path
            obj.basename = Path.basename obj.path
            # easy lookup if you have the full path via .all
            hierachy.all[obj.path] = obj
            # push into root directory
            if obj.dirname == '.'
                hierachy.push obj
                hierachy.contents[obj.basename] = obj
            # push into some directory
            else if obj.dirname of path_tree_map
                dir = path_tree_map[obj.dirname]
                dir.push obj
                dir.contents[obj.basename] = obj
            # queue it back so the needed directory is there next time
            else trees = [obj].concat trees
            # if the needed directory is not there next time,
            # we are in an infinite loop, so we through an error after we have
            # seen too much ^^
            if !(n -= 1) and trees.length
                msg = "tree_hierachy: path '#{Path.dirname(trees[0].path)}' "+
                    "missing #{n} #{trees.length}"
                throw new Error msg
        hierachy

    # commit_tree_hierachy      # annotates blobs with corresponding commits
    #                             in a tree_hierachy INPLACE
    # tree_hierachy             # the return of tree_hierachy
    # args...                   # @commits args...
    commit_tree_hierachy: (tree_hierachy, args..., options) =>
        todo = 0
        blobs = {}
        for path, blob of tree_hierachy.all
            continue if blob.type != 'blob'
            blobs[path] = blob
            todo += 1
        ee = new Stream
        commits = @commits args..., options
        commits.on 'data', (commit) =>
            if todo
                for path of commit.changes
                    if path of blobs
                        blobs[path].commit = commit
                        ee.emit 'data', blobs[path]
                        delete blobs[path]
                        todo -= 1
        commits.on 'end', => ee.emit 'end'
        ee

    # cat               # cats the content of an blob as a Buffer
    # treeish           # a string which is a path, revision will be HEAD
    #                   # or a object of the form { revision: path }
    # args...           # git cat-file args...
    cat: (treeish, args..., options) =>
        if typeof treeish == 'string'
            path = treeish
            revision = 'HEAD'
        else for k, v of treeish
            path = v
            revision = k
        @cat_file '-p', args..., "#{revision}:#{path}",
            obj_merge(options)

    # diffs             # returns diff objects
    # args...           # git diff args...
    diffs: (args..., options) =>
        # TODO when the parser supports it: --full-index
        @diff { 'no-color': null }, args..., obj_merge(options, parser: 'diff')

class Git
    no_git: ['constructor', 'git_commands', 'tree_hierachy']

    # TODO öhm, bäh
    constructor: (@options) ->
        nice_git = new NiceGit
        @tree_hierachy = nice_git.tree_hierachy
        funcs = [].concat RawGit.commands
        for own k of nice_git
            funcs.push k unless k in @no_git
        @commands = [].concat funcs

        for func in funcs
            this[func] = do (func) => (opts...) =>
                { args, options, cb } = split_args_options_cb opts
                ee = nice_git[func](args..., obj_merge(@options, options))
                if cb
                    accu = []
                    ee.on 'data', (x) -> accu.push x
                    ee.on 'end', -> cb accu
                ee

# see CommitsParser to see an example of the usage
# a possible error in usage is a wrong regex at index 0 which results surely in
# a TypeError cause of setting a property of null
class ItemsParser extends Stream
    constructor: (@regexes = []) ->
        @item = null
        @splitter = '\n'
    end: () =>
        @emit 'item', @item unless @no_match
        @emit 'end'
    chunk: (line) =>
        line = "#{line}"
        return_item = null
        matched = false
        for [ regex, func ], i in @regexes
            match = line.match regex
            if match
                matched = true
                if i == 0
                    @emit 'item', @item if @item
                    @item = {}
                func.call this, match
        unless matched
            debug_log "ItemsParser.line - unknown line:", line

class CommitsParser extends ItemsParser
    constructor: () -> super regexes
    regexes = [
        [/^commit ([0-9a-z]+)/, (match) ->
            @item.sha = match[1]]
        [/^tree ([0-9a-z]+)/, (match) ->
            @item.tree = match[1]]
        [/^parent ([0-9a-z]+)/, (match) ->
            (@item.parents ?= []).push match[1]]
        [/^author (.+) (\S+) (\d+) (\S+)/, (match) ->
            # TODO take timezone into account
            [ _, name, email, secs, timezone ] = match
            date = new Date secs * 1000
            @item.author = { name, email, date }]
        [/^committer (.+) (\S+) (\d+) (\S+)/, (match) ->
            # TODO take timezone into account
            [ _, name, email, secs, timezone ] = match
            date = new Date secs * 1000
            @item.committer = { name, email, date }]
        [/^\s\s\s\s(.*)/, (match) ->
            @item.message = (@item.message or "") + match[1]
            @item.short_message = @item.message[...80]]
        [/^:(\S+) (\S+) ([0-9a-z]+) ([0-9a-z]+) (.+)\t(.+)/, (match) ->
            [ _, modea, modeb, shaa, shab, status, path ] = match
            (@item.changes ?= {})[path] = { modea, modeb, shaa, shab, status }]
        [/^([0-9-]+)\s+([0-9-]+)\s+(.+)/, (match) ->
            [ _, plus, minus, path ] = match
            (@item.numstats ?= {})[path] = { plus, minus }]
        [/^$/, ->]
    ]

class TreesParser extends ItemsParser
    constructor: () -> super regexes
    regexes = [
        [/^(\S+) (\S+) (\S+)\s+(\S+)\t(.+)/, (match) ->
            [ _, mode, type, sha, size, path ] = match
            @item = { mode, type, sha, size, path }]]

class DiffsParser extends ItemsParser
    constructor: () -> super regexes
    set_by_list: (names..., match) ->
        for name, i in names
            @item[name] = match[i] if name
    regexes = [
        [/^diff (.+) a\/(.+) b\/(.+)/, (match) ->
            @set_by_list null, 'type', 'src', 'dst', match]
        [/^@@ -(\d+),(\d+) \+(\d+),(\d+) @@ ?(.*)$/, (match) ->
            [ line, a_start, a_end, b_start, b_end, beginning ] = match
            head = { line, a_start, a_end, b_start, b_end, beginning }
            (@item.chunks ?= []).push { head, lines: [] }]
        [/^([ \-+])(.*)/, (match) ->
            line = type: match[1], line: match[2]
            # "?" is a fix for "+++"/"---" lines in the header
            @item.chunks?[-1..][0].lines.push line]
        [//, ->]
    ]

Parsers =
    item: ItemsParser
    commit: CommitsParser
    tree: TreesParser
    diff: DiffsParser

module.exports = { Git, RawGit, NiceGit }

