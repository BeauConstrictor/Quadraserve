# Hexaserve

A minimal static web server that serves content over six different protocols

![MIT License](https://img.shields.io/badge/license-MIT-blue)

These are the protocols that this server supports:

- [x] HTTP (port 8080 for now)
- [x] Gemini
- [ ] Gopher
- [ ] Finger
- [ ] FTP
- [ ] Telnet

Note that Hexaserve is still in a very early state and should not be used in production. All the servers are still single-threaded, so one slow client can completely block other requests. You have been warned.

## Getting Started

To try out hexaserve, clone the repo and run these commands:

```sh
$ make
$ ./install
$ sudo ./serve
```

NOTE: `./serve` requires sudo because some ports require special privileges to bind to

This will build the project, create an ssl certificate for your website and start the servers for every protocol. To disable a certain protocol, just delete its binary from the `bin/` directory.

## Contributing

Contributions are welcome! Especially bug reports and patches.

## License

This project is licensed under the [GNU AGPL-3.0](https://github.com/BeauConstrictor/Ozpex-128/blob/main/LICENSE).
