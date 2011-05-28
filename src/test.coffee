Git = require 'treeeater'

# i know my tests are no tests. nor good, not complete neither helpfull :P

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
    commits.on 'close', ->
        result.b = n
        check()

test_tree = () ->
    git = new Git cwd: '../..' # TODO path to a test repo
    git.tree 'HEAD', (trees) ->
        git.tree_hierachy(trees) # TODO not really a test ^^
        console.log "tree hierachy okay"

test_cat = () ->
    git = new Git cwd: '../..'
    git.cat 'package.json', (blob) ->
        return console.log "cat okay" if blob.length
        console.log "fail at cat cause no content"

test_diffs = () ->
    git = new Git cwd: '../..'
    git.diffs 'HEAD^..HEAD', (diffs) ->
        return console.log "diffs okay" if diffs.length
        console.log "fail at diffs cause no elements"

test_commits()
test_tree()
test_cat()
test_diffs()

