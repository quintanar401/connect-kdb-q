C = require './c'

class Servers
  constructor: ->
    @srvView = null; @barView = @pendingQuery = null
    @srvs = []; @tags = {}; @srvMap = {}
    @init(); @currSrv = -1

  setConnection: () ->
    try
      if !@srvView
        view = require './servers-view'
        @srvView = new view()
        @srvView.init this
      @srvView.show()
    catch err
      console.error err

  init: ->
    path = require 'path'
    fs = require 'fs'
    srvs = []
    @srvFilePath = path.join atom.config.configDirPath, 'qservers.json'
    @srvFilePathUser = path.join atom.config.configDirPath, 'qservers_user.json'
    if fs.existsSync @srvFilePathUser
      @initSrvs fs.readFileSync @srvFilePathUser
    else
      console.log "Use #{@srvFilePathUser} file to set your servers."
    if fs.existsSync @srvFilePath
      @initSrvs fs.readFileSync @srvFilePath
    else
      console.log "Use #{@srvFilePath} file to set global servers."

  initSrvs: (file) ->
    try
      ctx = JSON.parse file
      for n,v of ctx
        v = v.split ' ' if typeof v is 'string'
        if n is "servers"
          @updSrv i for i in v
        else if v instanceof Array
          @tags[n] = v
        else
          console.error "JSON config file has an incorrect entry " + n
    catch error
      console.error "Couldn't load the config file: " + error

  updSrv: (cfg) ->
    throw "port is not defined: " + JSON.stringify cfg unless cfg.port
    cfg.tags = cfg.tags.split ' ' if cfg.tags and typeof cfg.tags is 'string'
    cfg.host ?= 'localhost'
    cfg.name ?= cfg.tags.join('-') if cfg.tags
    cfg.name ?= cfg.host + ":" + cfg.port
    cfg.uname ?=  ""
    cfg.pass ?= ""
    cfg.handle = null
    cfg.lastErr = ""
    cfg.inProgress = false
    @srvs.push cfg

  getEditorPath: ->
    return null unless editor = atom.workspace.getActiveTextEditor()
    return null unless editor.getGrammar().scopeName is "source.q"
    editor.getPath() || 'undefined'

  isConnected: ->
    return false if @currSrv is -1 or !@srvs[@currSrv].handle or @srvs[@currSrv].handle.status() isnt 'conn'
    true

  # cb from servers-view
  srvViewCallback: (srvId) ->
    return unless srvId?
    if typeof srvId is 'string'
      srv = srvId.split ':'
      return if srv.length < 2
      @srvs.push name: srvId, host: srv[0] || 'localhost', port: Number(srv[1]), uname: srv[2] || '', pass: srv[3] || '', handle: null, lastErr: '', inProgress: false
      srvId = @srvs.length - 1
      @srvView.addSrv srvId
    @pendingQuery.currSrv = srvId if @pendingQuery
    @srvMap[path] = srvId if path = @getEditorPath()
    @connectToSrv srvId

  connectToSrv: (srvId) ->
    return unless srvId?
    @currSrv = srvId; srv = @srvs[srvId]
    if srv.handle?.status() is 'conn'
      @barView.update()
      return
    srv.inProgress = true
    @barView.update()
    srv.handle?.clearEvents()
    srv.handle = null
    C.C.connect srv, (err,res) => @onConnect(srvId,err,res)

  onConnect: (srvId, err, res) ->
    srv = @srvs[srvId]
    srv.inProgress = false; srv.lastErr = null
    if err
      srv.lastErr = err
    else
      srv.handle = res
      srv.handle.on 'down', (err) =>
        @onDisconnect srvId, err
      @srvView.updateOnline srvId, true
    @barView.update()

    q = @pendingQuery
    if q and q.currSrv is srvId
      if err and q.cnt is 0
        q.cnt++
        @setConnection()
      else if err
        @pendingQuery = null
        q.cb err
      else
        @pendingQuery = null
        @send q.msg, q.cb

  onDisconnect: (srvId, err) ->
    srv = @srvs[srvId]
    srv.lastErr = err
    srv.inProgress = false
    @pendingQuery = null if @pendingQuery?.srvId is srvId
    srv.handle?.clearEvents()
    srv.handle = null
    @barView.update()
    @srvView.updateOnline srvId, false
    atom.notifications.addError "Server #{srv.name} has disconnected"

  setStatusBar: (statusBar) ->
    if !@statusBarTile
      view = require './bar-view'
      @barView = new view()
      @barView.init this
      @statusBarTile = statusBar.addLeftTile item: @barView.getElement(), priority: 100

  updateStatus: () ->
    path = @getEditorPath()
    @currSrv = @srvMap[path] if path and @srvMap[path]
    @barView?.update()

  send: (msg, cb) ->
    try
      if @isConnected()
        srv = @srvs[@currSrv]
        srv.inProgress = true
        @barView.update()
        srv.handle.sendSync msg, (err, res) =>
          @pendingQuery = null if @pendingQuery?.srvId is srv.srvId
          srv.inProgress = false
          @barView.update()
          res.srv = srv.name if res
          res = err: err, srv: srv.name if err
          cb err, res
      else
        # cnt = 0 means try to connect automatically, show srv view otherwise, 1 means stop
        @pendingQuery = {@currSrv, msg, cb, cnt: 0}
        if @currSrv is -1
          @pendingQuery.cnt++
          @setConnection()
        else
          @connectToSrv @currSrv
    catch err
      console.error err

  destroy: ->
    @srvView?.destroy()
    @statusBarTile?.destroy()
    @srvs = []; @tags = {}; @srvView = null; @srvMap = {}
    @statusBarTile = @pendingQuery = null

module.exports =
  servers: new Servers()
