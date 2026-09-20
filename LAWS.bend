import Base
import ./main.bend as Json

# Laws deliberately cover properties the checker proves today. The README
# distinguishes these theorems from RFC conformance tests and from unproved
# claims about every possible tree.

law bool_round_trip:
  for b: Bool
  {Json.Json.parse(Result.default(&2, &2, Json.JsonError, String, Json.Json.stringify_with(16n, Json.JBool{b}), "")) == Done{Json.JBool{b}} : Result<&2, &2, Json.JsonError, Json.Json>}

law null_round_trip:
  {Json.Json.parse(Result.default(&2, &2, Json.JsonError, String, Json.Json.stringify_with(16n, Json.JNull{}), "")) == Done{Json.JNull{}} : Result<&2, &2, Json.JsonError, Json.Json>}

law number_grammar_examples:
  {Json.Json.number_valid("-12.50e+3") == True{} : Bool}

law leading_zero_rejected:
  {Json.Json.number_valid("01") == False{} : Bool}

law escaped_string_example:
  {Json.Json.parse("\"quote: \\\" slash: \\\\ line: \\n\"") == Done{Json.JString{"quote: \" slash: \\ line: \n"}} : Result<&2, &2, Json.JsonError, Json.Json>}

law unicode_pair_example:
  {Json.Json.parse("\"\\uD834\\uDD1E\"") == Done{Json.JString{SCon{Chr{119070}, SNil{}}}} : Result<&2, &2, Json.JsonError, Json.Json>}

law duplicate_key_rejected:
  {Result.is_fail(&2, &2, Json.JsonError, Json.Json, Json.Json.parse("{\"a\":1,\"a\":2}")) == True{} : Bool}

law nested_round_trip_example:
  {Json.Json.parse(Result.default(&2, &2, Json.JsonError, String, Json.Json.stringify_with(256n,
    Json.JObject{[Json.Member{"ok", Json.JBool{True{}}}, Json.Member{"items", Json.JArray{[Json.JNull{}, Json.JNumber{"-1.25e2"}, Json.JString{"x\ny"}]}}]}), ""))
    == Done{Json.JObject{[Json.Member{"ok", Json.JBool{True{}}}, Json.Member{"items", Json.JArray{[Json.JNull{}, Json.JNumber{"-1.25e2"}, Json.JString{"x\ny"}]}}]}}
    : Result<&2, &2, Json.JsonError, Json.Json>}

