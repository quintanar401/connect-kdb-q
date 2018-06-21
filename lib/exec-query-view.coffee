{TextEditor,CompositeDisposable} = require 'atom'

module.exports =
class ResultView
  constructor: ->
    @C = require './c'
    @model = null

  init: (@model) ->
    @editor = atom.workspace.buildTextEditor autoHeight:false
    # @editor = atom.workspace.textEditorRegistry.build()
    @editor.getTitle = -> 'Query Results'
    @editor.save = (->
      return unless pane = atom.workspace.paneForItem this
      if @getPath() then super() else pane.saveItemAs this).bind @editor
    @editor.getURI = -> 'kdb://query.results'
    @editor.isModified = -> false
    @editor.getQDocName = -> 'qdoc..execview'
    @editor.serialize = -> null
    if atom.grammars.assignLanguageMode
      atom.grammars.assignLanguageMode(@editor.getBuffer(), 'source.q')
    else
      grammar = atom.grammars.grammarForScopeName 'source.q'
      grammar.maxTokensPerLine = 1000
      @editor.setGrammar grammar if grammar
      atom.workspace.textEditorRegistry.setGrammarOverride(@editor,'source.q')
    @editor.setText '========== cut line =========='
    disposable = atom.textEditors.add(@editor)
    @editor.onDidDestroy -> disposable.dispose()
    @subscriptions = new CompositeDisposable
    @subscriptions.add @editor.onDidChangeCursorPosition (ev) => @updateRes ev.newBufferPosition

  getEditor: -> @editor

  addResult: (res) ->
    buffer = @editor.getBuffer()
    pos = 0
    for l in buffer.getLines()
      break if /\=== cut line ===/.test l
      pos++
    if pos is buffer.getLines().length
      buffer.insert [0,0], '========== cut line ==========\n'
      pos = 0
    if /CLEAR/.test(buffer.lineForRow 0)
      @editor.setText 'CLEAR\n========== cut line =========='
    if res.err
      buffer.insert [pos,100000], "\n(`EXCEPTION; \"#{res.srv}\"; #{res.err.toString()})\n"
      @markOverview pos+1, false
      return
    if !res.overview
      res.width ?= @model.showWidth; res.height ?= @model.showHeight; res.sep = ' '
      res.wscroll = res.hscroll = false
      r = if res.res instanceof @C.KException then 'EXCEPTION' else 'SUCCESS'
      cnt = if 0<= res.res.tyId < 20 or res.res.tyId in [98,99,127] then res.res.length() else 0
      res.overview = "(`#{r}; \"#{res.srv}\"; #{res.time}ms; #{if cnt>0 then cnt+'; ' else ''}#{@C.showProto res.res})"
      res.result = @show res, res.res
      res.query = 'Q: '+res.query
      res.query = res.query.replace /\n/g, '\n   ' if res.query.includes '\n'

    buffer.insert [pos,10000], '\n'
    pos = pos + 1
    cfg = atom.config.get('connect-kdb-q.resultFmt').split(" ")
    RES = QUERY = INFO = false
    opos = pos
    for cEntry in cfg
      if cEntry is 'INFO' and !INFO
        INFO = true
        buffer.insert [pos,0], res.overview + '\n'
        @markOverview pos, /SUCCESS/.test res.overview
        pos = pos+1
      if cEntry is 'RES' and !RES
        RES = true
        buffer.insert [pos,0], (res.result.join '\n')+'\n'
        @markScroll pos, res
        pos = pos + res.result.length
      if cEntry is 'QUERY' and !QUERY
        QUERY = true
        buffer.insert [pos,0], res.query + '\n'
        @editor.foldBufferRow pos if res.query.includes '\n'
        pos = pos + res.query.split('\n').length
    @editor.setCursorBufferPosition [opos,0] if @editor.getCursorBufferPosition().row > opos

  updateRes: (pos) ->
    m = @editor.findMarkers containsBufferPosition: pos
    for i in m
      p = i.getProperties()
      if p.resultId?
        return unless res = @resById p.resultId
        @unmarkScroll res
        res.wscroll = res.hscroll = false
        return unless res.res
        if p.horizontal then res.width += @model.showWidth else res.height += @model.showHeight
        start = if p.horizontal then pos.row else 1+pos.row-res.result.length
        @editor.getBuffer().deleteRows start,start+res.result.length-1
        res.result = @show res, res.res
        @editor.getBuffer().insert [start,0], (res.result.join '\n') + '\n'
        wline = 0
        if p.horizontal and !res.wscroll
          for l,i in res.result
            wline = i if res.result[wline].length < l.length
        @editor.setCursorBufferPosition if p.horizontal then [pos.row+wline, pos.column + @model.showWidth - 3] else [start+res.result.length-1,0]
        @markScroll start, res
        return

  resById: (id) ->
    for r in @model.results
      return r if r.id is id
    null

  show: (cfg, res, lvl=0) ->
    return [res.toString()] if res.tyId < 0 or res.tyId is 128
    return res.toString().split '\n' if 99 < res.tyId < 120
    str = switch
      when res.tyId is 10 then [res.toString cfg.width+4]
      when res.tyId is 0 then @showList cfg, res, lvl
      when res.tyId < 20 then  @showTList cfg, res
      when res.tyId is 98 then @showTbl cfg, res, lvl
      when res.tyId in [99,127] and (res.keys().tyId is 98 or res.values().tyId is 98) then @showKeyTbl cfg, res, lvl
      when res.tyId in [99,127] then @showDict cfg, res, lvl
      else res.toString().split '\n'
    str = @setScroll cfg, str

  setScroll: (cfg,str) ->
    if str.length > cfg.height
      str = str.slice(0,cfg.height-1)
      str.push '...'
      cfg.hscroll = true
    for s,i in str
      if s.length >= cfg.width
        cfg.wscroll = true
        str[i] = s.slice 0, cfg.width
    if cfg.wscroll
      str[0] += ' '.repeat cfg.width - str[0].length if cfg.width > str[0].length
      str[0] += '...'
    str

  showDict: (cfg,res,lvl) ->
    return res.toString().split '\n' if lvl > 0 or res.keys().length() is 0 or !(0 <= res.values().tyId < 20)
    t = new @C.Table new @C.Dict(new @C.List(['a','b'], 11), new @C.List [res.keys(), res.values()])
    cfg.height += 2; cfg.sep = '|'
    r = @showTbl cfg, t, lvl
    cfg.height -= 2
    r.slice 2

  showKeyTbl: (cfg,res,lvl) ->
    return res.toString().split '\n' if lvl > 0
    ktbl = @getTbl cfg,res.keys(),lvl
    ktbl = ktbl.map (e) ->
      e.map (e) -> e+'|'
    if cfg.width>(w = ktbl[0][0].length)
      cfg.width -= w
      ktbl = @getTbl cfg,res.values(),lvl,ktbl
      cfg.width += w
    ktbl.reduce ((s,e)->s.concat e), []

  showTbl: (cfg,res,lvl) ->
    return res.toString().split '\n' if lvl > 0 or !(res.values().lst instanceof Array)
    tbl = @getTbl cfg,res,lvl
    tbl.reduce ((s,e)->s.concat e), []

  getTbl: (cfg,res,lvl,cols=null) ->
    vals = if res.tyId is 98 then res.values().lst else [res]
    tw = -1
    cls = if res.tyId is 98 then res.columns().lst else [' ']
    for k,i in cls
      cfg.height -= 2
      v = if vals[i].length() is 0 then [[k],0] else [[k],0].concat @showList0 cfg, vals[i], 0
      cfg.height += 2
      # max width
      w = 0
      v.map (e) ->
        return if e is 0
        e.map (e) -> w = Math.max w,e.length
      # pad
      v = v.map (e) ->
        return ['-'.repeat w] if e is 0
        e.map (e) -> e+' '.repeat w - e.length
      # merge
      if cols
        cols = cols.slice 0, v.length if v.length < cols.length
        cols = for c,i in cols
          vi = v[i]; l = -1+Math.max vi.length, c.length
          for j in [0..l]
            (c[j]||' '.repeat tw)+(if i is 1 then '-' else cfg.sep)+(vi[j]||' '.repeat w)
      else cols = v
      tw += 1 + w
      break if tw > cfg.width
    cols

  showTList: (cfg,res) ->
    return [res.toString()] if res.length() < 2
    str = @C.Consts.listPref[res.tyId]
    sep = @C.Consts.listSep[res.tyId]
    end = @C.Consts.listPost[res.tyId]
    for i in [0..res.length()-1]
      item = res.toStringAt i, res.tyId is 11
      str += (if i is 0 then '' else sep) + item
      return [str] if str.length >= cfg.width
    [str + end]

  showList: (cfg, res, lvl) ->
    return [res.toString()] if res.length() is 0
    if lvl is 0
      str = @showList0 cfg,res,lvl
      str[0][0] = 'enlist ' + str[0][0] if res.length() is 1
      return str.reduce ((s,e)->s.concat e), []
    @showList1 cfg,res,lvl

  showList0: (cfg, res, lvl) ->
    str = []; h = 0
    for i in [0..res.length()-1]
      s = if res.tyId>0 then [res.toStringAt i, false] else @show cfg, res.lst[i], lvl+1
      h += s.length
      str.push s
      break if h>cfg.height
    str

  showList1: (cfg,res,lvl) ->
    sep = if lvl is 1 then ' ' else ';'
    str = [if res.length is 1 then 'enlist ' else if lvl>1 then '(' else '']
    for i in [0..res.length()-1]
      s = @show cfg, res.lst[i], lvl+1
      str[str.length-1] += s[0]
      str = str.concat s.slice 1 if s.length > 1
      str[str.length-1] += sep if i<res.length()-1
      break if str.length >= cfg.height or str[str.length-1].length >= cfg.width
    str[str.length-1] += ')' if lvl>1
    str

  markOverview: (pos, isSuc) ->
    return if isSuc
    marker = @editor.markBufferRange [[pos,2],[pos,if isSuc then 9 else 11]], persistent: false
    dec = @editor.decorateMarker marker, type: 'highlight', class: (if isSuc then 'kdb-success' else 'kdb-exception')

  markScroll: (pos, res) ->
    if res.wscroll
      res.wmarker = @editor.markBufferRange [[pos,res.result[0].length-3],[pos,res.result[0].length]], persistent: false, resultId: res.id, horizontal: true
      dec = @editor.decorateMarker res.wmarker, type: 'highlight', class: 'kdb-show'
    if res.hscroll
      pos = pos + res.result.length - 1
      res.hmarker = @editor.markBufferRange [[pos,0],[pos,3]], persistent: false, resultId: res.id, horizontal: false
      dec = @editor.decorateMarker res.hmarker, type: 'highlight', class: 'kdb-show'

  unmarkScroll: (res) ->
    res.wmarker?.destroy()
    res.hmarker?.destroy()
    res.wmarker = res.hmarker = null

  destroy: ->
    @editor.destroy()
    @subscriptions?.dispose()
    @model = @editor = null
