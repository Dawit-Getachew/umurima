"""Fixed replies. Everything safety-critical lives here, not in the model, so it can
be reviewed line by line and never changes from one farmer to the next."""

WELCOME = {
    "en": "Muraho! I am Umurima AI, your farming advisor. Send any question about "
          "crops, soil, pests or animals. Example: When should I plant maize?",
    "rw": "Muraho! Ndi Umurima AI, umujyanama wawe mu buhinzi. Ohereza ikibazo cyose "
          "ku bihingwa, ubutaka, udukoko cyangwa amatungo. Urugero: Ni ryari natera ibigori?",
}

THANKS = {
    "en": "You are welcome. Send another farming question any time.",
    "rw": "Murakoze namwe! Ohereza ikindi kibazo igihe cyose.",
}

# A first message with no crop, animal or symptom in it: ask rather than guess.
ASK_DETAIL = {
    "en": "Please tell me the crop or animal and what you see. Example: My maize leaves "
          "are turning yellow.",
    "rw": "Mbwira igihingwa cyangwa itungo n'ibyo ubona. Urugero: Amababi y'ibigori "
          "byanjye yahindutse umuhondo.",
}

BUSY = {
    "en": "Sorry, Umurima AI cannot answer this right now. Please try again soon.",
    "rw": "Ihangane, Umurima AI ntiyabashije gusubiza ubu. Ongera ugerageze nyuma gato.",
}

# A sick or dying animal gets two SMS: a safe first step (generated from the notes,
# or this text when the model is down or unsafe), then this fixed escalation, which
# is never generated.
LIVESTOCK_FIRST_AID = {
    "en": "Keep the animal apart from the herd, in the shade, with clean water to drink.",
    "rw": "Shyira itungo rirwaye ukwaryo mu gicucu, uriha amazi meza yo kunywa.",
}

LIVESTOCK_URGENT = {
    "en": "This is urgent. Call your sector veterinary officer today. Do not give old or "
          "leftover drugs, and do not eat or sell meat from an animal that died sick.",
    "rw": "Ni ikibazo cyihutirwa. Hamagara veterineri w'umurenge wawe uyu munsi. Ntuhe "
          "itungo imiti ishaje, kandi ntukarye cyangwa ngo ugurishe inyama z'itungo "
          "ryapfuye rirwaye.",
}

HUMAN_URGENT = {
    "en": "This is a health emergency. Go to the nearest health centre now or call 912. "
          "If it is a pesticide, wash the skin with soap and water, remove the clothes "
          "and take the product label with you.",
    "rw": "Iki ni ikibazo cy'ubuzima cyihutirwa. Jya ku kigo nderabuzima kiri hafi ubu "
          "cyangwa uhamagare 912. Niba ari umuti wica udukoko, karaba uruhu n'isabune "
          "n'amazi, ukuremo imyenda, ujyane n'icupa ry'umuti.",
}

# Second SMS for a crop problem that is killing plants or spreading; on its own when
# the model is down.
CROP_URGENT = {
    "en": "This may be a serious, spreading problem. Report it today to your Farmer "
          "Promoter or sector agronomist. Until they check, do not carry plants, soil or "
          "tools from the affected spot to other fields.",
    "rw": "Iki gishobora kuba ikibazo gikomeye gikwirakwira. Bimenyeshe umuhinzi "
          "mwitozwa cyangwa agronome w'umurenge uyu munsi. Mu gihe bataraza, ntukure "
          "ibimera, ubutaka cyangwa ibikoresho aho byafashwe ngo ubijyane mu yindi mirima.",
}

# Appended by code, not written by the model, so every answer ends with a human
# to ask and the model has no reason to send the farmer away instead of answering.
FOOTER = {
    ("crop", "en"): "More help: your Farmer Promoter or sector agronomist.",
    ("crop", "rw"): "Ubundi bufasha: umuhinzi mwitozwa cyangwa agronome w'umurenge.",
    ("animal", "en"): "More help: your sector veterinary officer.",
    ("animal", "rw"): "Ubundi bufasha: veterineri w'umurenge.",
}
