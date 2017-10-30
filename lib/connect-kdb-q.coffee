{CompositeDisposable, TextEditor} = require 'atom'

module.exports = ConnectKdbQ =
  subscriptions: null

  config:
    QueryResultsPosition:
      default: 'bottom'
      type: 'string'
      enum: ['right','left','bottom','top']
    ResultFontSize:
      default: 11
      type: 'integer'
      minimum: 5
      maximum: 20
      title: 'Result view font size'
    maxResults:
      default: 10
      minimum: 1
      type: 'integer'
      title: 'Maximum number of processed results to remember'
    maxFullResults:
      default: 2
      minimim: 1
      maximum: 10
      type: 'integer'
      title: 'Maximum number of raw result data to hold'
      description: 'Beware - raw query data may consume much memory, do not abuse this setting'
    showWidth:
      default: 150
      minimum: 20
      maximum: 2000
      type: 'integer'
      title: 'Chars per line to show'
    showHeight:
      default: 30
      minimum: 5
      maximum: 500
      type: 'integer'
      title: 'Lines per result to show'
    resultFmt:
      default: "INFO RES QUERY"
      type: "string"
      title: "What information to print for query results and in what order"
      description: "You can list any of INFO, RES, QUERY in any order and they will be printed accordingly in the result's window"
    limitResSize:
      default: 1024
      type: 'integer'
      title: 'Result size limit in Mbytes'
      description: 'Drop the result if its size is greater than this value'

  activate: (state) ->
    @subscriptions = new CompositeDisposable
    @servers = null
    @registerEvents()
    # TODO: change this if ever it becomes possible to publish branch deps
    atom.vue = require '../resources/vue.min' unless atom.vue

  deactivate: ->
    @subscriptions.dispose()
    @servers?.destroy()
    @minimap?.unregisterPlugin 'hide-query-view'
    @minimap = null
    @servers = @statusBar = @subscriptions = null

  serialize: ->

  registerEvents: ->
    @subscriptions.add atom.commands.add 'atom-workspace', 'connect-kdb-q:servers': (event) =>
      @setupServers()
      @servers.setConnection()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'connect-kdb-q:exec-line': (event) =>
      @setupExec()
      @exec.execLine()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'connect-kdb-q:exec-selection': (event) =>
      @setupExec()
      @exec.execSelect()
    @subscriptions.add atom.workspace.observeActivePaneItem (i) =>
      @servers.updateStatus() if @servers
      @hideMinimap(i) if i instanceof TextEditor

    @subscriptions.add atom.workspace.addOpener (uri) ->
      if uri is 'kdb://query.results'
        null
      null

  consumeStatusBar: (@statusBar) ->

  consumeMinimapServiceV1: (@minimap) ->
    @minimap.registerPlugin 'hide-query-view', this

  consumeCharts: (@charts) ->

  activatePlugin: ->
    return if @minimapActive
    @minimapActive = true

    for editor in atom.workspace.getTextEditors()
      @hideMinimap(editor)

  deactivatePlugin: -> @minimapActive = false

  isActive: -> @minimapActive

  hideMinimap: (editor) ->
    return unless @minimap and @minimapActive
    return unless uri = editor.getURI()
    if /kdb:/.test uri
      minimapElement = atom.views.getView @minimap.minimapForEditor editor
      if minimapElement?.offsetParent isnt null
        minimapElement?.detach()

  setupServers: ->
    if !@servers
      @servers = require('./servers').servers
      @servers.setStatusBar @statusBar

  setupExec: ->
    @setupServers()
    if !@exec
      @exec = require('./exec-query').exec
      @exec.init @servers
