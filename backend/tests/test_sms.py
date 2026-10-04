from app.sms import sanitize


def test_short_clean_text_passes_through():
    text = "Plant maize in September for season A."
    assert sanitize(text) == text


def test_emojis_and_non_ascii_are_removed():
    assert sanitize("Muraho! 🌽 Plant now 👨‍🌾") == "Muraho! Plant now"


def test_whitespace_is_collapsed():
    assert sanitize("  use\n\nurea   at\ttopdressing  ") == "use urea at topdressing"


def test_long_text_is_cut_at_a_full_sentence():
    out = sanitize(("Scout your field weekly. " * 20) + "Then call RAB.")
    assert len(out) <= 300
    assert out.endswith("weekly.")


def test_long_text_without_sentence_end_is_cut_at_a_word():
    out = sanitize("beans " * 100)
    assert len(out) <= 300
    assert out.endswith("beans")


def test_empty_input_is_safe():
    assert sanitize("") == ""


def test_reply_of_only_non_ascii_becomes_empty():
    # the caller must treat this as "no reply" and send the fallback instead
    assert sanitize("\U0001F33D\U0001F33E") == ""
