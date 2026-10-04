"""Answer cache: a question asked before is answered instantly and without a model
call, and still gets an answer while the model is down.

Keys are the question's intent terms, so "When should I plant maize?" and "when to
plant maize" share an entry. Near misses match on term overlap. Entries carry a
version hash of the knowledge notes, prompt and model, so editing any of them
retires every cached answer built on the old version."""
import hashlib
import logging
import threading

from app import llm, memory, rag
from app.nlp import intent_terms, words

log = logging.getLogger("umurima")

MAX_ENTRIES = 5000
MATCH = 0.8  # term overlap needed to reuse an answer normally
LOOSE_MATCH = 0.6  # accepted only when the model is down and nothing better exists

# A question opening like this leans on the previous turn ("and for beans?"), so
# its answer is only right inside that conversation.
FOLLOW_UP = {"and", "also", "what about", "how about", "it", "that", "this", "them",
             "those", "same", "then", "ok", "yes", "no", "ndetse", "none", "se"}
PRONOUNS = {"it", "they", "them", "that", "this", "those", "these", "there"}

_entries: dict[str, tuple[str, frozenset, str]] = {}
_lock = threading.Lock()
VERSION = ""


def _version() -> str:
    digest = hashlib.sha1()
    for chunk in rag.CHUNKS:
        digest.update(chunk.encode())
    digest.update(llm.SYSTEM_PROMPT.encode())
    digest.update(llm.model().encode())
    return digest.hexdigest()[:12]


def _key(lang: str, terms: frozenset) -> str:
    return lang + ":" + " ".join(sorted(terms))


def cacheable(question: str) -> bool:
    ws = words(question)
    if not ws or ws[0] in FOLLOW_UP or " ".join(ws[:2]) in FOLLOW_UP:
        return False
    if PRONOUNS & set(ws):
        return False
    content = intent_terms(question) - {"how", "what", "when", "why", "which", "much",
                                        "many", "ryari", "gute", "nigute", "kuki", "iki"}
    return len(content) >= 2


def load() -> None:
    global VERSION
    VERSION = _version()
    try:
        rows = memory.cache_load(VERSION)
    except Exception as error:
        log.warning("Answer cache not loaded: %s", error)
        return
    with _lock:
        for key, lang, terms, _question, answer in rows[-MAX_ENTRIES:]:
            _entries[key] = (lang, frozenset(terms.split()), answer)
    log.info("Answer cache loaded: %d entries (version %s)", len(_entries), VERSION)


def get(question: str, lang: str, threshold: float = MATCH) -> str | None:
    if not cacheable(question):
        return None
    terms = frozenset(intent_terms(question))
    with _lock:
        exact = _entries.get(_key(lang, terms))
        if exact:
            return exact[2]
        best, best_score = None, threshold
        for entry_lang, entry_terms, answer in _entries.values():
            if entry_lang != lang:
                continue
            score = len(terms & entry_terms) / len(terms | entry_terms)
            if score >= best_score:
                best, best_score = answer, score
        return best


def put(question: str, lang: str, answer: str) -> None:
    if not cacheable(question):
        return
    terms = frozenset(intent_terms(question))
    key = _key(lang, terms)
    with _lock:
        if len(_entries) >= MAX_ENTRIES:
            _entries.pop(next(iter(_entries)))  # oldest first: dicts keep insertion order
        _entries[key] = (lang, terms, answer)
    try:
        memory.cache_save(key, lang, " ".join(sorted(terms)), question, answer, VERSION)
    except Exception as error:
        log.warning("Answer cache not persisted: %s", error)


def size() -> int:
    return len(_entries)
