import std/[net, uri, logging]

import ../content

var
  consoleLogger = newConsoleLogger(fmtStr="TELNET/$levelname ")
  fileLog = newFileLogger("logs/gemini.txt", levelThreshold=lvlError) 

const
  welcomeMessage = "**** Hexaserve Telnet Server ****\n\nEnter a path to visit:\n"

proc handleClient(client: Socket, address: string) =
  try:

    client.send("\e[2J\e[H\n")
    client.send(welcomeMessage)

    info("[REQUEST] " & address & " ...")

    let path = client.recvLine()
    client.send("Fetching " & path & "...\n")
    let (page, _) = getPage(path)

    info("[REQUEST] " & address & " " & path)

    client.send(page)

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()
  
proc startServer() =
  let socket = newSocket()
  socket.setSockOpt(OptReuseAddr, true)

  socket.bindAddr(Port(2323))
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
