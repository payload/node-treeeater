treeeater = require 'treeeater'

assert_same = (a, b, msg) ->
    if a != b
        console.log "fail at #{msg} cause #{a} != #{b}"
    else console.log "#{msg} okay"

test_git = () ->
    n = 0
    repo = new treeeater.Repo
    result = {}
    check = ->
        if result.a and result.b
            assert_same result.a, result.b, 'serving and counting commits'
    commits = repo.commits (commits) ->
        result.a = commits.length
        check()
    commits.on 'commit', (commit) ->
        n += 1
    commits.on 'end', ->
        result.b = n
        check()

test_git()

