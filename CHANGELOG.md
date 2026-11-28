# Changelog

## 0.2.0

- Alerts take a title of their own: `> [!TIP] A good title` (inline Markdown works in it; without one the title is still the kind).
- Alerts can be folded: `> [!NOTE]- Title` gives a closed `<details>`, `> [!NOTE]+ Title` an open one; the title is its `<summary>`.
- `[!NOTE]x` (no space) and unknown kinds stay plain quotes.

## 0.1.1

- The package is named `quenti77/markdown`, the `vendor/package` form the registry asks for. No change to the code.

## 0.1.0

- First version, close to GitHub Markdown: headings (ATX and setext) with GitHub ids, paragraphs, emphasis, strike, code
  (fenced with a highlight hook, indented), inline / reference / bare links, images, nested and task lists, quotes,
  alerts, tables, footnotes, entities, hard breaks, rules. Raw HTML is escaped unless `allow_html` is set.
