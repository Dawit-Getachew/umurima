import os
import tempfile

os.environ.pop("DATABASE_URL", None)
os.environ["SQLITE_PATH"] = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["OPENROUTER_API_KEY"] = "test-key"

import pytest  # noqa: E402

from app import advisor, cache, faq, llm, memory, replies, triage  # noqa: E402
from app.nlp import language  # noqa: E402

memory.init_db()
cache.load()


@pytest.fixture
def model(monkeypatch):
    """Stand-in for the LLM that records every call."""
    calls = []

    def fake(question, history, chunks, lang, urgent=False, first_aid=False):
        calls.append({"question": question, "urgent": urgent, "first_aid": first_aid,
                      "chunks": chunks})
        return fake.answer

    fake.answer = "Mulch the soil and plant short duration varieties."
    monkeypatch.setattr(llm, "reply", fake)
    advisor._recent.clear()
    return fake, calls


def ask(text, phone="+250788000001"):
    return advisor.answer(phone, text)


def test_language_detection():
    assert language("When should I plant maize?") == "en"
    assert language("When should I plant ibigori?") == "en"
    assert language("Ni ryari natera ibigori?") == "rw"
    assert language("Inka yanjye irwaye") == "rw"


def test_dying_cow_gets_a_first_step_then_the_fixed_escalation(model):
    fake, calls = model
    fake.answer = "This may be East Coast fever. Keep her in the shade and check for ticks."
    out = ask("My cow is dying and not eating")
    assert out.source == "triage"
    assert calls[0]["first_aid"] is True
    assert out.parts == [f"(1/2) {fake.answer}", f"(2/2) {replies.LIVESTOCK_URGENT['en']}"]


def test_dying_cow_in_kinyarwanda(model):
    fake, _ = model
    fake.answer = "Shyira inka mu gicucu, uyihe amazi meza."
    out = ask("Inka yanjye irapfa, nkore iki?")
    assert out.parts[1] == f"(2/2) {replies.LIVESTOCK_URGENT['rw']}"


def test_first_aid_naming_a_drug_or_dose_is_replaced(model):
    fake, _ = model
    fake.answer = "Inject 10 ml of oxytetracycline into the neck."
    out = ask("My goat is sick and has diarrhea", phone="+250788000012")
    assert out.parts[0] == f"(1/2) {replies.LIVESTOCK_FIRST_AID['en']}"


def test_first_aid_when_the_model_is_down(model):
    fake, _ = model
    fake.answer = None
    out = ask("My chickens are dying", phone="+250788000013")
    assert out.parts == [f"(1/2) {replies.LIVESTOCK_FIRST_AID['en']}",
                         f"(2/2) {replies.LIVESTOCK_URGENT['en']}"]


def test_prevention_question_is_not_an_emergency():
    assert triage.check("How do I prevent my chickens from getting sick?") is None


def test_pesticide_poisoning_goes_to_health_centre(model):
    out = ask("My child drank pesticide")
    assert out.text == replies.HUMAN_URGENT["en"]


def test_dying_crop_is_answered_then_escalated(model):
    fake, calls = model
    out = ask("My maize plants are dying in the whole field")
    assert calls and calls[0]["urgent"] is True
    assert out.parts == [f"(1/2) {fake.answer}", f"(2/2) {replies.CROP_URGENT['en']}"]


def test_human_poisoning_stays_one_fixed_message(model):
    _, calls = model
    out = ask("I sprayed pesticide and now I feel dizzy", phone="+250788000014")
    assert out.parts == [] and calls == []


def test_simple_question_gets_verified_answer_and_footer(model):
    _, calls = model
    out = ask("When should I plant maize?")
    assert out.source == "faq"
    assert "September" in out.text
    assert out.text.endswith(replies.FOOTER[("crop", "en")])
    assert calls == []


def test_detailed_question_skips_the_canned_answer():
    assert faq.match("When should I plant maize in Bugesera where it is very dry?") is None


def test_kinyarwanda_never_gets_english_faq(model):
    _, calls = model
    model[0].answer = "Tera ibigori hagati muri Nzeri."
    out = ask("Ni ryari natera ibigori?", phone="+250788000002")
    assert out.source == "ai"
    assert len(calls) == 1


def test_model_answer_is_cached_and_reused(model):
    fake, calls = model
    first = ask("How can I grow sweet potato vines faster in season C?")
    assert first.source == "ai"
    advisor._recent.clear()
    second = ask("how to grow sweet potato vines faster in season c", phone="+250788000003")
    assert second.source == "cache"
    assert second.text == first.text
    assert len(calls) == 1


def test_follow_up_questions_are_not_cached():
    assert not cache.cacheable("and for beans?")
    assert not cache.cacheable("how much of it should I use")


def test_referral_sentences_are_stripped_and_footer_added(model):
    fake, _ = model
    fake.answer = ("Use clean planting material for cassava. "
                   "Contact your Farmer Promoter for more advice.")
    out = ask("Where can I find clean cassava cuttings for my cassava farm plot")
    assert "Contact your Farmer Promoter" not in out.text
    assert out.text.count("Farmer Promoter") == 1


def test_model_down_falls_back_to_the_notes(model):
    fake, _ = model
    fake.answer = None
    out = ask("How should I hill up soil around irish potato ridges?", phone="+250788000004")
    assert out.source in {"offline", "cache"}
    assert "potato" in out.text.lower()


def test_model_down_and_nothing_known_says_ask_a_person(model):
    fake, _ = model
    fake.answer = None
    out = ask("Ese ingurube zanjye zikeneye iki kugira ngo zikure vuba", phone="+250788000005")
    assert out.text.endswith(replies.FOOTER[("animal", "rw")])


def test_greeting(model):
    assert ask("Muraho").text == replies.WELCOME["rw"]
    assert ask("hello").text == replies.WELCOME["en"]


def test_retry_of_same_sms_reuses_answer(model):
    _, calls = model
    first = ask("What is the best spacing for climbing beans stakes rows?", phone="+250788000006")
    second = ask("What is the best spacing for climbing beans stakes rows?", phone="+250788000006")
    assert first.text == second.text
    assert len(calls) == 1


def test_every_fixed_reply_fits_one_sms_pair():
    texts = [*replies.WELCOME.values(), *replies.THANKS.values(), *replies.BUSY.values(),
             *replies.LIVESTOCK_URGENT.values(), *replies.HUMAN_URGENT.values(),
             *replies.CROP_URGENT.values(), *replies.ASK_DETAIL.values(),
             *replies.LIVESTOCK_FIRST_AID.values()]
    for text in texts:
        assert len("(2/2) " + text) <= 300, text
        assert text.isascii()


def test_every_verified_answer_fits_with_footer():
    for _, answer in faq.ENTRIES:
        for footer in replies.FOOTER.values():
            assert len(answer) + len(footer) + 2 <= 300, answer


def test_poisoned_animal_goes_to_the_vet():
    assert triage.check("My cow drank pesticide") == "livestock"
    assert triage.check("A snake bit my goat") == "livestock"


def test_unsure_answers_are_not_cached(model):
    fake, calls = model
    fake.answer = "I am not sure about this."
    ask("How do I raise ducks in a valley marsh farm?", phone="+250788000007")
    advisor._recent.clear()
    ask("How do I raise ducks in a valley marsh farm?", phone="+250788000008")
    assert len(calls) == 2


def test_vague_first_message_asks_for_detail(model):
    _, calls = model
    out = ask("What should I do?", phone="+250788000010")
    assert out.text == replies.ASK_DETAIL["en"]
    assert calls == []


def test_vague_follow_up_uses_the_conversation(model):
    _, calls = model
    ask("My maize leaves have small holes in the funnel and frass", phone="+250788000011")
    ask("What should I do?", phone="+250788000011")
    assert len(calls) == 2
    # the follow-up retrieves notes for the earlier question, not for "what should I do"
    assert any("armyworm" in c for c in calls[1]["chunks"])


def test_advice_that_names_a_person_is_kept():
    text = ("Your coffee has leaf rust. Ask your cooperative or the NAEB agronomist "
            "which approved fungicide to use and when.")
    assert llm.drop_referrals(text) == text


def test_disease_question_with_leaf_word_gets_verified_answer():
    assert "leaf rust" in faq.match("My coffee leaves have orange powder underneath")
