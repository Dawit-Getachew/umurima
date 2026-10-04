# Umurima AI — backend

SMS farming advisor for Rwandan smallholder farmers on basic button phones. The
[SMS gateway](https://github.com/Dawit-Getachew/umurima/tree/main/sms-gateway) forwards
each farmer SMS here, and the API returns one plain-text reply of at most 300
characters (2 SMS), in English or Kinyarwanda.

Part of [umurima](https://github.com/Dawit-Getachew/umurima). This directory is
mirrored to [ai-sms-backend](https://github.com/Dawit-Getachew/ai-sms-backend), which
Coolify deploys. Design notes:
[architecture](https://github.com/Dawit-Getachew/umurima/blob/main/docs/architecture.md),
[responsible AI](https://github.com/Dawit-Getachew/umurima/blob/main/docs/responsible-ai.md),
[data](https://github.com/Dawit-Getachew/umurima/blob/main/docs/data.md).

## How a question is answered

Cheapest and safest layer first. Only step 4 needs the internet.

| Step | What it does | Model call |
|---|---|---|
| 1. Triage | Rules catch emergencies: a dying or sick animal, a person poisoned by pesticide, plants dying or a problem spreading. Animals and people get a **fixed** escalation reply (vet, health centre, 912). | none |
| 2. Verified answers | 27 reviewed answers to the most common questions (planting dates, spacing, urea on beans, fall armyworm, coffee yield and price...). The same answer every time, so it can be audited in advance. | none |
| 3. Answer cache | Earlier model answers keyed by the question's intent terms ("When should I plant maize?" = "when to plant maize"), with fuzzy matching. Stored in Postgres and versioned by a hash of the notes, prompt and model, so editing a note retires stale answers. | none |
| 4. Model | BM25 retrieval over `knowledge/*.md` (Kinyarwanda crop and animal words are mapped to English so they retrieve English notes), plus the farmer's last 6 messages, then OpenRouter (`gemini-3.1-flash-lite`). | 1 |
| 5. Offline fallback | If the model is down: a looser cache match, then the best-matching sentence from the notes (English), then "try again". | none |

Every reply ends with a contact the code appends: the Farmer Promoter or sector
agronomist, the sector vet for animal questions, or "report it today" for a
spreading crop problem. The model gives one concrete recommendation, and the
code strips any "ask your Farmer Promoter" sentence it adds, so a simple question
is answered rather than deflected.

## Guardrails (responsible AI)

- **Human in the loop.** The tool advises; the farmer decides. Every answer names a person to ask, and life-at-risk cases always go to a person (rules, not the model, decide this).
- **No hallucinated numbers.** The prompt forbids invented doses, brand names, prices, dates and phone numbers; dose questions are pointed to the product label. When the notes do not cover a question, the model says "I am not sure" and the footer says who to ask.
- **Fixed list of answers where it matters.** Emergency replies and the 27 verified answers are reviewable text in `app/replies.py` and `app/faq.py`.
- **Privacy.** Only the phone number and message text are stored (`messages` table) to give the model the last 6 turns. No names, no location, nothing sold or shared. Delete one farmer's history with `DELETE FROM messages WHERE phone = '...'`.
- **Language.** Replies match the farmer: English or Kinyarwanda. Kinyarwanda is low-resource; model quality is lower there, so verified answers are English-only for now and fixed Kinyarwanda replies cover emergencies.

## Data

| Data | Use | What it does not cover |
|---|---|---|
| `knowledge/*.md`: 8 notes, 68 paragraphs, written from RAB, MINAGRI and NAEB public guidance (seasons, crops, coffee, fertilizer, pests, livestock, extension, regional) | What the tool answers from | Drafts, not yet reviewed by RAB. No plot-level soil data, no live prices, no rates per hectare, no weather. |
| NISR Census 2022 (RPHC5 Agriculture): 78% of agricultural households have a mobile phone, 9% a smartphone, 16% internet; 32% of household heads cannot read | Why SMS on a button phone | — |
| NISR EICV7 2023/24: 62% of workers are in agriculture | Scale of the problem | — |
| RAB, Oct 2025: 14,000+ Twigire Muhinzi Farmer Promoters | The humans the tool escalates to | — |
| NAEB: about 400,000 smallholder coffee families | Coffee note | — |

Ideas taken from the [World Bank AI Repository](https://airepository.worldbank.org/)
and related Bank work: hybrid AI and human extension (Digital Green Farmer.Chat, Kisan
e-Mitra: hybrid models cut advisory cost to under $1 per farmer per year), local
language first, offline first (Wadhwani AI CottonAce, PlantVillage Nuru), and
showing sources to build trust (MahaVISTAAR-AI): `/sms` returns the note names
behind each answer, and the relay dashboard shows them.

## Run

    python -m venv .venv && . .venv/bin/activate
    pip install -r requirements.txt
    cp .env.example .env          # add your OpenRouter key; DATABASE_URL is optional
    pytest
    uvicorn app.main:app --reload

    docker build -t umurima-backend . && docker run --env-file .env -p 8000:8000 umurima-backend

Without `DATABASE_URL` the service uses SQLite at `data/umurima.db`. Without
`OPENROUTER_API_KEY` it still answers from triage, verified answers, the cache and
the notes.

## API

    POST /sms   {"phone_number": "+2507...", "message": "..."}
             -> {"phone_number": "+2507...", "message": "...",
                 "source": "faq|cache|ai|triage|offline|greeting|clarify|busy",
                 "language": "en|rw", "sources": ["crops", ...]}
    GET  /health -> status, database, model, knowledge and cache sizes, answers by source

`/sms` always returns 200: whatever fails, the farmer still gets a reply and a
person to ask. A repeat of the same SMS within 2 minutes (a relay retry) gets
the same answer without a second model call.

## Env vars

    OPENROUTER_API_KEY=                                     # needed for step 4
    OPENROUTER_MODEL=google/gemini-3.1-flash-lite
    OPENROUTER_FALLBACK_MODEL=                              # optional second model
    DATABASE_URL=postgresql://user:pass@host:5432/dbname    # optional, SQLite otherwise

## Notes

`knowledge/*.md` is draft content: verify it against RAB, MINAGRI and NAEB before
any real use. One blank-line paragraph = one retrieval chunk, so keep each one
self-contained.

Not built yet: auth on `/sms`, rate limiting, a telco short code, Kinyarwanda
verified answers reviewed by a native agronomist, live market prices.
