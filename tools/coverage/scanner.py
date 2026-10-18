"""GDScript text to statements and uninstrumented spans, for the coverage instrumenter (no Godot needed).

  scan(text) -> {"statements": [...], "uninstrumented": [...]}
    statements      {"line", "col", "kind", "function", "class"} per statement inside a function body, in source
                    order: `line` 1-based, `col` the 0-based column of its first character (where the counter goes),
                    `kind` function / branch / statement (tools/coverage/README.md, "Statement map")
    uninstrumented  {"line", "end_line", "reason"} per span left untouched because the scanner is not sure of it

GDScript exposes no parser to scripts, so this works from indentation and brackets. A tokenizer drops comments and
keeps strings whole (`"…"`, `'…'`, triple-quoted, with the `r` / `&` / `^` prefixes), so neither is ever read as code;
a parser then walks the class bodies (functions, inner classes, property get/set blocks) and each function body's
statements: simple ones, compound ones (`if` / `elif` / `else`, `for`, `while`, `match` and its arms) with indented or
one-line bodies, and lambdas, written inline or over several lines, also inside a call's arguments. A lambda's
statements belong to the function it is written in.

Where it is not sure it says so instead of guessing: a statement starting on the closing line of a multi-line string,
a statement under an annotation, a lambda in a class-level declaration (no function runs it), and any function or file
it cannot follow are listed as uninstrumented with the reason, and get no counter.
"""
import re
from dataclasses import dataclass

KEYWORD_COMPOUND = {"if", "elif", "else", "for", "while", "match"}
# What a class member's line starts with: where the scanner picks up again after a function it could not follow.
CLASS_LEVEL = {"func", "static", "var", "const", "signal", "enum", "class", "class_name", "extends", "@"}
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(r"[0-9][0-9A-Za-z_.]*")
TWO_CHAR_OPS = ("->", ":=", "==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "**", "<<", ">>",
                "&=", "|=", "^=")


class Unsure(Exception):
    """The scanner cannot follow this code; the caller lists the span as uninstrumented."""


class LambdaClosed(Exception):
    """A lambda's block inside brackets ended on its last line, at the bracket (or `,`) that closes around it:
    `func(o):` … `return true)`. Unwinds the block's statements back to the lambda."""


@dataclass
class Token:
    kind: str     # name, number, string, op, newline
    text: str
    line: int     # 1-based
    col: int      # 0-based
    indent: int   # the indentation of the token's physical line (tabs counted as 4)
    first: bool   # the first token on its physical line


class Lexer:
    """The tokens of a GDScript file, plus which lines begin inside a multi-line string."""

    def __init__(self, text: str):
        self.lines = text.split("\n")
        self.tokens: list[Token] = []
        self.in_string_lines: set[int] = set()  # 1-based lines whose start lies inside a multi-line string
        self._lex()

    def _lex(self) -> None:
        string = None  # (quote, raw, start line) while inside a multi-line string
        continued = False
        for n, raw_line in enumerate(self.lines, start=1):
            length = len(raw_line)
            lead = length - len(raw_line.lstrip(" \t"))
            indent = len(raw_line[:lead].expandtabs(4))
            first = not continued and string is None
            continued = False
            had_token = False
            i = lead
            if string is not None:
                self.in_string_lines.add(n)
                end = self._string_end(raw_line, 0, string[0], string[1])
                if end < 0:
                    continue
                i = end
                string = None
                had_token = True  # the logical line holding the string ends on this line
            while i < length:
                c = raw_line[i]
                if c in " \t\r":
                    i += 1
                    continue
                if c == "#":
                    break
                if c == "\\" and raw_line[i + 1:].strip() == "":
                    continued = True
                    break
                start = i
                quote_at = i + 1 if c in "r&^" and i + 1 < length and raw_line[i + 1] in "\"'" else i
                if raw_line[quote_at] in "\"'":
                    raw = c == "r"
                    q = raw_line[quote_at]
                    quote = q * 3 if raw_line.startswith(q * 3, quote_at) else q
                    end = self._string_end(raw_line, quote_at + len(quote), quote, raw)
                    if end < 0:
                        if len(quote) == 1:
                            raise Unsure(f"line {n}: a string that does not end on its line")
                        string = (quote, raw, n)
                        self._add("string", raw_line[start:], n, start, indent, first and not had_token)
                        had_token = True
                        break
                    self._add("string", raw_line[start:end], n, start, indent, first and not had_token)
                    had_token = True
                    i = end
                    continue
                m = NAME.match(raw_line, i) or NUMBER.match(raw_line, i)
                if m:
                    kind = "name" if c.isalpha() or c == "_" else "number"
                    text = m.group(0)
                else:
                    kind = "op"
                    text = raw_line[i:i + 2] if raw_line[i:i + 2] in TWO_CHAR_OPS else c
                self._add(kind, text, n, start, indent, first and not had_token)
                had_token = True
                i = start + len(text)
            if had_token and not continued and string is None:
                self._add("newline", "", n, length, indent, False)
        if string is not None:
            raise Unsure(f"line {string[2]}: a multi-line string that never ends")
        if self.tokens and self.tokens[-1].kind != "newline":
            last = self.tokens[-1]
            self._add("newline", "", last.line, last.col + len(last.text), last.indent, False)

    def _add(self, kind, text, line, col, indent, first) -> None:
        self.tokens.append(Token(kind, text, line, col, indent, first))

    @staticmethod
    def _string_end(line: str, i: int, quote: str, raw: bool) -> int:
        """The index just past `quote` closing a string from `i` on `line`, or -1 when it does not close there."""
        while i < len(line):
            if not raw and line[i] == "\\":
                i += 2
                continue
            if line.startswith(quote, i):
                return i + len(quote)
            i += 1
        return -1


class Parser:
    """Walks the tokens: class bodies, functions, statements."""

    def __init__(self, lexer: Lexer):
        self.lx = lexer
        self.toks = lexer.tokens
        self.pos = 0
        self.statements: list[dict] = []
        self.uninstrumented: list[dict] = []
        self.bracketed: list[bool] = []  # per block lambda being read: whether it sits inside brackets

    # --- token helpers ------------------------------------------------------------------------

    def peek(self, offset: int = 0) -> Token | None:
        i = self.pos + offset
        return self.toks[i] if i < len(self.toks) else None

    def next(self) -> Token:
        tok = self.peek()
        if tok is None:
            raise Unsure("the file ends in the middle of a construct")
        self.pos += 1
        return tok

    def at(self, *texts: str, offset: int = 0) -> bool:
        tok = self.peek(offset)
        return tok is not None and tok.kind in ("name", "op") and tok.text in texts

    def line_of_last(self) -> int:
        return self.toks[self.pos - 1].line if self.pos else 1

    def skip_newlines(self) -> None:
        while self.peek() is not None and self.peek().kind == "newline":
            self.pos += 1

    def end_of_line(self) -> None:
        """The end of a logical line: its newline, or nothing when a compound statement already took its lines."""
        tok = self.peek()
        if tok is None or tok.first:
            return
        if self.closes_lambda(tok):
            raise LambdaClosed()
        if tok.kind != "newline":
            raise Unsure(f"line {tok.line}: unexpected `{tok.text}`")
        self.next()

    def closes_lambda(self, tok: Token) -> bool:
        """Whether `tok` ends the bracketed block lambda being read (its closing bracket, or a `,` after it)."""
        return bool(self.bracketed) and self.bracketed[-1] and tok.kind == "op" and tok.text in ",)]}"

    # --- class level --------------------------------------------------------------------------

    def parse_file(self) -> None:
        self.skip_newlines()
        if self.peek() is not None:
            self.class_body(self.peek().indent, "")

    def class_body(self, indent: int, cls: str) -> None:
        """Members at `indent` until a line indented less (or the end)."""
        while True:
            self.skip_newlines()
            tok = self.peek()
            if tok is None or tok.indent < indent:
                return
            if tok.indent > indent or not tok.first:
                raise Unsure(f"line {tok.line}: unexpected indentation at class level")
            self.member(indent, cls)

    def member(self, indent: int, cls: str) -> None:
        """One class member, after any annotations on its line (an annotation alone on a line is a member too)."""
        start = self.peek()
        while self.at("@"):
            self.annotation()
        tok = self.peek()
        if tok is None or tok.kind == "newline":
            self.end_of_line()
        elif self.at("func") or self.at("static") and self.at("func", offset=1):
            self.guarded(indent, start, self.function, indent, cls)
        elif self.at("class") and self.peek(1) is not None and self.peek(1).kind == "name":
            self.inner_class(indent, cls, start)
        else:
            self.declarations(indent, cls, start)

    def guarded(self, indent: int, start: Token, part, *args) -> None:
        """Run `part(*args)`; when the scanner cannot follow it, drop what it recorded, skip to the next member and
        list the span as uninstrumented."""
        mark, marks = len(self.statements), len(self.uninstrumented)
        try:
            part(*args)
        except Unsure as why:
            del self.statements[mark:]
            del self.uninstrumented[marks:]
            end = self.recover(indent, start.line)
            self.unsure(start.line, end, f"the scanner could not follow this: {why}")

    def recover(self, indent: int, line: int) -> int:
        """Skip to the next class member at `indent` or less; returns the last line skipped."""
        last = max(line, self.line_of_last())
        while self.peek() is not None:
            tok = self.peek()
            if tok.first and tok.indent <= indent and tok.line > line and (tok.text in CLASS_LEVEL):
                break
            last = max(last, tok.line)
            self.pos += 1
        return last

    def annotation(self) -> None:
        at = self.next()  # @
        self.next()       # its name
        if self.at("(") and self.peek().line == at.line:
            self.skip_group()

    def inner_class(self, indent: int, cls: str, start: Token) -> None:
        self.next()  # class
        name = self.next().text
        self.header_colon()
        if self.peek() is not None and self.peek().kind == "newline":
            self.next()
        inner = f"{cls}.{name}" if cls else name
        self.skip_newlines()
        body = self.peek()
        if body is None or body.indent <= indent:
            raise Unsure(f"line {start.line}: an inner class without a body")
        self.class_body(body.indent, inner)

    def declarations(self, indent: int, cls: str, start: Token) -> None:
        """A var / const / signal / enum / extends / class_name line (several with `;`, or a stray `pass`); a var may
        carry a get/set block, whose bodies are functions named `<var>.get` / `<var>.set`."""
        while True:
            is_var = self.at("var") or self.at("static") and self.at("var", offset=1)
            name = ""
            if is_var:
                if self.at("static"):
                    self.next()
                self.next()
                name = self.peek().text if self.peek() is not None else ""
            mark = len(self.statements)
            last = self.expression(owner=("", cls))
            if len(self.statements) > mark:
                inside = self.statements[mark:]
                del self.statements[mark:]
                self.unsure(start.line, max(s["line"] for s in inside),
                            "a lambda in a class-level declaration runs outside any function")
            if self.at(";"):
                self.next()
                continue
            break
        if is_var and last is not None and last.text == ":" and self.peek() is not None \
                and self.peek().kind == "newline":
            self.next()
            self.skip_newlines()
            body = self.peek()
            if body is None or body.indent <= indent:
                raise Unsure(f"line {start.line}: a property without its get/set block")
            self.accessors(body.indent, cls, name)
        else:
            self.end_of_line()

    def accessors(self, indent: int, cls: str, prop: str) -> None:
        """A property's `get:` / `set(value):` bodies (functions) and `get = f` / `set = f` lines (no body)."""
        while True:
            self.skip_newlines()
            tok = self.peek()
            if tok is None or tok.indent < indent:
                return
            start = tok
            if not (self.at("get", "set") and tok.first and tok.indent == indent):
                raise Unsure(f"line {tok.line}: a property block holding something other than get / set")
            if self.at("=", offset=1):
                self.expression(owner=None)
                self.end_of_line()
                continue
            self.guarded(indent, start, self.accessor, indent, cls, prop)

    def accessor(self, indent: int, cls: str, prop: str) -> None:
        which = self.next().text
        if self.at("("):
            self.skip_group()
        self.body_after_colon(indent, f"{prop}.{which}", cls, "function")

    def function(self, indent: int, cls: str) -> None:
        if self.at("static"):
            self.next()
        header = self.next()  # func
        name = self.next().text
        if not self.at("("):
            raise Unsure(f"line {header.line}: a func without its parameters")
        self.skip_group()
        self.body_after_colon(indent, name, cls, "function")

    # --- function bodies ----------------------------------------------------------------------

    def body_after_colon(self, indent: int, function: str, cls: str, first_kind: str) -> None:
        """The `:` ending a header, then its body: statements on the same line, or a block indented past `indent`."""
        colon = self.header_colon()
        tok = self.peek()
        if tok is None:
            raise Unsure(f"line {colon.line}: a header without a body")
        if tok.kind == "newline":
            self.next()
            self.skip_newlines()
            body = self.peek()
            if body is None or body.indent <= indent or not body.first:
                raise Unsure(f"line {colon.line}: a header without an indented body")
            self.block(body.indent, function, cls, first_kind)
        else:
            self.inline_body(function, cls, first_kind, in_brackets=False)
            self.end_of_line()

    def header_colon(self) -> Token:
        """Skip a header's tokens up to its `:` at bracket depth 0 (brackets skipped whole)."""
        while True:
            tok = self.peek()
            if tok is None or tok.kind == "newline":
                raise Unsure(f"line {self.line_of_last()}: a header without its `:`")
            if tok.kind == "op" and tok.text in "([{":
                self.skip_group()
                continue
            self.next()
            if tok.kind == "op" and tok.text == ":":
                return tok

    def block(self, indent: int, function: str, cls: str, first_kind: str) -> None:
        """Statements at `indent` until a line indented less."""
        kind = first_kind
        while True:
            self.skip_newlines()
            tok = self.peek()
            if tok is None or tok.first and tok.indent < indent:
                return
            if not tok.first or tok.indent > indent:
                raise Unsure(f"line {tok.line}: unexpected indentation in a body")
            self.statement_line(indent, function, cls, kind)
            kind = "statement"

    def statement_line(self, indent: int, function: str, cls: str, kind: str) -> None:
        """One line's statements, `a; b; if c:` (the first of them gets `kind`), and what their compounds hold."""
        record = True
        if self.at("@"):
            line = self.peek().line
            self.annotation()
            self.skip_newlines()
            nxt = self.peek()
            self.unsure(line, nxt.line if nxt is not None else line,
                        "a statement under an annotation: a counter before it would take the annotation")
            record = False
        self.statement(indent, function, cls, kind, record)
        while self.at(";"):
            self.next()
            if self.peek() is None or self.peek().kind == "newline":
                break
            self.statement(indent, function, cls, "statement", record)
        self.end_of_line()

    def statement(self, indent: int, function: str, cls: str, kind: str, record: bool = True) -> None:
        tok = self.peek()
        if record:
            self.record(tok, kind, function, cls)
        word = tok.text if tok.kind == "name" else ""
        owner = (function, cls)
        if word in ("if", "while"):
            self.next()
            self.expression(owner, until_colon=True)
            self.body_after_colon(indent, function, cls, "branch")
            if word == "if":
                self.else_chain(indent, function, cls)
        elif word == "for":
            self.next()
            self.for_header(owner)
            self.body_after_colon(indent, function, cls, "branch")
        elif word == "match":
            self.next()
            self.match_rest(indent, function, cls)
        elif word in ("elif", "else"):
            raise Unsure(f"line {tok.line}: `{word}` without its `if`")
        else:
            self.expression(owner)

    def for_header(self, owner) -> None:
        """`for name [: Type] in iterable` up to the `:` (a typed loop variable has a `:` of its own)."""
        self.next()  # the loop variable
        if self.at(":"):
            while not self.at("in"):
                if self.peek() is None or self.peek().kind == "newline":
                    raise Unsure(f"line {self.line_of_last()}: a for without `in`")
                if self.at("[", "("):
                    self.skip_group()
                else:
                    self.next()
        self.expression(owner, until_colon=True)

    def else_chain(self, indent: int, function: str, cls: str) -> None:
        while True:
            save = self.pos
            self.skip_newlines()
            tok = self.peek()
            if tok is not None and tok.first and tok.indent == indent and self.at("elif"):
                self.next()
                self.expression((function, cls), until_colon=True)
                self.body_after_colon(indent, function, cls, "branch")
            elif tok is not None and tok.first and tok.indent == indent and self.at("else"):
                self.next()
                self.body_after_colon(indent, function, cls, "branch")
            else:
                self.pos = save
                return

    def match_rest(self, indent: int, function: str, cls: str) -> None:
        self.expression((function, cls), until_colon=True)
        colon = self.header_colon()
        if self.peek() is None or self.peek().kind != "newline":
            raise Unsure(f"line {colon.line}: a match without its arms")
        self.next()
        self.skip_newlines()
        arms = self.peek()
        if arms is None or arms.indent <= indent or not arms.first:
            raise Unsure(f"line {colon.line}: a match without indented arms")
        while True:
            self.skip_newlines()
            tok = self.peek()
            if tok is None or tok.first and tok.indent < arms.indent:
                return
            if not tok.first or tok.indent > arms.indent:
                raise Unsure(f"line {tok.line}: unexpected indentation in a match")
            self.body_after_colon(arms.indent, function, cls, "branch")

    def inline_body(self, function: str, cls: str, first_kind: str, in_brackets: bool) -> None:
        """Statements after a header's `:` on the same line, separated by `;`. A one-line lambda inside brackets
        (`in_brackets`) ends at the bracket closing around it or at a `,`."""
        kind = first_kind
        while True:
            tok = self.peek()
            if tok is None or tok.kind == "newline":
                return
            if in_brackets and tok.kind == "op" and tok.text in ",)]}":
                return
            self.record(tok, kind, function, cls)
            kind = "statement"
            word = tok.text if tok.kind == "name" else ""
            if word in KEYWORD_COMPOUND:
                if word in ("elif", "else", "match") or in_brackets:
                    raise Unsure(f"line {tok.line}: a `{word}` inside a one-line body")
                self.next()
                if word == "for":
                    self.for_header((function, cls))
                else:
                    self.expression((function, cls), until_colon=True)
                self.header_colon()
                self.inline_body(function, cls, "branch", in_brackets)
                return
            self.expression((function, cls), in_brackets=in_brackets)
            if not self.at(";"):
                return
            self.next()

    def expression(self, owner, until_colon: bool = False, in_brackets: bool = False):
        """Skip an expression to its end: a `;` or the end of the logical line at depth 0, a header's `:` with
        `until_colon`, and, `in_brackets` (a one-line lambda's body), the bracket closing around it or a `,`. A lambda
        in it is followed and its statements recorded for `owner`, (function, class). Returns the last token taken."""
        depth = 0
        last = None
        while True:
            tok = self.peek()
            if tok is None:
                if depth:
                    raise Unsure("a bracket that never closes")
                return last
            if tok.kind == "newline":
                if depth == 0:
                    return last
                self.next()
                continue
            if tok.kind == "op":
                if depth == 0 and not in_brackets and self.closes_lambda(tok):
                    return last
                if tok.text in "([{":
                    depth += 1
                elif tok.text in ")]}":
                    if depth == 0:
                        if in_brackets:
                            return last
                        raise Unsure(f"line {tok.line}: a closing `{tok.text}` without its opening one")
                    depth -= 1
                elif depth == 0 and (tok.text == ";" or tok.text == "," and in_brackets
                                     or tok.text == ":" and until_colon):
                    return last
            if tok.kind == "name" and tok.text == "func":
                block = self.lambda_(owner, depth > 0 or in_brackets)
                last = self.toks[self.pos - 1]
                if block and depth == 0:
                    return last  # a lambda's block ends the logical line it began on
                continue
            last = self.next()

    def lambda_(self, owner, in_brackets: bool) -> bool:
        """A lambda: `func [name](params) [-> type]:` and its body, inline or an indented block (then True)."""
        header = self.next()
        if self.peek() is not None and self.peek().kind == "name":
            self.next()
        if not self.at("("):
            raise Unsure(f"line {header.line}: a lambda without its parameters")
        self.skip_group()
        function, cls = owner if owner is not None else ("", "")
        colon = self.header_colon()
        tok = self.peek()
        if tok is None:
            raise Unsure(f"line {colon.line}: a lambda without a body")
        if tok.kind == "newline" or tok.line > colon.line:
            if tok.kind == "newline":
                self.next()
            self.skip_newlines()
            body = self.peek()
            if body is None or body.indent <= header.indent or not body.first:
                raise Unsure(f"line {colon.line}: a lambda without an indented body")
            self.bracketed.append(in_brackets)
            try:
                self.block(body.indent, function, cls, "statement")
            except LambdaClosed:
                return False  # the bracket around it closed on its last line: the outer expression goes on
            finally:
                self.bracketed.pop()
            return True
        self.inline_body(function, cls, "statement", in_brackets)
        return False

    def skip_group(self) -> None:
        """Skip a bracketed group from its opening bracket to its matching close."""
        opening = self.next()
        closing = {"(": ")", "[": "]", "{": "}"}[opening.text]
        while True:
            tok = self.peek()
            if tok is None:
                raise Unsure(f"line {opening.line}: a `{opening.text}` that never closes")
            if tok.kind == "op" and tok.text in "([{":
                self.skip_group()
            elif tok.kind == "op" and tok.text in ")]}":
                self.next()
                if tok.text != closing:
                    raise Unsure(f"line {tok.line}: a `{tok.text}` closing a `{opening.text}`")
                return
            elif tok.kind == "name" and tok.text == "func":
                raise Unsure(f"line {tok.line}: a lambda inside a header")
            else:
                self.next()

    # --- results ------------------------------------------------------------------------------

    def record(self, tok: Token, kind: str, function: str, cls: str) -> None:
        if tok.line in self.lx.in_string_lines:
            self.unsure(tok.line, tok.line, "a statement starts on the closing line of a multi-line string")
            return
        self.statements.append({"line": tok.line, "col": tok.col, "kind": kind, "function": function, "class": cls})

    def unsure(self, line: int, end_line: int, reason: str) -> None:
        self.uninstrumented.append({"line": line, "end_line": end_line, "reason": reason})


def scan(text: str) -> dict:
    """The statements and uninstrumented spans of one GDScript file (see the module docstring)."""
    try:
        lexer = Lexer(text)
        parser = Parser(lexer)
        parser.parse_file()
    except (Unsure, IndexError) as why:
        last = max(1, len(text.split("\n")) - (1 if text.endswith("\n") else 0))
        return {"statements": [], "uninstrumented": [
            {"line": 1, "end_line": last, "reason": f"the scanner could not follow this file: {why}"}]}
    statements = sorted(parser.statements, key=lambda s: (s["line"], s["col"]))
    spans = sorted(parser.uninstrumented, key=lambda u: (u["line"], u["end_line"]))
    return {"statements": statements, "uninstrumented": spans}
