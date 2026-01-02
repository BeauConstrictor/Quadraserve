# ------------------- #
#    GOPHER CONFIG    #

const
  welcomeMessage = "**** Hexaserve Telnet Server ****\n\nEnter a path to visit:\n"
  port = 2323

# =------------------ #

import std/[net, uri, logging]

import ../content

var
  consoleLogger = newConsoleLogger(fmtStr="TELNET/$levelname ")
  fileLog = newFileLogger("logs/gemini.txt", levelThreshold=lvlError) 


proc handleClient(client: Socket, address: string) =
  try:

    client.send("\e[2J\e[H\n")
    client.send(welcomeMessage)

    info("[CONNECTION]       " & address & " ...")

    let path = client.recvLine()
    client.send("Fetching " & path & "...\n")
    let (page, _) = getPage(path)

    info("[REQUEST]          " & address & " " & path)

    client.send(page)

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()
  
proc startServer() =
  let socket = newSocket()
  socket.setSockOpt(OptReuseAddr, true)

  socket.bindAddr(Port(port))
  socket.listen()

  info("[START]            Listening on port " & $port)

  while true:
    var client: Socket
    var address = ""
    socket.acceptAddr(client, address, flags={SafeDisconn})
    handleClient(client, address)

if isMainModule:
  addHandler(consoleLogger)
  addHandler(fileLog)
  startServer()
