# Data

The challenge asks for two kinds of data: evidence that the problem is real, and the
data the tool is built with, including what that data does not cover.

## 1. Evidence of the problem

| Figure | Source | Year |
|---|---|---|
| 69% of Rwandan households (2.3 million) are agricultural; 83% of rural households | [NISR, RPHC5 Thematic Report: Agriculture](https://statistics.gov.rw/sites/default/files/documents/2025-02/RPHC5%20Thematic%20Report_Agriculture.pdf) | Census 2022 |
| In agricultural households: 78% have a member with a mobile phone, 9% a smartphone, 16% internet; 32% of household heads are illiterate | same | Census 2022 |
| 62% of workers are in agriculture; 85% of households own a mobile phone vs 34% a smartphone (23% in rural areas) | [NISR, EICV7 Main Indicators Report](https://statistics.gov.rw/sites/default/files/documents/2025-07/EICV7_Main%20Indicator%20Report.pdf) | 2023/24 |
| Smartphones are 22% of mobile connections; mobile internet usage gap of 80% | [GSMA, *Assessing Rwanda Mobile Tax*](https://www.gsma.com/solutions-and-impact/connectivity-for-good/public-policy/wp-content/uploads/2024/12/Assessing-Rwanda-Mobile-Tax.pdf) | 2023 data, published 2024 |
| Average farm is 0.4 ha; 77.2% of agricultural households farm under 0.5 ha | [NISR, Agricultural Household Survey](https://microdata.statistics.gov.rw/index.php/catalog/101/download/907) | 2019/20 |
| 14,000+ Farmer Promoters trained under Twigire Muhinzi, supporting 2M+ farmers | [RAB](https://www.rab.gov.rw/1-1/news-details/rab-and-one-acre-fund-graduate-first-cohort-of-agriculture-extension-certification-training-program) | 2025 |
| About 400,000 smallholder families grow coffee on 42,000 ha | [NAEB](https://www.naeb.gov.rw/rwanda-coffee/about-rwanda-coffee) | undated |

These figures set the design constraints: a basic phone, no data connection, limited
literacy, and a human extension network that already exists but is spread thin.

## 2. Data the tool is built with

No model was trained or fine-tuned. The tool uses a hosted model plus the following:

| Asset | Contents | Size | Origin | License |
|---|---|---|---|---|
| Knowledge notes (`backend/knowledge/*.md`) | Seasons, crops, coffee, fertilizer, pests and diseases, livestock, extension services, regional context | 8 files, 68 paragraphs, ~20 KB | Written by the team from public RAB, MINAGRI and NAEB guidance | Same as this repository |
| Verified answers (`backend/app/faq.py`) | 27 short answers to the most common questions | 27 entries | Derived from the notes | Same as this repository |
| Fixed replies (`backend/app/replies.py`) | Emergency, greeting and fallback messages in English and Kinyarwanda | 7 messages and 3 contact lines, each in 2 languages | Written by the team | Same as this repository |
| Kinyarwanda term map (`backend/app/nlp.py`) | Kinyarwanda crop, animal, input and verb forms mapped to English retrieval terms | 64 terms | Written by the team | Same as this repository |
| Model | `google/gemini-3.1-flash-lite` via OpenRouter | hosted | Google | Provider terms of service |

No synthetic data was used.

## 3. What the data does not cover

This section is scored by the challenge.

- **No review by RAB.** The notes are drafts written from public material. Nobody at RAB has checked them.
- **No plot-level data.** No soil tests, rainfall or satellite data per farm. Advice is national or regional, not specific to a plot.
- **No rates or doses.** Fertilizer and pesticide quantities depend on soil and plot size. The tool deliberately refers dose questions to the bag label or an agro-dealer.
- **No live prices.** The tool cannot tell a farmer today's market or farm-gate price. It points to the cooperative, the washing station, or comparing buyers.
- **No weather.** There are no forecasts. Planting advice relies on the rule "plant after a week of steady rain".
- **Limited crops and animals.** Maize, beans, cassava, potato, rice, banana, coffee, tea, cattle, goats and poultry are covered. Horticulture (tomato, cabbage, onion), pigs, rabbits, fish and bees are covered thinly or not at all.
- **Kinyarwanda.** The term map covers common nouns and a few verb forms, but not the language's full morphology. Dialect variation and spelling errors in SMS are untested.
- **No real usage data.** All testing used questions written by the team, not messages from farmers.

## 4. Ideas taken from the World Bank AI Repository

| Case | What we took |
|---|---|
| [Virtual Agronomist (iSDA)](https://airepository.worldbank.org/use-case/virtual-agronomist): fertilizer advice over WhatsApp in 7 African countries | Concrete, actionable advice beats general information. |
| Digital Green Farmer.Chat; Kisan e-Mitra ([World Bank blog, 2025](https://blogs.worldbank.org/en/agfood/can-ai-give-small-scale-producers-the-right-advice-)) | Hybrid AI and human extension, local language first. Hybrid models cut advisory cost to under $1 per farmer per year. |
| Wadhwani AI CottonAce, PlantVillage Nuru ([World Bank, 2024](https://thedocs.worldbank.org/en/doc/20ca38de6ebb3fc55a9c6a2883bffda8-0050022024/original/AI-the-new-wingman-of-development-Siddharth-Dixit-and-Indermit-Gill.pdf)) | Work offline and degrade gracefully when connectivity fails. |
| MahaVISTAAR-AI ([World Bank, 2026](https://www.worldbank.org/en/news/feature/2026/08/27/small-ai-transforms-farming-in-india)) | Showing the source of an answer builds trust. `/sms` returns the notes behind each reply. |
| "Small AI, big impact" ([World Bank blog, 2025](https://blogs.worldbank.org/en/voices/small-ai-big-impact-harnessing-artificial-intelligence-for-development)) | Build on existing networks (SMS), mobile-first, through existing partners (Farmer Promoters). |
