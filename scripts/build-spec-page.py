#!/usr/bin/env python3
"""把 workspace/spec/*.md 渲染为单页 HTML（需要 pandoc）。
用法：python3 scripts/build-spec-page.py [输出路径，默认 spec.html]"""
import datetime, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "spec")
TPL = os.path.join(ROOT, "scripts", "spec-page-template.html")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "spec.html")

if not shutil.which("pandoc"):
    sys.exit("需要 pandoc：https://pandoc.org/installing.html")

def render(md: str) -> str:
    html = subprocess.run(["pandoc", "-f", "gfm", "-t", "html"], input=md,
                          capture_output=True, text=True, check=True).stdout
    html = re.sub(r'<pre class="mermaid"><code>(.*?)</code></pre>',
                  r'<div class="figure"><pre class="mermaid">\1</pre></div>', html, flags=re.S)
    html = re.sub(r"<blockquote>\s*<p>(.*?)</p>\s*</blockquote>", r'<div class="callout">\1</div>', html, flags=re.S)
    html = html.replace("<table>", '<div class="scroll"><table>').replace("</table>", "</table></div>")
    html = re.sub(r'<h([2-4]) id="[^"]*">', lambda m: "<h3>" if m.group(1) != "2" else "<h3>", html)
    html = re.sub(r"</h[2-4]>", "</h3>", html)
    html = html.replace("<p>", '<p class="prose">')
    html = html.replace("<ul>", '<div class="prose"><ul>').replace("</ul>", "</ul></div>")
    html = re.sub(r"<ol( start=\"\d+\")?>", '<ol class="steps">', html)
    html = re.sub(r'<pre class="\w+"><code>', "<pre><code>", html)
    # 规则编号加锚点
    html = re.sub(r"<strong>([A-Z]{2,4}-\d{2})</strong>", r'<strong id="\1">\1</strong>', html)
    return html

files = sorted(f for f in os.listdir(SPEC) if re.match(r"\d{2}-.*\.md$", f))
toc, body = [], []
for f in files:
    md = open(os.path.join(SPEC, f), encoding="utf-8").read()
    first, rest = md.split("\n", 1)
    m = re.match(r"#\s+(\d+)\s+(.*)", first)
    num, title = m.group(1), m.group(2)
    sid = f"s{num}"
    toc.append(f'    <li><a href="#{sid}"><span>{num}</span>{title}</a></li>')
    body.append(f'<section id="{sid}">\n  <div class="sec-head"><span class="sec-num">{num}</span><h2>{title}</h2></div>\n'
                f"{render(rest)}</section>\n")

page = open(TPL, encoding="utf-8").read()
page = page.replace("{{TOC}}", "\n".join(toc)).replace("{{BODY}}", "\n".join(body))
page = page.replace("{{DATE}}", datetime.date.today().isoformat())
open(OUT, "w", encoding="utf-8").write(page)
print(f"已生成 {OUT}（{len(files)} 个文件）")
