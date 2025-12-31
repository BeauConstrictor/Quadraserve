# Hexaserve

Hexaserve is a simple, static web server that simultaneously serves your content over 6 different protocols - partly for fun, and partly for what that says about you :).

Hexaserve uses `*.gmi` files (like a simplified Markdown) for your content, which are translated at runtime into the appropriate format for whichever format is appropriate for the protocol that the request is using. Gemtext files were chosen because they allow enough formatting to look good when translated to more stylised formats like HTML, while still being easy to reduce down to plaintext for more limited protocols.

Currently, Hexaserve supports a small subset of the target protocols:

- [x] HTTP (port 8080 during early development) (HTTPS is coming later)
- [x] Gemini
- [x] Telnet (port 2323 during early development) (currently slow, using blocking I/O)
- [ ] FTP
- [ ] Gopher
- [ ] Finger

## Build & Install

To build Hexaserve:

```shell
$ make
$ ./install
```

The `./install` command will create a self-signed SSL certificate for you to use temporarily (if you don't care about HTTPS support, you can actually keep this certificate if you wish). It will also create a Hello World page that you can quickly test with

To start Hexaserve:

```shell
$ ./serve
```

This will start the server for each protocol, and restart it if it crashes. If you want to disable a certain protocol, just delete its binary from `bin/` after building.

## Creating Pages

Your pages go in the `content/` directory, and are directly mapped to URLS (or the equivalent system in some of the protcols). For exmaple, `content/test/hello.gmi` could be accessed through `https://example.com/test/hello.gmi`, or `telnet 2323 /test/hello.gmi`. You can create redirects by going into `src/content.nim` and adding entries to the `redirects` table (line 17).
