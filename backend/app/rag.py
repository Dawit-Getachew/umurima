import re
from pathlib import Path

from rank_bm25 import BM25Okapi

from app.nlp import terms, words

KNOWLEDGE_DIR = Path(__file__).resolve().parent.parent / "knowledge"


def _load_chunks() -> list[tuple[str, str]]:
    chunks = []
    for path in sorted(KNOWLEDGE_DIR.glob("*.md")):
        for paragraph in path.read_text(encoding="utf-8").split("\n\n"):
            para = " ".join(paragraph.split())
            if len(para) > 60:  # skips headings and the draft disclaimer line
                chunks.append((path.stem, para))
    return chunks


SOURCED = _load_chunks()
CHUNKS = [text for _, text in SOURCED]
_INDEX = BM25Okapi([terms(c) for c in CHUNKS]) if CHUNKS else None


# "When" questions are answered by the season calendar, which says "Season A", not "when".
TIMING = {"when", "ryari", "month", "date"}


def _query(question: str) -> list[str]:
    query = terms(question)
    if TIMING & set(words(question)):
        query.append("season")
    return query


def _ranked(question: str, k: int) -> list[int]:
    if _INDEX is None:
        return []
    scores = _INDEX.get_scores(_query(question))
    best = sorted(range(len(CHUNKS)), key=lambda i: scores[i], reverse=True)[:k]
    return [i for i in best if scores[i] > 0]


def search(question: str, k: int = 4) -> list[str]:
    return [CHUNKS[i] for i in _ranked(question, k)]


def sources(question: str, k: int = 2) -> list[str]:
    """Names of the notes behind an answer, shown to the operator to build trust."""
    return list(dict.fromkeys(SOURCED[i][0] for i in _ranked(question, k)))


def extract(question: str, chunks: list[str], max_len: int = 230) -> str | None:
    """Best matching sentence from the notes, used when the model is unreachable.

    Returns None unless the sentence covers most of the question's content terms,
    so a merely related sentence is never sent as advice."""
    wanted = set(_query(question)) - {"season"}
    best, best_score = None, max(1, min(3, len(wanted)) - 1)
    for chunk in chunks[:2]:
        for sentence in re.split(r"(?<=[.!?])\s+", chunk):
            score = len(wanted & set(terms(sentence)))
            if score > best_score and len(sentence) <= max_len:
                best, best_score = sentence.strip(), score
    return best
