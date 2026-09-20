import Base
import ./main.bend as Json
import ./LAWS.bend as Laws

def Laws.bool_round_trip(b):
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

def Laws.null_round_trip():
  {==}

def Laws.number_grammar_examples():
  {==}

def Laws.leading_zero_rejected():
  {==}

def Laws.escaped_string_example():
  {==}

def Laws.unicode_pair_example():
  {==}

def Laws.duplicate_key_rejected():
  {==}

def Laws.nested_round_trip_example():
  {==}

