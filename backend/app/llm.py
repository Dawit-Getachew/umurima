import logging
import os
import re

import httpx

log = logging.getLogger("umurima")

API_URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "google/gemini-3.1-flash-lite"

SYSTEM_PROMPT = """You are Umurima AI, an SMS farming advisor for Rwandan smallholder farmers who use basic button phones.

Write 1 or 2 short sentences, under 220 characters. Plain text only: no emojis, no lists, no formatting, no links.

Answer the question. Give ONE clear, practical recommendation the farmer can act on today: the specific practice, timing, spacing or sign to look for, taken from the knowledge notes. Do not end with "contact your Farmer Promoter", "ask RAB" or any other referral: the system adds the right contact after your answer.

Use only the knowledge notes and well established basic farming practice. Never invent pesticide or fertilizer doses, chemical brand names, prices, dates or phone numbers. For a dose or rate question, still give the practical step (where and when to apply it) and tell the farmer to use the rate printed on the bag or label. If the notes do not cover the question and you are not sure, say "I am not sure about this" instead of guessing, then give one safe general step from the notes only if one clearly applies. Never give human medical advice. If the question is not about farming, animals, soil or selling farm produce, say in one short sentence that you can only help with farming questions.

Match the farmer's language exactly. Answer an English question in English, even when it names a crop, an input or a place in Kinyarwanda. Answer a Kinyarwanda question in Kinyarwanda, using the real local terms rather than literal translations: umuhinzi mwitozwa for Farmer Promoter, and ibigori, ibishyimbo, imyumbati, ibirayi, ifumbire, ibimenyetso, indwara. The knowledge notes are always written in English; that is never a reason to answer in English.

Before you answer, check you are writing in the same language as the question."""

URGENT_NOTE = (
    "\n\nThis farmer reports plants dying or a problem spreading. Name the most likely "
    "cause from the notes and give one safe step to take today. The system will tell "
    "them to report it."
)

FIRST_AID_NOTE = (
    "\n\nThis farmer reports a sick, poisoned or dying animal. A second SMS from the "
    "system tells them to call the veterinary officer today, so do not say that. Name "
    "the most likely cause from the notes as a possibility, and give ONE safe step to "
    "take while they wait, such as isolating the animal, shade, clean water, a dry clean "
    "shed or checking for ticks. Never name a drug, injection, dose, vaccine or home remedy."
)

# The vet decides treatment. Any first-aid text that names one, or gives a number, is
# replaced by the fixed step in replies.LIVESTOCK_FIRST_AID.
_UNSAFE_FIRST_AID = re.compile(
    r"\d|\b(antibiotic\w*|oxytetracycline|tetracycline|penicillin|ivermectin|albendazole|"
    r"inject\w*|syringe|dos(e|es|age)|tablet\w*|paracetamol|aspirin|drugs?|medicin\w*|"
    r"vaccin\w*|deworm\w*|acaricide\w*|pesticide\w*|spray\w*|herb\w*|"
    r"umuti|imiti|urushinge|inshinge|ikinini|ibinini|urukingo)\b", re.I)

LANGUAGE_NAMES = {"en": "English", "rw": "Kinyarwanda"}

# Referral sentences the model adds despite the prompt; the footer already covers them.
_REFERRAL = re.compile(
    r"(farmer promoter|agronomist|umuhinzi mwitozwa|agronome|\brab\b|veterinar|veterineri|"
    r"extension (officer|worker)|agro ?dealer)", re.I)
_REFERRAL_VERB = re.compile(r"\b(contact|ask|call|visit|see|consult|talk|reach|baza|hamagara|gana|egera)\b", re.I)

_client = httpx.Client(timeout=httpx.Timeout(20.0, connect=5.0))


def model() -> str:
    return os.getenv("OPENROUTER_MODEL", DEFAULT_MODEL)


def configured() -> bool:
    return bool(os.getenv("OPENROUTER_API_KEY"))


def drop_referrals(text: str) -> str:
    """Remove bare "ask your Farmer Promoter" sentences, which the footer repeats.

    Only short sentences go: "ask your cooperative which approved fungicide to use"
    is advice, not a referral, and it stays."""
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    kept = [s for s in sentences
            if not (_REFERRAL.search(s) and _REFERRAL_VERB.search(s) and len(s.split()) <= 10)]
    joined = " ".join(kept)
    return joined if len(joined) >= 30 else text.strip()


def safe_first_aid(text: str) -> bool:
    return not _UNSAFE_FIRST_AID.search(text)


def reply(question: str, history: list[dict], chunks: list[str], language: str,
          urgent: bool = False, first_aid: bool = False) -> str | None:
    """The model's answer, or None when no model could answer."""
    key = os.getenv("OPENROUTER_API_KEY")
    if not key:
        return None
    notes = "\n\n".join(chunks) or "No notes available for this question."
    note = FIRST_AID_NOTE if first_aid else URGENT_NOTE if urgent else ""
    messages = [{"role": "system", "content": SYSTEM_PROMPT + note}]
    messages += history
    messages.append({
        "role": "user",
        "content": f"Knowledge notes:\n{notes}\n\nFarmer question: {question}"
                   f"\n\nWrite your reply in {LANGUAGE_NAMES[language]}.",
    })
    models = [model()] + [m for m in [os.getenv("OPENROUTER_FALLBACK_MODEL", "")] if m]
    for name in models:
        try:
            response = _client.post(
                API_URL,
                headers={"Authorization": f"Bearer {key}"},
                json={
                    "model": name,
                    "messages": messages,
                    "temperature": 0.2,
                    "max_tokens": 200,  # Kinyarwanda needs more tokens per character
                },
            )
            response.raise_for_status()
            text = (response.json()["choices"][0]["message"]["content"] or "").strip()
            if text:
                return text
        except Exception as error:
            log.warning("Model %s failed: %s", name, error)
    return None
