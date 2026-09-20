import Base
import ../main.bend as Json

# Executable tests for bend-json. Every check prints "ok <name>" and the
# program exits with status 1 on the first failure.

def code_name(code: Json.JsonErrorCode) -> String:
  match code:
    case Json.InputTooLong{}: "InputTooLong"
    case Json.UnexpectedCharacter{}: "UnexpectedCharacter"
    case Json.UnexpectedEnd{}: "UnexpectedEnd"
    case Json.UnexpectedToken{}: "UnexpectedToken"
    case Json.InvalidLiteral{}: "InvalidLiteral"
    case Json.InvalidNumber{}: "InvalidNumber"
    case Json.InvalidEscape{}: "InvalidEscape"
    case Json.InvalidUnicode{}: "InvalidUnicode"
    case Json.ControlInString{}: "ControlInString"
    case Json.TokenTooLong{}: "TokenTooLong"
    case Json.TooDeep{}: "TooDeep"
    case Json.TooManyNodes{}: "TooManyNodes"
    case Json.DuplicateKey{}: "DuplicateKey"
    case Json.TrailingData{}: "TrailingData"
    case Json.RenderFuelExhausted{}: "RenderFuelExhausted"

def error_name(error: Json.JsonError) -> String:
  match error:
    case Json.JsonError{code, position}:
      code_name(code)

def render(value: Json.Json) -> Result<&2, &2, Json.JsonError, String>:
  Json.Json.stringify_with(100000n, value)

# Assertion helpers
# -----------------

def expect.same(name: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": value differs")

def expect.text(name: String, +want: String, +got: String, same: Bool) -> IO(Unit):
  match same:
    case True{}:
      IO.print("ok " ++ name)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": expected " ++ want ++ " but got " ++ got)

def expect.rendered(name: String, got: Result<&2, &2, Json.JsonError, String>, want: Result<&2, &2, Json.JsonError, String>) -> IO(Unit):
  match got want:
    case Done{+a} Done{+b}:
      expect.text(name, b, a, String.eq(a, b))
    case got want:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": a value could not be rendered")

# The parse succeeds and the value renders exactly like `want`.
def expect(+name: String, got: Result<&2, &2, Json.JsonError, Json.Json>, want: Json.Json) -> IO(Unit):
  match got:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": parse failed with " ++ error_name(error))
    case Done{value}:
      expect.rendered(name, render(value), render(want))

# The parse succeeds and re-serializes to exactly `want`.
def expect_text(+name: String, got: Result<&2, &2, Json.JsonError, Json.Json>, want: String) -> IO(Unit):
  match got:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": parse failed with " ++ error_name(error))
    case Done{value}:
      expect.rendered(name, render(value), Done{want})

def expect_ok(+name: String, got: Result<&2, &2, Json.JsonError, Json.Json>) -> IO(Unit):
  match got:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": parse failed with " ++ error_name(error))
    case Done{value}:
      IO.print("ok " ++ name)

def expect_fail(+name: String, got: Result<&2, &2, Json.JsonError, Json.Json>) -> IO(Unit):
  match got:
    case Fail{error}:
      IO.print("ok " ++ name)
    case Done{value}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": accepted invalid JSON")

# The parse fails with exactly the named error code.
def expect_code(+name: String, got: Result<&2, &2, Json.JsonError, Json.Json>, +want: String) -> IO(Unit):
  match got:
    case Fail{error}:
      +got_name = error_name(error)
      expect.text(name, want, got_name, String.eq(want, got_name))
    case Done{value}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": accepted invalid JSON, expected " ++ want)

# Serialization succeeds with exactly `want`.
def expect_render(+name: String, got: Result<&2, &2, Json.JsonError, String>, +want: String) -> IO(Unit):
  match got:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": stringify failed with " ++ error_name(error))
    case Done{+text}:
      expect.text(name, want, text, String.eq(want, text))

# Serialization fails with exactly the named error code.
def expect_render_code(+name: String, got: Result<&2, &2, Json.JsonError, String>, +want: String) -> IO(Unit):
  match got:
    case Fail{error}:
      +got_name = error_name(error)
      expect.text(name, want, got_name, String.eq(want, got_name))
    case Done{+text}:
      IO.die(Unit, 1, "FAIL " ++ name ++ ": stringify succeeded with " ++ text ++ ", expected " ++ want)

# Input generators
# ----------------

def nested(+n: Nat) -> String:
  match n:
    case 0n: "1"
    case 1n+p: "[" ++ nested(p) ++ "]"

def members(+n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: members(p, ",\"k" ++ Nat.show(p) ++ "\":" ++ Nat.show(p) ++ acc)

def wide_object(+n: Nat) -> String:
  "{\"first\":true" ++ members(n, "}")

def wide_object_with_duplicate(+n: Nat) -> String:
  "{\"first\":true" ++ members(n, ",\"first\":false}")

def main() -> IO(Unit):
  do IO<Unit>:
    # Scalars and structure
    expect("null", Json.Json.parse("null"), Json.JNull{})
    expect("bool", Json.Json.parse(" true \n"), Json.JBool{True{}})
    expect("number", Json.Json.parse("-12.50e+3"), Json.JNumber{"-12.50e+3"})
    expect("negative zero", Json.Json.parse("-0"), Json.JNumber{"-0"})
    expect_text("exponent spellings", Json.Json.parse("[1E+2, 1e-2, 0e0, 0.0]"), "[1E+2,1e-2,0e0,0.0]")
    expect("escapes", Json.Json.parse("\"a\\n\\t\\\"\\\\b\""), Json.JString{"a\n\t\"\\b"})
    expect("solidus escape", Json.Json.parse("\"\\/\""), Json.JString{"/"})
    expect("unicode", Json.Json.parse("\"A\\u00df\\u6771\\uD834\\uDD1E\""), Json.JString{SCon{'A', SCon{'ß', SCon{'東', SCon{Chr{119070}, SNil{}}}}}})
    expect("uppercase hex digits", Json.Json.parse("\"\\u00DF\""), Json.JString{"ß"})
    expect("nested", Json.Json.parse("{\"a\":[null,true,false,{\"n\":1}]}"), Json.JObject{[Json.Member{"a", Json.JArray{[Json.JNull{}, Json.JBool{True{}}, Json.JBool{False{}}, Json.JObject{[Json.Member{"n", Json.JNumber{"1"}}]}]}}]})
    expect_text("member order preserved", Json.Json.parse("{\"b\":1,\"a\":2}"), "{\"b\":1,\"a\":2}")
    expect_text("empty containers", Json.Json.parse(" { \"a\" : [ ] , \"b\" : { } } "), "{\"a\":[],\"b\":{}}")
    expect_text("escaped key", Json.Json.parse("{\"\\n\\u0000\":1}"), "{\"\\n\\u0000\":1}")
    expect_text("same key in different objects", Json.Json.parse("{\"a\":{\"a\":1},\"b\":[{\"a\":2},{\"a\":3}]}"), "{\"a\":{\"a\":1},\"b\":[{\"a\":2},{\"a\":3}]}")
    expect_text("whitespace everywhere", Json.Json.parse("\t[\r\n 1 ,\n\"x\"\t, null ]\n"), "[1,\"x\",null]")
    expect_ok("wide object", Json.Json.parse(wide_object(2000n)))
    expect_ok("deep array at the default limit", Json.Json.parse(nested(64n)))

    # Rejections, by error code
    expect_code("empty input", Json.Json.parse(""), "UnexpectedEnd")
    expect_code("whitespace only", Json.Json.parse(" \n"), "UnexpectedEnd")
    expect_code("unterminated array", Json.Json.parse("[1,2"), "UnexpectedEnd")
    expect_code("unterminated object", Json.Json.parse("{\"a\":1"), "UnexpectedEnd")
    expect_code("unterminated string", Json.Json.parse("\"abc"), "UnexpectedEnd")
    expect_code("unterminated literal", Json.Json.parse("tru"), "UnexpectedEnd")
    expect_code("unterminated escape", Json.Json.parse("\"\\"), "UnexpectedEnd")
    expect_code("two roots", Json.Json.parse("1 2"), "TrailingData")
    expect_code("two arrays", Json.Json.parse("[][]"), "TrailingData")
    expect_code("container after root", Json.Json.parse("{} ["), "TrailingData")
    expect_code("string after root", Json.Json.parse("null \"x\""), "TrailingData")
    expect_code("bracket after root", Json.Json.parse("[]]"), "TrailingData")
    expect_code("comma after root", Json.Json.parse("1,"), "TrailingData")
    expect_code("garbage after root", Json.Json.parse("[] x"), "UnexpectedCharacter")
    expect_code("plus sign", Json.Json.parse("+1"), "UnexpectedCharacter")
    expect_code("form feed is not whitespace", Json.Json.parse("\u{C}1"), "UnexpectedCharacter")
    expect_code("single quotes", Json.Json.parse("'a'"), "UnexpectedCharacter")
    expect_code("trailing comma", Json.Json.parse("[1,]"), "UnexpectedToken")
    expect_code("trailing comma in object", Json.Json.parse("{\"a\":1,}"), "UnexpectedToken")
    expect_code("leading comma", Json.Json.parse("[,1]"), "UnexpectedToken")
    expect_code("missing comma", Json.Json.parse("[1 2]"), "UnexpectedToken")
    expect_code("missing colon", Json.Json.parse("{\"a\" 1}"), "UnexpectedToken")
    expect_code("missing value", Json.Json.parse("{\"a\":}"), "UnexpectedToken")
    expect_code("non-string key", Json.Json.parse("{1:2}"), "UnexpectedToken")
    expect_code("close without open", Json.Json.parse("]"), "UnexpectedToken")
    expect_code("mismatched close", Json.Json.parse("[}"), "UnexpectedToken")
    expect_code("leading zero", Json.Json.parse("01"), "InvalidNumber")
    expect_code("negative leading zero", Json.Json.parse("-01"), "InvalidNumber")
    expect_code("lone minus", Json.Json.parse("-"), "InvalidNumber")
    expect_code("minus then dot", Json.Json.parse("-.5"), "InvalidNumber")
    expect_code("dot without fraction", Json.Json.parse("1."), "InvalidNumber")
    expect_code("dot before exponent", Json.Json.parse("1.e5"), "InvalidNumber")
    expect_code("bad exponent", Json.Json.parse("1e"), "InvalidNumber")
    expect_code("signed exponent without digits", Json.Json.parse("1e+"), "InvalidNumber")
    expect_code("dot after exponent", Json.Json.parse("1e5.5"), "UnexpectedCharacter")
    expect_code("hex number", Json.Json.parse("0x1"), "UnexpectedCharacter")
    expect_code("misspelled literal", Json.Json.parse("nulx"), "InvalidLiteral")
    expect_code("capitalized literal", Json.Json.parse("True"), "UnexpectedCharacter")
    expect_code("unknown escape", Json.Json.parse("\"\\x\""), "InvalidEscape")
    expect_code("escaped single quote", Json.Json.parse("\"\\'\""), "InvalidEscape")
    expect_code("raw control", Json.Json.parse(SCon{'"', SCon{Chr{1}, SCon{'"', SNil{}}}}), "ControlInString")
    expect_code("raw newline in string", Json.Json.parse("\"a\nb\""), "ControlInString")
    expect_code("unpaired high surrogate", Json.Json.parse("\"\\uD800\""), "InvalidUnicode")
    expect_code("lone low surrogate", Json.Json.parse("\"\\uDC00\""), "InvalidUnicode")
    expect_code("high surrogate then non-surrogate", Json.Json.parse("\"\\uD800\\u0041\""), "InvalidUnicode")
    expect_code("high surrogate then other escape", Json.Json.parse("\"\\uD800\\n\""), "InvalidUnicode")
    expect_code("high surrogate then plain char", Json.Json.parse("\"\\uD800a\""), "InvalidUnicode")
    expect_code("non-hex digit", Json.Json.parse("\"\\u00G0\""), "InvalidUnicode")
    expect_code("short hex escape", Json.Json.parse("\"\\u00\""), "InvalidUnicode")
    expect_code("duplicate key", Json.Json.parse("{\"a\":1,\"a\":2}"), "DuplicateKey")
    expect_code("duplicate key via escape", Json.Json.parse("{\"a\":1,\"\\u0061\":2}"), "DuplicateKey")
    expect_code("duplicate empty key", Json.Json.parse("{\"\":1,\"\":2}"), "DuplicateKey")
    expect_code("duplicate key in wide object", Json.Json.parse(wide_object_with_duplicate(2000n)), "DuplicateKey")

    # Limits
    expect_ok("input limit exact", Json.Json.parse_with(Json.JsonLimits{4n, 64n, 100n, 100n}, "null"))
    expect_code("input limit", Json.Json.parse_with(Json.JsonLimits{3n, 64n, 100n, 100n}, "null"), "InputTooLong")
    expect_ok("depth limit exact", Json.Json.parse_with(Json.JsonLimits{100n, 1n, 100n, 100n}, "[1]"))
    expect_code("depth limit", Json.Json.parse_with(Json.JsonLimits{100n, 1n, 100n, 100n}, "[[]]"), "TooDeep")
    expect_ok("depth zero allows scalars", Json.Json.parse_with(Json.JsonLimits{100n, 0n, 100n, 100n}, "1"))
    expect_code("depth zero rejects containers", Json.Json.parse_with(Json.JsonLimits{100n, 0n, 100n, 100n}, "{}"), "TooDeep")
    expect_code("default depth limit", Json.Json.parse(nested(65n)), "TooDeep")
    expect_ok("node limit exact", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 3n, 100n}, "[1,2]"))
    expect_code("node limit", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 2n, 100n}, "[1,2]"), "TooManyNodes")
    expect_code("node limit zero", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 0n, 100n}, "1"), "TooManyNodes")
    expect_ok("number token limit exact", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 100n, 5n}, "1.5e7"))
    expect_code("number token limit", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 100n, 4n}, "1.5e7"), "TokenTooLong")
    expect_code("number token limit zero", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 100n, 0n}, "1"), "TokenTooLong")
    expect_ok("string token limit exact", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 100n, 2n}, "\"ab\""))
    expect_code("string token limit", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 100n, 1n}, "\"ab\""), "TokenTooLong")
    expect_ok("string token limit counts decoded chars", Json.Json.parse_with(Json.JsonLimits{100n, 64n, 100n, 1n}, "\"\\uD834\\uDD1E\""))

    # Number validation API
    expect_ok("number api accepts", Json.Json.number("-0.5E-3"))
    expect_code("number api rejects exponent", Json.Json.number("1e"), "InvalidNumber")
    expect_code("number api rejects leading zero", Json.Json.number("007"), "InvalidNumber")
    expect_code("number api rejects empty", Json.Json.number(""), "InvalidNumber")
    expect_code("number api rejects spaces", Json.Json.number(" 1"), "InvalidNumber")

    # Serializer
    expect_render("render scalars", Json.Json.stringify(Json.JArray{[Json.JNull{}, Json.JBool{True{}}, Json.JBool{False{}}, Json.JNumber{"1e3"}]}), "[null,true,false,1e3]")
    expect_render("render escapes", Json.Json.stringify(Json.JString{"a\"b\\c/d\u{8}\u{C}\n\r\t\u{0}\u{1F}\u{7F}é"}), "\"a\\\"b\\\\c/d\\b\\f\\n\\r\\t\\u0000\\u001f\u{7F}é\"")
    expect_render("render nested", Json.Json.stringify(Json.JObject{[Json.Member{"a", Json.JArray{[Json.JObject{[]}, Json.JArray{[]}]}}, Json.Member{"b", Json.JString{""}}]}), "{\"a\":[{},[]],\"b\":\"\"}")
    expect_render_code("render invalid number", Json.Json.stringify(Json.JNumber{"01"}), "InvalidNumber")
    expect_render_code("render empty number", Json.Json.stringify(Json.JNumber{""}), "InvalidNumber")
    expect_render_code("render duplicate keys", Json.Json.stringify(Json.JObject{[Json.Member{"a", Json.JNull{}}, Json.Member{"b", Json.JNull{}}, Json.Member{"a", Json.JNull{}}]}), "DuplicateKey")
    expect_render_code("render fuel zero", Json.Json.stringify_with(0n, Json.JNull{}), "RenderFuelExhausted")
    expect_render("render fuel one", Json.Json.stringify_with(1n, Json.JNull{}), "null")
    expect_render_code("render fuel short", Json.Json.stringify_with(4n, Json.JArray{[Json.JNumber{"1"}]}), "RenderFuelExhausted")
    expect_render("render fuel exact", Json.Json.stringify_with(5n, Json.JArray{[Json.JNumber{"1"}]}), "[1]")

    # Round trips
    expect_text("canonical round trip", Json.Json.parse("{\"ok\":true,\"items\":[1,-2.5e+3,\"x\\ny\",null,{\"k\":[]}]}"), "{\"ok\":true,\"items\":[1,-2.5e+3,\"x\\ny\",null,{\"k\":[]}]}")
    expect_text("pretty input round trip", Json.Json.parse("{\n  \"ok\": true,\n  \"items\": [ 1, 2 ]\n}\n"), "{\"ok\":true,\"items\":[1,2]}")
    expect_text("escape round trip", Json.Json.parse("\"\\u0041\\u00e9\\uD83D\\uDE00\\u0007\""), "\"Aé😀\\u0007\"")
    IO.print("all bend-json tests passed")
