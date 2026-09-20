# Changelog

## Unreleased

- Fixed: `TrailingData` is reported for any token after a complete root value. The code was declared but never produced; such input surfaced as `UnexpectedToken` or `UnexpectedEnd`.
- Fixed: duplicate-key detection uses a string-keyed set instead of scanning every earlier member, so wide objects parse in near-linear time (4,001 keys: 4.6 s down to 0.15 s).
- Fixed: the serializer rejects objects with duplicate names with `DuplicateKey`, so its output always round-trips through the parser.
- Tests assert exact error codes and exact serializer output. The old value comparison could pass when both sides failed to render; it now fails.
- Added `LICENSE-MIT`; the package is dual-licensed MIT or Apache-2.0.
- `check.sh` runs from any working directory.

## 0.1.0 — 2026-09-19

- Added total single-pass JSON parsing with bounded resources.
- Added exact JSON-number preservation and grammar validation.
- Added Unicode escape and surrogate-pair decoding.
- Added duplicate-key rejection.
- Added a fuel-bounded serializer with scalar validation.
- Added Bend-checked laws and executable conformance tests.
