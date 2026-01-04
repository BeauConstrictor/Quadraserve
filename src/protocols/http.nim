# ------------------- #
#     HTTP CONFIG     #

const
  useHttp = true
  httpPort = 80

  useHttps = true
  httpsPort = 443

# =------------------ #

import std/[asyncnet, asyncdispatch, net, logging, strutils, tables, times, os]

import ../content

type
  HttpMessage = object
    startLine: string
    header: Table[string, string]
    body: string

  HttpError = object of ValueError


const
  htmlTemplate = staticRead("../template.html")

var
  consoleLogger = newConsoleLogger(fmtStr="HTTP/$levelname   ")
  fileLog = newFileLogger("logs/gemini.txt", levelThreshold=lvlError) 

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
    .replace("&",  "&amp;")
    .replace("<",  "&lt;")
    .replace(">",  "&gt;")
    .replace("\"", "&quot;")
    .replace("'",  "&#39;")

proc generateHtml(hostname: string, page: string): string =
  var article = ""
  var preformatted = false
  var lastLineWasAListItem = false

  for line in page.split("\n"):
    if not lastLineWasAListItem and (line.startsWith("=> ") or line.startsWith("* ")):
      article &= "<ul>\n"
      lastLineWasAListItem = true
    if lastLineWasAListItem and not (line.startsWith("=> ") or line.startsWith("* ")):
      article &= "</ul>\n"
      lastLineWasAListItem = false

    if line.startsWith("```") and not preformatted:
      preformatted = true
      if line.len() == 3: article &= "<pre>\n"
      else: article &= "<pre title=\"" & line[3..^1] & "\">\n"
    elif line.startsWith("```") and preformatted:
      preformatted = false
      article &= "</pre>\n"
    elif preformatted:
      article &= line.escapeTextForHtml() & "\n"
    elif line.startsWith("# "):
      article &= "<h1>" & line[2..^1].escapeTextForHtml() & "</h1>\n"
    elif line.startsWith("## "):
      article &= "<h2>" & line[3..^1].escapeTextForHtml() & "</h2>\n"
    elif line.startsWith("### "):
      article &= "<h3>" & line[4..^1].escapeTextForHtml() & "</h3>\n"
    elif line.startsWith("=> "):
      let parts = line.escapeTextForHtml().split(" ")
      article &= "<li><a href=\"" & parts[1] & "\">" & parts[2..^1].join(" ") & "</a></li>\n"
    elif line.startsWith("* "):
      let parts = line.escapeTextForHtml().split(" ")
      article &= "<li>" & line[2..^1] & "</li>\n"
    elif line.strip().len() > 0:
      article &= "<p>" & line.escapeTextForHtml() & "</p>\n"

  if lastLineWasAListItem:
    article &= "</ul>\n"

  result = htmlTemplate.replace("$CONTENT", article)
  result = result.replace("$HOSTNAME", hostname.escapeTextForHtml())
  result = result.replace("$TITLE", page.split("\n")[0].replace("# ", ""))

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
    if startLineParts[0].toUpperAscii() != "GET":
      await client.handleInvalidMethod()
      return
  
    let path = startLineParts[1]
    let (page, status) = getPage(path)
    let body = generateHtml(request.header["host"], page)

    info("[REQUEST]          " & address & " " & path)

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

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()

proc startServer(useTls: bool, port: uint) {.async.} =
  if useTls and not
   (fileExists("ssl/https.cert") and fileExists("ssl/https.key")):
    error("[START]            Missing './ssl/https.key' and/or './ssl/https.cert'")


  let socket = newAsyncSocket()
  socket.setSockOpt(OptReuseAddr, true)

  var ctx: SslContext
  if useTls:
    ctx = newContext(certFile="ssl/https.cert", keyFile="ssl/https.key")

  socket.bindAddr(Port(port))
  socket.listen()

  info("[START]            Listening on port " & $port)

  while true:
    let (address, client) = await socket.acceptAddr(flags={SafeDisconn})
    if useTls:
      asyncnet.wrapConnectedSocket(ctx, client, handshakeAsServer, "localhost")
    asyncCheck handleClient(client, address)

if isMainModule:
  addHandler(consoleLogger)
  addHandler(fileLog)

  if useHttps: asyncCheck startServer(true, httpsPort)
  if useHttp: asyncCheck startServer(false, httpPort)

  runForever()
