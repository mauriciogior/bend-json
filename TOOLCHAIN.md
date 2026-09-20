# Reproducible toolchain

The checked result was produced with:

- Bend `2.0.16`
- Linux x86-64 release archive
- archive SHA-256: `496ff13a312221c3dc0dde4077368ced42c0f3eadcb61c2d43de5caddf0e50b4`
- telemetry disabled with `BEND_NO_TELEMETRY=1`

The same result was reproduced on macOS arm64 with the `bend-2.0.16-darwin-arm64.tar.gz` release archive (SHA-256 `856a7b80c4401569228d3e3d4aa3efbe8b535741a57793aa343c95b49db7490c`).

The package does not modify or vendor the Bend compiler. It imports the released `Base` module.

Run `./check.sh` from this directory with `bend` on `PATH`, or set `BEND_BIN` to an explicit executable path.
