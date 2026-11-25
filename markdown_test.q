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
            has(doc.html, "<h2 id=\"second-2\">Second</h2>")
            expect(doc.title).to_be("Hello, World!")
            expect(doc.headings.len()).to_be(3)
        end)

        it("joins lines into paragraphs", fun()
            has(render("one\ntwo\n\nthree"), "<p>one\ntwo</p>")
            has(render("one\ntwo\n\nthree"), "<p>three</p>")
        end)

        it("renders fenced code through the highlight hook", fun()
            let options = Options { highlight: fun(language: string, code: string) -> string "[{language}]" + escape(code) end, heading_ids: true }
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

    finish()
end
