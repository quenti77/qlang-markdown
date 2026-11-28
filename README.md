# qlang-markdown

Markdown to HTML, written in qlang.

```
import "@markdown/markdown.q" as markdown

let html = markdown.render("# Hello\n\nSome *text* with `code`.")
```

Add it to a project: `markdown = { git = "https://github.com/quenti77/qlang-markdown", version = "^0.1" }`.

## What it reads

It follows GitHub's Markdown (CommonMark plus the GFM extensions): headings (`#` and underlined, with GitHub-style
ids), paragraphs, `*emphasis*`, `**strong**`, `***both***`, `~~strike~~`, `` `code` ``, fenced and indented code, inline
and reference links, bare `https://` / `www.` addresses, `<autolinks>`, images, bullet / numbered / task lists
(nested), quotes, alerts (`> [!NOTE]`), tables (alignment, `\|`), footnotes, entities, hard line breaks, rules.
`<!-- comments -->` are dropped.

## Safe by default

Raw HTML is **escaped**, and a link to `javascript:` (or any scheme other than `http`, `https`, `mailto`) is
written as plain text: a text written by a user can be shown as is. With `Options.allow_html` the HTML of the text goes
through (`<details>`, `<kbd>`, `<img>`…), minus `<script>`, `<iframe>`, `<style>`…, event attributes and
`javascript:` addresses. Even so, only use it for text you trust: this is a filter, not a sanitizer.

## API

| Function | What it gives |
| --- | --- |
| `render(source)` | the HTML |
| `convert(source, options)` | a `Document`: `html`, `title` (the first `#` heading) and `headings` (`level`, `id`, `text`, for a table of contents) |
| `Options.plain()` | the default options, to change a field of |
| `slugify(text)` | `Hello, World!` → `hello-world` |
| `escape(text)` | the text with `& < > "` escaped |

`Options.highlight(language, code)` gives the HTML of a fenced code block: plug a syntax highlighter there.
`Options.heading_ids` puts an `id` on each heading (repeated titles get `-1`, `-2`… as on GitHub).

## Alerts

`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` and `[!CAUTION]` start an alert. The rest of the first line is its title
(`> [!TIP] A good title`, inline Markdown allowed); `+` or `-` right after the kind makes it foldable, open or closed
(`> [!NOTE]- Details`), and the output is a `<details>` whose `<summary class="markdown-alert-title">` is the title.

## Not supported (yet)

Link reference definitions inside lists or quotes, HTML blocks that mix with Markdown, the full CommonMark emphasis
rules for odd nestings, and the GitHub-only extras (emoji `:shortcodes:`, `@mentions`, `#123` references, math).
