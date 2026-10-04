"""Verified answers to the questions farmers ask most, written from the knowledge
notes and checked by a person. A match is answered instantly, without a model call,
and is the same every time, so the most common answers can be audited in advance.

Each entry lists groups of words; a question matches when it hits every group."""
from app.nlp import intent_terms, normalize

_ENTRIES = [
    ([["maize"], ["plant"], ["when", "time", "month", "season", "ryari"]],
     "Plant maize in mid September for Season A and in late February or March for "
     "Season B, once rain has fallen steadily for about a week."),
    ([["maize"], ["spacing", "space", "distance", "apart", "row", "far"]],
     "Space maize 75 cm between rows and 25 to 30 cm between plants, with 1 or 2 seeds "
     "per hole. Use certified seed suited to your altitude."),
    ([["bean"], ["plant"], ["when", "time", "month", "season", "ryari"]],
     "Plant beans in mid September for Season A and in late February or March for "
     "Season B, when the rains are steady. Climbing beans suit the cool highlands."),
    ([["urea"], ["bean", "legume", "soybean"]],
     "Do not put urea on beans. Beans make their own nitrogen, so urea is wasted money "
     "and gives leafy plants with few pods. Use DAP or NPK at planting plus manure."),
    ([["urea"], ["maize"]],
     "Top dress maize with urea when it is knee high and again near tasselling. Place "
     "it in a band beside the row on moist soil and cover it with soil."),
    ([["dap"], ["how", "when", "apply", "put", "plant"]],
     "DAP is a planting fertilizer. Put it in the planting hole or furrow and mix it "
     "lightly with soil so the seed does not sit directly on the granules."),
    ([["armyworm"]],
     "Fall armyworm leaves ragged holes and wet sawdust in the maize funnel. Scout twice "
     "a week from emergence and crush small larvae by hand. Keep the field weed free."),
    ([["maize"], ["yellow"]],
     "Yellow lower maize leaves usually mean the crop needs nitrogen. Top dress with "
     "urea on moist soil at knee height and add compost or manure. Also check that the "
     "field is not waterlogged."),
    ([["banana"], ["wilt", "yellow", "ooze", "bxw"]],
     "This may be banana bacterial wilt. Cut out and bury sick plants, remove the male "
     "bud with a forked stick, and clean tools with fire or bleach between plants."),
    ([["cassava"], ["mosaic", "yellow", "twisted", "curl", "mottled"]],
     "Mottled, twisted cassava leaves are cassava mosaic. Uproot and destroy badly hit "
     "plants and plant only clean certified cuttings, never from a sick field."),
    ([["potato"], ["blight", "spot", "patch", "rot", "black", "dark"]],
     "Dark wet patches on potato leaves in cool rain are late blight. Remove sick plants, "
     "use certified seed potato, space plants for air flow and keep cull piles away."),
    ([["store", "storage", "weevil", "keep"], ["grain", "maize", "bean", "harvest"]],
     "Dry the grain until it is hard, clean it, and store it in sealed hermetic bags. "
     "Clean the store first and never pour new grain on top of old infested grain."),
    ([["coffee"], ["yield", "low", "drop", "less", "few", "decline", "reduce", "poor"]],
     "Low coffee yield often comes from old unpruned trees, tired soil and pests. Prune "
     "after harvest, mulch, add compost or manure, and pick only red ripe cherries."),
    ([["coffee"], ["rust", "orange", "powder"]],
     "Orange powder under coffee leaves is leaf rust. Prune to let air through, keep the "
     "trees well fed and mulched, and ask your cooperative which approved spray to use."),
    ([["coffee"], ["price", "sell", "cherry", "money", "buyer"]],
     "Before you sell, ask your washing station or cooperative for this season's NAEB "
     "reference price for cherry. Deliver only red ripe cherries on the day you pick."),
    ([["coffee"], ["antestia", "bug", "potato taste"]],
     "Antestia bugs cause the potato taste defect that lowers coffee prices. Check trees "
     "often, collect and kill the bugs, and prune to open the canopy."),
    ([["acid", "lime", "travertine"]],
     "Acid soil locks up fertilizer. Agricultural lime, travertine, corrects it, but the "
     "amount depends on a soil test. Add compost or manure every season too."),
    ([["compost"], ["how", "make", "prepare"]],
     "Pile crop residues, kitchen waste and manure in layers, keep the heap moist and "
     "turn it every 2 to 3 weeks. It is ready when dark and crumbly, after 2 to 3 months."),
    ([["cattle", "dairy"], ["feed", "milk", "fodder", "grass", "eat"]],
     "Feed dairy cows napier grass plus legume fodder like calliandra or desmodium, and "
     "give clean water all day. Milk drops fast when water is short."),
    ([["tick"]],
     "Spray or dip cattle against ticks on the schedule your sector vet gives and keep "
     "the shed clean. Call the vet at once if a cow has high fever or stops eating."),
    ([["poultry"], ["newcastle", "vaccine", "vaccinate", "vaccination"]],
     "Vaccinate chickens against Newcastle disease on the schedule your vet gives and "
     "repeat it as advised. Give clean water daily and keep a dry, predator proof house."),
    ([["subsidy", "nkunganire"]],
     "Subsidised seed and fertilizer are ordered through Smart Nkunganire. Register with "
     "your Farmer Promoter or cooperative before the season and order early."),
    ([["erosion"]],
     "Stop erosion on slopes with terraces, contour bunds and grass strips of napier or "
     "vetiver. Mulch bare soil and dig trenches to keep water on the plot."),
    ([["drought", "dry"], ["rain", "season", "spell", "crop", "plant", "water"]],
     "In dry spells, mulch to keep the soil moist, harvest rain water into trenches or "
     "tanks, and choose short duration varieties next season."),
    ([["striga", "witchweed"]],
     "Pull striga before it flowers, add manure or compost, and rotate maize with beans, "
     "soybean or desmodium to cut the striga seed in the soil."),
    ([["sell", "price", "market"], ["when", "best", "time", "harvest", "store"]],
     "Prices are lowest right after harvest. If you can, dry and store grain in hermetic "
     "bags and sell later. Selling through a cooperative usually pays more."),
    ([["farmer promoter", "promoter", "mwitozwa"]],
     "Your Farmer Promoter, umuhinzi mwitozwa, is a trained volunteer lead farmer in your "
     "village. Ask your village office or cooperative for their name. Advice is free."),
]

# Questions with this many terms beyond the matched ones carry detail a canned answer
# would ignore, so they go to the model instead.
MAX_EXTRA_TERMS = 1

# Words that add no detail a verified answer would miss.
IGNORED = {"how", "what", "when", "why", "which", "much", "many", "leaf", "plant", "crop",
           "field", "farm", "tree", "turn", "look", "see", "year"}


def _norm_group(group: list[str]) -> set[str]:
    return {" ".join(normalize(w) for w in phrase.split()) for phrase in group}


ENTRIES = [([_norm_group(g) for g in groups], answer) for groups, answer in _ENTRIES]


def match(question: str) -> str | None:
    """The verified answer for an English question, or None to ask the model."""
    q = intent_terms(question)
    best, best_groups = None, 0
    for groups, answer in ENTRIES:
        hit = set()
        for group in groups:
            # a phrase like "farmer promoter" matches when all its words are present
            found = [t.split() for t in group if all(p in q for p in t.split())]
            if not found:
                break
            hit.update(p for words in found for p in words)
        else:
            extra = q - hit - IGNORED
            if len(extra) <= MAX_EXTRA_TERMS and len(groups) > best_groups:
                best, best_groups = answer, len(groups)
    return best
