import std/[net, logging, strutils, tables, times, strformat]

import ../content

type
  HttpMessage = object
    startLine: string
    header: Table[string, string]
    body: string

  HttpError = object of ValueError

const
  htmlTemplate = staticRead("../template.html")
  recvTimeout = 1000#ms



var
  consoleLogger = newConsoleLogger()
  fileLog = newFileLogger("logs/gemini.txt", levelThreshold=lvlError) 

proc `$`(msg: HttpMessage): string =
  result &= msg.startLine & "\r\n"
  for key in msg.header.keys():
    result &= key.toLowerAscii() & ": " & msg.header[key] & "\r\n"
  result &= "\r\n"
  result &= msg.body
proc recvHttpMessage(client: Socket): HttpMessage =
  result.startLine = client.recvLine(timeout=recvTimeout)
  while true:
    let line = client.recvLine(timeout=recvTimeout)
    if line.strip() == "": break
    let parts = line.split(": ")
    if parts.len() < 2: raise newException(HttpError, "Malformed header")
    result.header[parts[0].toLowerAscii()] = parts[1..^1].join(": ")
  
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
    result.body = client.recv(contentLength, timeout=recvTimeout)

proc getStatusLine(status: statusCode): string =
  return case status:
    of scSuccess: "200 OK"
    of scNotFound: "404 Not Found"
    of scAccessDenied: "403 Forbidden"
    of scUnhandledError: "500 Internal Server Error"

proc getHttpTimestamp(): string =
  return now().utc().format("ddd, dd MMM yyyy hh:mm:ss") & " GMT"

proc handleBadRequest(client: Socket) =
  let body = "Bad request."
  client.send($HttpMessage(
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
proc handleInvalidVersion(client: Socket) =
  let body = "HTTP version not supported."
  client.send($HttpMessage(
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
proc handleInvalidMethod(client: Socket) =
  let body = "Method not allowed."
  client.send($HttpMessage(
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
  
proc generateHtml(page: string): string =
  var article = ""
  var preformatted = false
  var lastLineWasAListItem = false

  for line in page.split("\n"):
    if line.strip() == "": continue

    if not lastLineWasAListItem and (line.startsWith("=> ") or line.startsWith("* ")):
      article &= "<ul>\n"
      lastLineWasAListItem = true
    if lastLineWasAListItem and not (line.startsWith("=> ") or line.startsWith("* ")):
      article &= "</ul>\n"
      lastLineWasAListItem = false

    if line.startsWith("```") and not preformatted:
      preformatted = true
      article &= "<pre>\n"
    elif line.startsWith("```") and preformatted:
      preformatted = false
      article &= "</pre>\n"
    elif preformatted:
      article &= line & "\n"
    elif line.startsWith("# "):
      article &= "<h1>" & line[2..^1] & "</h1>\n"
    elif line.startsWith("## "):
      article &= "<h2>" & line[3..^1] & "</h2>\n"
    elif line.startsWith("### "):
      article &= "<h3>" & line[4..^1] & "</h3>\n"
    elif line.startsWith("=> "):
      let parts = line.split(" ")
      article &= "<li><a href=\"" & parts[1] & "\">" & parts[2..^1].join(" ") & "</a></li>\n"
    elif line.startsWith("* "):
      let parts = line.split(" ")
      article &= "<li>" & line[2..^1] & "</li>\n"
    else:
      article &= "<p>" & line & "</p>\n"

  result = htmlTemplate.replace("$CONTENT", article)
  result = result.replace("$TITLE", page.split("\n")[0].replace("# ", ""))

proc handleClient(client: Socket, address: string) =
  try:

    let request = client.recvHttpMessage()
    let startLineParts = request.startLine.split(" ")
    if not startLineParts.len() == 3:
      client.handleBadRequest()
      return
    if startLineParts[2] != "HTTP/1.1":
      client.handleInvalidVersion()
      return
    if startLineParts[0] != "GET":
      client.handleInvalidMethod()
      return
  
    let path = startLineParts[1]
    let (page, status) = getPage(path)
    let body = generateHtml(page)

    let response = HttpMessage(
      startLine: "HTTP/1.1 " & getStatusLine(status),
      header: {
        "Content-Length": $len(body),
        "Connection": "close",
        "Server": "Hexaserve",
        "Content-Type": "text/html; charset=utf-8",
        "Date": getHttpTimestamp(),
      }.toTable,
      body: body,
    )

    client.send($response)

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()

proc startServer() =
  let socket = newSocket()
  socket.setSockOpt(OptReuseAddr, true)

  socket.bindAddr(Port(8080))
  socket.listen()

  while true:
    var client: Socket
    var address = ""
    socket.acceptAddr(client, address, flags={SafeDisconn})
    handleClient(client, address)

if isMainModule:
  addHandler(consoleLogger)
  addHandler(fileLog)
  startServer()
