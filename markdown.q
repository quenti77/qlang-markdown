--" # Markdown

Turns Markdown text into HTML.

```
import "@markdown/markdown.q" as markdown

markdown.render("# Hello\n\nSome *text* with `code`.")
```

What it reads: headings (`#`), paragraphs, emphasis (`*a*`, `**a**`, `~~a~~`), `code`, fenced code blocks, links
and images, bullet / numbered / task lists (nested), quotes, tables, and horizontal rules.

What it does not do: raw HTML is **escaped**, never passed through, and links to `javascript:` or other
unknown schemes are written as plain text. A text that comes from a user is therefore safe to show as is.

Fenced code goes through `Options.highlight(language, code)`, which gives the HTML of the code: plug your
own colouring there. By default the code is only escaped.
--"

--" What `convert` can be told. --"
struct Options
    --" Gives the HTML of a code block from its language (may be empty) and its code. --"
    public highlight: fun(string, string) -> string
    --" Put an `id` on each heading (`hello-world`), so that pages can link to it. --"
    public heading_ids: bool
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

--" What the rendering carries along: the options, the headings met so far and the ids already used. --"
struct Context
    public options: Options
    public headings: array<Heading>
    public used: map<string, int>
end

--" Escapes the characters that have a meaning in HTML. --"
fun escape(text: string) -> string
    text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
end

impl Options
    --" The default options: code is escaped, headings get ids. --"
    public fun plain() -> Options
        Options { highlight: fun(language: string, code: string) -> string escape(code) end, heading_ids: true }
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
    line.substring(n, line.chars().len())
end

fun matches_at(chars: array<string>, at: int, text: string) -> bool
    let want = text.chars()
    if at + want.len() > chars.len() then
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

--" Where `text` starts in `chars` at or after `from`, or -1. Backslash escapes are skipped. --"
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

fun is_word_char(c: string) -> bool
    c.is_alpha() or c.is_digit()
end

--" The inline markup of a text: code, emphasis, links, images. --"
fun inline(text: string) -> string
    let chars = text.chars()
    let n = chars.len()
    let out = ""
    let i = 0
    while i < n do
        let c = chars[i]
        if c == "\\" and i + 1 < n then
            out = out + escape(chars[i + 1])
            i = i + 2
        elseif c == "`" then
            let ticks = "`"
            if i + 1 < n and chars[i + 1] == "`" then
                ticks = "``"
            end
            let close = find_text(chars, i + ticks.len(), ticks)
            if close < 0 then
                out = out + ticks
                i = i + ticks.len()
            else
                let code = chars.slice(i + ticks.len(), close).join("").trim()
                out = out + "<code>" + escape(code) + "</code>"
                i = close + ticks.len()
            end
        elseif (c == "!" and i + 1 < n and chars[i + 1] == "[") or c == "[" then
            let image = c == "!"
            let open = if image then i + 1 else i end
            let close = find_bracket(chars, open)
            if close > 0 and close + 1 < n and chars[close + 1] == "(" then
                let stop = find_text(chars, close + 2, ")")
                if stop > 0 then
                    let label = chars.slice(open + 1, close).join("")
                    let target = chars.slice(close + 2, stop).join("").trim()
                    let space = target.index_of(" ")
                    if space != none and space > 0 then
                        target = target.substring(0, space)
                    end
                    if image then
                        out = out + "<img src=\"" + escape(target) + "\" alt=\"" + escape(label) + "\">"
                    elseif safe_url(target) then
                        out = out + "<a href=\"" + escape(target) + "\">" + inline(label) + "</a>"
                    else
                        out = out + inline(label)
                    end
                    i = stop + 1
                else
                    out = out + escape(c)
                    i = i + 1
                end
            else
                out = out + escape(c)
                i = i + 1
            end
        elseif c == "<" and (matches_at(chars, i + 1, "http://") or matches_at(chars, i + 1, "https://")) then
            let close = find_text(chars, i, ">")
            if close < 0 then
                out = out + "&lt;"
                i = i + 1
            else
                let url = chars.slice(i + 1, close).join("")
                out = out + "<a href=\"" + escape(url) + "\">" + escape(url) + "</a>"
                i = close + 1
            end
        elseif c == "*" or c == "_" or c == "~" then
            let run = c
            if i + 1 < n and chars[i + 1] == c then
                run = c + c
            end
            let before_ok = i == 0 or not is_word_char(chars[i - 1]) or c != "_"
            let close = -1
            if before_ok and (c != "~" or run == "~~") and i + run.len() < n and chars[i + run.len()] != " " then
                close = find_text(chars, i + run.len(), run)
            end
            let after = close + run.len()
            let word_end = c == "_" and after < n and is_word_char(chars[after])
            if close > i + run.len() and not word_end then
                let inner = inline(chars.slice(i + run.len(), close).join(""))
                let tag = if c == "~" then "del" elseif run.len() == 2 then "strong" else "em" end
                out = out + "<" + tag + ">" + inner + "</" + tag + ">"
                i = after
            else
                out = out + c
                i = i + 1
            end
        elseif c == " " and i + 2 < n and chars[i + 1] == " " and chars[i + 2] == "\n" then
            out = out + "<br>"
            i = i + 2
        else
            out = out + escape(c)
            i = i + 1
        end
    end
    out
end

--" The text of a heading without its markup, for its id. --"
fun plain_text(text: string) -> string
    let out = ""
    for c in text.chars() do
        if c != "*" and c != "`" and c != "~" and c != "[" and c != "]" then
            out = out + c
        end
    end
    out.trim()
end

--" `Hello, World!` becomes `hello-world`. --"
fun slugify(text: string) -> string
    let out = ""
    let dash = false
    for c in text.lower().chars() do
        if is_word_char(c) then
            out = out + c
            dash = false
        elseif not dash and out != "" then
            out = out + "-"
            dash = true
        end
    end
    out.strip_suffix("-") ?? out
end

fun unique_id(ctx: Context, base: string) -> string
    let slug = if base == "" then "section" else base end
    let seen = ctx.used.get(slug, 0)
    ctx.used[slug] = seen + 1
    if seen == 0 then slug else slug + "-{seen + 1}" end
end

--" How many `#` open the line (1 to 6) when it is a heading, otherwise 0. --"
fun heading_level(line: string) -> int
    let n = 0
    let chars = line.chars()
    while n < chars.len() and chars[n] == "#" do
        n = n + 1
    end
    if n >= 1 and n <= 6 and n < chars.len() and chars[n] == " " then
        return n
    end
    0
end

fun is_rule(line: string) -> bool
    let t = line.trim().replace(" ", "")
    if t.len() < 3 then
        return false
    end
    t == "-".repeat(t.len()) or t == "*".repeat(t.len()) or t == "_".repeat(t.len())
end

fun fence_of(line: string) -> string
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
    let digits = 0
    let chars = rest.chars()
    while digits < chars.len() and chars[digits].is_digit() do
        digits = digits + 1
    end
    if digits > 0 and digits < 10 and digits + 1 < chars.len() and (chars[digits] == "." or chars[digits] == ")") and chars[digits + 1] == " " then
        let number = chars.slice(0, digits).join("").to_int() ?? 1
        return Marker { indent: ind, width: ind + digits + 2, ordered: true, number: number }
    end
    none
end

fun split_cells(line: string) -> array<string>
    let t = line.trim()
    if t.starts_with("|") then
        t = t.substring(1, t.len())
    end
    if t.ends_with("|") then
        t = t.substring(0, t.len() - 1)
    end
    t.split("|").map(fun(cell: string) -> string cell.trim() end)
end

fun is_table_separator(line: string) -> bool
    if not line.contains("-") or not line.contains("|") and not line.contains(":") then
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

fun starts_block(line: string) -> bool
    let t = line.trim()
    heading_level(t) > 0 or fence_of(t) != "" or t.starts_with(">") or is_rule(t) or marker_of(line) != none
end

fun render_table(header: string, separator: string, rows: array<string>, ctx: Context) -> string
    let aligns = split_cells(separator).map(fun(cell: string) -> string
        if cell.starts_with(":") and cell.ends_with(":") then " style=\"text-align:center\""
        elseif cell.ends_with(":") then " style=\"text-align:right\""
        elseif cell.starts_with(":") then " style=\"text-align:left\""
        else "" end
    end)
    let out = "<table>\n<thead><tr>"
    let col = 0
    for cell in split_cells(header) do
        let align = if col < aligns.len() then aligns[col] else "" end
        out = out + "<th" + align + ">" + inline(cell) + "</th>"
        col = col + 1
    end
    out = out + "</tr></thead>\n<tbody>\n"
    for row in rows do
        out = out + "<tr>"
        let k = 0
        for cell in split_cells(row) do
            let align = if k < aligns.len() then aligns[k] else "" end
            out = out + "<td" + align + ">" + inline(cell) + "</td>"
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

--" The list that starts at `start`: the HTML and the index of the first line after it. --"
fun render_list(lines: array<string>, start: int, ctx: Context) -> (string, int)
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
    ("<" + tag + attr + ">\n" + items + "</" + tag + ">\n", i)
end

fun render_heading(level: int, text: string, ctx: Context) -> string
    let plain = plain_text(text)
    let id = unique_id(ctx, slugify(plain))
    ctx.headings.push(Heading { level: level, id: id, text: plain })
    if ctx.options.heading_ids then
        "<h{level} id=\"{id}\">" + inline(text) + "</h{level}>\n"
    else
        "<h{level}>" + inline(text) + "</h{level}>\n"
    end
end

fun render_blocks(lines: array<string>, ctx: Context) -> string
    let out = ""
    let i = 0
    let n = lines.len()
    while i < n do
        let line = lines[i]
        let t = line.trim()
        if t == "" then
            i = i + 1
        elseif fence_of(t) != "" then
            let fence = fence_of(t)
            let language = t.substring(3, t.len()).trim().split(" ")[0]
            let code: array<string> = []
            i = i + 1
            while i < n and not lines[i].trim().starts_with(fence) do
                code.push(lines[i])
                i = i + 1
            end
            i = i + 1
            let body = ctx.options.highlight(language, code.join("\n"))
            let cls = if language == "" then "" else " class=\"language-" + escape(language) + "\"" end
            out = out + "<pre><code" + cls + ">" + body + "</code></pre>\n"
        elseif heading_level(t) > 0 then
            let level = heading_level(t)
            let text = t.substring(level + 1, t.len()).trim()
            while text.ends_with("#") do
                text = text.substring(0, text.len() - 1)
            end
            out = out + render_heading(level, text.trim(), ctx)
            i = i + 1
        elseif is_rule(t) then
            out = out + "<hr>\n"
            i = i + 1
        elseif t.starts_with(">") then
            let quoted: array<string> = []
            while i < n and lines[i].trim().starts_with(">") do
                let q = lines[i].trim().substring(1, lines[i].trim().len())
                quoted.push(if q.starts_with(" ") then q.substring(1, q.len()) else q end)
                i = i + 1
            end
            out = out + "<blockquote>\n" + render_blocks(quoted, ctx) + "</blockquote>\n"
        elseif marker_of(line) != none then
            let listed = render_list(lines, i, ctx)
            out = out + listed.0
            i = listed.1
        elseif line.contains("|") and i + 1 < n and is_table_separator(lines[i + 1]) then
            let rows: array<string> = []
            let j = i + 2
            while j < n and not is_blank(lines[j]) and lines[j].contains("|") do
                rows.push(lines[j])
                j = j + 1
            end
            out = out + render_table(line, lines[i + 1], rows, ctx)
            i = j
        else
            let paragraph = [line]
            i = i + 1
            while i < n and not is_blank(lines[i]) and not starts_block(lines[i]) do
                paragraph.push(lines[i])
                i = i + 1
            end
            out = out + "<p>" + inline(paragraph.join("\n")) + "</p>\n"
        end
    end
    out
end

--" Renders a text, and gives back its headings and its title along with the HTML. --"
fun convert(source: string, options: Options) -> Document
    let ctx = Context { options: options, headings: [], used: {} }
    let html = render_blocks(source.replace("\r\n", "\n").split("\n"), ctx)
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
