# qlang-markdown

Markdown to HTML, written in qlang.

```
import "@markdown/markdown.q" as markdown

let html = markdown.render("# Hello\n\nSome *text* with `code`.")
```

Add it to a project: `markdown = { git = "https://github.com/quenti77/qlang-markdown", version = "^0.1" }`.

## What it reads

Headings (`#` to `######`), paragraphs, `*emphasis*`, `**strong**`, `~~strike~~`, `` `code` ``, fenced code blocks,
links, images, bullet / numbered / task lists (nested), quotes, tables (with alignment) and horizontal rules.

## Safe by default

Raw HTML is **escaped**, never passed through, and a link to `javascript:` (or any scheme other than `http`,
`https`, `mailto`) is written as plain text. A text written by a user can be shown as is.

## API

| Function | What it gives |
| --- | --- |
| `render(source)` | the HTML |
| `convert(source, options)` | a `Document`: `html`, `title` (the first `#` heading) and `headings` (`level`, `id`, `text`, for a table of contents) |
| `Options.plain()` | the default options, to change a field of |
| `slugify(text)` | `Hello, World!` → `hello-world` |
| `escape(text)` | the text with `& < > "` escaped |

`Options.highlight(language, code)` gives the HTML of a fenced code block: plug a syntax highlighter there.
`Options.heading_ids` puts an `id` on each heading (repeated titles get `-2`, `-3`…).

## Not supported (yet)

Raw HTML blocks, reference-style links (`[a][b]`), setext headings (`===`), indented code blocks, footnotes.
