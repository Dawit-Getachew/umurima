import re

from app.nlp import to_ascii

MAX_LEN = 300


def sanitize(text: str, max_len: int = MAX_LEN) -> str:
    """Make model output safe for a button phone: ASCII only, one line, <= max_len chars."""
    ascii_only = re.sub(r"[^\x20-\x7E\t\r\n]", "", to_ascii(text or ""))
    clean = re.sub(r"\s+", " ", ascii_only).strip()
    if len(clean) <= max_len:
        return clean

    cut = clean[:max_len]
    end = max(cut.rfind("."), cut.rfind("!"), cut.rfind("?"))
    # only end on a sentence if that still leaves a useful reply
    if end >= max_len // 2:
        return cut[: end + 1]
    space = cut.rfind(" ")
    return cut[:space].rstrip() if space > 0 else cut


def with_footer(body: str, footer: str) -> str:
    """Body trimmed so the footer always fits: the contact line is never the part cut."""
    room = MAX_LEN - len(footer) - 2  # the space, and a full stop we may add
    trimmed = sanitize(body, room)
    if trimmed and trimmed[-1] not in ".!?":
        trimmed += "."
    return f"{trimmed} {footer}" if trimmed else footer
