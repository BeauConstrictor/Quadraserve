import std/[os, strutils, tables, times, osproc, strtabs]

import cache

# -------------------- #
#    GENERAL CONFIG   ##

const
  # map certain URLs on your server to files, so that filenames do not have to
  # be used as-is. You should generally always have a redirect for the homepage
  # ('/'), as is provided here.
  redirects = {
    "/": "index.gmi",
  }.toTable

  # how many a page can remain cached for before a full file lookup is required
  # this value should reflect somewhat how frequently you make changes to your
  # pages.
  cacheLifetimeMins = 5
  # how many pages can be cached as a maximum. if requests to your server are
  # slow enough that cacheLifetimeMins is frequently reached, the cache may
  # never hit this limit. If your server has low memory, reduce this value.
  cacheSize = 100

# -------------------- #

type
  PathTraversalError = object of ValueError

  statusCode* = enum
    scSuccess
    scNotFound
    scUnhandledError
    scAccessDenied

  fileType* = enum
    ftGemtext
    ftModule
    ftRaw

const
  pathTraversalErrMsg = staticRead("errs/traversal.gmi")
  notFoundErrMsg = staticRead("errs/notfound.gmi")

var
  pageCache = initLRUCache(readFile)

proc getFileType*(path: string): fileType =
  var extension = ""
  let extensionParts = path.split(".")
  if extensionParts.len > 0: extension = extensionParts[^1]

  if path.startsWith("content/modules/"):
    return ftModule

  return case extension:
    of "gmi": ftGemtext
    else: ftRaw

proc getPath*(originalLocation: string): string =
  var location = originalLocation
  if originalLocation in redirects:
    location = redirects[originalLocation]

  location = location.strip(chars={'/'}, trailing=false)

  if ".." in location:
    raise newException(PathTraversalError, "'..' substring detected.")
  if location.startsWith("/"):
    raise newException(PathTraversalError, "'/' substring detected.")

  if location in redirects:
    return joinPath("content", redirects[location])
  else:
    return joinPath("content", location)

proc getPage*(location: string): (string, statusCode, fileType) =
  var path: string
  try:
    path = getPath(location)
  except PathTraversalError:
    return (pathTraversalErrMsg, scAccessDenied, ftGemtext)
  if not fileExists(path):
    return (notFoundErrMsg, scNotFound, ftGemtext)

  let fType = getFileType(path)
  if fType == ftModule: return ("You cannot visit this page directly.",
                                scSuccess, fType)

  let chosenMinsAgo = epochTime() - cacheLifetimeMins*60
  pageCache.clean(maxItems=cacheSize)

  return (pageCache.get(path, oldest=chosenMinsAgo), scSuccess, fType)

proc runModule*(location: string, query: string, protocol: string): string =
  var path: string
  try:
    path = getPath(location)
  except PathTraversalError:
    return "Path traversal? I don't think so."
  if not fileExists(path):
    return "That file does not exist."

  let fType = getFileType(getPath(location))
  if fType != ftModule: return "Not a module that can be executed. File is " &
                               "of type '" & $fType & "'"

  try:
    return execProcess(path, args=[query],
                       env={"protocol": protocol}.newStringTable)
  except OSError:
    return "No such file or directory."
