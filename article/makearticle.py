"""Script to create an article html file out of a md file and template, with nice code blocks."""

import datetime
import sys
import markdown2


def _make_link_to_repo(fname: str, display: str = None) -> str:
    if display is None:
        display = fname
    # NOTE: unsafe, doesn't escape HTML special chars, but okay for our purpose
    base_article_url = "https://github.com/FRex/frex.github.io/blob/main/article"
    return f"""<a href="{base_article_url}/{fname}">{display}</a>"""


def _make_article(fname: str, title: str, desc: str) -> None:
    if not fname.endswith(".md"):
        print(f"{fname} does not end in .md")
        return
    with open("article-template.html", encoding="UTF-8") as templatefile:
        template = templatefile.read()
    art = markdown2.markdown_path(fname, extras=["fenced-code-blocks"])
    art = art.replace('"codehilite"', '"highlight"')
    html = template
    html = template.replace("$TITLE", title)
    html = html.replace("$DESCRIPTION", desc)
    x = _make_link_to_repo("makearticle.py")
    outname = fname.replace(".md", ".html")
    y = _make_link_to_repo(outname, "Generated")
    timestamp = datetime.datetime.now().strftime(r"%Y-%m-%d %H:%M")
    madeby = f"""\n{y} from {_make_link_to_repo(fname)} using {x} on {timestamp}."""
    html = html.replace("$MADEBY", madeby)
    html = html.replace("$BODY", art)
    print(f"Writing to {outname}")
    with open(outname, "w", encoding="UTF-8", newline="\n") as f:
        f.write(html)


if __name__ == "__main__":
    _make_article(sys.argv[1], sys.argv[2], sys.argv[3])
