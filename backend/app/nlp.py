"""Tokenizing and language detection shared by retrieval, the FAQ, triage and the cache."""
import re
import unicodedata

# Kinyarwanda farm words mapped to the English terms the knowledge notes use, so a
# Kinyarwanda question still retrieves the right English note.
RW_TO_EN = {
    "ibigori": "maize", "ikigori": "maize",
    "ibishyimbo": "bean", "igishyimbo": "bean",
    "imyumbati": "cassava", "umwumbati": "cassava",
    "ibirayi": "potato", "ikirayi": "potato",
    "umuceri": "rice",
    "urutoke": "banana", "igitoke": "banana", "ibitoki": "banana", "insina": "banana",
    "ikawa": "coffee",
    "icyayi": "tea",
    "amasaka": "sorghum",
    "ingano": "wheat",
    "imboga": "vegetable",
    "inyanya": "tomato",
    "inka": "cattle", "inyana": "cattle",
    "ihene": "goat",
    "intama": "sheep",
    "ingurube": "pig",
    "inkoko": "poultry",
    "urukwavu": "rabbit", "inkwavu": "rabbit",
    "amatungo": "livestock", "itungo": "livestock",
    "amata": "milk",
    "ifumbire": "fertilizer",
    "imborera": "manure",
    "imbuto": "seed",
    "imvura": "rain",
    "igihembwe": "season",
    "udukoko": "pest", "agakoko": "pest",
    "nkongwa": "armyworm",
    "indwara": "disease",
    "ubutaka": "soil",
    "amazi": "water",
    "isoko": "market",
    "igiciro": "price", "ibiciro": "price",
    "umusaruro": "yield",
    "ububiko": "storage",
    "ubwatsi": "fodder",
    "ibyatsi": "weed",
    "amababi": "leaf", "ibibabi": "leaf", "ikibabi": "leaf",
    # common verb forms: to plant, harvest, sell, store
    "gutera": "plant", "natera": "plant", "nateye": "plant", "guhinga": "plant",
    "nahinga": "plant", "gusarura": "harvest", "nasarura": "harvest",
    "kugurisha": "sell", "nagurisha": "sell", "kubika": "storage", "nabika": "storage",
    "umuhondo": "yellow",
    "kirabiranya": "wilt",
}

# English spellings and plurals the crude stemmer cannot fold on its own.
EN_SYNONYMS = {
    "corn": "maize",
    "cow": "cattle", "cows": "cattle", "bull": "cattle", "bulls": "cattle",
    "heifer": "cattle", "heifers": "cattle", "calf": "cattle", "calves": "cattle",
    "chicken": "poultry", "chickens": "poultry", "hen": "poultry", "hens": "poultry",
    "chick": "poultry", "chicks": "poultry", "layers": "poultry", "broilers": "poultry",
    "pigs": "pig", "piglets": "pig",
    "fertiliser": "fertilizer", "fertilisers": "fertilizer",
    "leaves": "leaf",
    "plantain": "banana", "matoke": "banana",
    "irish": "potato",
    "insect": "pest", "insects": "pest",
    "insecticide": "pesticide", "insecticides": "pesticide",
    "sow": "plant", "sowing": "plant", "sown": "plant",
    "sold": "sell",
    "spacing": "space", "spaced": "space",
    "acidic": "acid", "acidity": "acid",
}

# Interrogatives and negations: dropped for retrieval, but kept for the FAQ and the
# cache because "when to plant maize" and "how to plant maize" are different questions.
QUESTION_WORDS = {
    "when", "how", "why", "what", "where", "which", "much", "many", "long", "not",
    "no", "never", "dont", "ryari", "gute", "nigute", "kuki", "iki", "angahe",
}

STOPWORDS = {
    "a", "an", "the", "is", "are", "am", "was", "were", "be", "been", "i", "my",
    "me", "mine", "we", "our", "you", "your", "to", "of", "in", "on", "at", "for",
    "and", "or", "but", "with", "do", "does", "did", "can", "could", "should",
    "would", "will", "shall", "it", "its", "this", "that", "these", "those", "have",
    "has", "had", "there", "please", "hello", "hi", "about", "from", "by", "as",
    "so", "if", "any", "some", "best", "good", "way", "get", "make", "need",
    "want", "know", "tell", "help", "thank", "thanks", "also", "they", "them",
    "their", "he", "she", "his", "her", "who", "use", "using", "now", "today",
    "really", "very", "just", "sir", "madam", "ok", "okay",
    # Kinyarwanda function words
    "ni", "na", "mu", "ku", "kuri", "cyangwa", "ese", "ndashaka", "nshobora",
    "njye", "hari", "kandi", "ariko", "muraho", "mwaramutse", "mwiriwe",
    "murakoze", "ndabaza", "mfite", "yanjye", "byanjye", "wanjye", "zanjye",
    "rwanjye", "bwanjye", "ryanjye", "cyanjye", "ngo", "nka", "nta", "aho",
    "uko", "ubu", "none", "se", "ko", "ese", "neza", "cyane", "nkore", "nakora",
    "bifite", "zifite", "ifite", "afite", "dufite", "nifuza",
}

# Words only Kinyarwanda uses, crop names excluded: an English question may still
# say ibigori, and that must not flip the reply language.
RW_GRAMMAR = {
    "ni", "mu", "ku", "kuri", "cyangwa", "iki", "ryari", "nkore", "ngomba", "ese",
    "gute", "nigute", "kuki", "nte", "muraho", "murakoze", "yanjye", "byanjye",
    "zanjye", "wanjye", "ndashaka", "nshobora", "njye", "hari", "kandi", "ariko",
    "nagira", "nakora", "natera", "nahinga", "mfite", "dufite", "afite", "ifite",
    "zifite", "bifite", "irwaye", "zirwaye", "birwaye", "irarwaye", "ararwaye",
    "irapfa", "zirapfa", "birapfa", "yapfuye", "zapfuye", "byapfuye", "ntirya",
    "ntizirya", "angahe", "mwaramutse", "mwiriwe", "amakuru", "ndabaza", "bite",
    "ubu", "none", "neza", "cyane", "ngo", "nka", "nta", "uyu", "iyi", "izi",
    "ibi", "aba", "uwo", "iyo", "kubera", "ndetse", "nyuma", "mbere", "gusa",
    "kugira", "gukora", "gutera", "guhinga", "gusarura", "kubika", "kugurisha",
    "byumye", "birumye", "biraboze", "zirarwaye", "zirwara", "irwara",
}

EN_GRAMMAR = {
    "the", "is", "are", "my", "what", "when", "how", "should", "can", "do", "does",
    "i", "to", "of", "and", "why", "which", "it", "in", "for", "with", "have",
    "has", "a", "an", "be", "will", "much", "many", "where", "there", "this",
    "that", "not", "dying", "sick", "plant", "please",
}

_RW_PREFIX = re.compile(r"^(umu|aba|imi|ama|iki|ibi|uru|aka|utu|ubu|uku|nda|ara|ntu|nti|ndi|zi|bi)\w{3,}$")

_PUNCT = str.maketrans({
    "‘": "'", "’": "'", "“": '"', "”": '"', "–": "-",
    "—": "-", "…": "...", " ": " ",
})


def to_ascii(text: str) -> str:
    """Fold curly quotes and accents to ASCII, so w'umurenge keeps its apostrophe."""
    folded = unicodedata.normalize("NFKD", (text or "").translate(_PUNCT))
    return folded.encode("ascii", "ignore").decode("ascii")


def clean(text: str, max_len: int = 500) -> str:
    return " ".join(to_ascii(text).split())[:max_len]


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", to_ascii(text).lower())


def _stem(word: str) -> str:
    # crude suffix stripping so "plant" matches "planting" and "bean" matches "beans"
    for suffix in ("ing", "es", "ed", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 4:
            return word[: -len(suffix)]
    return word


def normalize(word: str) -> str:
    word = RW_TO_EN.get(word) or EN_SYNONYMS.get(word) or word
    stem = _stem(word)
    return EN_SYNONYMS.get(stem, stem)


def terms(text: str) -> list[str]:
    """Content terms for retrieval: no stopwords, no question words."""
    return [normalize(w) for w in words(text)
            if len(w) > 1 and w not in STOPWORDS and w not in QUESTION_WORDS]


def intent_terms(text: str) -> set[str]:
    """Content terms plus question words, for matching one question to another."""
    return {normalize(w) for w in words(text) if w not in STOPWORDS or w in QUESTION_WORDS}


def language(text: str) -> str:
    """'rw' for Kinyarwanda, 'en' otherwise."""
    ws = words(text)
    rw = sum(w in RW_GRAMMAR for w in ws) + 0.5 * sum(w in RW_TO_EN for w in ws)
    en = sum(w in EN_GRAMMAR for w in ws)
    if rw == 0 and en == 0:
        # no marker words at all: fall back to the shape of Kinyarwanda noun classes
        rw = sum(bool(_RW_PREFIX.match(w)) for w in ws) >= 2
    return "rw" if rw > en else "en"


def has_any(text: str, phrases) -> bool:
    """True when any word or multi-word phrase occurs in text as whole words."""
    padded = " " + " ".join(words(text)) + " "
    return any(f" {p} " in padded for p in phrases)
