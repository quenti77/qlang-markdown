import describe, it, expect, finish from "@test"
import render, convert, Options, escape from "./markdown.q"

fun has(html: string, part: string)
    if not html.contains(part) then
        panic("expected {part} in:\n{html}")
    end
end

fun test_suite()
    describe("blocks", fun()
        it("renders headings with ids and a title", fun()
            let doc = convert("# Hello, World!\n\n## Second\n\n## Second", Options.plain())
            has(doc.html, "<h1 id=\"hello-world\">Hello, World!</h1>")
            has(doc.html, "<h2 id=\"second\">Second</h2>")
            has(doc.html, "<h2 id=\"second-1\">Second</h2>")
            expect(doc.title).to_be("Hello, World!")
            expect(doc.headings.len()).to_be(3)
        end)

        it("joins lines into paragraphs", fun()
            has(render("one\ntwo\n\nthree"), "<p>one\ntwo</p>")
            has(render("one\ntwo\n\nthree"), "<p>three</p>")
        end)

        it("renders fenced code through the highlight hook", fun()
            let options = Options { highlight: fun(language: string, code: string) -> string "[{language}]" + escape(code) end, heading_ids: true, allow_html: false }
            let html = convert("```qlang\nlet a = 1 < 2\n```", options).html
            has(html, "<pre><code class=\"language-qlang\">[qlang]let a = 1 &lt; 2</code></pre>")
        end)

        it("renders lists, nested and numbered", fun()
            let html = render("- one\n- two\n  - inner\n- three")
            has(html, "<ul>")
            has(html, "<li>one</li>")
            has(html, "<li>two\n<ul>")
            has(html, "<li>inner</li>")
            let ordered = render("3. a\n4. b")
            has(ordered, "<ol start=\"3\">")
        end)

        it("renders task lists", fun()
            has(render("- [x] done\n- [ ] todo"), "<input type=\"checkbox\" checked disabled> done")
        end)

        it("renders quotes, rules and tables", fun()
            has(render("> quoted *text*"), "<blockquote>")
            has(render("> quoted *text*"), "<em>text</em>")
            has(render("a\n\n---\n\nb"), "<hr>")
            let table = render("| a | b |\n|---|--:|\n| 1 | 2 |")
            has(table, "<th>a</th>")
            has(table, "<th style=\"text-align:right\">b</th>")
            has(table, "<td>1</td>")
        end)
    end)

    describe("inline", fun()
        it("renders emphasis, strong, strike and code", fun()
            let html = render("*a* **b** ~~c~~ `d < e`")
            has(html, "<em>a</em>")
            has(html, "<strong>b</strong>")
            has(html, "<del>c</del>")
            has(html, "<code>d &lt; e</code>")
        end)

        it("leaves snake_case and lone stars alone", fun()
            has(render("a snake_case_name and 2 * 3"), "snake_case_name and 2 * 3")
        end)

        it("renders links and images", fun()
            has(render("[the site](https://a.fr/x?y=1)"), "<a href=\"https://a.fr/x?y=1\">the site</a>")
            has(render("![logo](/logo.png)"), "<img src=\"/logo.png\" alt=\"logo\">")
            has(render("<https://a.fr>"), "<a href=\"https://a.fr\">https://a.fr</a>")
        end)

        it("honours backslash escapes", fun()
            has(render("\\*not em\\*"), "*not em*")
        end)
    end)

    describe("safety", fun()
        it("escapes raw HTML", fun()
            let html = render("<script>alert(1)</script>")
            expect(html.contains("<script>")).to_be(false)
            has(html, "&lt;script&gt;")
        end)

        it("does not link javascript: addresses", fun()
            let html = render("[click](javascript:alert(1))")
            expect(html.contains("href")).to_be(false)
            has(html, "click")
        end)
    end)

    describe("GitHub flavour", fun()
        it("reads setext headings and indented code", fun()
            has(render("Title\n=====\n\nSub\n---\n"), "<h1 id=\"title\">Title</h1>")
            has(render("Title\n=====\n\nSub\n---\n"), "<h2 id=\"sub\">Sub</h2>")
            has(render("text\n\n    let a = 1 < 2\n    b\n"), "<pre><code>let a = 1 &lt; 2\nb</code></pre>")
        end)

        it("writes heading ids the GitHub way", fun()
            has(render("## Hello, World! (v2)"), "id=\"hello-world-v2\"")
            has(render("## a - b"), "id=\"a---b\"")
            has(render("## Café `code`"), "id=\"café-code\"")
        end)

        it("reads reference links, titles and footnotes", fun()
            let html = render("See [the site][s] and [s] and ![pic][p].\n\n[s]: https://a.fr \"Site\"\n[p]: /p.png\n")
            has(html, "<a href=\"https://a.fr\" title=\"Site\">the site</a>")
            has(html, "<a href=\"https://a.fr\" title=\"Site\">s</a>")
            has(html, "<img src=\"/p.png\" alt=\"pic\">")
            has(render("[x](/u \"T\")"), "<a href=\"/u\" title=\"T\">x</a>")
            let note = render("A claim[^1].\n\n[^1]: The proof.\n")
            has(note, "<sup class=\"footnote-ref\"><a href=\"#fn-1\" id=\"fnref-1\">1</a></sup>")
            has(note, "<li id=\"fn-1\"><p>The proof. <a href=\"#fnref-1\">↩</a></p></li>")
        end)

        it("links bare addresses and keeps entities", fun()
            has(render("go to https://a.fr/x. then"), "<a href=\"https://a.fr/x\">https://a.fr/x</a>. then")
            has(render("www.a.fr"), "<a href=\"http://www.a.fr\">www.a.fr</a>")
            has(render("a &amp; b &copy; c & d"), "a &amp; b &copy; c &amp; d")
            has(render("<me@a.fr>"), "<a href=\"mailto:me@a.fr\">me@a.fr</a>")
        end)

        it("reads ***both***, single ~strike~ and hard breaks", fun()
            has(render("***both***"), "<em><strong>both</strong></em>")
            has(render("~one~"), "<del>one</del>")
            has(render("a\\\nb"), "a<br>\nb")
            has(render("a  \nb"), "a<br>\nb")
        end)

        it("renders alerts", fun()
            let html = render("> [!WARNING]\n> Careful *now*")
            has(html, "<div class=\"markdown-alert markdown-alert-warning\">")
            has(html, "<p class=\"markdown-alert-title\">Warning</p>")
            has(html, "<em>now</em>")
        end)

        it("drops comments and escapes tables pipes", fun()
            let html = render("a\n\n<!-- hidden -->\n\nb <!-- inline --> c")
            expect(html.contains("hidden")).to_be(false)
            expect(html.contains("inline")).to_be(false)
            has(render("| a |\n|---|\n| x \\| y |"), "<td>x | y</td>")
        end)

        it("passes safe HTML only when allowed", fun()
            let options = Options.plain()
            options.allow_html = true
            has(convert("<details>\n<summary>More</summary>\n\ntext\n\n</details>", options).html, "<details>")
            has(convert("a <kbd>Ctrl</kbd>", options).html, "<kbd>Ctrl</kbd>")
            let bad = convert("<div onclick=\"x()\">a</div>\n\nb <script>x</script> <a href=\"javascript:x\">y</a>", options).html
            expect(bad.contains("<div onclick")).to_be(false)
            expect(bad.contains("<script>")).to_be(false)
            expect(bad.contains("<a href=\"javascript")).to_be(false)
            expect(render("<div>a</div>").contains("<div>")).to_be(false)
        end)
    end)

    finish()
end
