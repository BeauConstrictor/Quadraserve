# ------------------- #
#     HTTP CONFIG     #

const
  # If you do not want to allow unencrypted connections to your server, disable
  # this. Note that Quadraserve only uses static pages, so unencrypted
  # connections pose little-to-no risk and allow older machines to more easily
  # access your website.
  useHttp = true
  # if this port is below 1024, then you will have to run ./ALLOW_LOW_PORTS and
  # and enter your password in order to give Quadraserver permission to use the
  # port. The default port below is recommended and means that users can simply
  # enter no port at all when visiting your site. For testing, you may want to
  # set this port higher if you do not currently have admin permissions. This
  # port setting is for insecure connections.
  httpPort = 80

  # Select whether or not to allow encrypted connecftions. Users will get a
  # warning if you disable this, but they will also get a warning if you do not
  # set up proper TLS certificates for this as well. Look into 'certbot' to get
  # certificates.
  useHttps = false
  # The same applies here as to the above port setting, but to secure
  # connections instead.
  httpsPort = 443

# =------------------ #

import std/[asyncnet, asyncdispatch, net, logging, strutils, tables, times, os,
            uri]

import ../content

type
  HttpMessage = object
    startLine: string
    header: Table[string, string]
    body: string

  HttpError = object of ValueError


const
  htmlTemplate = staticRead("../template.html")
# let
#   htmlTemplate = readFile("src/template.html")

var
  consoleLogger = newConsoleLogger(fmtStr = "HTTP/$levelname   ")
  fileLog = newFileLogger("logs/http.txt", levelThreshold = lvlError)

proc `$`(msg: HttpMessage): string =
  result &= msg.startLine & "\r\n"
  for key in msg.header.keys():
    result &= key.toLowerAscii() & ": " & msg.header[key] & "\r\n"
  result &= "\r\n"
  result &= msg.body

proc recvHttpMessage(client: AsyncSocket): Future[HttpMessage] {.async.} =
  result.startLine = await client.recvLine()
  while true:
    let line = await client.recvLine()
    if line.strip() == "": break
    let parts = line.split(": ")
    if parts.len() < 2: raise newException(HttpError, "Malformed header")
    let (key, val) = (parts[0].toLowerAscii(), parts[1..^1].join(": "))
    result.header[key] = val

  var contentLength: int = 0
  if result.header.hasKey("content-length"):
    try:
      contentLength = parseUInt(result.header["content-length"]).int
    except ValueError:
      raise newException(HttpError, "Malformed Content-Length header")

  if contentLength == 0:
    result.body = ""
  elif result.header.hasKey("transfer-encoding"):
    raise newException(HttpError, "Transfer-Encoding is unsupported")
  else:
    result.body = await client.recv(contentLength)

proc getStatusLine(status: statusCode): string =
  return case status:
    of scSuccess: "200 OK"
    of scNotFound: "404 Not Found"
    of scAccessDenied: "403 Forbidden"
    of scUnhandledError: "500 Internal Server Error"

proc getHttpTimestamp(): string =
  return now().utc().format("ddd, dd MMM yyyy hh:mm:ss") & " GMT"

proc handleBadRequest(client: AsyncSocket) {.async.} =
  let body = "Bad request."
  await client.send($HttpMessage(
    startLine: "HTTP/1.1 400 Bad Request",
    header: {
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Length": $len(body),
      "Connection": "close",
      "Date": getHttpTimestamp(),
    }.toTable,
    body: body,
  ))
  client.close()
proc handleInvalidVersion(client: AsyncSocket) {.async.} =
  let body = "HTTP version not supported."
  await client.send($HttpMessage(
    startLine: "HTTP/1.1 505 HTTP Version not Supported",
    header: {
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Length": $len(body),
      "Connection": "close",
      "Date": getHttpTimestamp(),
    }.toTable,
    body: body,
  ))
  client.close()
proc handleInvalidMethod(client: AsyncSocket) {.async.} =
  let body = "Method not allowed."
  await client.send($HttpMessage(
    startLine: "HTTP/1.1 405 Method not Allowed",
    header: {
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Length": $len(body),
      "Connection": "close",
      "Date": getHttpTimestamp(),
    }.toTable,
    body: body,
  ))
  client.close()

proc escapeTextForHtml(text: string): string =
  return text
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
    .replace("\"", "&quot;")
    .replace("'", "&#39;")

proc generateHtmlArticle(gemtext: string): string =
  var article = ""
  var preformatted = false
  var lastLineWasAListItem = false

  for line in gemtext.split("\n"):
    if not lastLineWasAListItem and (line.startsWith("=> ") or line.startsWith("* ")):
      result &= "<ul>\n"
      lastLineWasAListItem = true
    if lastLineWasAListItem and not (line.startsWith("=> ") or line.startsWith("* ")):
      result &= "</ul>\n"
      lastLineWasAListItem = false

    if line.startsWith("```") and not preformatted:
      preformatted = true
      if line.len() == 3: result &= "<pre>\n"
      else: result &= "<pre title=\"" & line[3..^1] & "\">\n"
    elif line.startsWith("```") and preformatted:
      preformatted = false
      result &= "</pre>\n"
    elif preformatted:
      result &= line.escapeTextForHtml() & "\n"
    elif line.startsWith("# "):
      result &= "<h1>" & line[2..^1].escapeTextForHtml() & "</h1>\n"
    elif line.startsWith("## "):
      result &= "<h2>" & line[3..^1].escapeTextForHtml() & "</h2>\n"
    elif line.startsWith("### "):
      result &= "<h3>" & line[4..^1].escapeTextForHtml() & "</h3>\n"
    elif line.startsWith("=> "):
      let parts = line.escapeTextForHtml().split(" ")
      let label = parts[2..^1].join(" ")
      let target = parts[1]
      let url = parseUri(target)
      if not url.isAbsolute() and getFileType(getPath(target)) == ftModule:
        result &= "<li><a class=\"module-prompt\" data-path=\""
        result &= target.escapeTextForHtml() & "\">" & label & "</a></li>"
      else:
        result &= "<li><a href=\"" & parts[1] & "\">" & target & "</a></li>\n"
    elif line.startsWith("* "):
      let parts = line.escapeTextForHtml().split(" ")
      result &= "<li>" & line[2..^1] & "</li>\n"
    elif line.strip().len() > 0:
      result &= "<p>" & line.escapeTextForHtml() & "</p>\n"

  if lastLineWasAListItem:
    result &= "</ul>\n"

proc generateHtmlPage(hostname: string, gemtext: string): string =
  let article = generateHtmlArticle(gemtext)
  result = htmlTemplate.replace("$CONTENT", article)
  result = result.replace("$HOSTNAME", hostname.escapeTextForHtml())
  result = result.replace("$TITLE", gemtext.split("\n")[0].replace("# ", ""))

proc handleClient(client: AsyncSocket, address: string) {.async.} =
  try:

    let request = await client.recvHttpMessage()
    let startLineParts = request.startLine.split(" ")

    if not startLineParts.len() == 3:
      await client.handleBadRequest()
      return
    if not request.header.hasKey("host"):
      await client.handleBadRequest()
      return
    if startLineParts[2] != "HTTP/1.1":
      await client.handleInvalidVersion()
      return
    if startLineParts[0].toUpperAscii() != "GET" and
       startLineParts[0].toUpperAscii() != "POST":
      await client.handleInvalidMethod()
      return

    let path = startLineParts[1]
    info("[REQUEST]          " & address & " " & path)

    if startLineParts[0].toUpperAscii() == "GET":
      let (page, status, fType) = getPage(path)
      var body = page
      if fType == ftGemtext:
        body = generateHtmlPage(request.header["host"], page)
      elif fType == ftModule:
        body = generateHtmlPage(
          request.header["host"],
          "*exec-module:" & path
        )

      let response = HttpMessage(
        startLine: "HTTP/1.1 " & getStatusLine(status),
        header: {
          "Content-Length": $len(body),
          "Connection": "close",
          "Server": "Quadraserve",
          "Content-Type": "text/html; charset=utf-8",
          "Date": getHttpTimestamp(),
        }.toTable,
        body: body,
      )
      await client.send($response)

    elif startLineParts[0].toUpperAscii() == "POST":
      let body = generateHtmlArticle(runModule(path, request.body, "HTTP"))

      let response = HttpMessage(
        startLine: "HTTP/1.1 200",
        header: {
          "Content-Length": $len(body),
          "Connection": "close",
          "Server": "Quadraserve",
          "Content-Type": "text/html; charset=utf-8",
          "Date": getHttpTimestamp(),
        }.toTable,
        body: body,
      )
      await client.send($response)

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()

proc startServer(useTls: bool, port: uint) {.async.} =
  if useTls and not
   (fileExists("ssl/https.cert") and fileExists("ssl/https.key")):
    error "[START]           Missing './ssl/https.key' and/or './ssl/https.cert'"
    while true: discard

  let socket = newAsyncSocket()
  socket.setSockOpt(OptReuseAddr, true)

  var ctx: SslContext
  if useTls:
    ctx = newContext(certFile = "ssl/https.cert", keyFile = "ssl/https.key")

  socket.bindAddr(Port(port))
  socket.listen()

  info("[START]            Listening on port " & $port)

  while true:
    let (address, client) = await socket.acceptAddr(flags = {SafeDisconn})
    if useTls:
      asyncnet.wrapConnectedSocket(ctx, client, handshakeAsServer, "localhost")
    asyncCheck handleClient(client, address)

if isMainModule:
  addHandler(consoleLogger)
  addHandler(fileLog)

  if useHttps: asyncCheck startServer(true, httpsPort)
  if useHttp: asyncCheck startServer(false, httpPort)

  runForever()
