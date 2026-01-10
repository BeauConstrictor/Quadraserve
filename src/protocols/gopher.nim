# ------------------- #
#    GOPHER CONFIG    #

const
  # if this port is below 1024, then you will have to run ./ALLOW_LOW_PORTS and
  # and enter your password in order to give Quadraserver permission to use the
  # port. The default port below is recommended and means that users can simply
  # enter no port at all when visiting your site. For testing, you may want to
  # set this port higher if you do not currently have admin permissions.
  port = 70
  # this should be the domain that your server is running on. You can leave this
  # value as 'localhost' for as long as you only access your server from the
  # machine that it is running on.
  host = "localhost"

# =------------------ #

import std/[asyncdispatch, asyncnet, strutils, logging, uri]

import ../content


var
  consoleLogger = newConsoleLogger(fmtStr="GOPHER/$levelname ")
  fileLog = newFileLogger("logs/gopher.txt", levelThreshold=lvlError)

proc getItemType(fType: fileType): string =
  case fType:
    of ftGemtext: "1"
    of ftRaw: "0"
    of ftModule: "7"

proc wrap(text: string, width: int): string =
  var lines = newSeq[string]()
  var inCodeBlock = false

  for line in text.splitLines():
    if line.startsWith("```"):
      inCodeBlock = not inCodeBlock
      lines.add(line)
      continue

    if inCodeBlock:
      lines.add(line)
      continue

    if line.strip() == "":
      lines.add("")
      continue

    var isGemLink = line.startsWith("=>")
    var prefix = ""
    var content = line

    if isGemLink:
      let parts = line.splitWhitespace()
      if parts.len >= 2:
        prefix = parts[0] & " " & parts[1] & " "
        content = parts[2 .. ^1].join(" ")
      else:
        lines.add(line)
        continue

    var currentLine = ""

    for word in content.splitWhitespace():
      if currentLine.len + word.len + (if currentLine.len > 0: 1 else: 0) > width:
        if currentLine.len > 0:
          lines.add(prefix & currentLine)
        currentLine = word
      else:
        if currentLine.len > 0:
          currentLine.add(" ")
        currentLine.add(word)

    if currentLine.len > 0:
      if isGemLink:
        lines.add(prefix & currentLine)
      else:
        lines.add(currentLine)

  return lines.join("\n")

proc gemtextLinkToGophermap(line: string): string =
  let parts = line.split(" ")

  let target = parts[1]
  let url = parseUri(target)
  var name = target
  if parts.len() > 2:
    name = parts[2..^1].join(" ")

  if url.scheme == "gopher":
    var port = url.port
    if port == "": port = "70"

    result &= "1" & name & "\t" & url.path & "\t" & url.hostname & "\t"
    result &= port & "\r\n"
  elif url.isAbsolute():
    var port = url.port
    if port == "": port = "70"
    result &= "h" & name & "\tURL:" & $url & "\t" & url.hostname & "\t" 
    result &= port & "\r\n"
  else:
    let it = getItemType(getFileType(getPath(target)))
    result &= it & name & "\t" & target & "\t" & host & "\t" & $port
    result &= "\r\n"

proc translateToGophermap(gemtext: string): string =
  for line in gemtext.wrap(70).split("\n"):
    if line.startsWith("```"):
      result &= "i\r\n"
    elif line.startsWith("=> "):
      result &= gemtextLinkToGophermap(line)
    elif line.startsWith("# "):
      let text = line[2..^1]
      result &= "i" & "#".repeat(text.len()) & "\tfake\t(NULL)\t0\r\n"
      result &= "i" & text  & "\tfake\t(NULL)\t0\r\n"
      result &= "i" & "#".repeat(text.len()) & "\tfake\t(NULL)\t0\r\n"
    elif line.startsWith("## "):
      let text = line[3..^1]
      result &= "i" & "=".repeat(text.len()) & "\tfake\t(NULL)\t0\r\n"
      result &= "i" & text  & "\tfake\t(NULL)\t0\r\n"
      result &= "i" & "=".repeat(text.len()) & "\tfake\t(NULL)\t0\r\n"
    elif line.startsWith("### "):
      let text = line[4..^1]
      result &= "i" & text  & "\tfake\t(NULL)\t0\r\n"
      result &= "i" & "-".repeat(text.len()) & "\tfake\t(NULL)\t0\r\n"
    else:
      result &= "i" & line & "\tfake\t(NULL)\t0\r\n"

  result &= ".\r\n"

proc handleClient(client: AsyncSocket, address: string) {.async.} =
  try:
    let pathTabParts = (await client.recvLine(maxLength=1024)).strip().split("\t")
    var path = ""
    if pathTabParts.len > 0: path = pathTabParts[0]
    var query = ""
    if len(pathTabParts) > 1: query = pathTabParts[1..^1].join("\t")

    let (src, _, fType) = getPage(path)

    var page = src
    if fType == ftGemtext:
      page = src.translateToGophermap()
    elif fType == ftModule:
      page = path.runModule(query, "Gopher").translateToGophermap()

    info("[REQUEST]          " & address & " " & path)

    await client.send(page)

  except CatchableError as err:
    error("[REQUEST/RESPONSE] " & err.msg)
  finally:
    client.close()

proc startServer() {.async.} =
  let socket = newAsyncSocket()
  socket.setSockOpt(OptReuseAddr, true)

  socket.bindAddr(Port(port))
  socket.listen()

  info("[START]            Listening on port " & $port)

  while true:
    let (address, client) = await socket.acceptAddr(flags={SafeDisconn})
    await handleClient(client, address)

if isMainModule:
  addHandler(consoleLogger)
  addHandler(fileLog)
  asyncCheck startServer()
  runForever()
