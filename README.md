# bend-json

A dependency-free JSON parser and serializer written in Bend 2.

## Status

This is an experimental `0.1.0` package targeting Bend `2.0.16`. It supports:

- `null`, booleans, strings, arrays, objects, and exact JSON number lexemes;
- all JSON string escapes, including UTF-16 surrogate pairs;
- strict rejection of raw control characters, invalid escapes, malformed numbers, unpaired surrogates, trailing data, trailing commas, and duplicate object keys;
- parser limits for input length, nesting depth, node count, and string/number token length;
- bounded serialization through an explicit work budget;
- machine-checked Bend laws in `PROOF.bend`.

Numbers remain strings in `JNumber`. This preserves precision and spelling; a typed codec can decide whether a number fits `U32`, a decimal type, or another application representation.

## Use

```bend
import 0x<package-hash>/main.bend as Json

def main() -> Result<&2, &2, Json.JsonError, Json.Json>:
  Json.Json.parse("{\"ok\":true,\"items\":[1,2,3]}")
```

For a local checkout:

```bend
import ./bend-json/main.bend as Json
```

Run the proof gate and executable tests:

```sh
bend bend-json/PROOF.bend
bend bend-json/tests/main.bend
bend bend-json/tests/json_test_suite.bend
```

`./check.sh` runs all of them plus a type check of `main.bend`, from any working directory.

## Errors

`Json.parse` returns `Fail{JsonError{code, position}}` when it rejects input. `position` is the 1-based index of the character at which the error was detected. Errors found at end of input report the input length, `InputTooLong` reports `0n`, and serialization errors always report `0n`.

## Serialization budget

`Json.stringify` uses a fixed budget of 10000 work units; `Json.stringify_with(fuel, value)` takes an explicit one. Every emitted token, container item, and string character costs one unit, so a document needs roughly one unit per character of output plus a small constant per value. Running out returns `RenderFuelExhausted`. The default suits small API payloads; pass a larger budget for anything bigger.

## Proof coverage

`LAWS.bend` and `PROOF.bend` machine-check:

- round trips for both Boolean values and null through the real generic serializer and parser;
- acceptance and rejection examples for the number grammar;
- decoding of escapes and a Unicode surrogate pair;
- duplicate-key rejection;
- a nested object/array round trip containing every JSON value category.

These proofs establish exactly the stated propositions. They do not yet constitute a universal proof that `parse(stringify(value)) == value` for every JSON tree, nor a full mechanization of RFC 8259. The test suite covers broader valid and invalid inputs. Expanding the general round-trip theorem is the next proof milestone.

The vendored conformance program contains 93 valid and 174 invalid UTF-8 text cases derived from Nicolas Seriot's JSONTestSuite. It excludes implementation-defined cases, byte sequences that cannot be represented as Bend `String` values, oversized compiler-stress fixtures, and two duplicate-key fixtures because this package intentionally applies the stricter duplicate-rejection policy. See `tests/JSONTestSuite-LICENSE`.

## Security choices

- Duplicate object names are rejected instead of applying first-wins or last-wins behavior. Detection uses a string-keyed set, so wide objects parse in near-linear time.
- The serializer also rejects duplicate names, so every text `stringify` produces is accepted by `parse`.
- Numbers are validated against the JSON grammar and never coerced to `F32`.
- Invalid Unicode scalar values and unpaired surrogate escapes are rejected.
- Parsing is total: the recursive scanner consumes one source character per recursive call.
- Serialization is total under the caller's explicit fuel; exhaustion returns an error.

The AST constructors are public in Bend, so `JNumber` can be constructed with invalid text. Serialization validates every number before emitting it.

## License

MIT License
