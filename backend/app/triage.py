"""Rule-based triage that runs before any model call.

A dying animal or a poisoned person gets a fixed escalation reply; a crop problem
that is killing plants or spreading is answered, but always ends with "report it
today". Rules, not a model, so the fail-safe cannot be talked out of firing."""
from app.nlp import has_any

ANIMALS = {
    "cow", "cows", "cattle", "calf", "calves", "heifer", "bull", "ox", "oxen", "goat",
    "goats", "sheep", "pig", "pigs", "piglet", "piglets", "chicken", "chickens", "hen",
    "hens", "poultry", "bird", "birds", "chick", "chicks", "rabbit", "rabbits",
    "livestock", "animal", "animals", "duck", "ducks",
    "inka", "inyana", "ikimasa", "ihene", "intama", "ingurube", "inkoko", "urukwavu",
    "inkwavu", "amatungo", "itungo",
}

CROPS = {
    "crop", "crops", "plant", "plants", "field", "farm", "garden", "maize", "corn",
    "bean", "beans", "cassava", "potato", "potatoes", "rice", "banana", "bananas",
    "coffee", "tea", "sorghum", "wheat", "tomato", "tomatoes", "cabbage", "vegetables",
    "leaves", "seedlings", "trees",
    "ibigori", "ibishyimbo", "imyumbati", "ibirayi", "umuceri", "urutoke", "insina",
    "ikawa", "icyayi", "imboga", "inyanya", "amashu", "umurima", "imirima",
    "ibihingwa", "ibimera",
}

# Death or a sign that cannot wait for an SMS conversation.
STRONG_DANGER = {
    "dying", "dead", "died", "die", "dies", "death", "collapsed", "collapse",
    "bleeding", "blood", "poisoned", "poison", "not eating", "stopped eating",
    "won t eat", "will not eat", "refuses to eat", "cannot stand", "can t stand",
    "cant stand", "bloated", "bloat", "convulsing", "convulsions", "foaming",
    "aborted", "abortion", "difficult birth", "stuck calf", "sudden death",
    "irapfa", "zirapfa", "birapfa", "arapfa", "iri gupfa", "ziri gupfa", "biri gupfa",
    "yapfuye", "zapfuye", "byapfuye", "ipfuye", "gupfa", "amaraso", "ntirya",
    "ntizirya", "ntiyarya", "yabyimbye", "zabyimbye", "uburozi",
}

# Illness that still needs a vet, unless the farmer is asking how to prevent it.
WEAK_DANGER = {
    "sick", "ill", "illness", "fever", "diarrhea", "diarrhoea", "swollen", "swelling",
    "coughing", "limping", "wound", "injured", "injury", "discharge",
    "irwaye", "zirwaye", "irarwaye", "ararwaye", "zirarwaye", "umuriro", "impiswi",
}

PREVENTION = {
    "prevent", "prevention", "avoid", "protect", "vaccine", "vaccinate", "vaccination",
    "before", "kwirinda", "gukingira", "urukingo", "kurinda",
}

SPREAD = {
    "whole field", "entire field", "all my plants", "all my crops", "all plants",
    "spreading", "spread fast", "many farms", "neighbours", "neighbors", "everywhere",
    "destroyed", "rotting", "wiping", "umurima wose", "birakwirakwira", "biraboze",
    "byaboze",
}

PESTICIDE = {"pesticide", "pesticides", "insecticide", "chemical", "chemicals", "spray",
             "sprayed", "spraying", "poison", "umuti", "imiti", "uburozi"}
PERSON_HARM = {
    "drank", "drink", "swallowed", "swallow", "vomiting", "vomit", "dizzy", "fainted",
    "faint", "breathe", "breathing", "eyes burning", "skin burning", "headache",
    "yanyoye", "yanywe", "aruka", "araruka", "isereri",
}
SNAKE = {"snake", "inzoka"}
BITE = {"bite", "bitten", "bit", "yarumwe", "kurumwa"}


def check(question: str) -> str | None:
    """'livestock' or 'human' (fixed reply), 'crop' (answer, then escalate), or None."""
    animal = has_any(question, ANIMALS)
    strong = has_any(question, STRONG_DANGER)
    preventing = has_any(question, PREVENTION)
    poisoned = has_any(question, PESTICIDE) and has_any(question, PERSON_HARM)
    bitten = has_any(question, SNAKE) and has_any(question, BITE)

    if animal and (strong or poisoned or bitten
                   or (has_any(question, WEAK_DANGER) and not preventing)):
        return "livestock"
    if not animal and (poisoned or bitten):
        return "human"
    if has_any(question, CROPS) and (strong or (has_any(question, SPREAD) and not preventing)):
        return "crop"
    return None


def topic(question: str) -> str:
    return "animal" if has_any(question, ANIMALS) else "crop"
