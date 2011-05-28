Git = (require 'treeeater').Git

assert_same = (a, b, msg) ->
    if a != b
        console.log "fail at #{msg} cause #{a} != #{b}"
    else console.log "#{msg} with a=#{a} and b=#{b} okay"

test_commits = () ->
    n = 0
    git = new Git cwd: '../..' # TODO path to a test repo
    result = {}
    check = ->
        if result.a and result.b
            assert_same result.a, result.b, 'serving and counting commits'
    commits = git.commits (commits) ->
        result.a = commits.length
        check()
    commits.on 'commit', (commit) ->
        n += 1
    commits.on 'end', ->
        result.b = n
        check()

test_tree = () ->
    git = new Git cwd: '../..' # TODO path to a test repo
    git.tree 'HEAD', (trees) ->
        git.tree_hierachy(trees) # TODO not really a test ^^

test_commits()
test_tree()

