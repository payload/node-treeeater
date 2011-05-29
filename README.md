# treeeater

* trees are a treat for treeeater
* use it to call [git](http://git-scm.com) commands in [Node](http://nodejs.org)
* it is written in [CoffeeScript](http://jashkenas.github.com/coffee-script/) and is heavily using its sweet syntactic sugar
* http://flattr.com - yes, you can give me money :P

## principle

* an asynchronous wrapper around git spawning commands
* use `git help` to find out how to get things done
* specify command line options in an readable and easy way in Coffee Script
* some output is being parsed into objects which actually make some sense!

## usage in Coffee Script

  * provide a callback to get the whole output

        git.version console.log
        # git version 1.7.5.2

  * or listen on _item_ or _data_ events to get it line-, item- or chunkwise

        n = 0
        buffer = git.log()
        buffer.on 'item', (line) -> console.log "#{n += 1}:", line

        buffer = git.cat 'package.json', 'HEAD^'
        file = fs.createWriteStream("package.json.bak")
        file.on 'open', -> buffer.pipe file

  * put command line arguments as `key: value` pairs or strings into your call

        Git = require 'treeeater'
        # an option on construction is default for all calls
        git = new Git cwd: 'parrot'
        # ~/parrot$ git log -1 --pretty=raw HEAD^^
        log = git.log 1:null, pretty:'raw', 'HEAD^^'
        log.on 'item', do_something_with_it
        # change current working directory, which must exist
        git.opts.cwd = 'dead'
        # git init --bare -L .
        git.init bare:null, L:'.'

  * some functions are not named after git commands and provide some parsed
    output

        n = 0
        commits = git.commits()
        commits.on 'item', (commit) ->
            if my_email is commit.author.email
                n += 1
        commits.on 'close', ->
            console.log "I've authored #{n} commits!"

        git.tree 'HEAD', (trees) ->
            coffee = []
            tree = git.tree_hierachy(trees)
            for stuff in tree
                if stuff.type == 'tree'
                    for more_stuff in stuff
                        if '.coffee' in more_stuff.path
                            coffee.push more_stuff
            console.log "#{coffe.length} coffee files in level 1 subfolders"

