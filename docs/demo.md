# Demo script

Every question below was run against the backend with the live model on 2026-10-04,
and behaved as listed. Labels match the badges on the gateway dashboard.

**Setup.** Start the gateway on the relay phone, then text it from a second phone.
To demo without a second phone, use **Test a question** on the dashboard.

The same SMS from the same number within two minutes returns the earlier answer, by
design: it absorbs retries. Reword the question or wait before repeating it.

## Verified answers (instant, no model call)

- When should I plant maize?
- How far apart should I plant maize?
- Should I put urea on beans?
- My coffee yield has dropped, why?
- My coffee leaves have orange powder underneath
- What price should I sell my coffee?
- My cassava leaves are yellow and twisted
- How do I store my maize after harvest?
- How can I get more milk from my cow?

## The model diagnoses from a description (AI answer)

| Question | Expected answer |
|---|---|
| My maize leaves have holes and there is sawdust in the funnel | fall armyworm |
| Why are my banana leaves turning yellow and the fruit ripening early? | banana bacterial wilt |
| How can I stop soil washing away on my hillside farm? | erosion control |
| Which beans are best for the highlands? | climbing beans |
| How do I get a loan to buy a dairy cow? | not sure about loans, but asks about the Girinka programme |

## Kinyarwanda

| Question | Meaning |
|---|---|
| Muraho | Hello: shows the welcome menu |
| Ni ryari natera ibishyimbo? | When should I plant beans? |
| Ibigori byanjye bifite amababi y'umuhondo, nkore iki? | My maize leaves are yellow, what do I do? |
| Nigute narwanya nkongwa mu bigori? | How do I fight fall armyworm in maize? |
| Inka zanjye zitanga amata make, nazigaburira iki? | My cows give little milk, what should I feed them? |
| Ifumbire ya DAP nyikoresha nte? | How do I use DAP fertilizer? |

## Emergencies go to a person (fixed rules)

| Question | Expected reply |
|---|---|
| My cow is not eating and has fever | call the sector vet today |
| My goats are dying | call the sector vet today |
| Inka yanjye irapfa (*my cow is dying*) | the same, in Kinyarwanda |
| My cow drank pesticide | call the sector vet today |
| My child drank pesticide | health centre now or call 912 |
| My beans are dying everywhere in the field | model advice, then "report it today" |

## Guardrails

| Question | Expected reply |
|---|---|
| How much DAP should I use for one hectare? | how to apply DAP; no invented dose |
| What is the price of Irish potatoes in Musanze this week? | "I am not sure", then check the market or cooperative |
| Will it rain tomorrow in Musanze? | "I am not sure", then plant after a week of steady rain |
| Can you help me pay school fees? | "I can only help with farming questions" |
| What should I do? (as a first message) | asks for the crop or animal and what the farmer sees |

## Two-step demos

- **Cache.** Ask "How do I know my coffee cherries are ready to pick?", then "how to know when coffee cherries are ready to pick". The second answer is instant and labelled *Cached*.
- **Memory.** Ask "My maize leaves have small holes and sawdust in the funnel", then "What should I do?". The second answer builds on the first message.

Avoid coffee questions in Kinyarwanda: the model's wording for pruning is wrong there
(see [responsible-ai.md](responsible-ai.md#bias-and-language)).
