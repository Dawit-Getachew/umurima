# Responsible AI

A confident wrong answer about a sick cow or a pesticide can cost a farmer a season's
income or a person their health. The design treats that as the main risk. The system
informs; the farmer decides; a named person is always one SMS away.

## Human in the loop

- Umurima only sends advice. It never acts for the farmer, places orders or shares data.
- Every reply ends with a human contact, appended by code rather than generated:
  - a Farmer Promoter or sector agronomist for crop questions;
  - the sector veterinary officer for animal questions;
  - "report it today" when a crop problem is spreading.
- When the notes do not cover a question, the model is instructed to say "I am not
  sure" instead of guessing. The contact line then tells the farmer who to ask.
- Off-topic questions get "I can only help with farming questions."

## Escalation rules

Escalation is decided by rules in `backend/app/triage.py`, never by the model, so the
fail-safe cannot be talked out of firing.

| Case | Example | Response |
|---|---|---|
| Animal dying, poisoned, bitten, or sick with a danger sign | "My cow is not eating and has fever", "Inka yanjye irapfa" | Fixed reply: call the sector vet today; isolate the animal, give water and shade, no old drugs; do not eat or sell meat from an animal that died sick. |
| Person poisoned or bitten | "My child drank pesticide" | Fixed reply: health centre now or call 912; wash skin, remove clothes, bring the label. |
| Crops dying or a problem spreading | "My beans are dying everywhere in the field" | Model names the likely cause and one safe step, then "report it today". If the model is down, a fixed reply. |

Questions about prevention ("how do I prevent ticks?") are deliberately not escalated,
so routine questions still get an answer. Fixed replies exist in English and
Kinyarwanda and are covered by tests (`tests/test_advisor.py`).

## Limiting hallucination

- **Grounding.** The model sees only the retrieved notes, the recent conversation and the question.
- **Prompt rules.** No doses, brand names, prices, dates or phone numbers that are not in the notes. A dose question gets the practical step plus "use the rate printed on the bag".
- **Fixed answers where it matters.** Emergency replies and the 27 verified answers are reviewable text (`replies.py`, `faq.py`). The glossary of the challenge brief says "if it can say anything, it cannot be checked for safety"; these layers can be checked line by line.
- **Short output.** At most 300 characters, ASCII, one or two sentences, so a reviewer can read every reply in the dashboard.
- **Traceability.** Each reply reports how it was produced (`faq`, `cache`, `ai`, `triage`, `offline`) and which notes it came from. The gateway dashboard shows both.

## Privacy

| Question | Answer |
|---|---|
| What is stored | Phone number, message text, reply text and a timestamp. No name, location or other identity data. |
| Where | Backend: Postgres (`messages`, `answer_cache`). Gateway phone: a SQLite queue of received messages and replies. |
| Why | The last six turns give the model context for follow-up questions. |
| Who can read it | Operators with access to the backend database or the gateway phone. Nothing is sold or shared. |
| Sent to a third party | The question, retrieved notes and recent turns are sent to OpenRouter for uncached questions. The phone number is not sent. |
| Deletion | `DELETE FROM messages WHERE phone = '...'` removes one farmer's history. The answer cache holds no phone numbers. |
| Farmer's phone lost or shared | Messages sit in the phone's normal SMS inbox. Nothing extra is stored on the farmer's side. |
| Gateway phone lost | Its queue exposes recent questions and numbers. Mitigations: screen lock, full-disk encryption (Android default), regular queue clean-up. A telco short code would remove the gateway phone entirely. |

## Bias and language

- **Kinyarwanda is low-resource.** Model output in Kinyarwanda is usable but weaker than English. In testing it occasionally used the wrong word (for example, for pruning coffee). Verified answers are therefore English-only until a native-speaking agronomist reviews translations. The safety-critical fixed replies are hand-written in both languages.
- **National guidance is not local.** The notes summarize national RAB, MINAGRI and NAEB guidance. Altitude, rainfall and soil vary between sectors, so the notes cannot give plot-level advice, which is why every reply names a local person.
- **Literacy.** SMS still assumes the farmer can read. A Kinyarwanda voice line (IVR) is the natural next channel for the 32% of household heads who cannot.

## Known gaps before real deployment

- No consent message on first contact and no `STOP` command yet.
- No authentication or rate limiting on `/sms`.
- Knowledge notes and verified answers have not been reviewed by RAB.
- Escalations are not yet reported to a human dashboard for follow-up.
