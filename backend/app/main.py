import logging

from dotenv import load_dotenv

load_dotenv()  # must run before memory and llm read their env vars

from fastapi import FastAPI  # noqa: E402
from pydantic import BaseModel  # noqa: E402

from app import advisor, cache, faq, llm, memory, rag, replies  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("umurima")

app = FastAPI(title="Umurima AI")
memory.init_db()
cache.load()


class SmsIn(BaseModel):
    phone_number: str
    message: str


class SmsOut(BaseModel):
    phone_number: str
    message: str
    # Extra fields for the relay dashboard; the relay sends only `message` by SMS.
    source: str = "ai"
    language: str = "en"
    sources: list[str] = []
    # The SMS to send, in order. Urgent replies are split in two; `message` joins them
    # for gateways that send a single SMS.
    messages: list[str] = []


@app.post("/sms", response_model=SmsOut)
def sms(request: SmsIn) -> SmsOut:
    phone = request.phone_number.strip()
    try:
        result = advisor.answer(phone, request.message)
    except Exception:
        # whatever failed, the farmer still gets a reply and a person to ask
        log.exception("Answer pipeline failed for %s", phone)
        return SmsOut(phone_number=phone, message=replies.BUSY["en"], source="busy",
                      messages=[replies.BUSY["en"]])
    log.info("%s [%s/%s] %r -> %r", phone, result.source, result.language,
             request.message[:80], result.text[:80])
    return SmsOut(phone_number=phone, message=result.text, source=result.source,
                  language=result.language, sources=result.sources,
                  messages=result.parts or [result.text])


@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "database": memory.kind(),
        "model": llm.model() if llm.configured() else None,
        "knowledge_chunks": len(rag.CHUNKS),
        "verified_answers": len(faq.ENTRIES),
        "cached_answers": cache.size(),
        "answers_by_source": dict(advisor.STATS),
    }
