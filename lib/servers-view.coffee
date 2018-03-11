# Vue = require 'vue'

selectSrvView = '''
  <atom-panel class='modal' v-on='keydown: onKey($event), mousedown: onMouseDown($event)'>
    <div class='block text-highlight' v-on='click: showTags = !showTags'>Tag filters</div>
    <table v-show='showTags'>
      <tr v-repeat='tag in tags'>
        <td><span style='margin-right: 5px'>{{tag.name}}:</span></td>
        <td>
          <div v-if='tag.ty === "btn"' class='inline-block btn-group'>
            <template v-repeat='it in tag.tags'>
              <button class='btn' v-class='selected : it.isSelected', v-on='click: onClick(it)'>{{it.val}}</button>
            </template>
          </div>
          <select v-if='tag.ty === "lst"'
                  class='q-select'
                  v-on='change: onChange(tag,$event)'
                  v-attr='value: tag.select'>
            <option v-repeat='it in tag.tags'>{{it}}</option>
          </select>
        </td>
      </tr>
    </table>
    <div>
      <label>
        <div class='text-subtle'>
          Enter the full server name with the optional user name and password or enter some tags and select the server from the list below.
        </div>
      </label>
    </div>
    <div class='select-list'>
      <atom-text-editor v-el='editor' mini placeholder-text='Enter server info'></atom-text-editor>
      <ol class='list-group' v-el='list'>
        <template v-repeat='srv in srvs'>
          <li class='two-lines'
              v-class='selected : srv.isSelected'
              v-show='srv.isVisible'
              v-on='click: onListClick(srv), dblclick: onListDblClick(srv)'>
            <div class='primary-line' v-class='text-success: srv.isOnline'>{{srv.title}}</div>
            <div class='secondary-line'>{{srv.desc}}</div>
          </li>
        </template>
      </ol>
    </div>
  </atom-panel>
 '''

module.exports =
class SrvView
  constructor: ->
    @model = null
    @panel = null

  init: (@model) ->
    container = document.createElement 'div'
    @data = srvs: @generateList(), tags: @generateTags(), showTags: false
    meths =
      onClick: (v) =>
        v.isSelected = !v.isSelected
        @filterSrvs()
      onKey: (e) =>
        if e.key is 'ArrowUp'
          @selectPrev()
          e.stopPropagation()
        else if e.key is 'ArrowDown'
          @selectNext()
          e.stopPropagation()
        else if e.key is 'Enter'
          @hide @getSrv()
          e.stopPropagation()
        else if  e.keyCode is 27
          @hide null
          e.stopPropagation()
      onListClick: (srv,e) =>
        return if srv.isSelected
        @clearSelect()
        srv.isSelected = true
      onListDblClick: (srv) =>
        @hide srv.idx
      onMouseDown: (e) =>
        if !(e.path[0].localName is 'select')
          e.preventDefault()
          @focus()
          false
      onChange: (tag, el) =>
        tag.select = el.srcElement.value
        @filterSrvs()
        @focus()
    @vm = new atom.vue data: @data, template: selectSrvView, el: container, methods: meths
    @panel = atom.workspace.addModalPanel(item: @getElement(), visible: false)
    @editor = @vm.$$.editor.getModel()
    @editor.getBuffer().onDidStopChanging =>
      @filterSrvs()

  generateList: -> @setSrv o,i for o,i in @model.srvs

  addSrv: (id) -> @data.srvs.unshift @setSrv @model.srvs[id], id

  setSrv: (o, id) ->
    el = title: o.name, isSelected: false, isVisible: true, idx: id, isOnline: false
    el.desc = o.host + ":" + o.port
    el.desc = el.desc + ":" + o.uname if o.uname
    el.desc = el.desc + ":<pass> " if o.uname and o.pass
    el.desc = el.desc + "[" + o.tags.join(' ') + "]" if o.tags
    el.str = el.title + " " + el.desc
    el

  generateTags: ->
    tags = []
    for t,v of @model.tags
      isLst = t in @model.tagLists
      tag = name: t, ty: (if isLst then 'lst' else 'btn')
      if isLst
        tag.tags = v
        tag.tags.unshift 'All'
      else
        tag.tags = v.map (i) ->
          isSelected: false, val: i
      tags.push tag
    hosts = []; ports = []
    for s in @model.srvs
      hosts.push s.host unless s.host in hosts
      ports.push s.port unless s.port in ports
    ports = (ports.sort((a,b)->a>b)).map (e) -> e.toString()
    hosts = hosts.sort()
    ports.unshift 'All'
    hosts.unshift 'All'
    tags.push name: "host", tags: hosts, ty: 'lst', select: 'All'
    tags.push name: "port", tags: ports, ty: 'lst', select: 'All'
    tags

  filterSrvs: ->
    patts = @collectTags().map (e) -> new RegExp e
    setSel = true
    for srv in @data.srvs
      srv.isVisible = patts.reduce ((s,p) -> s && p.test srv.str), true
      srv.isSelected = false
      if srv.isVisible and setSel
        srv.isSelected = true
        setSel = false

  collectTags: ->
    empty = true
    for ts in @data.tags
      empty = empty && (if ts.ty is 'btn' then !ts.tags.reduce ((s,t) -> s || t.isSelected), false else ts.select is 'All')
    res = (@editor.getText().split ' ').filter (e) -> e.length > 0
    return [".*"] if empty and res.length is 0
    return res if empty

    for ts in @data.tags
      if ts.ty is 'lst' and ts.select isnt 'All'
        res.push ts.select
        continue
      tp = []
      for t in ts.tags
        tp.push t.val if t.isSelected
      res.push tp.join '|' if tp.length > 0
    res

  selectNext: ->
    sel = null
    for srv in @data.srvs
      if !sel and srv.isSelected
        sel = srv
        continue
      if sel and srv.isVisible
        sel.isSelected = false
        srv.isSelected = true
        @scrollToItemView  srv
        return
    for srv in @data.srvs
      if srv.isVisible
        srv.isSelected = true
        @scrollToItemView  srv
        return

  selectPrev: ->
    sel = null
    for srv in @data.srvs
      if sel and srv.isSelected
        sel.isSelected = true
        srv.isSelected = false
        @scrollToItemView  sel
        break
      if srv.isVisible
        sel = srv

  getSelected: ->
    for srv,i in @data.srvs
      return i if srv.isSelected
    null

  getSrv: ->
    txt = @editor.getText()
    # srv:port:user:pass
    if /[\w\.]*:\d+(?::[^\s:]+(?::[^\s:]+)?)?$/.test txt
      txt
    else @getSelected()


  clearSelect: -> srv.isSelected = false for srv in @data.srvs; null

  scrollToItemView: (srv) ->
    idx = 0
    for s,i in @data.srvs
      if s.idx is srv.idx
        idx = i
        break
    list = @vm.$$.list
    return unless li = list.children[idx]
    if li.offsetTop < list.scrollTop
      list.scrollTop = li.offsetTop
    else if li.offsetTop + li.offsetHeight > list.clientHeight + list.scrollTop
      list.scrollTop = li.offsetTop + li.offsetHeight - list.clientHeight

  getElement: -> @vm.$el

  updateOnline: (srvId, val) ->
    for s in @data.srvs
      s.isOnline = val if s.idx is srvId

  focus: -> @vm.$$.editor.focus()

  show: ->
    @previouslyFocusedElement = document.activeElement
    @panel.show()
    @focus()

  hide: (rval) ->
    @panel?.hide()
    @editor.setText('')
    @previouslyFocusedElement?.focus()
    @model.srvViewCallback rval

  destroy: ->
    @panel?.destroy()
    @vm?.$destroy()
    @model = @data = @editor = @panel = @vm = null
