# Hexaserve

A minimal static web server that serves content over six different protocols

![MIT License](https://img.shields.io/badge/license-MIT-blue)

These are the protocols that this server supports:

- [ ] HTTP(S)
- [x] Gemini
- [ ] Gopher
- [ ] Finger
- [ ] FTP
- [ ] SSH

## Getting Started

To try out hexaserve, clone the repo and run these commands:

```sh
$ make
$ ./install
$ sudo ./serve
```

NOTE: `./serve` requires sudo because some ports require special privileges to bind to

This will build the project, create some empty log files and start the servers for every protocol. To disable a certain protocol, just delete its binary from the `bin/` directory.

## Contributing

Contributions are welcome! Especially bug reports and patches.

## License

This project is licensed under the [GNU AGPL-3.0](https://github.com/BeauConstrictor/Ozpex-128/blob/main/LICENSE).
