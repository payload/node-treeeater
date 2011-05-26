treeeater = require 'treeeater'

assert_same = (a, b, msg) ->
    if a != b
        console.log "fail at #{msg} cause #{a} != #{b}"
    else console.log "#{msg} okay"

test_git = () ->

    n = 0
    git = new treeeater.Git
    git.call 'git', ['log'], (line, end) ->
        return unless line
        n += line.split('\n').length - 1
    assert_same(n, 0, "line output")

    #git.commits (commit) -> console.log 1, commit

test_git()

