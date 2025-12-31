import std/[net, uri, logging]

import ../content

var
  consoleLogger = newConsoleLogger(fmtStr="GEMINI/$levelname ")
  fileLog = newFileLogger("logs/gemini.txt", levelThreshold=lvlError)

proc getStatusNumber(status: statusCode): (string, bool) =
  return case status:
    of scSuccess: ("20", true)
    of scNotFound: ("51", false)
    of scAccessDenied: ("59", false)
    of scUnhandledError: ("40", false)

proc handleClient(client: Socket, address: string) =
  try:

    let urlText = client.recvLine(timeout=1000, maxLength=1024)
    let url = parseUri(decodeUrl(urlText))
    let (page, status) = getPage(url.path)

    info("[REQUEST] " & address & " " & url.path)

    let (statusNumber, shouldGiveBody) = getStatusNumber(status)

    client.send(statusNumber & " ")
    if not shouldGiveBody:
      client.send(($status)[2..^1] & " for resource '" & url.path & "'")
    else:
      client.send("text/gemini")
    client.send("\r\n")

    if shouldGiveBody:
      client.send(page)

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()

proc startServer() =
  let socket = newSocket()
  socket.setSockOpt(OptReuseAddr, true)

  let ctx = newContext(certFile="ssl/cert.pem", keyFile="ssl/key.pem")

  socket.bindAddr(Port(1965))
  socket.listen()

  while true:
    var client: Socket
    var address = ""
    socket.acceptAddr(client, address, flags={SafeDisconn})
    ctx.wrapConnectedSocket(client, handshakeAsServer, "localhost")
    handleClient(client, address)

if isMainModule:
  addHandler(consoleLogger)
  addHandler(fileLog)
  startServer()
