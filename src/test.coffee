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
    commits.on 'item', (commit) ->
        n += 1
    commits.on 'close', ->
        result.b = n
        check()

test_trees = () ->
    git = new Git cwd: '../..' # TODO path to a test repo
    git.trees 'HEAD', (trees) ->
        tree_h = git.tree_hierachy(trees) # TODO not really a test ^^
        n = 0
        for k of tree_h.all
            n += 1
        assert_same trees.length, n, 'tree hierachy'

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

test_commit_tree_hierachy = () ->
    git = new Git cwd: '../..'
    git.trees 'HEAD', (trees) ->
        todo = 0
        for blob in trees
            if blob.type == 'blob'
                todo += 1
        blobs = git.commit_tree_hierachy git.tree_hierachy(trees)
        blobs.on 'item', (blob) ->
            todo -= 1
        blobs.on 'close', ->
            assert_same todo, 0, 'commit tree hierachy'

test_commits()
test_trees()
test_cat()
test_diffs()
test_commit_tree_hierachy()

