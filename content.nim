import std/[os, strutils, tables]

type
  PathTraversalError = object of ValueError

  statusCode* = enum
    scSuccess
    scNotFound
    scUnhandledError
    scAccessDenied

const
  unhandledErrMsg = staticRead("errs/unhandled.gmi")
  pathTraversalErrMsg = staticRead("errs/traversal.gmi")
  notFoundErrMsg = staticRead("errs/notfound.gmi")

  redirects = {
    "": "index.gmi",
    "/": "index.gmi",
  }.toTable

proc getPath(originalLocation: string): string =
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

proc getPage*(location: string): (string, statusCode) =
  var path: string
  
  try:
    path = getPath(location)
  except PathTraversalError:
    return (pathTraversalErrMsg, scAccessDenied)

  if not fileExists(path):
    return (notFoundErrMsg, scNotFound)

  try:
    return (readFile(path), scSuccess)
  except CatchableError:
    return (unhandledErrMsg, scUnhandledError)
