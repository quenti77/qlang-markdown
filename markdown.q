--" # Markdown

Turns Markdown text into HTML, the way GitHub reads it (CommonMark plus the GitHub extensions).

```
import "@markdown/markdown.q" as markdown

markdown.render("# Hello\n\nSome *text* with `code`.")
```

What it reads: headings (`#` and underlined), paragraphs, emphasis (`*a*`, `**a**`, `***a***`, `_a_`, `~~a~~`),
`code`, fenced and indented code blocks, links (inline, reference and bare `https://…` addresses), images,
bullet / numbered / task lists (nested), quotes, alerts (`> [!NOTE]`), tables, footnotes, horizontal rules,
HTML entities, hard line breaks, and `<!-- comments -->` (dropped).

Raw HTML is **escaped** unless `Options.allow_html` is set, and even then `<script>`, `<iframe>`, `<style>`…,
event attributes (`onclick=`) and `javascript:` are refused. Links to `javascript:` or other unknown schemes are
written as plain text. Use `allow_html` only for text you trust.

Fenced code goes through `Options.highlight(language, code)`, which gives the HTML of the code: plug your own
colouring there. By default the code is only escaped.
--"

--" What `convert` can be told. --"
struct Options
    --" Gives the HTML of a code block from its language (may be empty) and its code. --"
    public highlight: fun(string, string) -> string
    --" Put an `id` on each heading (`hello-world`), so that pages can link to it. --"
    public heading_ids: bool
    --" Let raw HTML through (minus the dangerous parts). Off by default: only for text you trust. --"
    public allow_html: bool
end

--" A heading of the text, for a table of contents. --"
struct Heading
    public level: int
    public id: string
    public text: string
end

--" The result of `convert`: the HTML, the text of the first level 1 heading, and every heading. --"
struct Document
    public html: string
    public title: string
    public headings: array<Heading>
end

struct LinkRef
    public url: string
    public title: string
end

--" What the rendering carries along: the options, the headings met so far, the ids already used, the link
definitions and the footnotes. --"
struct Context
    public options: Options
    public headings: array<Heading>
    public used: map<string, int>
    public refs: map<string, LinkRef>
    public notes: map<string, array<string>>
    public order: array<string>
end

--" A piece of output and where the reading goes on. --"
struct Piece
    public html: string
    public next: int
end

--" A block of output and the index of the first line after it. --"
struct Step
    public html: string
    public next: int
end

--" Escapes the characters that have a meaning in HTML. --"
fun escape(text: string) -> string
    text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
end

impl Options
    --" The default options: code is escaped, headings get ids, raw HTML is escaped. --"
    public fun plain() -> Options
        Options { highlight: fun(language: string, code: string) -> string escape(code) end, heading_ids: true, allow_html: false }
    end
end

fun is_blank(line: string) -> bool
    line.trim() == ""
end

fun indent_of(line: string) -> int
    let n = 0
    let chars = line.chars()
    while n < chars.len() and chars[n] == " " do
        n = n + 1
    end
    n
end

fun drop_indent(line: string, count: int) -> string
    let n = indent_of(line)
    if n > count then
        n = count
    end
    line.substring(n, line.len())
end

fun matches_at(chars: array<string>, at: int, text: string) -> bool
    let want = text.chars()
    if at < 0 or at + want.len() > chars.len() then
        return false
    end
    let k = 0
    while k < want.len() do
        if chars[at + k] != want[k] then
            return false
        end
        k = k + 1
    end
    true
end

fun is_word_char(c: string) -> bool
    c.is_alpha() or c.is_digit()
end

fun is_space(c: string) -> bool
    c == " " or c == "\n" or c == "\t"
end

fun is_punct(c: string) -> bool
    "!\"#$%&'()*+,-./:;<=>?@[\\]^_`\{|}~".contains(c)
end

fun count_run(chars: array<string>, at: int, c: string) -> int
    let n = 0
    while at + n < chars.len() and chars[at + n] == c do
        n = n + 1
    end
    n
end

--" Where `text` starts in `chars` at or after `begin`, or -1. Backslash escapes are skipped. --"
fun find_text(chars: array<string>, begin: int, text: string) -> int
    let i = begin
    while i < chars.len() do
        if chars[i] == "\\" then
            i = i + 2
        elseif matches_at(chars, i, text) then
            return i
        else
            i = i + 1
        end
    end
    -1
end

--" Where the `]` that closes the `[` at `open` is, or -1. --"
fun find_bracket(chars: array<string>, open: int) -> int
    let depth = 0
    let i = open
    while i < chars.len() do
        if chars[i] == "\\" then
            i = i + 1
        elseif chars[i] == "`" then
            let run = count_run(chars, i, "`")
            let close = find_run(chars, i + run, run)
            if close >= 0 then
                i = close + run - 1
            else
                i = i + run - 1
            end
        elseif chars[i] == "[" then
            depth = depth + 1
        elseif chars[i] == "]" then
            depth = depth - 1
            if depth == 0 then
                return i
            end
        end
        i = i + 1
    end
    -1
end

--" Where a run of exactly `size` backticks starts at or after `begin`, or -1. --"
fun find_run(chars: array<string>, begin: int, size: int) -> int
    let i = begin
    while i < chars.len() do
        if chars[i] == "`" then
            let run = count_run(chars, i, "`")
            if run == size then
                return i
            end
            i = i + run
        else
            i = i + 1
        end
    end
    -1
end

--" Only web, mail and relative addresses become links. --"
fun safe_url(url: string) -> bool
    let u = url.trim().lower()
    let colon = u.index_of(":")
    if colon == none then
        return true
    end
    for stop in ["/", "?", "#"] do
        let at = u.index_of(stop)
        if at != none and at < colon then
            return true
        end
    end
    let scheme = u.substring(0, colon)
    scheme == "http" or scheme == "https" or scheme == "mailto"
end

let FILTERED_TAGS = ["title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script", "plaintext", "object", "embed"]

--" Raw HTML that must not go through, even when HTML is allowed. --"
fun html_is_unsafe(raw: string) -> bool
    let low = raw.lower()
    if low.contains("javascript:") or low.contains("vbscript:") or low.contains("data:text/html") then
        return true
    end
    for name in FILTERED_TAGS do
        if low.contains("<" + name) or low.contains("</" + name) then
            return true
        end
    end
    let chars = low.chars()
    let i = 0
    while i + 3 < chars.len() do
        if chars[i] == "o" and chars[i + 1] == "n" and (is_space(chars[i - 1 + (if i == 0 then 1 else 0 end)]) or chars[i - 1 + (if i == 0 then 1 else 0 end)] == "\"" or chars[i - 1 + (if i == 0 then 1 else 0 end)] == "'" or chars[i - 1 + (if i == 0 then 1 else 0 end)] == "/") and i > 0 then
            let j = i + 2
            while j < chars.len() and chars[j].is_alpha() do
                j = j + 1
            end
            while j < chars.len() and is_space(chars[j]) do
                j = j + 1
            end
            if j < chars.len() and chars[j] == "=" and j > i + 2 then
                return true
            end
        end
        i = i + 1
    end
    false
end

fun tag_name(raw: string) -> string
    let out = ""
    for c in raw.chars() do
        if c == "<" or c == "/" or c == "!" then
            if out != "" then break end
        elseif is_word_char(c) then
            out = out + c
        else
            break
        end
    end
    out.lower()
end

--" The text of an HTML fragment: the tags removed, the entities left as they are. --"
fun strip_tags(html: string) -> string
    let out = ""
    let inside = false
    for c in html.chars() do
        if c == "<" then
            inside = true
        elseif c == ">" and inside then
            inside = false
        elseif not inside then
            out = out + c
        end
    end
    out
end

fun is_entity_char(c: string) -> bool
    is_word_char(c) or c == "#"
end

--" `&amp;`, `&#169;`, `&copy;` stay as written; a lone `&` is escaped. --"
fun try_entity(chars: array<string>, i: int) -> Piece
    let j = i + 1
    while j < chars.len() and j < i + 32 and is_entity_char(chars[j]) do
        j = j + 1
    end
    if j > i + 1 and j < chars.len() and chars[j] == ";" then
        return Piece { html: chars.slice(i, j + 1).join(""), next: j + 1 }
    end
    Piece { html: "&amp;", next: i + 1 }
end

fun try_escape(chars: array<string>, i: int) -> Piece
    if i + 1 >= chars.len() then
        return Piece { html: "\\", next: i + 1 }
    end
    let c = chars[i + 1]
    if c == "\n" then
        return Piece { html: "<br>\n", next: i + 2 }
    end
    if is_punct(c) then
        return Piece { html: escape(c), next: i + 2 }
    end
    Piece { html: "\\", next: i + 1 }
end

fun try_code(chars: array<string>, i: int) -> Piece
    let run = count_run(chars, i, "`")
    let close = find_run(chars, i + run, run)
    if close < 0 then
        return Piece { html: "`".repeat(run), next: i + run }
    end
    let code = chars.slice(i + run, close).join("").replace("\n", " ")
    if code.starts_with(" ") and code.ends_with(" ") and code.trim() != "" then
        code = code.substring(1, code.len() - 1)
    end
    Piece { html: "<code>" + escape(code) + "</code>", next: close + run }
end

--" `<https://…>`, `<me@host.org>`, raw tags and comments. --"
fun try_angle(chars: array<string>, i: int, ctx: Context) -> Piece
    if matches_at(chars, i, "<!--") then
        let close = find_text(chars, i + 4, "-->")
        if close >= 0 then
            return Piece { html: "", next: close + 3 }
        end
    end
    let close = find_text(chars, i, ">")
    if close > i + 1 then
        let inner = chars.slice(i + 1, close).join("")
        if not inner.contains(" ") and not inner.contains("<") then
            if inner.starts_with("http://") or inner.starts_with("https://") or inner.starts_with("mailto:") then
                return Piece { html: "<a href=\"" + escape(inner) + "\">" + escape(inner) + "</a>", next: close + 1 }
            end
            if inner.contains("@") and not inner.contains("/") and not inner.starts_with("@") then
                return Piece { html: "<a href=\"mailto:" + escape(inner) + "\">" + escape(inner) + "</a>", next: close + 1 }
            end
        end
        let first = chars[i + 1]
        if ctx.options.allow_html and (first.is_alpha() or first == "/") and not inner.contains("<") then
            let raw = chars.slice(i, close + 1).join("")
            if not html_is_unsafe(raw) then
                return Piece { html: raw, next: close + 1 }
            end
        end
    end
    Piece { html: "&lt;", next: i + 1 }
end

--" A link destination and its optional title, after an opening `(`. --"
struct Dest
    public url: string
    public title: string
    public next: int
end

fun parse_dest(chars: array<string>, begin: int) -> Dest?
    let n = chars.len()
    let i = begin
    while i < n and is_space(chars[i]) do
        i = i + 1
    end
    let url = ""
    if i < n and chars[i] == "<" then
        i = i + 1
        while i < n and chars[i] != ">" and chars[i] != "\n" do
            url = url + chars[i]
            i = i + 1
        end
        if i >= n or chars[i] != ">" then
            return none
        end
        i = i + 1
    else
        let depth = 0
        while i < n and not is_space(chars[i]) do
            if chars[i] == "\\" and i + 1 < n then
                url = url + chars[i + 1]
                i = i + 2
            else
                if chars[i] == "(" then
                    depth = depth + 1
                elseif chars[i] == ")" then
                    if depth == 0 then break end
                    depth = depth - 1
                end
                url = url + chars[i]
                i = i + 1
            end
        end
    end
    while i < n and is_space(chars[i]) do
        i = i + 1
    end
    let title = ""
    if i < n and (chars[i] == "\"" or chars[i] == "'" or chars[i] == "(") then
        let quote = if chars[i] == "(" then ")" else chars[i] end
        i = i + 1
        while i < n and chars[i] != quote do
            if chars[i] == "\\" and i + 1 < n then
                i = i + 1
            end
            title = title + chars[i]
            i = i + 1
        end
        if i >= n then
            return none
        end
        i = i + 1
        while i < n and is_space(chars[i]) do
            i = i + 1
        end
    end
    if i < n and chars[i] == ")" then
        return Dest { url: url, title: title, next: i + 1 }
    end
    none
end

fun normalize_label(label: string) -> string
    label.lower().words().join(" ")
end

fun link_html(label_html: string, url: string, title: string, image: bool) -> string
    let attr = if title == "" then "" else " title=\"" + escape(title) + "\"" end
    if image then
        let alt = strip_tags(label_html)
        if not safe_url(url) then
            return alt
        end
        return "<img src=\"" + escape(url) + "\" alt=\"" + alt + "\"" + attr + ">"
    end
    if not safe_url(url) then
        return label_html
    end
    "<a href=\"" + escape(url) + "\"" + attr + ">" + label_html + "</a>"
end

fun footnote_number(ctx: Context, id: string) -> int
    let k = 0
    while k < ctx.order.len() do
        if ctx.order[k] == id then
            return k + 1
        end
        k = k + 1
    end
    ctx.order.push(id)
    ctx.order.len()
end

--" `[text](url)`, `[text][label]`, `[label]`, `![alt](url)` and `[^note]`. --"
fun try_link(chars: array<string>, i: int, ctx: Context) -> Piece?
    let n = chars.len()
    let image = chars[i] == "!"
    let open = if image then i + 1 else i end
    let close = find_bracket(chars, open)
    if close < 0 then
        return none
    end
    let raw = chars.slice(open + 1, close).join("")
    if not image and raw.starts_with("^") and ctx.notes.has(normalize_label(raw.substring(1, raw.len()))) then
        let id = normalize_label(raw.substring(1, raw.len()))
        let number = footnote_number(ctx, id)
        let slug = slugify(id)
        return Piece { html: "<sup class=\"footnote-ref\"><a href=\"#fn-{slug}\" id=\"fnref-{slug}\">{number}</a></sup>", next: close + 1 }
    end
    let after = close + 1
    if after < n and chars[after] == "(" then
        let dest = parse_dest(chars, after + 1)
        if dest != none then
            return Piece { html: link_html(inline(raw, ctx), dest.url, dest.title, image), next: dest.next }
        end
    end
    let label = raw
    let next = after
    if after < n and chars[after] == "[" then
        let second = find_bracket(chars, after)
        if second > 0 then
            let named = chars.slice(after + 1, second).join("")
            if named != "" then
                label = named
            end
            next = second + 1
        end
    end
    let key = normalize_label(label)
    if ctx.refs.has(key) then
        let ref = ctx.refs[key].unwrap()
        return Piece { html: link_html(inline(raw, ctx), ref.url, ref.title, image), next: next }
    end
    none
end

--" A bare `https://…` or `www.…` address becomes a link. --"
fun try_bare_url(chars: array<string>, i: int) -> Piece?
    if i > 0 and is_word_char(chars[i - 1]) then
        return none
    end
    let prefix = ""
    if matches_at(chars, i, "https://") or matches_at(chars, i, "http://") then
        prefix = ""
    elseif matches_at(chars, i, "www.") then
        prefix = "http://"
    else
        return none
    end
    let j = i
    while j < chars.len() and not is_space(chars[j]) and chars[j] != "<" do
        j = j + 1
    end
    while j > i + 4 and ".,:;!?*_~'\"".contains(chars[j - 1]) do
        j = j - 1
    end
    let url = chars.slice(i, j).join("")
    if url.count("(") < url.count(")") and chars[j - 1] == ")" then
        j = j - 1
        url = chars.slice(i, j).join("")
    end
    if j <= i + 6 then
        return none
    end
    Piece { html: "<a href=\"" + escape(prefix + url) + "\">" + escape(url) + "</a>", next: j }
end

fun find_emphasis_close(chars: array<string>, begin: int, delim: string) -> int
    let c = delim.chars()[0]
    let size = delim.len()
    let j = begin
    while j < chars.len() do
        if chars[j] == "\\" then
            j = j + 2
        elseif chars[j] == "`" then
            let run = count_run(chars, j, "`")
            let close = find_run(chars, j + run, run)
            if close >= 0 then
                j = close + run
            else
                j = j + run
            end
        elseif chars[j] == c then
            let run = count_run(chars, j, c)
            let after = j + run
            let word_after = c == "_" and after < chars.len() and is_word_char(chars[after])
            if run >= size and j > begin and not is_space(chars[j - 1]) and not word_after then
                return j + run - size
            end
            j = j + run
        else
            j = j + 1
        end
    end
    -1
end

--" Emphasis, strong text and strikethrough starting at `i`. --"
fun try_emphasis(chars: array<string>, i: int, ctx: Context) -> Piece
    let n = chars.len()
    let c = chars[i]
    let run = count_run(chars, i, c)
    let size = if c == "~" then (if run >= 2 then 2 else 1 end) elseif run >= 3 then 3 else run end
    let literal = Piece { html: c.repeat(run), next: i + run }
    let opens = i + size < n and not is_space(chars[i + size]) and (c != "_" or i == 0 or not is_word_char(chars[i - 1]))
    if not opens or (c == "~" and run > 2) then
        return literal
    end
    let delim = c.repeat(size)
    let close = find_emphasis_close(chars, i + size, delim)
    if close < 0 then
        return literal
    end
    let inner = inline(chars.slice(i + size, close).join(""), ctx)
    let html = if c == "~" then "<del>" + inner + "</del>"
    elseif size == 3 then "<em><strong>" + inner + "</strong></em>"
    elseif size == 2 then "<strong>" + inner + "</strong>"
    else "<em>" + inner + "</em>" end
    Piece { html: html, next: close + size }
end

fun next_piece(chars: array<string>, i: int, ctx: Context) -> Piece
    let c = chars[i]
    if c == "\\" then
        return try_escape(chars, i)
    elseif c == "`" then
        return try_code(chars, i)
    elseif c == "&" then
        return try_entity(chars, i)
    elseif c == "<" then
        return try_angle(chars, i, ctx)
    elseif c == "*" or c == "_" or c == "~" then
        return try_emphasis(chars, i, ctx)
    elseif (c == "!" and i + 1 < chars.len() and chars[i + 1] == "[") or c == "[" then
        let link = try_link(chars, i, ctx)
        if link != none then
            return link
        end
    elseif c == "h" or c == "w" then
        let url = try_bare_url(chars, i)
        if url != none then
            return url
        end
    elseif c == " " and i + 2 < chars.len() and chars[i + 1] == " " and chars[i + 2] == "\n" then
        return Piece { html: "<br>", next: i + 2 }
    end
    Piece { html: escape(c), next: i + 1 }
end

--" The inline markup of a text: code, emphasis, links, images. --"
fun inline(text: string, ctx: Context) -> string
    let chars = text.chars()
    let out = ""
    let i = 0
    while i < chars.len() do
        let piece = next_piece(chars, i, ctx)
        out = out + piece.html
        i = piece.next
    end
    out
end

--" `Hello, World!` becomes `hello-world`, the way GitHub writes the id of a heading. --"
fun slugify(text: string) -> string
    let out = ""
    for c in text.lower().chars() do
        if is_word_char(c) or c == "-" or c == "_" then
            out = out + c
        elseif c == " " then
            out = out + "-"
        end
    end
    out
end

fun unique_id(ctx: Context, base: string) -> string
    let slug = if base == "" then "section" else base end
    let seen = ctx.used.get(slug, 0)
    ctx.used[slug] = seen + 1
    if seen == 0 then slug else slug + "-{seen}" end
end

--" How many `#` open the line (1 to 6) when it is a heading, otherwise 0. --"
fun heading_level(line: string) -> int
    if indent_of(line) > 3 then
        return 0
    end
    let t = line.trim()
    let n = count_run(t.chars(), 0, "#")
    if n >= 1 and n <= 6 and (n == t.len() or t.chars()[n] == " ") then
        return n
    end
    0
end

fun is_rule(line: string) -> bool
    let t = line.trim().replace(" ", "")
    if t.len() < 3 or indent_of(line) > 3 then
        return false
    end
    t == "-".repeat(t.len()) or t == "*".repeat(t.len()) or t == "_".repeat(t.len())
end

--" 1 for a `===` line, 2 for a `---` line, 0 otherwise: what turns the paragraph above into a heading. --"
fun setext_level(line: string) -> int
    let t = line.trim()
    if t == "" or indent_of(line) > 3 then
        return 0
    end
    if t == "=".repeat(t.len()) then
        return 1
    end
    if t == "-".repeat(t.len()) then
        return 2
    end
    0
end

fun fence_of(line: string) -> string
    if indent_of(line) > 3 and not line.trim().starts_with("```") then
        return ""
    end
    let t = line.trim()
    if t.starts_with("```") then
        return "```"
    end
    if t.starts_with("~~~") then
        return "~~~"
    end
    ""
end

--" A list marker: its indentation, the width up to the text, and whether it is numbered. --"
struct Marker
    public indent: int
    public width: int
    public ordered: bool
    public number: int
end

fun marker_of(line: string) -> Marker?
    let ind = indent_of(line)
    let rest = line.substring(ind, line.len())
    for bullet in ["- ", "* ", "+ "] do
        if rest.starts_with(bullet) and not is_rule(line) then
            return Marker { indent: ind, width: ind + 2, ordered: false, number: 0 }
        end
    end
    let chars = rest.chars()
    let digits = count_digits(chars)
    if digits > 0 and digits < 10 and digits + 1 < chars.len() and (chars[digits] == "." or chars[digits] == ")") and chars[digits + 1] == " " then
        let number = chars.slice(0, digits).join("").to_int() ?? 1
        return Marker { indent: ind, width: ind + digits + 2, ordered: true, number: number }
    end
    none
end

fun count_digits(chars: array<string>) -> int
    let n = 0
    while n < chars.len() and chars[n].is_digit() do
        n = n + 1
    end
    n
end

fun split_cells(line: string) -> array<string>
    let t = line.trim().replace("\\|", "\0")
    if t.starts_with("|") then
        t = t.substring(1, t.len())
    end
    if t.ends_with("|") then
        t = t.substring(0, t.len() - 1)
    end
    t.split("|").map(fun(cell: string) -> string cell.trim().replace("\0", "|") end)
end

fun is_table_separator(line: string) -> bool
    if not line.contains("-") or not line.contains("|") then
        return false
    end
    for cell in split_cells(line) do
        let t = cell.replace("-", "").replace(":", "")
        if t != "" or not cell.contains("-") then
            return false
        end
    end
    true
end

let BLOCK_TAGS = ["address", "article", "aside", "blockquote", "body", "center", "details", "dialog", "dd", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "html", "li", "main", "nav", "ol", "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"]

fun is_html_block_start(line: string) -> bool
    let t = line.trim()
    if indent_of(line) > 3 or not t.starts_with("<") then
        return false
    end
    if t.starts_with("<!--") then
        return true
    end
    BLOCK_TAGS.contains(tag_name(t))
end

fun starts_block(line: string) -> bool
    let t = line.trim()
    heading_level(line) > 0 or fence_of(line) != "" or t.starts_with(">") or is_rule(line) or marker_of(line) != none or is_html_block_start(line)
end

fun render_table(header: string, separator: string, rows: array<string>, ctx: Context) -> string
    let aligns = split_cells(separator).map(fun(cell: string) -> string
        if cell.starts_with(":") and cell.ends_with(":") then " style=\"text-align:center\""
        elseif cell.ends_with(":") then " style=\"text-align:right\""
        elseif cell.starts_with(":") then " style=\"text-align:left\""
        else "" end
    end)
    let columns = aligns.len()
    let out = "<table>\n<thead><tr>"
    let col = 0
    for cell in split_cells(header) do
        let align = if col < columns then aligns[col] else "" end
        out = out + "<th" + align + ">" + inline(cell, ctx) + "</th>"
        col = col + 1
    end
    out = out + "</tr></thead>\n<tbody>\n"
    for row in rows do
        out = out + "<tr>"
        let k = 0
        for cell in split_cells(row) do
            if k < columns then
                out = out + "<td" + (if k < columns then aligns[k] else "" end) + ">" + inline(cell, ctx) + "</td>"
            end
            k = k + 1
        end
        out = out + "</tr>\n"
    end
    out + "</tbody>\n</table>\n"
end

fun render_item(item: array<string>, ctx: Context) -> string
    let loose = false
    let k = 1
    while k < item.len() do
        if is_blank(item[k]) and k + 1 < item.len() and marker_of(item[k + 1]) == none then
            loose = true
        end
        k = k + 1
    end
    let first = item[0]
    let checkbox = ""
    if first.starts_with("[ ] ") then
        checkbox = "<input type=\"checkbox\" disabled> "
        item[0] = first.substring(4, first.len())
    elseif first.starts_with("[x] ") or first.starts_with("[X] ") then
        checkbox = "<input type=\"checkbox\" checked disabled> "
        item[0] = first.substring(4, first.len())
    end
    let html = render_blocks(item, ctx)
    if not loose then
        html = html.replace("<p>", "").replace("</p>\n", "\n")
    end
    "<li>" + checkbox + html.trim() + "</li>\n"
end

--" The list that starts at `start`. --"
fun render_list(lines: array<string>, start: int, ctx: Context) -> Step
    let first = marker_of(lines[start]).unwrap()
    let base = first.indent
    let items = ""
    let i = start
    while i < lines.len() do
        let m = marker_of(lines[i])
        if m == none or m.indent != base or m.ordered != first.ordered then
            break
        end
        let item = [lines[i].substring(m.width, lines[i].len())]
        i = i + 1
        while i < lines.len() do
            let line = lines[i]
            if is_blank(line) then
                let next = i + 1
                while next < lines.len() and is_blank(lines[next]) do
                    next = next + 1
                end
                if next < lines.len() and indent_of(lines[next]) > base then
                    item.push("")
                    i = i + 1
                else
                    break
                end
            elseif indent_of(line) > base then
                item.push(drop_indent(line, m.width - base))
                i = i + 1
            else
                break
            end
        end
        items = items + render_item(item, ctx)
    end
    let tag = if first.ordered then "ol" else "ul" end
    let attr = if first.ordered and first.number != 1 then " start=\"{first.number}\"" else "" end
    Step { html: "<" + tag + attr + ">\n" + items + "</" + tag + ">\n", next: i }
end

fun render_heading(level: int, text: string, ctx: Context) -> string
    let html = inline(text, ctx)
    let plain = strip_tags(html)
    let id = unique_id(ctx, slugify(plain.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")))
    ctx.headings.push(Heading { level: level, id: id, text: plain })
    if ctx.options.heading_ids then
        "<h{level} id=\"{id}\">" + html + "</h{level}>\n"
    else
        "<h{level}>" + html + "</h{level}>\n"
    end
end

fun block_fence(lines: array<string>, start: int, ctx: Context) -> Step
    let t = lines[start].trim()
    let fence = fence_of(t)
    let info = t.substring(3, t.len()).trim()
    let language = if info == "" then "" else info.replace("\{", "").replace("\}", "").replace(".", "").split(" ")[0] end
    let code: array<string> = []
    let i = start + 1
    let ind = indent_of(lines[start])
    while i < lines.len() and not lines[i].trim().starts_with(fence) do
        code.push(drop_indent(lines[i], ind))
        i = i + 1
    end
    let body = ctx.options.highlight(language, code.join("\n"))
    let cls = if language == "" then "" else " class=\"language-" + escape(language) + "\"" end
    Step { html: "<pre><code" + cls + ">" + body + "</code></pre>\n", next: i + 1 }
end

fun block_indented_code(lines: array<string>, start: int) -> Step
    let code: array<string> = []
    let i = start
    while i < lines.len() do
        if indent_of(lines[i]) >= 4 then
            code.push(drop_indent(lines[i], 4))
            i = i + 1
        elseif is_blank(lines[i]) and i + 1 < lines.len() and (indent_of(lines[i + 1]) >= 4 or is_blank(lines[i + 1])) then
            code.push("")
            i = i + 1
        else
            break
        end
    end
    while code.len() > 0 and code[code.len() - 1] == "" do
        code.pop()
    end
    Step { html: "<pre><code>" + escape(code.join("\n")) + "</code></pre>\n", next: i }
end

--" The first line of an alert: its kind, `+` or `-` when it can be folded (open or closed), and its own title. --"
struct AlertHead
    public kind: string
    public fold: string
    public title: string
end

--" Reads `[!KIND]`, then an optional `+` or `-`, then an optional title, from the first line of a quote. The kind is empty when the line does not start an alert. --"
fun alert_head(line: string) -> AlertHead
    let t = line.trim()
    for kind in ["note", "tip", "important", "warning", "caution"] do
        let mark = "[!" + kind + "]"
        if t.len() >= mark.len() and t.substring(0, mark.len()).lower() == mark then
            let rest = t.substring(mark.len(), t.len())
            let fold = if rest.starts_with("+") or rest.starts_with("-") then rest.substring(0, 1) else "" end
            let title = if fold == "" then rest else rest.substring(1, rest.len()) end
            if title == "" or title.starts_with(" ") or title.starts_with("\t") then
                return AlertHead { kind: kind, fold: fold, title: title.trim() }
            end
        end
    end
    AlertHead { kind: "", fold: "", title: "" }
end

--" An alert: a box with a title (the kind, or the one the text gave) and the quoted blocks; with `+` or `-` it is a `<details>`, open or closed. --"
fun alert_html(head: AlertHead, quoted: array<string>, ctx: Context) -> string
    let rest = render_blocks(quoted.slice(1, quoted.len()), ctx)
    let title = if head.title == "" then head.kind.capitalize() else inline(head.title, ctx) end
    let class_name = "markdown-alert markdown-alert-{head.kind}"
    if head.fold == "" then
        return "<div class=\"{class_name}\">\n<p class=\"markdown-alert-title\">{title}</p>\n" + rest + "</div>\n"
    end
    let open = if head.fold == "+" then " open" else "" end
    "<details class=\"{class_name}\"{open}>\n<summary class=\"markdown-alert-title\">{title}</summary>\n" + rest + "</details>\n"
end

fun block_quote(lines: array<string>, start: int, ctx: Context) -> Step
    let quoted: array<string> = []
    let i = start
    while i < lines.len() and lines[i].trim().starts_with(">") do
        let q = lines[i].trim().substring(1, lines[i].trim().len())
        quoted.push(if q.starts_with(" ") then q.substring(1, q.len()) else q end)
        i = i + 1
    end
    let head = alert_head(quoted[0])
    if head.kind != "" then
        return Step { html: alert_html(head, quoted, ctx), next: i }
    end
    Step { html: "<blockquote>\n" + render_blocks(quoted, ctx) + "</blockquote>\n", next: i }
end

--" A block of raw HTML, up to the next blank line. Comments are dropped; other HTML goes through only when allowed. --"
fun block_html(lines: array<string>, start: int, ctx: Context) -> Step?
    let comment = lines[start].trim().starts_with("<!--")
    let i = start
    let raw: array<string> = []
    if comment then
        while i < lines.len() and not lines[i].contains("-->") do
            i = i + 1
        end
        i = i + 1
        if lines[start].trim().len() > 4 and i <= lines.len() and not lines[i - 1].trim().ends_with("-->") then
            return none
        end
        return Step { html: "", next: i }
    end
    if not ctx.options.allow_html then
        return none
    end
    while i < lines.len() and not is_blank(lines[i]) do
        raw.push(lines[i])
        i = i + 1
    end
    let text = raw.join("\n")
    if html_is_unsafe(text) then
        return Step { html: "<p>" + escape(text) + "</p>\n", next: i }
    end
    Step { html: text + "\n", next: i }
end

fun block_table(lines: array<string>, start: int, ctx: Context) -> Step
    let rows: array<string> = []
    let j = start + 2
    while j < lines.len() and not is_blank(lines[j]) and lines[j].contains("|") do
        rows.push(lines[j])
        j = j + 1
    end
    Step { html: render_table(lines[start], lines[start + 1], rows, ctx), next: j }
end

fun block_paragraph(lines: array<string>, start: int, ctx: Context) -> Step
    let paragraph = [lines[start].trim_start()]
    let i = start + 1
    while i < lines.len() and not is_blank(lines[i]) do
        let level = setext_level(lines[i])
        if level > 0 then
            return Step { html: render_heading(level, paragraph.join("\n").trim(), ctx), next: i + 1 }
        end
        if starts_block(lines[i]) then
            break
        end
        paragraph.push(lines[i].trim_start())
        i = i + 1
    end
    Step { html: "<p>" + inline(paragraph.join("\n"), ctx) + "</p>\n", next: i }
end

fun block_atx(line: string, ctx: Context) -> string
    let t = line.trim()
    let level = heading_level(line)
    let text = t.substring(level, t.len()).trim()
    while text.ends_with("#") and (text.len() == 1 or text.substring(text.len() - 2, text.len() - 1) == " ") do
        text = text.substring(0, text.len() - 1).trim()
    end
    render_heading(level, text, ctx)
end

fun render_blocks(lines: array<string>, ctx: Context) -> string
    let out = ""
    let i = 0
    let n = lines.len()
    while i < n do
        let line = lines[i]
        let t = line.trim()
        let blk: Step? = none
        if t == "" then
            i = i + 1
        elseif indent_of(line) >= 4 then
            blk = block_indented_code(lines, i)
        elseif fence_of(line) != "" then
            blk = block_fence(lines, i, ctx)
        elseif heading_level(line) > 0 then
            out = out + block_atx(line, ctx)
            i = i + 1
        elseif is_rule(line) then
            out = out + "<hr>\n"
            i = i + 1
        elseif t.starts_with(">") then
            blk = block_quote(lines, i, ctx)
        elseif marker_of(line) != none then
            blk = render_list(lines, i, ctx)
        elseif is_html_block_start(line) then
            blk = block_html(lines, i, ctx)
            if blk == none then
                blk = block_paragraph(lines, i, ctx)
            end
        elseif line.contains("|") and i + 1 < n and is_table_separator(lines[i + 1]) then
            blk = block_table(lines, i, ctx)
        else
            blk = block_paragraph(lines, i, ctx)
        end
        if blk != none then
            out = out + blk.html
            i = blk.next
        end
    end
    out
end

--" The `[label]: url "title"` and `[^note]: text` lines, taken out of the text and kept in the context. --"
fun extract_definitions(lines: array<string>, ctx: Context) -> array<string>
    let kept: array<string> = []
    let fence = ""
    let i = 0
    while i < lines.len() do
        let line = lines[i]
        let t = line.trim()
        if fence != "" then
            if t.starts_with(fence) then
                fence = ""
            end
            kept.push(line)
            i = i + 1
        elseif fence_of(line) != "" then
            fence = fence_of(line)
            kept.push(line)
            i = i + 1
        elseif indent_of(line) < 4 and t.starts_with("[") and t.contains("]:") then
            let close = t.index_of("]:").unwrap()
            let label = t.substring(1, close)
            let rest = t.substring(close + 2, t.len()).trim()
            if label.starts_with("^") then
                let body = [rest]
                i = i + 1
                while i < lines.len() and (indent_of(lines[i]) >= 2 or (is_blank(lines[i]) and i + 1 < lines.len() and indent_of(lines[i + 1]) >= 2)) do
                    body.push(drop_indent(lines[i], 4))
                    i = i + 1
                end
                ctx.notes[normalize_label(label.substring(1, label.len()))] = body
            elseif rest != "" and not label.contains("[") then
                let dest = parse_dest((rest + ")").chars(), 0)
                if dest != none then
                    ctx.refs[normalize_label(label)] = LinkRef { url: dest.url, title: dest.title }
                    i = i + 1
                else
                    kept.push(line)
                    i = i + 1
                end
            else
                kept.push(line)
                i = i + 1
            end
        else
            kept.push(line)
            i = i + 1
        end
    end
    kept
end

fun render_footnotes(ctx: Context) -> string
    if ctx.order.len() == 0 then
        return ""
    end
    let out = "<section class=\"footnotes\">\n<hr>\n<ol>\n"
    for id in ctx.order do
        let slug = slugify(id)
        let body = render_blocks(ctx.notes[id].unwrap(), ctx).trim()
        let back = " <a href=\"#fnref-{slug}\">↩</a>"
        if body.ends_with("</p>") then
            body = body.substring(0, body.len() - 4) + back + "</p>"
        else
            body = body + back
        end
        out = out + "<li id=\"fn-{slug}\">" + body + "</li>\n"
    end
    out + "</ol>\n</section>\n"
end

--" Renders a text, and gives back its headings and its title along with the HTML. --"
fun convert(source: string, options: Options) -> Document
    let ctx = Context { options: options, headings: [], used: {}, refs: {}, notes: {}, order: [] }
    let lines = extract_definitions(source.replace("\r\n", "\n").replace("\t", "    ").split("\n"), ctx)
    let html = render_blocks(lines, ctx) + render_footnotes(ctx)
    let title = ""
    for h in ctx.headings do
        if h.level == 1 and title == "" then
            title = h.text
        end
    end
    Document { html: html, title: title, headings: ctx.headings }
end

--" The HTML of a Markdown text, with the default options. --"
fun render(source: string) -> string
    convert(source, Options.plain()).html
end

export Options, Heading, Document, convert, render, escape, slugify
