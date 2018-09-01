net = require 'net'
{Buffer} = require 'buffer'

npmLong = require 'long'

ni = -2147483648 # i,m,v,t,d
nw = 2147483647 # -nw = neg nw
nj = npmLong.MIN_VALUE
nwj = npmLong.MAX_VALUE
nnwj = nwj.negate()
attr = 'supg'

i2 = (i) -> ('00'+i.toString()).slice(-2)
i3 = (i) -> ('000'+i.toString()).slice(-3)
i9 = (i) -> ('000000000'+i.toString()).slice(-9)
ix16 = (i) -> ('0000000000000000'+i.toString(16)).slice(-16)
getJSDate = (i) -> new Date 946684800000+i*1000 # 86400000*10957
time2str = (i) ->
  s = if i<0 then '-' else ''
  j = if i<0 then -i else i
  js = Math.floor j/1000; jm = Math.floor js/60
  s+i2(Math.floor jm/60)+':'+i2(jm%60)+':'+i2(js%60)+'.'+i3(j%1000)
exception = (m) -> throw new KException(m)
enc = (m) ->
  return m if m.tyId isnt undefined
  if typeof m is 'object'
    if m instanceof Array
      l = (enc x for x in m)
      return new QWList l
    keys = []; vals = []
    for k,v of m
      keys.push enc k; vals.push enc v
    return new QDict(new QWList(keys), new QWList(vals))
  return new QFloat m if typeof m is 'number'
  return new QSymbol m if typeof m is 'string'
  return new QBoolean m if typeof m is 'boolean'
  exception "encode: unkown type"
showProto = (res) ->
  return '`unexpected' unless res.tyId?
  return '`'+QConsts.names[-res.tyId]+'$' if res.tyId < 0
  return '()' if res.tyId is 0
  return "#{if res.attr then '`'+res.attr+'#' else ''}`#{QConsts.names[res.tyId]}$()" if res.tyId < 20
  if res.tyId is 98
    vals = res.values()
    r = []
    for k,i in res.columns().lst
      r.push k.toString() + ':' + if vals.tyId is -11 then 'unknown' else showProto vals.lst[i]
    return "([] #{r.join '; '})"
  if res.tyId in [99,127]
    k = res.keys(); v = res.values()
    if k.tyId is 98 and v.tyId is 98
      return "([#{showProto(k).slice(4,-1)}] #{showProto(v).slice(3)}"
    return "(#{showProto k})!#{showProto v}"
  return "`exception" if res.tyId is 128
  return "`function" if res.tyId > 99
  '`unexpected'

class QBase
  # q type
  tyId: 0
  constructor: (@i) ->
  toStr: -> @i.toString()
  toString: (full = true) ->
    res = @toStr()
    if full then QConsts.listPref[-@tyId]+res+QConsts.listPost[-@tyId] else res
  value: -> @i
  equals: (o) ->
    return false unless o?.tyId is @tyId
    @i is o.i
  compareTo: (o) ->
    return null unless o?.tyId is @tyId
    @i-o.i
  s: -> 1+QConsts.size[-@tyId]
  w: (B) -> B.wub @i
  rv: (b) -> @i = @rr b
  @r: (b) -> new this @rr b
  @rr: (b) -> b.rub()

class QBoolean extends QBase
  tyId: -1
  constructor: (i) -> @i = if i then true else false
  toStr: -> if @i then '1' else '0'
  w: (B) -> B.wub if @i then 1 else 0

class QByte extends QBase
  tyId: -4
  toStr: -> i2 (@i&0xFF).toString(16)
  w: (B) -> B.wub @i
  @rr: (b) -> b.rub()

class QShort extends QBase
  tyId: -5
  w: (B) -> B.wh @i
  @rr: (b) -> b.rh()

class QInt extends QBase
  tyId: -6
  toString: ->
    if @i is ni
      '0N'+QConsts.types[-@tyId]
    else if @i is nw
      '0W'+QConsts.types[-@tyId]
    else if @i is -nw
      '-0W'+QConsts.types[-@tyId]
    else
      @toStr()
  w: (B) -> B.wi @i
  @rr: (b) -> b.ri()

class QLong extends QBase
  tyId: -7
  constructor: (v,v2) ->
    if v instanceof npmLong
      @i = v
    else if typeof v is 'number'
      v2 = v2 || 0
      @i = new npmLong v, v2
    else
      @i = 0
  toString: ->
      if @i.equals nj
        '0N'+QConsts.types[-@tyId]
      else if @i.equals nwj
        '0W'+QConsts.types[-@tyId]
      else if @i.equals nnwj
        '-0W'+QConsts.types[-@tyId]
      else
        @toStr()
  value: -> @i.toNumber()
  equals: (o) ->
    return false unless o instanceof QLong
    @i.equals o.i
  compareTo: (o) ->
    return null unless o instanceof QLong
    @i.compare o.i
  w: (B) -> B.wi @i.getLowBits(); B.wi @i.getHighBits()
  @rr: (b) ->
    b1 = b.ri(); b2 = b.ri()
    if b.a then new npmLong b1,b2 else new npmLong b2,b1

class QReal extends QBase
  tyId: -8
  w: (B) -> B.we @i
  toStr: -> if isNaN @i then "0n" else if isFinite @i then @i.toString() else if @i>0 then "0w" else "-0w"
  @rr: (b) -> b.re()

class QFloat extends QBase
  tyId: -9
  w: (B) -> B.wf @i
  toStr: -> if isNaN @i then "0n" else if isFinite @i then @i.toString() else if @i>0 then "0w" else "-0w"
  @rr: (b) -> b.rf()

class QChar extends QBase
  tyId: -10
  toStr: -> JSON.stringify @i
  compareTo: (o) ->
    return null unless o instanceof QChar
    if @i>o.i then 1 else if @i<o.i then -1 else 0
  w: (B) -> B.wstr @i||' '
  @rr: (b) -> b.rstr 1

class QSymbol extends QBase
  tyId: -11
  toStr: -> '`' + @i
  compareTo: (o) ->
    return null unless o instanceof QSymbol
    if @i>o.i then 1 else if @i<o.i then -1 else 0
  s: -> 2+(@i||'').length
  w: (B) -> s = @i||''; B.ws s
  @rr: (b) -> b.rs()

class QTimestamp extends QLong
  tyId: -12
  toStr: ->
    k = if @i.isNegative() then -1 else 1
    j = if @i.isNegative() then @i.negate() else @i
    ms = i9 (j.modulo 1000000000).getLowBitsUnsigned()
    d = (j.div 1000000000).getLowBitsUnsigned()
    (getJSDate k*d).toISOString().replace(/...Z/,ms).replace(/-/g,'.').replace(/T/,'D')
  value: -> getJSDate @i.toNumber()/1000000

class QMonth extends QInt
  tyId: -13
  toStr: ->
    m=@i+24000
    y=Math.floor m/12
    return "" if @i is ni
    i2(Math.floor y/100)+i2(y%100)+"."+i2(1+m%12)
  value: ->
    m=@i+24000
    y=Math.floor m/12
    new Date y, 1+m%12

class QDate extends QInt
  tyId: -14
  toStr: -> (new Date 86400000*(10957+@i)).toISOString().slice(0,10).replace(/-/g,'.')
  value: -> new Date 86400000*(10957+@i)

class QDatetime extends QFloat
  tyId: -15
  toStr: -> if isNaN @i then "0Nz" else if isFinite @i then (new Date 86400000*(10957+@i)).toISOString().replace(/-/g,'.').replace(/Z/g,'z') else if @i>0 then "0wz" else "-0wz"
  value: -> new Date 86400000*(10957+@i)

class QTimespan extends QLong
  tyId: -16
  toStr: ->
    s=if @i.isNegative() then "-" else ""
    j=if @i.isNegative() then @i.negate() else @i
    ms = i9 (j.modulo 1000000000).getLowBitsUnsigned()
    d = (j.div 1000000000).getLowBitsUnsigned()
    days = (Math.floor d/86400).toString() + 'D'
    s+(getJSDate d).toISOString().replace(/...Z/,ms).replace(/.*T/,days)
  value: -> new Date 86400000*10957+@i.toNumber()/1000000

class QMinute extends QInt
  tyId: -17
  toStr: -> i2(Math.floor @i/60)+":"+i2(@i%60)
  value: -> new Date 86400000*10957+@i*60000

class QSecond extends QInt
  tyId: -18
  toStr: ->
    j = Math.floor @i/60
    i2(Math.floor j/60)+":"+i2(j%60)+':'+i2(@i%60)
  value: -> new Date 86400000*10957+@i*1000

class QTime extends QInt
  tyId: -19
  toStr: -> time2str @i
  value: -> new Date 86400000*10957+@i

class QUUID extends QBase
  tyId: -2
  toStr: ->
    s = []
    for i,j in @i
      s.push i2 i.toString(16)
      s.push '-' if j in [3,5,7,9]
    s.join ''
  w: (B) -> B.wub x for x in @i; null
  @rr: (b) -> b.rub() for i in [0..15]

class QList
  constructor: (lst) -> {@lst, @tyId, @attr} = lst
  length: -> @lst.b.length/QConsts.size[@tyId]
  toString: ->
    if (l=@length()) is 0
      return "`#{QConsts.names[@tyId]}$()"  if @tyId>0
      return '()'
    return "enlist #{@toStringAt 0}" if l is 1
    mx = Math.min l, QConsts.showListMax
    res = (@toStringRng 0, mx, false).join QConsts.listSep[@tyId]
    res = res+'...' if mx < l
    QConsts.listPref[@tyId]+res+QConsts.listPost[@tyId]
  toStringAt: (i,full) ->
    @lst.moveTo i*QConsts.size[@tyId]
    (QConsts.atoms[@tyId].r @lst).toString full
  toStringRng: (f,n,full=true) ->
    a = null; @lst.moveTo f*QConsts.size[@tyId]
    if a then (a.rv @lst).toString(full) else (a=QConsts.atoms[@tyId].r @lst).toString(full) for i in [1..n]
  value: (i) ->
    @lst.moveTo i*QConsts.size[@tyId]
    (QConsts.atoms[@tyId].r @lst).value()
  s: -> 6 + @lst.b.length
  @r: (b) -> new this @rr b
  @rh: (b) ->
    ty = b.rub();
    exception 'bad message: list type' unless 0 <= ty < 20
    attr = QConsts.attr[b.rub()-1] || ''; l = b.ri()
    tyId: ty, attr: attr, l:l
  @rr: (b) ->
    lst = @rh b
    lst.lst = b.slice lst.l*QConsts.size[lst.tyId]
    lst

class QList0 extends QList
  length: -> @lst.length
  s: ->
    res = 6 + if @tyId in [0,11] then @lst.reduce ((x,y) -> x+y.s()), 0 else @lst.length*QConsts.size[@tyId]
    if @tyId is 11 then res - @lst.length else res
  toStringAt: (i,full) -> @lst[i].toString full
  toStringRng: (f,n,full=true) -> @lst[i].toString() for i in [f..f+n-1]
  value: (i) -> @lst[i]
  @rr: (b) ->
    lst = @rh b
    lst.lst = if lst.l>0 then b.rv() for i in [1..lst.l] else []
    lst
  wh: (B) -> B.wub QConsts.battr[@attr] || 0; B.wi @lst.length
  w: (B) ->
    @wh B
    if @tyId is 0
      B.wv enc i for i in @lst
    else if @tyId is 10 and typeof @lst is 'string'
      B.wstr @lst
    else
      for i in @lst
        i = enc i
        exception 'list item type is not the same as the list type' if i.tyId isnt @tyId
        i.w B

class QSymList extends QList0
  toStringAt: (i,full) -> (if full then "`" else '') + @lst[i]
  toStringRng: (f,n) -> @toStringAt i,true for i in [f..f+n-1]
  @rr: (b) ->
    lst = @rh b; lst.lst = []
    return lst if lst.l is 0
    for i in [1..lst.l]
      lst.lst.push QSymbol.rr b
    lst

class QString extends QList0
  s: -> 6 + @lst.length
  toString: (len) ->
    return '""' if (l=@length()) is 0
    return "enlist #{@toStringAt 0}" if l is 1
    mx = Math.min l, len || QConsts.showStringMax-1
    res = @lst.slice 0,mx
    res = res+'...' if mx < l
    JSON.stringify res
  toStringAt: (i) -> JSON.stringify @lst[i]
  toStringRng: (f,n,full=true) ->
    return (@toStringAt i for i in [f..f+n-1]) if full
    JSON.stringify @lst.slice(f,f+n)
  @rr: (b) ->
    lst = @rh b; lst.lst = b.rstr lst.l
    lst
  @w: (B) -> @wh B; B.wstr @lst

class QWList extends QList0
  constructor: (@lst, @tyId = 0) ->
    if typeof @lst is 'string'
      @tyId = 10

class QTable
  tyId: 98
  constructor: (@dict,@attr = '') -> exception "Dictionary type is expected" unless @dict.tyId in [99,127]
  columns: -> @dict.keys()
  values: -> @dict.values()
  value: (i) -> @dict.value i
  s: -> 2 + @dict.s()
  length: -> if @dict.val instanceof QList then @dict.val.lst[0].length() else 0
  toString: -> (if @attr is '' then '' else "`#{@attr}#")+'+' + @dict.toString()
  @r: (b) ->
    a = QConsts.attr[b.rub()-1] || ''
    new QTable(b.rv(),a)
  w: (B) -> B.wub QConsts.battr[@attr] || 0; B.wv @dict

class QDict
  tyId: 99
  constructor: (k,v) ->
    @key = enc k; @val = enc v;
    exception 'bad message: dict key' unless @key instanceof QList or @key.tyId is 98
    exception 'bad message: dict val' unless @val instanceof QList or @val.tyId in [-11,98]
  s: -> 1 + @key.s() + @val.s()
  keys: -> @key
  values: -> @val
  value: (i) ->
    res = []
    res = @key.value i if @key.tyId is 98
    res = res.concat @val.value i if @val.tyId is 98
    res = res.concat (l.value i for l in @val.lst) if @val instanceof QList
    res
  length: -> @key.length()
  toString: -> (if @key.length() is 1 then "(#{@key.toString()})" else @key.toString())+'!'+@val.toString()
  @r: (b) -> new this(b.rv(), b.rv())
  w: (B) -> B.wv @key; B.wv @val

class QSDict extends QDict
  tyId: 127
  toString: -> '`s#'+super.toString()

class QFunc
  tyId: 100
  constructor: (@body, @ns = '') ->
    if typeof @body is 'string'
      @body = new QWList @body
  s: -> 2 + @ns.length + @body.s()
  length: -> @body.length()
  toString: -> @body.lst
  w: (B) -> B.ws @ns; B.wv @body
  @r: (b) -> v = @rr b; new this v[0],v[1]
  @rr: (b) ->
    n = QSymbol.rr b
    [b.rv(),n]

class QXFunc
  constructor: (@i) ->
  s: -> 2
  length: -> @i.length
  toString: -> @i
  @r: (b) -> new this @rr b

class QUFunc extends QXFunc
  tyId: 101
  @rr: (b) -> if (c = b.rub()) is 255 then '' else QConsts.unary[c] || 'unexpected'

class QBFunc extends QXFunc
  tyId: 102
  @rr: (b) -> QConsts.binary[b.rub()] || 'unexpected'

class QAFunc extends QXFunc
  tyId: 103
  @rr: (b) -> QConsts.adv[b.rub()] || 'unexpected'

class QPFunc extends QXFunc
  tyId: 104
  constructor: (@lst) ->
  s: -> 5 + @lst.reduce ((x,y)->x+y.s()), 0
  length: -> 0
  toString: -> @lst[0].toString()+'['+(@lst.slice(1).map (x)->x.toString()).join(';')+']'
  @rr: (b)-> b.rv() for i in [1..b.ri()]

class QCFunc extends QPFunc
  tyId: 105
  toString: -> "'["+(@lst.map (x)->x.toString()).join(';')+']'

class QAdFunc extends QXFunc
  constructor: (v) -> {@adv,@func,@tyId} = v
  s: -> 1 + @func.s()
  length: -> 1+@func.length()
  toString: -> @func.toString()+@adv
  @rr: (b) ->
    t = b.rub(); a = QConsts.adv[t-106]
    adv: a, func: b.rv(), tyId: t

class KException
  tyId: 128
  message: null
  constructor: (@message) ->
  toString: (full = true)-> if full then "'"+@message else @message
  w: (B) -> B.wstr @message

class QConsts
  @atoms: [null,QBoolean,QUUID,(-> exception 'bad message: bad type'),QByte,QShort,QInt,QLong,
    QReal,QFloat,QChar,QSymbol,QTimestamp,QMonth,QDate,QDatetime,QTimespan,QMinute,QSecond,QTime]
  @lists: [QList0,QList,QList,(-> exception 'bad message: bad type'),QList,QList,QList,QList,
    QList,QList,QString,QSymList,QList,QList,QList,QList,QList,QList,QList,QList]
  @extras: [QTable,QDict,QFunc,QUFunc,QBFunc,QAFunc,QPFunc,QCFunc,QAdFunc,QAdFunc,QAdFunc,QAdFunc,QAdFunc,QAdFunc]
  @unary: ['::','flip','neg','first','reciprocal','where','reverse','null','group','hopen','hclose',
    'string','enlist','count','floor','not','key','distinct','type','value','read0','read1','2::',
    'avg','last','sum','prd','min','max','exit','getenv','abs',"sqrt","log","exp","sin","asin","cos","acos","tan","atan","enlist","var","dev"]
  @binary: [':','+','-','*','%','&','|','^','=','<','>','$',',','#','_','~','!','?','@','.','0:',
    '1:','2:','in','within','like','bin','ss','insert','wsum','wavg','div',"xexp","setenv","binr","cov","cor"]
  @adv: ["'","/","\\","':","/:","\\:"]
  @attr: 'supg'
  @battr: s: 1, u: 2, p: 3, g: 4
  @size: [0,1,16,0,1,2,4,8,4,8,1,1,8,4,4,8,8,4,4,4]
  @names: ['','boolean','guid','','byte','short','int','long','real','float','char','symbol','timestamp','month','date','datetime','timespan','minute','second','time']
  @types: ['','b','g','','','h','i','j','e','f','c','','p','m','d','z','n','u','v','t']
  @showListMax: 10
  @showStringMax: 40
  @listSep:  [';','',' ','','',' ',' ',' ',' ',' ','','',' ',' ',' ',' ',' ',' ',' ',' ']
  @listPref: ['(','','','','0x','','','','','','','','','','','','','','','']
  @listPost: [')','b','','','','h','i','','e','f','','','','m','','','','','','']

class QMessage
  constructor: (@b) -> @i = 0
  moveTo: (@i) ->
  offset: -> @i
  slice: (l) ->
    msg = new QMessage @b.slice @i, @i+l
    @i += l; msg.a = @a; msg.i = 0
    msg
  rub: -> @b.readUInt8 @i++
  wub: (x) -> @b.writeUInt8 x, @i++
  rb: -> @b.readInt8 @i++
  wb: (x) -> @b.writeInt8 x, @i++
  rh: ->
    res = if @a then @b.readInt16LE @i else @b.readInt16BE @i
    @i += 2; res
  wh: (x) -> @b.writeInt16LE x, @i; @i += 2
  ri: ->
    res = if @a then @b.readInt32LE @i else @b.readInt32BE @i
    @i += 4; res
  wi: (x) -> @b.writeInt32LE x, @i; @i += 4
  re: ->
    res = if @a then @b.readFloatLE @i else @b.readFloatBE @i
    @i += 4; res
  we: (x) -> @b.writeFloatLE x, @i; @i += 4
  rf: ->
    res = if @a then @b.readDoubleLE @i else @b.readDoubleBE @i
    @i += 8; res
  wf: (x) -> @b.writeDoubleLE x, @i; @i += 8
  rs: () ->
    j = 0; j++ until @b[@i+j] is 0
    res = @rstr j
    @rub(); res
  ws: (x) -> @wstr(x); @wub(0)
  rstr: (l) ->
    return '' if l is 0
    res = @b.toString 'ascii', @i, @i+l
    @i += l; res
  wstr: (x) -> @b.write x, @i, x.length, 'ascii'; @i += x.length
  rheader: ->
    exception 'bad message: length' if @b.length < 9
    @i = 4; @a = @b[0]; @s = @b[1]; @c = @b[2]
    @ri()
  r: ->
    l = @rheader()
    exception 'bad message: length' if l isnt @b.length
    @u() if @c is 1
    @message = @rv()
  w: (msg, @s = 1) ->
    l = msg.s() + 8; @b = new Buffer l; @a = 1
    @wub @a; @wub @s; @wh 0; @wi l
    @wv msg
    @b
  rv: ->
    return QConsts.atoms[256-ty].r this if (ty = @rub())>236
    if ty<20
      @i--; return QConsts.lists[ty].r this
    return QSDict.r this if ty is 127
    return new KException @rs() if ty is 128
    return new QFunc '<func>' if ty>111
    @i-- if ty>105
    QConsts.extras[ty-98].r this
  wv: (msg) -> @wb msg.tyId; msg.w this
  u: ->
    dst = new Buffer @ri()
    aa = new Int32Array 256
    s = p = 8; ii = f = r = n = 0; d = @i
    while s<dst.length
      if ii is 0
        f = 0xff & @b[d++]; ii = 1
      if (f & ii) isnt 0
        r = aa[0xff & @b[d++]]
        dst[s++] = dst[r++]
        dst[s++] = dst[r++]
        n = 0xff & @b[d++]
        if n>0
          dst[s+m] = dst[r+m] for m in [0..n-1]
      else
        dst[s++] = @b[d++]

      while p < s-1
         aa[(0xff & dst[p]) ^ (0xff & dst[p+1])] = p++

      p = s += n if (f&ii) isnt 0
      ii *= 2
      ii = 0 if ii is 256
    @b = dst
    @i = 8

# disconn -> inproc -> conn -> down
class QConn
  constructor: (args) ->
    {@host, @port, @uname, @pass, @exclusive} = args
    @host ?= 'localhost'; @uname ?= ''; @pass ?= ''; @exclusive ?= false
    @uname = @uname + ':' + @pass if @uname isnt '' and @pass isnt ''
    @status = 'disconn'; @mode = 3
    @client = null; @request = null
    @lastTime = null
    @cbs = []; @proxies = []; @data = []; @l = -1; @cl = 0
    @lmt = atom.config.get('connect-kdb-q.limitResSize')
  toString: -> "#{@host}:#{@port}" + (if @uname is '' then '' else ":#{@uname}") +
    (if @exclusive then '[excl]' else '') + "[#{@status}]"
  getQueryTime: -> (new Date()) - @lastTime
  chkReq: (b) ->
    exception "unexpected: invalid connection" unless @client
    exception "disconnected" unless @status is 'conn'
    exception "unexpected request" if @request
  write: (b) ->
    @client.write b
    @lastTime = new Date()
  writeSync: (b, req) -> @chkReq(); @request = req; @write b
  writeAsync: (b) -> @chkReq(); @write b
  readAsync: (req) -> @chkReq(); @request = req
  ack: (st) ->
    @status = if !st then 'conn' else 'down'
    @cbs.map (e) => if !st then e st, @getProxy() else e st
    @cbs = []
  ackReq: (st, resp) ->
    if @request
      try
        @request st, resp
      catch e
        console.error e
    @request = null
  cleanup: (st) ->
    @status = 'down'; @data = []
    @ack st if @cbs.length > 0
    @ackReq st
    @proxies.map (el) -> try
        el.down st if el
      catch e
        console.error e
    @proxies = []
  getProxy: ->
    @proxies.push p = new QProxy this, @proxies.length
    p
  close: (p) ->
    # @proxies[p.id] = null
    # return if 0 < @proxies.reduce ((x,y)->x+(y is null)), 0
    @client.destroy()
  match: (conn) ->
    return false if @exclusive or conn.exclusive
    return false unless @host is conn.host and @port is conn.port and @uname is conn.uname
    return false if @status is 'down'
    true
  connect: (cb = (e,r) ->) ->
    exception 'unexpected: connection is down' if @status is 'down'
    return cb(null, @getProxy()) if @status is 'conn'
    @cbs.push cb
    return if @status is 'inproc'
    @startConnect()
  startConnect: ->
    @status = 'inproc'
    @client = net.connect {host:@host, port:@port}, ((e,r) => @onConn e,r)
    @client.on 'error', (e) => @onError e
    @client.on 'close', (e) => @onClose e
    @lastTime = new Date()
    null
  onConn: ->
    @client.setKeepAlive(true, 1000)
    i = @uname.length; b = new Buffer if @mode > 0  then i + 2 else i + 1
    b.write @uname, 0, i, 'ascii'
    b.writeUInt8 3, i++ if @mode > 0
    b.writeUInt8 0, i++
    @client.once 'data', (d) => @onAuthResp d
    @write b
  onAuthResp: (d) ->
    @client.on 'data', (d) => @onData d
    @ack null
  onError: (err) -> @cleanup err
  onClose: (err) ->
    @client = null
    if !err and @status is 'inproc'
      if @mode is 0
        @ack 'access'
      else
        @mode = 0
        @startConnect()
      return
    @cleanup 'closed'
  onData: (d) ->
    try
      exception 'unexpected msg' unless @request
      if @l < 0
        @cl = 0
        @l = (new QMessage d).rheader()
        atom.notifications.addError "Msg is too big, increase limitResSize setting. Msg size: #{@l/(1024*1024)}Mb, max size #{@lmt}Mb" if (@lmt*1048576)<=@l
      @cl += d.length
      @data.push d if @cl < (@lmt*1048576)
      exception 'unexpected msg length' if @cl > @l
      if @cl is @l
        res = Buffer.concat @data
        @data = []; @l = -1
        @ackReq null, res
    catch err
      @data = []; @l = -1
      console.error err
      @ackReq err

class QProxy
  constructor: (@conn, @id) ->
    @ev = {}; @subs = {}; @mode = 'query'
  on: (ev,cb) ->
    @ev[ev] = cb
  clearEvents: -> @ev = {}
  down: (err) ->
    try
      @ev['down'] err if @ev['down']
      @ev['error'] err if @ev['error'] and err isnt 'closed'
      @ev['close']() if @ev['close'] and err is 'closed'
    catch e
      console.error e
  status: -> if @conn then @conn.status else 'down'
  close: -> @conn.close(this); @conn = null
  deserialize: (b, ty = 2) ->
    msg = new QMessage b;
    res = msg.r()
    console.error "unexpected request return type "+msg.s if msg.s isnt ty
    res
  serialize: (m, t) -> msg = new QMessage();  msg.w (@encode m), t
  encode: (m) ->
    return new QWList m if typeof m is 'string'
    enc m
  sendSync: (msg, cb) -> @conn.writeSync (@serialize msg, 1), (err, res) =>
    return cb err if err
    try
      cb null, time: @conn.getQueryTime(), res: @deserialize(res)
    catch error
      cb error, null
  sendAsync: (msg) -> @conn.writeAsync (@serialize msg, 0)
  subs: (tbl, cb, initMsg) ->
    @subs[tbl] = cb; @mode = 'subs'
    @writeSync0 initMsg, ((err, data) => @onSubsMsg err, data) if initMsg
  onSubsMsg: (err, data) ->
    @conn.readAsync (err, data) => @onSubsMsg err, data
    return console.error err if err
    data = @deserialize data
    return console.error "Unexpected subs message" unless 0 <= data.tyId < 20 and data.length() > 0 and data.lst[0].tyId in [10,11]
    tbl = if data.lst[0].tyId is 10 then data.lst[0].lst else data.lst[0].i
    return console.error "Got unsubscribed table: " + tbl unless @subs[tbl]
    try
      @subs[tbl] data
    catch error
      console.error error

class C
  constructor: ->
    @conns = []
  getConn: (args) ->
    cc = new QConn args
    for c in @conns
      return c if c.match cc
    @conns.push cc
    cc
  connect: (args, cb = null) ->
    c = @getConn args
    c.connect cb

module.exports =
  Boolean: QBoolean
  UUID: QUUID
  Byte: QByte
  Short: QShort
  Int: QInt
  Long: QLong
  Real: QReal
  Float: QFloat
  Char: QChar
  Symbol: QSymbol
  Timestamp: QTimestamp
  Month: QMonth
  Date: QDate
  Datetime: QDatetime
  Timespan: QTimespan
  Minute: QMinute
  Second: QSecond
  Time: QTime
  List: QWList
  Table: QTable
  Dict: QDict
  Func: QFunc
  KException: KException
  Consts: QConsts
  Message: QMessage
  C: new C()
  showProto: showProto
