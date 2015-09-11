{CompositeDisposable} = require 'atom'
# Vue = require 'vue'

barView = '''
  <div class='inline-block' v-show='isQEditor'>
    <div class='inline-block' v-class='text-highlight: status==="init", text-success: status==="ok", text-error: status==="fail"'
         style='margin-right: 4px'
         v-el='tool'
         v-on='click: onClick()'>
         {{name}} <span v-on='click: onCloseClick($event)' v-show="status === 'ok'" title="Disconnect" class="icon icon-x"></span>
    </div>
    <div class='inline-block' v-show='inProgress'>
      <progress class='inline-block q-progress'/>
      <span class='inline-block'>Indeterminate</span>
    </div>
  </div>
'''

srvUndef = isQEditor: false, inProgress: false, name:"", status: 'init'
srvDef = isQEditor: true, inProgress: false, name:"Disconnected", status: 'init'

module.exports =
class srvBarView
  constructor: ->
    @model = null
    @data = null
    @tool = ""
    @subscriptions = new CompositeDisposable

  init: (@model) ->
    @data = isQEditor: false, inProgress: false, name:"", status: ""
    @update()
    container = document.createElement 'div'
    @vm = new atom.vue data: @data, template: barView, el: container, methods:
        onClick: => @model.setConnection()
        onCloseClick: (e) => @model.disconnect(); e.stopPropagation()
    @subscriptions.add atom.tooltips.add @vm.$$.tool, title: => @tool

  update: ->
    data = null
    if path = @model.getEditorPath()
      if @model.currSrv is -1
        data = srvDef
        @tool = "Click to connect to a server"
      else
        srv = @model.srvs[@model.currSrv]
        name = srv.name
        status = if srv.handle
                  if srv.handle.status() is 'conn' then 'ok' else 'fail'
                else if srv.lastErr then 'fail' else 'init'
        if !srv.inProgress
          @tool = 'Server is ready to execute a new query'
          if srv.lastErr is 'closed'
            name = name + " : disconnected"
            @tool = "Server has disconnected. Click to connect to a server"
          else if err = srv.lastErr
            if typeof err is 'string'
              name = name + " : " + err
              @tool = "Error: " + err
            else
              name = name + " : " + if err?.code then err.code else if err?.message then err.message else 'exception'
              @tool = err.toString()
        else @tool = 'Connecting to the server...'
        data = isQEditor: true, name: name, inProgress: srv.inProgress, status: status
    else
      data = srvUndef
      @tool = ""
    for t,v of data
      @data[t] = v
    null

  getElement: -> @vm.$el

  destroy: ->
    @subscriptions?.dispose()
    @vm?.$destroy()
    @vm = @data = @model = null
