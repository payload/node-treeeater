{ spawn } = require 'child_process'
BufferStream = require 'bufferstream'

debug_log = (what) ->
    console.log 'DEBUG:', "#{what}"

class Git
    call: (command, args, options..., cb) =>
        # cb = (line) ->
        buffer = new BufferStream
        child = spawn command, args, options[0] or {}
        child.stderr.on 'data', debug_log
        process.once 'exit', child.kill
        child.on 'exit', () ->
            process.removeListener 'exit', child.kill
            delete child
        child.stdout.pipe buffer
        buffer.split '\n', (l,t) -> cb "#{l}"

class Repo
    constructor: (@path) ->

exports.Git = Git

