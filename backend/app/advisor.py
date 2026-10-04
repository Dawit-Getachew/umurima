"""Turns one farmer SMS into one reply, cheapest and safest layer first:

    triage -> verified FAQ -> answer cache -> model -> offline fallback

Only the model step needs the internet, and every step after triage still ends
the reply with a person the farmer can ask."""
import logging
import threading
import time
from collections import Counter
from dataclasses import dataclass, field

from app import cache, faq, llm, memory, rag, replies, triage
from app.nlp import clean, has_any, language, terms
from app.sms import sanitize, with_footer

log = logging.getLogger("umurima")

GREETINGS = {"hi", "hello", "hey", "muraho", "mwaramutse", "mwiriwe", "bite", "amakuru",
             "start", "help", "ubufasha", "menu"}
THANKS = {"thanks", "thank you", "thank", "murakoze", "urakoze", "murakoze cyane"}
UNSURE = {"not sure", "simbizi", "sinzi", "ntabwo nzi"}

# The relay retries an upload whose response was lost; answer it from here instead
# of paying for the same model call twice.
RETRY_WINDOW = 120

STATS: Counter = Counter()


@dataclass
class Answer:
    text: str
    source: str
    language: str
    sources: list[str] = field(default_factory=list)


_recent: dict[tuple[str, str], tuple[float, Answer]] = {}
_recent_lock = threading.Lock()


def _small_talk(question: str, lang: str) -> str | None:
    lowered = " ".join(question.lower().strip(" .!?,").split())
    if lowered in GREETINGS or (len(lowered.split()) <= 3 and has_any(lowered, GREETINGS)
                                and not has_any(lowered, THANKS)):
        return replies.WELCOME[lang]
    if lowered in THANKS or (len(lowered.split()) <= 3 and has_any(lowered, THANKS)):
        return replies.THANKS[lang]
    return None


def _strip_footers(text: str) -> str:
    for footer in replies.FOOTER.values():
        text = text.replace(footer, "")
    return text.strip()


def _history(phone: str) -> list[dict]:
    """Earlier turns for the model, without the footers the code appended."""
    try:
        past = memory.history(phone)
    except Exception as error:
        log.warning("History unavailable: %s", error)
        return []
    return [{"role": m["role"], "content": _strip_footers(m["content"])} for m in past]


def _answer(phone: str, question: str, lang: str) -> Answer:
    canned = _small_talk(question, lang)
    if canned:
        return Answer(canned, "greeting", lang)

    urgency = triage.check(question)
    if urgency == "livestock":
        return Answer(replies.LIVESTOCK_URGENT[lang], "triage", lang)
    if urgency == "human":
        return Answer(replies.HUMAN_URGENT[lang], "triage", lang)

    past = None
    if not terms(question):
        # "what should I do?" can only be answered from earlier turns
        past = _history(phone)
        if not past:
            return Answer(replies.ASK_DETAIL[lang], "clarify", lang)

    urgent = urgency == "crop"
    footer = replies.FOOTER[("urgent" if urgent else triage.topic(question), lang)]
    sources = rag.sources(question)

    if not urgent:
        if lang == "en":
            verified = faq.match(question)
            if verified:
                return Answer(with_footer(verified, footer), "faq", lang, sources)
        cached = cache.get(question, lang)
        if cached:
            return Answer(cached, "cache", lang, sources)

    if past is None:
        past = _history(phone)

    # a follow-up like "what should I do?" is about the farmer's previous question
    query = question
    if not terms(question):
        previous = next((m["content"] for m in reversed(past) if m["role"] == "user"), "")
        query = f"{previous} {question}"
        sources = rag.sources(query)

    chunks = rag.search(query)
    body = llm.reply(question, past, chunks, lang, urgent=urgent)
    body = sanitize(llm.drop_referrals(body)) if body else ""
    if body:
        text = with_footer(body, footer)
        # an unsure answer is not worth repeating: the next farmer gets a fresh try
        if not urgent and not has_any(body, UNSURE):
            cache.put(question, lang, text)
        return Answer(text, "ai", lang, sources)

    # The model is unreachable: degrade to what works without it.
    if urgent:
        return Answer(replies.CROP_URGENT[lang], "triage", lang)
    cached = cache.get(question, lang, threshold=cache.LOOSE_MATCH)
    if cached:
        return Answer(cached, "cache", lang, sources)
    if lang == "en":
        extract = rag.extract(query, chunks)
        if extract:
            return Answer(with_footer(extract, footer), "offline", lang, sources)
    return Answer(with_footer(replies.BUSY[lang], footer), "busy", lang)


def answer(phone: str, message: str) -> Answer:
    question = clean(message)
    lang = language(question)
    if not question:
        return Answer(replies.WELCOME[lang], "greeting", lang)

    now = time.monotonic()
    with _recent_lock:
        for key in [k for k, (t, _) in _recent.items() if now - t > RETRY_WINDOW]:
            del _recent[key]
        repeat = _recent.get((phone, question))
    if repeat:
        STATS["retry"] += 1
        return repeat[1]

    result = _answer(phone, question, lang)
    STATS[result.source] += 1
    with _recent_lock:
        _recent[(phone, question)] = (now, result)

    try:
        memory.save(phone, "user", question)
        if result.source != "busy":  # keep "try again" replies out of the history
            memory.save(phone, "assistant", result.text)
    except Exception as error:
        log.warning("History not saved: %s", error)
    return result
