C = require './c'

class Servers
  constructor: ->
    @srvView = null; @barView = @pendingQuery = null
    @srvs = []; @tagLists = []; @tags = {}; @srvMap = {}; @defUname = null; @defPass = null
    @init(); @currSrv = -1

  setConnection: ->
    try
      if !@srvView
        view = require './servers-view'
        @srvView = new view()
        @srvView.init this
      @srvView.show()
    catch err
      console.error err

  disconnect: ->
    return unless @isConnected()
    @srvs[@currSrv].handle.close()

  init: ->
    path = require 'path'
    fs = require 'fs'
    srvs = []
    @srvFilePath = path.join atom.getConfigDirPath(), 'qservers.json'
    @srvFilePathUser = path.join atom.getConfigDirPath(), 'qservers_user.json'
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
        if n is "servers"
          @updSrv i for i in v
        else if n is 'uname'
          @defUname ?= v
        else if n is 'pass'
          @defPass ?= v
        else
          v = v.split ' ' if typeof v is 'string'
          if v instanceof Array
            if /:list$/.test n
              n = n.slice 0, -5
              @tagLists.push n
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
    s = host: srv.host, port: srv.port, uname: srv.uname, pass: srv.pass, exclusive: false
    if !srv.uname
      s.uname = @defUname
      s.pass = @defPass
    C.C.connect s, (err,res) => @onConnect(srvId,err,res)

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
    query = @pendingQuery
    @pendingQuery = null if query?.currSrv is srvId
    srv.handle?.clearEvents()
    srv.handle = null
    @barView.update()
    @srvView.updateOnline srvId, false
    atom.notifications.addError "Server #{srv.name} has disconnected"
    @send query.msg, query.cb if query?.retry and query?.currSrv is srvId

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
        if srv.inProgress
          b = atom.confirm
            message: 'Abort the running query?'
            detailedMessage: 'Do you really want to disconnect from the current server and try to run the new query?'
            buttons: ['No','Yes']
          if srv.inProgress and b is 1
            @pendingQuery = {@currSrv, msg, cb, cnt: 0, retry: true}
            @disconnect()
            return
        srv.inProgress = true
        @barView.update()
        srv.handle.sendSync msg, (err, res) =>
          @pendingQuery = null if @pendingQuery?.currSrv is srv.srvId
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
    @srvs = []; @tagLists = []; @tags = {}; @srvView = null; @srvMap = {}
    @statusBarTile = @pendingQuery = @defUname = @defPass = null

module.exports =
  servers: new Servers()
