"use strict"
sass                = require("node-sass")
path                = require("path")
fs                  = require("fs")
_                   = require("underscore")
WebSocketClient     = require("websocket").client
spawn               = require("child_process").spawn
shell               = require("shelljs")

module.exports = (grunt) ->
  grunt.registerMultiTask "takana", "Compile SCSS to CSS", ->
    done = @async()

    options = @options(
      includePaths: []
      outputStyle: "nested"
    )

    register options, =>

      grunt.util.async.forEachSeries @files, ((el, next) ->
        sass.render
          file: el.src[0]
          success: (css) ->
            grunt.file.write el.dest, css
            next()

          error: (err) ->
            grunt.warn err

          includePaths: options.includePaths
          outputStyle:  options.outputStyle
      )

  # attempts to create a websocket connection
  connect = (cb) ->
    client = new WebSocketClient()

    client.on "connectFailed", (error) =>
      cb(error, null)

    client.on "connect", (connection) ->
      cb(null, connection)

    client.connect "ws://localhost:48626/control"

  # auto-retries and waits 5 seconds before timing out 
  waitForConnection = (cb) ->
    timeout = 5000
    timedOut = false

    failureTimeout = setTimeout ->
      timedOut = true
      cb(true, null)
    , timeout

    onConnect = (err, connection) ->
      if err && !timedOut
        setTimeout ->
          connect onConnect
        , 1000

      else 
        clearTimeout failureTimeout
        cb(null, connection)

    connect onConnect

  launchAndConnect = (cb) ->
    # try and connect once (Takana is already running)
    connect (err, connection) ->
      if err
        shell.exec("open -a Takana")
        waitForConnection cb
      else
        cb(err, connection)


  register = (options, cb) -> 
    supportDir = path.join(process.env.HOME, 'Library/Application Support/Takana/')

    if !(fs.existsSync(supportDir))
      grunt.log.error "Couldn't find Takana Mac app, is it installed?"
      return

    launchAndConnect (err, connection) ->
      if err
        cb()

      else if connection 
        name = path.basename(process.cwd())
        path = process.cwd()

        message = 
          event: 'project/add'
          data: 
            path: path
            name: name
            includePaths: options.includePaths.join(',')

        connection.send JSON.stringify(message)

        grunt.log.write "Syncing project..."

        message = 
          event: 'project/update'
          data: 
            name: name
            path: path
            includePaths: options.includePaths.join(',')

        connection.send JSON.stringify(message)

        connection.on "error", (error) ->
          grunt.error "Couldn't register project, connection failed", error
          connection.close()
          cb()

        connection.on "close", ->
          cb()

        connection.on "message", (message) ->
          grunt.log.ok()
          connection.close()
          cb()
  @