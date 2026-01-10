# Quadraserve

Quadraserve is a simple, mostly-static web server that simultaneously serves your content over 6 different protocols - partly for fun, and partly for what that says about you :).

Quadraserve uses `*.gmi` files (like a simplified Markdown) for your content, which are translated at runtime into the appropriate format for whichever format is appropriate for the protocol that the request is using. Gemtext files were chosen because they allow enough formatting to look good when translated to more stylised formats like HTML, while still being easy to reduce down to plaintext for more limited protocols.

Currently, Quadraserve supports a small subset of the target protocols:

- [x] HTTP
- [x] Gemini
- [x] Gopher
- [x] Finger

## Setup

To start using Quadraserve, first clone the Github repo:

```shell
$ git clone https://github.com/BeauConstrictor/Quadraserve
$ cd Quadraserve
```

Once you are have cloned Quadraserve, you can set up logs and SSL certificates like so:

```shell
$ sh ./install
```

This will prompt you to enter some information to include in the SSL certificate, most of which you can leave blank by hitting return. The only required field is *Common Name*, where you should enter the hostname that you will use for your website.

Finally, to build and run Quadraserve, run these:

```shell
$ make
$ sudo ./ALLOW_LOW_PORTS # allows the binaries to bind to low ports (eg. 443, 70, 79)
$ ./serve 
```

## Creating Pages

Your pages go in the `content/` directory, and are directly mapped to URLS (or the equivalent system in some of the protcols). For exmaple, `content/test/hello.gmi` could be accessed through `https://example.com/test/hello.gmi`, or `telnet 2323 /test/hello.gmi`. You can create redirects by going into `src/content.nim` and adding entries to the `redirects`.

### Modules

Quadraserve also allows you to add dynamic behaviour to your site. In the `content/modules/` directory, you can place executable files (can be scripts if you add a shebang). If a user visits one of these files, they will be prompted to enter some text, which will be passed to the program as argument 1 and the output of the program will be rendered as Gemtext and sent to the client. The program will also be passed some environment variables:

- $PROTOCOL - either 'HTTP', 'Gemini' or 'Gopher'
