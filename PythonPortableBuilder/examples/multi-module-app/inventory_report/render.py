"""Plain-text rendering."""


def render_table(title, items):
    width = max([len(i["name"]) for i in items] + [4])
    lines = [title, "=" * len(title)]
    for item in items:
        lines.append("%s  %5d" % (item["name"].ljust(width), item["quantity"]))
    lines.append("%d item(s)" % len(items))
    return "\n".join(lines)
