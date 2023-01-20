import markdown2
import sys


def make_link(fname: str) -> str:
    # NOTE: unsafe, doesn't escape HTML special chars
    return f"""<a href={fname}>{fname}</a>"""


def make_article(fname: str, title: str, desc: str):
    if not fname.endswith(".md"):
        print(f"{fname} does not end in .md")
        return
    template = open("article-template.html", encoding="UTF-8").read()
    art = markdown2.markdown_path(fname, extras=["fenced-code-blocks"])
    art = art.replace('"codehilite"', '"highlight"')
    html = template
    html = template.replace("$TITLE", title)
    html = html.replace("$DESCRIPTION", desc)
    x = make_link("makearticle.py")
    madeby = f"""\nGenerated from {make_link(fname)} using {x}."""
    html = html.replace("$MADEBY", madeby)
    html = html.replace("$BODY", art)
    outname = fname.replace(".md", ".html")
    print(f"Writing to {outname}")
    with open(outname, "w", encoding="UTF-8") as f:
        f.write(html)


if __name__ == "__main__":
    make_article(sys.argv[1], sys.argv[2], sys.argv[3])
