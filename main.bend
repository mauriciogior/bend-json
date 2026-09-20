import Base

# bend-json: a dependency-free JSON parser and serializer for Bend 2.
#
# The parser is a total, single-pass state machine. Every recursive scan call
# consumes one character, so Bend checks termination. Numbers are kept as
# their exact RFC 8259 lexeme; applications opt into numeric conversion.
# Object frames carry a string-keyed Set of the names seen so far, so
# duplicate-key detection costs one set lookup per member instead of a scan
# of every earlier member.

# Public JSON model
# =================

type Member<-A: Data> is Data:
  Member{name: String, value: A}

type Json is Data:
  JNull{}
  JBool{value: Bool}
  JNumber{raw: String}
  JString{value: String}
  JArray{items: List<&2, Json>}
  JObject{members: List<&2, Member<Json>>}

type JsonErrorCode is Data:
  InputTooLong{}
  UnexpectedCharacter{}
  UnexpectedEnd{}
  UnexpectedToken{}
  InvalidLiteral{}
  InvalidNumber{}
  InvalidEscape{}
  InvalidUnicode{}
  ControlInString{}
  TokenTooLong{}
  TooDeep{}
  TooManyNodes{}
  DuplicateKey{}
  TrailingData{}
  RenderFuelExhausted{}

type JsonError is Data:
  JsonError{code: JsonErrorCode, position: Nat}

type JsonLimits is Data:
  JsonLimits{max_input: Nat, max_depth: Nat, max_nodes: Nat, max_token: Nat}

def Json.default_limits() -> JsonLimits:
  JsonLimits{1048576n, 64n, 100000n, 1048576n}

# Parser state
# ============

type NumberState is Data:
  NMinus{}
  NZero{}
  NInt{}
  NDot{}
  NFrac{}
  NExp{}
  NExpSign{}
  NExpDigit{}

type Mode is Data:
  Normal{}
  InString{rev: String, length: Nat}
  InEscape{rev: String, length: Nat}
  InUnicode{rev: String, length: Nat, digits: Nat, code: U32, high: Maybe<&2, U32>}
  HighSlash{rev: String, length: Nat, high: U32}
  HighU{rev: String, length: Nat, high: U32}
  InNumber{rev: String, length: Nat, state: NumberState}
  InLiteral{rest: String, value: Json}

type Frame is Data:
  RootNeed{}
  RootDone{value: Json}
  ArrayNeed{rev: List<&2, Json>, allow_end: Bool}
  ArrayAfter{rev: List<&2, Json>}
  ObjectKey{rev: List<&2, Member<Json>>, seen: Set(), allow_end: Bool}
  ObjectColon{rev: List<&2, Member<Json>>, seen: Set(), key: String}
  ObjectValue{rev: List<&2, Member<Json>>, seen: Set(), key: String}
  ObjectAfter{rev: List<&2, Member<Json>>, seen: Set()}

type Context is Data:
  Context{frames: List<&2, Frame>, position: Nat, nodes: Nat, limits: JsonLimits}

type ParserState is Data:
  Running{mode: Mode, context: Context}
  Broken{error: JsonError}

def Json.error(code: JsonErrorCode, position: Nat) -> ParserState:
  Broken{JsonError{code, position}}

def Json.error_at(code: JsonErrorCode, ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, limits}:
      Json.error(code, position)

def Json.advance(ctx: Context) -> Context:
  match ctx:
    case Context{frames, position, nodes, limits}:
      Context{frames, 1n+position, nodes, limits}

def Json.run(mode: Mode, ctx: Context) -> ParserState:
  Running{mode, ctx}

# Small predicates
# ----------------

def Json.number_accepting(state: NumberState) -> Bool:
  match state:
    case NZero{}:
      True{}
    case NInt{}:
      True{}
    case NFrac{}:
      True{}
    case NExpDigit{}:
      True{}
    case state:
      False{}

def Json.is_high_surrogate(+x: U32) -> Bool:
  Bool.and(U32.is_ge(x, 55296), U32.is_le(x, 56319))

def Json.is_low_surrogate(+x: U32) -> Bool:
  Bool.and(U32.is_ge(x, 56320), U32.is_le(x, 57343))

def Json.is_scalar(+x: U32) -> Bool:
  Bool.and(U32.is_le(x, 1114111), Bool.not(Bool.or(Json.is_high_surrogate(x), Json.is_low_surrogate(x))))

def Json.hex(c: Char) -> Maybe<&2, U32>:
  match c:
    case '0': Some{0}
    case '1': Some{1}
    case '2': Some{2}
    case '3': Some{3}
    case '4': Some{4}
    case '5': Some{5}
    case '6': Some{6}
    case '7': Some{7}
    case '8': Some{8}
    case '9': Some{9}
    case 'a': Some{10}
    case 'b': Some{11}
    case 'c': Some{12}
    case 'd': Some{13}
    case 'e': Some{14}
    case 'f': Some{15}
    case 'A': Some{10}
    case 'B': Some{11}
    case 'C': Some{12}
    case 'D': Some{13}
    case 'E': Some{14}
    case 'F': Some{15}
    case c: None{}

# Tokens that no open container can accept
# ----------------------------------------

def Json.misplaced(frames: List<&2, Frame>, position: Nat) -> ParserState:
  match frames:
    case RootDone{value} <> rest:
      Json.error(TrailingData{}, position)
    case frames:
      Json.error(UnexpectedToken{}, position)

# Emitting completed values into the container stack
# --------------------------------------------------

def Json.emit.allowed(allowed: Bool, value: Json, ctx: Context) -> ParserState:
  match allowed:
    case False{}:
      Json.error_at(TooManyNodes{}, ctx)
    case True{}:
      match ctx:
        case Context{frames, position, nodes, limits}:
          match frames:
            case RootNeed{} <> rest:
              Json.run(Normal{}, Context{RootDone{value} <> rest, position, 1n+nodes, limits})
            case ArrayNeed{rev, allow_end} <> rest:
              Json.run(Normal{}, Context{ArrayAfter{value <> rev} <> rest, position, 1n+nodes, limits})
            case ObjectValue{rev, seen, key} <> rest:
              Json.run(Normal{}, Context{ObjectAfter{Member{key, value} <> rev, seen} <> rest, position, 1n+nodes, limits})
            case frames:
              Json.misplaced(frames, position)

def Json.emit(value: Json, ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, +nodes, +limits}:
      match limits:
        case JsonLimits{max_input, max_depth, max_nodes, max_token}:
          Json.emit.allowed(Nat.is_lt(nodes, max_nodes), value, Context{frames, position, nodes, limits})

def Json.emit_string.unique(+text: String, members: List<&2, Member<Json>>, seen: Set(), rest: List<&2, Frame>, position: Nat, nodes: Nat, limits: JsonLimits, duplicate: Bool) -> ParserState:
  match duplicate:
    case True{}:
      Json.error(DuplicateKey{}, position)
    case False{}:
      Json.run(Normal{}, Context{ObjectColon{members, Set.add(seen, text), text} <> rest, position, nodes, limits})

def Json.emit_string.checked(+text: String, members: List<&2, Member<Json>>, rest: List<&2, Frame>, position: Nat, nodes: Nat, limits: JsonLimits, checked: Set() & Bool) -> ParserState:
  (seen, duplicate) = checked
  Json.emit_string.unique(text, members, seen, rest, position, nodes, limits, duplicate)

def Json.emit_string(+text: String, ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, limits}:
      match frames:
        case ObjectKey{members, seen, allow_end} <> rest:
          Json.emit_string.checked(text, members, rest, position, nodes, limits, Set.has(seen, text))
        case frames:
          Json.emit(JString{text}, Context{frames, position, nodes, limits})

# Containers and punctuation
# --------------------------

def Json.push.checked(ok: Bool, frame: Frame, ctx: Context) -> ParserState:
  match ok:
    case False{}:
      Json.error_at(TooDeep{}, ctx)
    case True{}:
      match ctx:
        case Context{frames, position, nodes, limits}:
          match frames:
            case RootDone{value} <> rest:
              Json.error(TrailingData{}, position)
            case frames:
              Json.run(Normal{}, Context{frame <> frames, position, nodes, limits})

def Json.push(frame: Frame, ctx: Context) -> ParserState:
  match ctx:
    case Context{+frames, position, nodes, +limits}:
      match limits:
        case JsonLimits{max_input, max_depth, max_nodes, max_token}:
          Json.push.checked(Nat.is_le(List.length(&2, Frame, frames), max_depth), frame, Context{frames, position, nodes, limits})

def Json.open_array(ctx: Context) -> ParserState:
  Json.push(ArrayNeed{Nil{}, True{}}, ctx)

def Json.open_object(ctx: Context) -> ParserState:
  Json.push(ObjectKey{Nil{}, Set.new(), True{}}, ctx)

def Json.close_array(ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, limits}:
      match frames:
        case ArrayNeed{rev, True{}} <> rest:
          Json.emit(JArray{List.reverse(&2, Json, rev)}, Context{rest, position, nodes, limits})
        case ArrayAfter{rev} <> rest:
          Json.emit(JArray{List.reverse(&2, Json, rev)}, Context{rest, position, nodes, limits})
        case frames:
          Json.misplaced(frames, position)

def Json.close_object(ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, limits}:
      match frames:
        case ObjectKey{rev, seen, True{}} <> rest:
          Json.emit(JObject{List.reverse(&2, Member<Json>, rev)}, Context{rest, position, nodes, limits})
        case ObjectAfter{rev, seen} <> rest:
          Json.emit(JObject{List.reverse(&2, Member<Json>, rev)}, Context{rest, position, nodes, limits})
        case frames:
          Json.misplaced(frames, position)

def Json.colon(ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, limits}:
      match frames:
        case ObjectColon{rev, seen, key} <> rest:
          Json.run(Normal{}, Context{ObjectValue{rev, seen, key} <> rest, position, nodes, limits})
        case frames:
          Json.misplaced(frames, position)

def Json.comma(ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, limits}:
      match frames:
        case ArrayAfter{rev} <> rest:
          Json.run(Normal{}, Context{ArrayNeed{rev, False{}} <> rest, position, nodes, limits})
        case ObjectAfter{rev, seen} <> rest:
          Json.run(Normal{}, Context{ObjectKey{rev, seen, False{}} <> rest, position, nodes, limits})
        case frames:
          Json.misplaced(frames, position)

# Token accumulation
# ------------------

def Json.string_char.allowed(allowed: Bool, c: Char, rev: String, length: Nat, ctx: Context) -> ParserState:
  match allowed:
    case False{}:
      Json.error_at(TokenTooLong{}, ctx)
    case True{}:
      Json.run(InString{SCon{c, rev}, 1n+length}, ctx)

def Json.string_char(c: Char, rev: String, +length: Nat, ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, +limits}:
      match limits:
        case JsonLimits{max_input, max_depth, max_nodes, max_token}:
          Json.string_char.allowed(Nat.is_lt(length, max_token), c, rev, length, Context{frames, position, nodes, limits})

def Json.string_plain(valid: Bool, c: Char, rev: String, length: Nat, ctx: Context) -> ParserState:
  match valid:
    case False{}:
      Json.error_at(ControlInString{}, ctx)
    case True{}:
      Json.string_char(c, rev, length, ctx)

def Json.escape_char(c: Char, rev: String, length: Nat, ctx: Context) -> ParserState:
  match c:
    case '"': Json.string_char('"', rev, length, ctx)
    case '\\': Json.string_char('\\', rev, length, ctx)
    case '/': Json.string_char('/', rev, length, ctx)
    case 'b': Json.string_char(Chr{8}, rev, length, ctx)
    case 'f': Json.string_char(Chr{12}, rev, length, ctx)
    case 'n': Json.string_char('\n', rev, length, ctx)
    case 'r': Json.string_char('\r', rev, length, ctx)
    case 't': Json.string_char('\t', rev, length, ctx)
    case 'u': Json.run(InUnicode{rev, length, 0n, 0, None{}}, ctx)
    case c: Json.error_at(InvalidEscape{}, ctx)

def Json.literal.same(same: Bool, c: Char, tail: String, value: Json, ctx: Context) -> ParserState:
  match same:
    case False{}:
      Json.error_at(InvalidLiteral{}, ctx)
    case True{}:
      match tail:
        case SNil{}:
          Json.emit(value, ctx)
        case tail:
          Json.run(InLiteral{tail, value}, ctx)

def Json.literal(+c: Char, rest: String, value: Json, ctx: Context) -> ParserState:
  match rest:
    case SNil{}:
      Json.error_at(InvalidLiteral{}, ctx)
    case SCon{expected, tail}:
      Json.literal.same(Char.is_eq(c, expected), c, tail, value, ctx)

# Unicode escape handling
# -----------------------

def Json.unicode.scalar(valid: Bool, rev: String, length: Nat, code: U32, ctx: Context) -> ParserState:
  match valid:
    case False{}:
      Json.error_at(InvalidUnicode{}, ctx)
    case True{}:
      Json.string_char(Char.from_u32(code), rev, length, ctx)

def Json.unicode.first.low(low: Bool, rev: String, length: Nat, +code: U32, ctx: Context) -> ParserState:
  match low:
    case True{}:
      Json.error_at(InvalidUnicode{}, ctx)
    case False{}:
      Json.unicode.scalar(Json.is_scalar(code), rev, length, code, ctx)

def Json.unicode.first(high: Bool, rev: String, length: Nat, +code: U32, ctx: Context) -> ParserState:
  match high:
    case True{}:
      Json.run(HighSlash{rev, length, code}, ctx)
    case False{}:
      Json.unicode.first.low(Json.is_low_surrogate(code), rev, length, code, ctx)

def Json.unicode.pair.valid(valid: Bool, rev: String, length: Nat, high: U32, low: U32, ctx: Context) -> ParserState:
  match valid:
    case False{}:
      Json.error_at(InvalidUnicode{}, ctx)
    case True{}:
      code = U32.add(65536, U32.add(U32.shln(U32.sub(high, 55296), 10n), U32.sub(low, 56320)))
      Json.string_char(Char.from_u32(code), rev, length, ctx)

def Json.unicode.complete(rev: String, length: Nat, +code: U32, high: Maybe<&2, U32>, ctx: Context) -> ParserState:
  match high:
    case None{}:
      Json.unicode.first(Json.is_high_surrogate(code), rev, length, code, ctx)
    case Some{hi}:
      Json.unicode.pair.valid(Json.is_low_surrogate(code), rev, length, hi, code, ctx)

def Json.unicode.digit.next(digits: Nat, rev: String, length: Nat, next: U32, high: Maybe<&2, U32>, ctx: Context) -> ParserState:
  match digits:
    case 0n:
      Json.run(InUnicode{rev, length, 1n, next, high}, ctx)
    case 1n+0n:
      Json.run(InUnicode{rev, length, 2n, next, high}, ctx)
    case 1n+1n+0n:
      Json.run(InUnicode{rev, length, 3n, next, high}, ctx)
    case 1n+1n+1n+0n:
      Json.unicode.complete(rev, length, next, high, ctx)
    case digits:
      Json.error_at(InvalidUnicode{}, ctx)

def Json.unicode.digit(value: Maybe<&2, U32>, rev: String, length: Nat, digits: Nat, code: U32, high: Maybe<&2, U32>, ctx: Context) -> ParserState:
  match value:
    case None{}:
      Json.error_at(InvalidUnicode{}, ctx)
    case Some{n}:
      Json.unicode.digit.next(digits, rev, length, U32.add(U32.mul(code, 16), n), high, ctx)

# Number DFA
# ----------

def Json.number_start.checked(ok: Bool, c: Char, state: NumberState, ctx: Context) -> ParserState:
  match ok:
    case False{}:
      Json.error_at(TokenTooLong{}, ctx)
    case True{}:
      Json.run(InNumber{SCon{c, SNil{}}, 1n, state}, ctx)

def Json.number_start(c: Char, state: NumberState, ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, +limits}:
      match limits:
        case JsonLimits{max_input, max_depth, max_nodes, max_token}:
          Json.number_start.checked(Nat.is_gt(max_token, 0n), c, state, Context{frames, position, nodes, limits})

def Json.normal(c: Char, ctx: Context) -> ParserState:
  match c:
    case ' ': Json.run(Normal{}, ctx)
    case '\n': Json.run(Normal{}, ctx)
    case '\r': Json.run(Normal{}, ctx)
    case '\t': Json.run(Normal{}, ctx)
    case '"': Json.run(InString{"", 0n}, ctx)
    case '[': Json.open_array(ctx)
    case '{': Json.open_object(ctx)
    case ']': Json.close_array(ctx)
    case '}': Json.close_object(ctx)
    case ':': Json.colon(ctx)
    case ',': Json.comma(ctx)
    case '-': Json.number_start('-', NMinus{}, ctx)
    case '0': Json.number_start('0', NZero{}, ctx)
    case '1': Json.number_start('1', NInt{}, ctx)
    case '2': Json.number_start('2', NInt{}, ctx)
    case '3': Json.number_start('3', NInt{}, ctx)
    case '4': Json.number_start('4', NInt{}, ctx)
    case '5': Json.number_start('5', NInt{}, ctx)
    case '6': Json.number_start('6', NInt{}, ctx)
    case '7': Json.number_start('7', NInt{}, ctx)
    case '8': Json.number_start('8', NInt{}, ctx)
    case '9': Json.number_start('9', NInt{}, ctx)
    case 't': Json.run(InLiteral{"rue", JBool{True{}}}, ctx)
    case 'f': Json.run(InLiteral{"alse", JBool{False{}}}, ctx)
    case 'n': Json.run(InLiteral{"ull", JNull{}}, ctx)
    case c: Json.error_at(UnexpectedCharacter{}, ctx)

def Json.number_digit.state(c: Char, rev: String, length: Nat, state: NumberState, ctx: Context, zero: Bool) -> ParserState:
  match state zero:
    case NMinus{} True{}:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NZero{}}, ctx)
    case NMinus{} False{}:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NInt{}}, ctx)
    case NZero{} zero:
      Json.error_at(InvalidNumber{}, ctx)
    case NInt{} zero:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NInt{}}, ctx)
    case NDot{} zero:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NFrac{}}, ctx)
    case NFrac{} zero:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NFrac{}}, ctx)
    case NExp{} zero:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NExpDigit{}}, ctx)
    case NExpSign{} zero:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NExpDigit{}}, ctx)
    case NExpDigit{} zero:
      Json.run(InNumber{SCon{c, rev}, 1n+length, NExpDigit{}}, ctx)

def Json.number_digit.allowed(allowed: Bool, +c: Char, rev: String, length: Nat, state: NumberState, ctx: Context) -> ParserState:
  match allowed:
    case False{}:
      Json.error_at(TokenTooLong{}, ctx)
    case True{}:
      Json.number_digit.state(c, rev, length, state, ctx, Char.is_eq(c, '0'))

def Json.number_digit(c: Char, rev: String, +length: Nat, state: NumberState, ctx: Context) -> ParserState:
  match ctx:
    case Context{frames, position, nodes, +limits}:
      match limits:
        case JsonLimits{max_input, max_depth, max_nodes, max_token}:
          Json.number_digit.allowed(Nat.is_lt(length, max_token), c, rev, length, state, Context{frames, position, nodes, limits})

def Json.reprocess(c: Char, state: ParserState) -> ParserState:
  match state:
    case Broken{error}:
      Broken{error}
    case Running{mode, context}:
      Json.normal(c, context)

def Json.number_end.accept(accept: Bool, c: Char, rev: String, state: NumberState, ctx: Context) -> ParserState:
  match accept:
    case False{}:
      Json.error_at(InvalidNumber{}, ctx)
    case True{}:
      Json.reprocess(c, Json.emit(JNumber{String.reverse(rev)}, ctx))

def Json.number_symbol(+state: NumberState, c: Char, rev: String, length: Nat, ctx: Context) -> ParserState:
  match state c:
    case NZero{} '.': Json.run(InNumber{SCon{c, rev}, 1n+length, NDot{}}, ctx)
    case NInt{} '.': Json.run(InNumber{SCon{c, rev}, 1n+length, NDot{}}, ctx)
    case NZero{} 'e': Json.run(InNumber{SCon{c, rev}, 1n+length, NExp{}}, ctx)
    case NZero{} 'E': Json.run(InNumber{SCon{c, rev}, 1n+length, NExp{}}, ctx)
    case NInt{} 'e': Json.run(InNumber{SCon{c, rev}, 1n+length, NExp{}}, ctx)
    case NInt{} 'E': Json.run(InNumber{SCon{c, rev}, 1n+length, NExp{}}, ctx)
    case NFrac{} 'e': Json.run(InNumber{SCon{c, rev}, 1n+length, NExp{}}, ctx)
    case NFrac{} 'E': Json.run(InNumber{SCon{c, rev}, 1n+length, NExp{}}, ctx)
    case NExp{} '+': Json.run(InNumber{SCon{c, rev}, 1n+length, NExpSign{}}, ctx)
    case NExp{} '-': Json.run(InNumber{SCon{c, rev}, 1n+length, NExpSign{}}, ctx)
    case state c:
      Json.number_end.accept(Json.number_accepting(state), c, rev, state, ctx)

def Json.number.next(digit: Bool, c: Char, rev: String, length: Nat, state: NumberState, ctx: Context) -> ParserState:
  match digit:
    case True{}:
      Json.number_digit(c, rev, length, state, ctx)
    case False{}:
      Json.number_symbol(state, c, rev, length, ctx)

# Scanner
# -------

def Json.step.mode(mode: Mode, +c: Char, +ctx: Context) -> ParserState:
  match mode:
    case Normal{}:
      Json.normal(c, ctx)
    case InString{+rev, +length}:
      match c:
        case '"': Json.emit_string(String.reverse(rev), ctx)
        case '\\': Json.run(InEscape{rev, length}, ctx)
        case c: Json.string_plain(U32.is_ge(Char.to_u32(c), 32), c, rev, length, ctx)
    case InEscape{rev, length}:
      Json.escape_char(c, rev, length, ctx)
    case InUnicode{rev, length, digits, code, high}:
      Json.unicode.digit(Json.hex(c), rev, length, digits, code, high, ctx)
    case HighSlash{+rev, +length, +high}:
      match c:
        case '\\': Json.run(HighU{rev, length, high}, ctx)
        case c: Json.error_at(InvalidUnicode{}, ctx)
    case HighU{+rev, +length, +high}:
      match c:
        case 'u': Json.run(InUnicode{rev, length, 0n, 0, Some{high}}, ctx)
        case c: Json.error_at(InvalidUnicode{}, ctx)
    case InNumber{rev, length, state}:
      Json.number.next(Char.is_digit(c), c, rev, length, state, ctx)
    case InLiteral{rest, value}:
      Json.literal(c, rest, value, ctx)

def Json.step(c: Char, state: ParserState) -> ParserState:
  match state:
    case Broken{error}:
      Broken{error}
    case Running{mode, context}:
      Json.step.mode(mode, c, Json.advance(context))

def Json.scan(source: String, state: ParserState) -> ParserState:
  match source:
    case SNil{}:
      state
    case SCon{+c, rest}:
      Json.scan(rest, Json.step(c, state))

# End-of-input and public parse API
# ---------------------------------

def Json.finish_root(ctx: Context) -> Result<&2, &2, JsonError, Json>:
  match ctx:
    case Context{frames, position, nodes, limits}:
      match frames:
        case RootDone{value} <> Nil{}:
          Done{value}
        case frames:
          Fail{JsonError{UnexpectedEnd{}, position}}

def Json.finish_emitted(state: ParserState) -> Result<&2, &2, JsonError, Json>:
  match state:
    case Broken{error}:
      Fail{error}
    case Running{Normal{}, context}:
      Json.finish_root(context)
    case Running{mode, Context{frames, position, nodes, limits}}:
      Fail{JsonError{UnexpectedEnd{}, position}}

def Json.finish_number(accept: Bool, rev: String, state: NumberState, ctx: Context) -> Result<&2, &2, JsonError, Json>:
  match accept:
    case False{}:
      match ctx:
        case Context{frames, position, nodes, limits}:
          Fail{JsonError{InvalidNumber{}, position}}
    case True{}:
      Json.finish_emitted(Json.emit(JNumber{String.reverse(rev)}, ctx))

def Json.finish(state: ParserState) -> Result<&2, &2, JsonError, Json>:
  match state:
    case Broken{error}:
      Fail{error}
    case Running{mode, context}:
      match mode:
        case Normal{}:
          Json.finish_root(context)
        case InNumber{rev, length, +state}:
          Json.finish_number(Json.number_accepting(state), rev, state, context)
        case mode:
          match context:
            case Context{frames, position, nodes, limits}:
              Fail{JsonError{UnexpectedEnd{}, position}}

def Json.parse_sized(source: String, limits: JsonLimits, allowed: Bool) -> Result<&2, &2, JsonError, Json>:
  match allowed:
    case False{}:
      Fail{JsonError{InputTooLong{}, 0n}}
    case True{}:
      initial = {Context{RootNeed{} <> Nil{}, 0n, 0n, limits} : Context}
      Json.finish(Json.scan(source, Json.run(Normal{}, initial)))

def Json.parse_with(+limits: JsonLimits, +source: String) -> Result<&2, &2, JsonError, Json>:
  match limits:
    case JsonLimits{max_input, max_depth, max_nodes, max_token}:
      Json.parse_sized(source, limits, Nat.is_le(String.length(source), max_input))

def Json.parse(source: String) -> Result<&2, &2, JsonError, Json>:
  Json.parse_with(Json.default_limits(), source)

# Number validation for smart construction
# ========================================

def Json.number_check_end(state: NumberState) -> Bool:
  Json.number_accepting(state)

def Json.number_check_digit(state: NumberState, zero: Bool) -> Maybe<&2, NumberState>:
  match state zero:
    case NMinus{} True{}: Some{NZero{}}
    case NMinus{} False{}: Some{NInt{}}
    case NZero{} zero: None{}
    case NInt{} zero: Some{NInt{}}
    case NDot{} zero: Some{NFrac{}}
    case NFrac{} zero: Some{NFrac{}}
    case NExp{} zero: Some{NExpDigit{}}
    case NExpSign{} zero: Some{NExpDigit{}}
    case NExpDigit{} zero: Some{NExpDigit{}}

def Json.number_check_symbol(state: NumberState, c: Char) -> Maybe<&2, NumberState>:
  match state c:
    case NZero{} '.': Some{NDot{}}
    case NInt{} '.': Some{NDot{}}
    case NZero{} 'e': Some{NExp{}}
    case NZero{} 'E': Some{NExp{}}
    case NInt{} 'e': Some{NExp{}}
    case NInt{} 'E': Some{NExp{}}
    case NFrac{} 'e': Some{NExp{}}
    case NFrac{} 'E': Some{NExp{}}
    case NExp{} '+': Some{NExpSign{}}
    case NExp{} '-': Some{NExpSign{}}
    case state c: None{}

def Json.number_check_next(state: NumberState, c: Char, digit: Bool) -> Maybe<&2, NumberState>:
  match digit:
    case True{}:
      Json.number_check_digit(state, Char.is_eq(c, '0'))
    case False{}:
      Json.number_check_symbol(state, c)

def Json.number_check_go(source: String, state: NumberState) -> Bool:
  match source:
    case SNil{}:
      Json.number_check_end(state)
    case SCon{+c, rest}:
      Maybe.default(&2, Bool,
        Maybe.map(&2, NumberState, Bool,
          next => Json.number_check_go(rest, next),
          Json.number_check_next(state, c, Char.is_digit(c))),
        False{})

def Json.number_valid.start(rest: String, first: Char) -> Bool:
  match first:
    case '-': Json.number_check_go(rest, NMinus{})
    case '0': Json.number_check_go(rest, NZero{})
    case '1': Json.number_check_go(rest, NInt{})
    case '2': Json.number_check_go(rest, NInt{})
    case '3': Json.number_check_go(rest, NInt{})
    case '4': Json.number_check_go(rest, NInt{})
    case '5': Json.number_check_go(rest, NInt{})
    case '6': Json.number_check_go(rest, NInt{})
    case '7': Json.number_check_go(rest, NInt{})
    case '8': Json.number_check_go(rest, NInt{})
    case '9': Json.number_check_go(rest, NInt{})
    case first: False{}

def Json.number_valid(source: String) -> Bool:
  match source:
    case SNil{}:
      False{}
    case SCon{first, rest}:
      Json.number_valid.start(rest, first)

def Json.number.done(valid: Bool, raw: String) -> Result<&2, &2, JsonError, Json>:
  match valid:
    case True{}:
      Done{JNumber{raw}}
    case False{}:
      Fail{JsonError{InvalidNumber{}, 0n}}

def Json.number(+raw: String) -> Result<&2, &2, JsonError, Json>:
  Json.number.done(Json.number_valid(raw), raw)

# Serializer
# ==========

type RenderJob is Data:
  RenderValue{value: Json}
  RenderText{text: String}
  RenderEscape{text: String}
  RenderArray{items: List<&2, Json>}
  RenderObject{members: List<&2, Member<Json>>, seen: Set()}

def Json.render_error() -> Result<&2, &2, JsonError, String>:
  Fail{JsonError{RenderFuelExhausted{}, 0n}}

def Json.render_key.unique(seen: Set(), duplicate: Bool) -> Result<&2, &2, JsonError, Set()>:
  match duplicate:
    case True{}:
      Fail{JsonError{DuplicateKey{}, 0n}}
    case False{}:
      Done{seen}

def Json.render_key(checked: Set() & Bool) -> Result<&2, &2, JsonError, Set()>:
  (seen, duplicate) = checked
  Json.render_key.unique(seen, duplicate)

def Json.hex_char(n: U32) -> Char:
  match n:
    case 0: '0'
    case 1: '1'
    case 2: '2'
    case 3: '3'
    case 4: '4'
    case 5: '5'
    case 6: '6'
    case 7: '7'
    case 8: '8'
    case 9: '9'
    case 10: 'a'
    case 11: 'b'
    case 12: 'c'
    case 13: 'd'
    case 14: 'e'
    case n: 'f'

def Json.control_escape(+code: U32) -> String:
  hi = Json.hex_char(U32.div(code, 16))
  lo = Json.hex_char(U32.mod(code, 16))
  "\\u00" ++ SCon{hi, SCon{lo, SNil{}}}

def Json.escape_piece.scalar(c: Char, code: U32, valid: Bool) -> Result<&2, &2, JsonError, String>:
  match valid:
    case False{}:
      Fail{JsonError{InvalidUnicode{}, 0n}}
    case True{}:
      Done{SCon{c, SNil{}}}

def Json.escape_piece.control(c: Char, +code: U32, control: Bool) -> Result<&2, &2, JsonError, String>:
  match control:
    case True{}:
      Done{Json.control_escape(code)}
    case False{}:
      Json.escape_piece.scalar(c, code, Json.is_scalar(code))

def Json.escape_piece(c: Char) -> Result<&2, &2, JsonError, String>:
  match c:
    case '"': Done{"\\\""}
    case '\\': Done{"\\\\"}
    case Chr{8}: Done{"\\b"}
    case Chr{12}: Done{"\\f"}
    case '\n': Done{"\\n"}
    case '\r': Done{"\\r"}
    case '\t': Done{"\\t"}
    case +c:
      +code = Char.to_u32(c)
      Json.escape_piece.control(c, code, U32.is_lt(code, 32))

def Json.render(fuel: Nat, jobs: List<&2, RenderJob>, chunks: List<&2, String>) -> Result<&2, &2, JsonError, String>:
  match fuel:
    case 0n:
      match jobs:
        case Nil{}:
          Done{String.concat(List.reverse(&2, String, chunks))}
        case jobs:
          Json.render_error()
    case 1n+more:
      match jobs:
        case Nil{}:
          Done{String.concat(List.reverse(&2, String, chunks))}
        case RenderText{text} <> rest:
          Json.render(more, rest, text <> chunks)
        case RenderValue{value} <> rest:
          match value:
            case JNull{}:
              Json.render(more, rest, "null" <> chunks)
            case JBool{False{}}:
              Json.render(more, rest, "false" <> chunks)
            case JBool{True{}}:
              Json.render(more, rest, "true" <> chunks)
            case JNumber{+raw}:
              Result.bind(&2, &2, JsonError, String, String,
                Bool.pick(Result<&2, &2, JsonError, String>, Json.number_valid(raw), Done{raw}, Fail{JsonError{InvalidNumber{}, 0n}}),
                text => Json.render(more, rest, text <> chunks))
            case JString{text}:
              Json.render(more, RenderText{"\""} <> RenderEscape{text} <> RenderText{"\""} <> rest, chunks)
            case JArray{items}:
              Json.render(more, RenderText{"["} <> RenderArray{items} <> RenderText{"]"} <> rest, chunks)
            case JObject{members}:
              Json.render(more, RenderText{"{"} <> RenderObject{members, Set.new()} <> RenderText{"}"} <> rest, chunks)
        case RenderEscape{text} <> rest:
          match text:
            case SNil{}:
              Json.render(more, rest, chunks)
            case SCon{c, tail}:
              Result.bind(&2, &2, JsonError, String, String, Json.escape_piece(c),
                piece => Json.render(more, RenderEscape{tail} <> rest, piece <> chunks))
        case RenderArray{items} <> rest:
          match items:
            case Nil{}:
              Json.render(more, rest, chunks)
            case head <> tail:
              match tail:
                case Nil{}:
                  Json.render(more, RenderValue{head} <> rest, chunks)
                case tail:
                  Json.render(more, RenderValue{head} <> RenderText{","} <> RenderArray{tail} <> rest, chunks)
        case RenderObject{members, seen} <> rest:
          match members:
            case Nil{}:
              Json.render(more, rest, chunks)
            case Member{+name, value} <> tail:
              match tail:
                case Nil{}:
                  Result.bind(&2, &2, JsonError, Set(), String, Json.render_key(Set.has(seen, name)),
                    seen2 => Json.render(more, RenderText{"\""} <> RenderEscape{name} <> RenderText{"\":"} <> RenderValue{value} <> rest, chunks))
                case tail:
                  Result.bind(&2, &2, JsonError, Set(), String, Json.render_key(Set.has(seen, name)),
                    seen2 => Json.render(more, RenderText{"\""} <> RenderEscape{name} <> RenderText{"\":"} <> RenderValue{value} <> RenderText{","} <> RenderObject{tail, Set.add(seen2, name)} <> rest, chunks))

def Json.stringify_with(fuel: Nat, value: Json) -> Result<&2, &2, JsonError, String>:
  Json.render(fuel, RenderValue{value} <> Nil{}, Nil{})

# A conservative default intended for small API values. Applications that
# serialize larger trees should supply their own explicit work budget.
def Json.stringify(value: Json) -> Result<&2, &2, JsonError, String>:
  Json.stringify_with(10000n, value)
