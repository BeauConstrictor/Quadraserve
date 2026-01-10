# ------------------- #
#    GEMINI CONFIG    #

const
  # if this port is below 1024, then you will have to run ./ALLOW_LOW_PORTS and
  # and enter your password in order to give Quadraserver permission to use the
  # port. The default port below is recommended and means that users can simply
  # enter no port at all when visiting your site. For testing, you may want to
  # set this port higher if you do not currently have admin permissions.
  port = 1965

# =------------------ #

import std/[asyncdispatch, asyncnet, net, uri, logging, os]

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

proc handleClient(client: AsyncSocket, address: string) {.async.} =
  try:

    let urlText = await client.recvLine(maxLength=1024)
    let url = parseUri(decodeUrl(urlText))
    var (page, status, fType) = getPage(url.path)

    info("[REQUEST]         " & address & " " & url.path)

    if fType == ftModule and url.query != "":
      page = runModule(url.path, url.query, "Gemini")
      fType = ftGemtext
    elif fType == ftModule:
      await client.send("10 Start typing:\r\n")
      client.close()
      return

    let (statusNumber, shouldGiveBody) = getStatusNumber(status)

    await client.send(statusNumber & " ")
    if not shouldGiveBody:
      await client.send(($status)[2..^1] & " for resource '" & url.path & "'")
    else:
      await client.send("text/gemini")
    await client.send("\r\n")

    if shouldGiveBody:
      await client.send(page)

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()

proc startServer() {.async.} =
  if not (fileExists("ssl/gemini.cert") and fileExists("ssl/gemini.key")):
    error "[START]           Missing './ssl/gemini.key' and/or './ssl/gemini.cert'"
    while true: discard

  let socket = newAsyncSocket()
  socket.setSockOpt(OptReuseAddr, true)

  let ctx = newContext(certFile="ssl/gemini.cert", keyFile="ssl/gemini.key")

  socket.bindAddr(Port(port))
  socket.listen()

  info("[START]            Listening on port " & $port)

  while true:
    let (address, client) = await socket.acceptAddr(flags={SafeDisconn})
    asyncnet.wrapConnectedSocket(ctx, client, handshakeAsServer, "localhost")
    await handleClient(client, address)

if isMainModule:
  addHandler(consoleLogger)
  addHandler(fileLog)
  asyncCheck startServer()
  runForever()
