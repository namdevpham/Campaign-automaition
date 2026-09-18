# NAM QUIZ — COMPLETE CURRENT MASTER RULES
## Source View → 20-Question NAM QUIZ JSON
### Current effective version: 2026-09-16

> **This file is the single current source of truth.**
>
> It supersedes older NAM QUIZ workflow files and older chat instructions.
> Rules that were replaced or removed are intentionally NOT repeated here.
> A future ChatGPT/model should be able to read only this file plus the newly uploaded Source View and produce the correct deliverables without needing a separate JSON example.

---

# 1. CORE BEHAVIOR

When the user uploads a new quiz **Source View** file, process it automatically.

- Do **not** ask what the user wants if the upload clearly matches this workflow.
- Do **not** ask for a JSON example.
- Do **not** ask the user to repeat rules already contained in this file.
- The uploaded Source View is the primary source of truth.
- Read the **complete** Source View, not only the visible/truncated preview.
- If the visible file preview is truncated, use the available file-reading/search mechanism or mounted file to access the full content.
- Do not switch to web search to reconstruct quiz data that exists in the Source View.
- Do not silently “correct” source facts. Prefer excluding a questionable source question when cleaner alternatives exist.
- If the source contains fewer than 20 usable questions, explicitly report that limitation instead of inventing or duplicating questions.

The normal deliverables are:

1. one final NAM QUIZ JSON in the **same language as the source quiz**;
2. one ZIP containing exactly that JSON;
3. one QA report;
4. one Canonical 20 Source Audit JSON.

---

# 2. LANGUAGE RULE — CURRENT RULE ONLY

The Source View language determines the output language.

## Required behavior

- English source → create **English JSON only**.
- Spanish source → create **Spanish JSON only**.
- Russian source → create **Russian JSON only**.
- Arabic source → create **Arabic JSON only**.
- Any other supported source language → create that language only.

Do **not** automatically create Russian / Arabic / Romanian / Croatian versions from a Source View.

Do **not** create a multi-language Source View package unless the user explicitly asks for it in that task.

## How to detect the real source language

Do not rely only on:

```html
<html lang="...">
```

Prefer embedded quiz data/state, for example:

- `data-language`
- `state.language`
- quiz application context language
- visible quiz content if necessary

The embedded quiz state/content has priority.

## Locale

Set root `"locale"` to the appropriate locale code, for example:

- English → `"en"`
- Spanish → `"es"`
- Russian → `"ru"`
- Arabic → `"ar"`

All interface text created by us must be in the same source language.

---

# 3. CURRENT `name` RULE

The root JSON field `"name"` must be a **short technical identifier**, not the full quiz title.

## Mandatory rules

- Keep it concise.
- Use underscores rather than spaces.
- Use a topic-oriented name.
- The final suffix must match the **target language / root `locale`**.
- Never use the old `_Testw1` suffix again.
- Never append the full language name.

Exact suffix mapping:

```text
English  / locale en → _EN
Russian  / locale ru → _RU
Arabic   / locale ar → _AR
Romanian / locale ro → _RO
Croatian / locale hr → _HR
```

## Correct examples

```json
"name": "Greek_God_EN"
```

```json
"name": "Greek_God_RU"
```

```json
"name": "Greek_God_AR"
```

```json
"name": "Greek_God_RO"
```

```json
"name": "Greek_God_HR"
```

Other examples:

```json
"name": "Church_Etiquette_EN"
```

```json
"name": "Country_Music_Lyrics_RU"
```

```json
"name": "60s_School_Quiz_AR"
```

## Incorrect patterns

```json
"name": "Greek_God_Testw1"
```

```json
"name": "Greek_God_English"
```

```json
"name": "Greek_God"
```

Critical:
- the topic/base identifier should remain stable across translations;
- only the final language suffix changes;
- e.g. `Greek_God_EN`, `Greek_God_RU`, `Greek_God_AR`, `Greek_God_RO`, `Greek_God_HR`.


---

# 4. SOURCE EXTRACTION

Extract the complete quiz state from the Source View.

At minimum capture:

- source file name;
- quiz ID;
- quiz title / `quizName`;
- actual source language;
- quiz type;
- source question count;
- full question list;
- option list for every question;
- correct answer if Standard/trivia;
- answer explanation / `answerParagraph`;
- question image URL;
- any source hint if present;
- question type;
- quiz tags when useful for QA/context;
- about-quiz text when available.

## Times Now / Times of India source-view parsing

These pages often contain browser-rendered escaped HTML and embedded Next.js payloads.

A robust pattern is:

1. Read the full HTML file.
2. Reconstruct visible source text from the `td.line-content` cells if necessary.
3. Find payloads shaped like:

```text
self.__next_f.push([1,"..."])
```

4. JSON-decode the string payload safely.
5. Locate the payload containing both `"quizName"` and `"questions"`.
6. Locate `"state":`.
7. Balanced-extract the full state object.
8. Parse the state JSON.

Do **not** use naïve global quote replacement.

Do **not** use `unicode_escape` decoding that can corrupt punctuation such as curly apostrophes/quotes.

## Options can appear in more than one source shape

Example string options:

```json
"options": ["A", "B", "C", "D"]
```

Example object options:

```json
"options": [
  {"option": "A", "image": ""},
  {"option": "B", "image": ""}
]
```

When options are objects:

- use the exact `option` value as the semantic visible option text;
- preserve source order exactly;
- preserve the source correct-answer identity exactly;
- do not alphabetize, reshuffle, or “improve” the answer choices.

---

# 5. QUIZ TYPE

Determine quiz type from source data before building output.

## Standard / trivia quiz

Use normal correctness/scoring behavior:

- one correct option;
- correct/wrong feedback;
- score-based Results page.

## Personality quiz

If the source is a personality quiz:

- do not invent a correct answer;
- do not add `.correct`;
- do not add `.ac` / `.aw` correctness logic;
- do not add correct/wrong feedback;
- do not score answers as right/wrong;
- preserve the source outcome mapping exactly.

Never force a personality quiz into the Standard/trivia template.

---

# 6. FULL-POOL REVIEW BEFORE SELECTION

Review the **entire source question pool** before selecting the final 20.

Do not simply take the first 20.

## Selection goals

Choose exactly 20 valid questions when possible.

The 20 should:

- represent the overall topic well;
- be diverse;
- avoid obvious repetition;
- avoid near-duplicate questions;
- avoid broken questions;
- avoid mismatched question/options;
- avoid ambiguous source questions when cleaner alternatives exist;
- avoid source-factually questionable questions when cleaner alternatives exist;
- avoid time-sensitive wording when it is already stale and an alternative exists;
- avoid overloading the final quiz with one subtopic/artist/show/category when the source offers broader coverage.

## Order rule

After selecting the 20 source positions:

- preserve their original **source-relative order**;
- do not reorder them by difficulty, topic, or aesthetics.

Example:

If selected source positions are:

```text
1, 4, 9, 17, 23
```

the final display order remains exactly:

```text
1 → 4 → 9 → 17 → 23
```

## Never do these

- never duplicate one source question to reach 20;
- never invent a new question;
- never invent a new option;
- never silently replace the source correct answer;
- never silently rewrite the source explanation.

---

# 7. SOURCE FIDELITY PRIORITY

For every selected question, preserve these elements with highest priority:

1. exact question meaning/text;
2. exact semantic option order;
3. exact correct answer identity;
4. exact correct option index;
5. source explanation / `answerParagraph`;
6. exact direct source question image identity;
7. selected source order;
8. scoring/outcome logic;
9. quiz type.

A generated hint is allowed because the current output requires hints, but the hint must not alter source truth.

---

# 8. CANONICAL 20 SOURCE AUDIT

Always create a separate Canonical Audit JSON.

Recommended metadata:

```json
{
  "sourceFile": "...",
  "quizId": "...",
  "quizName": "...",
  "sourceLanguage": "english",
  "quizType": "quiz",
  "sourceQuestionCount": 80,
  "selectedQuestionCount": 20,
  "selectedSourcePositions": [1, 3, 7, 12],
  "technicalName": "Topic_EN",
  "selectionNotes": "...",
  "questions": []
}
```

Each selected question should contain:

```json
{
  "displayNumber": 1,
  "sourcePosition": 7,
  "question": "Exact source question",
  "options": ["A", "B", "C", "D"],
  "correctAnswer": "B",
  "correctOptionIndex": 1,
  "answerParagraph": "Exact source explanation",
  "imageUrl": "Exact source image URL",
  "hint": "Generated/source hint",
  "type": null
}
```

`correctOptionIndex` is **0-based**.

---

# 9. EXACT ROOT JSON SCHEMA AND KEY ORDER

Root key order must be exactly:

```text
locale
title
name
description
main_content
confirm
sub_pages
```

Structure:

```json
{
  "locale": "en",
  "title": "Source Quiz Title",
  "name": "Short_Topic_EN",
  "description": "Same-language quiz description",
  "main_content": "...",
  "confirm": {
    "title": "...",
    "question": "...",
    "button_text": "..."
  },
  "sub_pages": [
    {
      "title": "...",
      "path": "1",
      "content": "..."
    },
    {
      "title": "...",
      "path": "2",
      "content": "..."
    },
    {
      "title": "...",
      "path": "3",
      "content": "..."
    },
    {
      "title": "...",
      "path": "4",
      "content": "..."
    },
    {
      "title": "...",
      "path": "5",
      "content": "..."
    }
  ]
}
```

## Confirm key order

Exactly:

```text
title
question
button_text
```

`confirm` is the **quiz start confirmation**, not the restart button.

## Sub-page key order

Exactly:

```text
title
path
content
```

Paths must be strings:

```text
"1"
"2"
"3"
"4"
"5"
```

---

# 10. PAGINATION

For 20 selected questions:

- `main_content` → Questions 1–4
- `path "1"` → Questions 5–8
- `path "2"` → Questions 9–12
- `path "3"` → Questions 13–16
- `path "4"` → Questions 17–20
- `path "5"` → Results

Question numbering must remain continuous:

```text
Question 1 / 20
...
Question 20 / 20
```

Expected question-card count per page:

```text
[4, 4, 4, 4, 4, 0]
```

---

# 11. APPROVED CSS — DO NOT MODIFY UNLESS USER UPDATES IT

Use this exact baseline:

```css
.tq{max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#172033;line-height:1.55}
.tq *{box-sizing:border-box}
.tq h2,.tq h3{line-height:1.25}
.qc{background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:16px;margin:0 0 18px;box-shadow:0 4px 14px rgba(15,23,42,.06)}
.qnum{font-size:13px;font-weight:700;color:#64748b;margin-bottom:8px}
.qtext{font-size:20px;font-weight:700;margin:0 0 12px}
.imgbox{width:100%;overflow:hidden;border-radius:12px;background:#f8fafc;margin:10px 0 14px}
.qimg{display:block;width:100%;height:auto}
.opts{display:grid;gap:10px}
.opt{display:block;border:1px solid #cbd5e1;border-radius:12px;padding:11px 12px;cursor:pointer;background:#fff}
.opt input{margin-right:8px}
.qc:has(input:checked) .opts{pointer-events:none}
.qc:has(input:checked) .opt.correct{border-color:#10b981;background:#ecfdf5}
.qc:has(.aw:checked) .opt:has(.aw:checked){border-color:#ef4444;background:#fef2f2}
.feedback{display:none;margin-top:12px;padding:12px;border-radius:10px}
.correct-feedback{background:#ecfdf5;border:1px solid #a7f3d0}
.wrong-feedback{background:#fef2f2;border:1px solid #fecaca}
.qc:has(.ac:checked) .correct-feedback{display:block}
.qc:has(.aw:checked) .wrong-feedback{display:block}
.hintbox{margin-top:12px;border:1px solid #fde68a;background:#fffbeb;border-radius:10px;padding:9px 11px}
.hintbox summary{cursor:pointer;font-weight:700}
.bulb{filter:drop-shadow(0 0 5px rgba(245,158,11,.85))}
.hint-content{padding-top:6px}
.hint-content p{margin:0}
.footer-note{margin-top:22px;padding:18px;border:1px solid #e2e8f0;border-radius:14px;background:#f8fafc;color:#475569;font-size:14px}
.footer-note h2{margin:0 0 10px;color:#172033;font-size:22px;line-height:1.25}
.footer-note h3{margin:20px 0 8px;color:#172033;font-size:16px;line-height:1.3}
.footer-note p{margin:0 0 10px}
.footer-note ul,.footer-note ol{margin:8px 0 14px;padding-left:22px}
.footer-note li{margin:0 0 8px}
.tq[dir="rtl"] .footer-note ul,.tq[dir="rtl"] .footer-note ol{padding-left:0;padding-right:22px}
.results{display:grid;gap:12px;margin:16px 0}
.result-card{border-radius:14px;padding:14px;border:1px solid #e5e7eb}
.result-card strong{display:block;font-size:18px;margin-bottom:4px}
.tq[dir="rtl"] .opt input{margin-left:8px;margin-right:0}
.tq[dir="rtl"]{text-align:right}
.result-tier-purple{background:#f1e8ff;border-color:#c9a6ff;color:#5b168c}
.result-tier-green{background:#e3fbe9;border-color:#72df95;color:#12642f}
.result-tier-yellow{background:#fff8c9;border-color:#f4c842;color:#7a4a00}
.result-tier-red{background:#ffe2e2;border-color:#ff8c8c;color:#8d1212}
.result-tier-purple strong,.result-tier-green strong,.result-tier-yellow strong,.result-tier-red strong{color:inherit}
```

Important:

- `max-width` is **600px**.
- Do not revert to 860px.
- No JavaScript is needed.
- Answer locking is implemented with CSS `:has(...)`.

---

# 12. STANDARD QUESTION CARD — EXACT PATTERN

For English Standard/trivia:

```html
<div class="qc">
<div class="qnum">Question 1 / 20</div>
<div class="qtext">QUESTION</div>
<div class="imgbox"><img class="qimg" src="IMAGE_URL" alt=""></div>
<div class="opts">
<label class="opt correct"><input type="radio" name="q1" class="ac"> CORRECT_OPTION</label>
<label class="opt"><input type="radio" name="q1" class="aw"> WRONG_OPTION</label>
<label class="opt"><input type="radio" name="q1" class="aw"> WRONG_OPTION</label>
<label class="opt"><input type="radio" name="q1" class="aw"> WRONG_OPTION</label>
</div>
<div class="feedback correct-feedback"><strong>Correct.</strong><br><strong>Explanation:</strong> SOURCE_EXPLANATION</div>
<div class="feedback wrong-feedback"><strong>Not quite.</strong><br><strong>Explanation:</strong> SOURCE_EXPLANATION</div>
<details class="hintbox"><summary><span class="bulb" aria-hidden="true">💡</span> <span>Hint</span></summary><div class="hint-content"><p>QUESTION_SPECIFIC_HINT</p></div></details>
</div>
```

## Important markup rules

- Correct option label:

```html
<label class="opt correct"><input type="radio" name="q1" class="ac"> OPTION</label>
```

- Wrong option label:

```html
<label class="opt"><input type="radio" name="q1" class="aw"> OPTION</label>
```

- Do not add extra `<span>` wrappers around option text.
- `.feedback` blocks are mandatory for Standard/trivia.
- Use the same exact source explanation in both feedback blocks.
- Localize `Question`, `Correct`, `Not quite`, `Explanation`, `Hint` when the source language is not English.

---

# 13. HINT RULE

Every selected Standard/trivia question must have one useful hint.

Required:

- exactly 20 hints for 20 questions;
- question-specific;
- concise;
- helpful;
- same language as source;
- not generic;
- not an exact copy of the answer;
- ideally unique.

If source already contains a useful hint, preserve/use it.

If source has no useful hint, create one.

Do not create hints that directly reveal the answer.

---

# 14. IMAGE RULE

Preserve exact question-image identity.

## Times Now / Times of India / Appwrite

Use the **direct exact Appwrite source URL**.

Example:

```text
https://cloud.appwrite.io/v1/storage/buckets/.../preview?project=...
```

Do not add a proxy to Times Now/Appwrite question images.

## Historical Grizly source

Use:

```text
https://wsrv.nl/?url=<URL_ENCODED_EXACT_GRIZLY_SOURCE_URL>
```

The underlying source image URL must still be the exact source image.

---

# 15. ADS

Question pages only:

- root/main_content → exactly 1 `<p>[ads/]</p>`
- path 1 → exactly 1
- path 2 → exactly 1
- path 3 → exactly 1
- path 4 → exactly 1
- path 5 Results → 0

Expected distribution:

```text
[1, 1, 1, 1, 1, 0]
```

Place the ad after the four question cards and before navigation/footer.

---

# 16. NAVIGATION

Required sequence:

```text
root → 1 → 2 → 3 → 4 → 5
```

Use shortcode format:

```text
[link title="..." custom="..."/]
```

For current English Standard output:

- root → `[link title="Next questions" custom="1"/]`
- path 1 → `[link title="Next questions" custom="2"/]`
- path 2 → `[link title="Next questions" custom="3"/]`
- path 3 → `[link title="Next questions" custom="4"/]`
- path 4 → `[link title="See your result" custom="5"/]`
- Results → `[link title="Take the quiz again" custom="Confirm"/]`

For non-English source:

- localize the visible `title`;
- keep the exact `custom` sequence.

Critical:

- root/path1/path2/path3 = equivalent of **Next questions**
- path4 = equivalent of **See your result**
- Results restart custom must be exactly **Confirm**

---

# 17. FOOTER

`.footer-note` must appear **exactly once on all six pages**:

- main_content
- paths 1–4
- Results path 5

Expected footer distribution:

```text
[1, 1, 1, 1, 1, 1]
```

The footer must be:

- professional;
- natural;
- same language as source;
- relevant to that quiz topic;
- useful to a real user.

Recommended footer content:

- About this quiz
- How to take the quiz
- What the questions cover
- Scoring
- Source fidelity / quiz purpose

Do not use an irrelevant generic footer.

---

# 18. RESULTS PAGE — STANDARD QUIZ

Path `"5"`:

- zero ads;
- heading;
- short intro;
- exactly four result cards;
- retake link with `custom="Confirm"`;
- one footer.

## Score ranges — exact

Purple:

```text
17–20
```

Green:

```text
13–16
```

Yellow:

```text
8–12
```

Red:

```text
0–7
```

## Exact classes

```text
result-tier-purple
result-tier-green
result-tier-yellow
result-tier-red
```

Each `.result-card strong` contains the literal range only.

Example:

```html
<div class="result-card result-tier-purple">
<strong>17–20</strong>
<b>TOPIC-SPECIFIC RESULT LABEL</b><br>
TOPIC-SPECIFIC RESULT TEXT
</div>
```

Result labels/text should match the quiz topic and source language.

---

# 19. RTL RULE

For Arabic or another RTL source language, every page wrapper must be:

```html
<div class="tq" dir="rtl">
```

For LTR languages:

```html
<div class="tq">
```

Important QA detail:

Do **not** detect RTL merely by searching the entire page for `dir="rtl"` because the CSS contains selectors such as:

```css
.tq[dir="rtl"]
```

Inspect the actual opening wrapper after `</style>`.

---

# 20. NO JAVASCRIPT

Do not include:

```html
<script>
```

Do not include:

```html
onclick=
```

Do not include:

```html
onchange=
```

The answer-locking and feedback behavior must rely on the approved CSS.

---

# 21. ESCAPING / HTML SAFETY

When injecting source text into HTML strings inside JSON:

- HTML-escape question text;
- HTML-escape option text;
- HTML-escape explanations;
- HTML-escape URLs as needed for valid HTML;
- preserve visible semantic text exactly.

Example:

Source option:

```text
Simon & Garfunkel
```

HTML inside JSON may correctly become:

```html
Simon &amp; Garfunkel
```

This is not a semantic content change.

---

# 22. OUTPUT FILES AND NAMING

Recommended output layout:

```text
/mnt/data/<Quiz_Base>_<Language>/01_<Language>.json
```

Example:

```text
/mnt/data/Can_You_Name_These_Jukebox_Songs_Every_Boomer_Remembers_English/01_English.json
```

ZIP:

```text
/mnt/data/<Quiz_Base>_<Language>_JSON_Pack.zip
```

QA:

```text
/mnt/data/<Quiz_Base>_<Language>_QA.txt
```

Canonical audit:

```text
/mnt/data/<Quiz_Base>_Canonical_20_Source_Audit.json
```

The ZIP must contain **exactly one file**:

```text
01_<Language>.json
```

No audit file inside the ZIP unless the user later changes this rule.

---

# 23. QA RELEASE GATE — MUST PASS BEFORE DELIVERY

Do not claim the task is complete until QA passes with **0 issues**.

Check all of the following.

## Schema

- root key order exact;
- confirm key order exact;
- subpage key order exact;
- locale matches source;
- title/source language correct;
- `"name"` concise and ends with the language suffix matching root `locale`;
- `"name"` does not contain obsolete `English` suffix;
- paths exactly `"1"` through `"5"`.

## Questions

- exactly 20 selected;
- distribution `[4,4,4,4,4,0]`;
- source-relative selected order preserved;
- exact source question text;
- exact semantic option order;
- correct answer identity exact;
- correct option index exact;
- explanation exact;
- image identity exact;
- correct platform image/proxy rule.

## UI

- 20 question-specific hints;
- correct feedback count = 20 for Standard;
- wrong feedback count = 20 for Standard;
- no JavaScript;
- correct LTR/RTL wrapper;
- approved 600px CSS unchanged unless user explicitly updates it.

## Ads

Exactly:

```text
[1,1,1,1,1,0]
```

## Navigation

- root → custom 1
- path 1 → custom 2
- path 2 → custom 3
- path 3 → custom 4
- path 4 → custom 5
- root/path1/path2/path3 visible title = localized “Next questions”
- path4 visible title = localized “See your result”
- results retake custom = `Confirm`

## Footer

Exactly once on all six pages:

```text
[1,1,1,1,1,1]
```

## Results

- exactly four result cards;
- exact result classes;
- exact ranges:
  - 17–20
  - 13–16
  - 8–12
  - 0–7

## ZIP

- contains exactly one JSON;
- correct filename;
- CRC PASS;
- zipped JSON bytes match standalone JSON.

## QA implementation warnings

### Feedback counting

Count exact HTML tags:

```html
<div class="feedback correct-feedback">
```

and

```html
<div class="feedback wrong-feedback">
```

Do not count class-name substrings across CSS because that creates false positives.

### Result card counting

Count exact card tags such as:

```html
<div class="result-card result-tier-purple">
```

Do not count CSS selector occurrences.

### Option-order verification

Verify options inside the individual question card, not by searching the whole page, because repeated text elsewhere can produce false positives.

---

# 24. INDEPENDENT RELEASE GATE

After the first QA pass, run a second independent verification against the **actual exported JSON and ZIP**, not only against in-memory variables.

The independent gate should re-check:

- schema/order;
- locale;
- name rule;
- paths;
- distribution;
- ads;
- footer count;
- hints;
- feedback;
- no JS;
- actual wrapper direction;
- navigation;
- result cards/ranges;
- exact source fidelity card-by-card;
- ZIP names;
- ZIP CRC;
- zipped JSON equals standalone JSON.

Final status should be:

```text
PASS — 0 issues
```

Only then deliver files.

---

# 25. FINAL RESPONSE TO USER

Keep the delivery response concise.

State:

- source title;
- detected source language / quiz type;
- source question count;
- final short `"name"`;
- selected 20 source positions;
- QA + independent release gate status.

Then provide links to:

1. final JSON;
2. ZIP pack;
3. QA report;
4. Canonical Source Audit.

When file-source citations are available, cite metadata claims from the uploaded Source View.

Do not clutter the response with implementation details unless the user asks.

---

# 26. CURRENT PRIORITY / CONFLICT RULE

If instructions conflict, use this priority:

1. latest explicit instruction from the user in the current turn;
2. latest direct user update in conversation;
3. this current Master Rules file;
4. older master/workflow files;
5. older generated examples;
6. model inference.

If the user later explicitly changes one rule, that new rule overrides this file only for the affected rule; keep all unrelated current rules.

---

# 27. DO NOT REVIVE OBSOLETE RULES

This current workflow intentionally does **not** include older rules that have already been replaced.

In particular, do not automatically return to:

- old multi-language Source View generation;
- old `..._English` technical-name suffix;
- long full-title `"name"` values;
- old wider layout;
- old combined language package behavior.

Only revive an older behavior if the user explicitly asks for it again.

---

# 28. SELF-CONTAINED JSON REFERENCE

The JSON below is a **real current-format output that passed the current QA structure**.

Use it as the reference for:

- root schema;
- key order;
- HTML/CSS placement;
- question cards;
- hint placement;
- ads;
- navigation;
- footer;
- Results page;
- `Confirm`;
- language-code technical naming (`_EN/_RU/_AR/_RO/_HR`).

The **content itself is only an example**. For every new Source View, replace the quiz-specific content with the newly extracted source data.

```json
{
  "locale": "en",
  "title": "Can You Name These Jukebox Songs Every Boomer Remembers?",
  "name": "Jukebox_Songs_EN",
  "description": "Test your memory of 20 classic jukebox songs spanning early rock ’n’ roll, doo-wop, Motown, soul, pop, psychedelic sounds, and 1970s favorites.",
  "main_content": "<style>.tq{max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#172033;line-height:1.55}\n.tq *{box-sizing:border-box}\n.tq h2,.tq h3{line-height:1.25}\n.qc{background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:16px;margin:0 0 18px;box-shadow:0 4px 14px rgba(15,23,42,.06)}\n.qnum{font-size:13px;font-weight:700;color:#64748b;margin-bottom:8px}\n.qtext{font-size:20px;font-weight:700;margin:0 0 12px}\n.imgbox{width:100%;overflow:hidden;border-radius:12px;background:#f8fafc;margin:10px 0 14px}\n.qimg{display:block;width:100%;height:auto}\n.opts{display:grid;gap:10px}\n.opt{display:block;border:1px solid #cbd5e1;border-radius:12px;padding:11px 12px;cursor:pointer;background:#fff}\n.opt input{margin-right:8px}\n.qc:has(input:checked) .opts{pointer-events:none}\n.qc:has(input:checked) .opt.correct{border-color:#10b981;background:#ecfdf5}\n.qc:has(.aw:checked) .opt:has(.aw:checked){border-color:#ef4444;background:#fef2f2}\n.feedback{display:none;margin-top:12px;padding:12px;border-radius:10px}\n.correct-feedback{background:#ecfdf5;border:1px solid #a7f3d0}\n.wrong-feedback{background:#fef2f2;border:1px solid #fecaca}\n.qc:has(.ac:checked) .correct-feedback{display:block}\n.qc:has(.aw:checked) .wrong-feedback{display:block}\n.hintbox{margin-top:12px;border:1px solid #fde68a;background:#fffbeb;border-radius:10px;padding:9px 11px}\n.hintbox summary{cursor:pointer;font-weight:700}\n.bulb{filter:drop-shadow(0 0 5px rgba(245,158,11,.85))}\n.hint-content{padding-top:6px}\n.hint-content p{margin:0}\n.footer-note{margin-top:22px;padding:18px;border:1px solid #e2e8f0;border-radius:14px;background:#f8fafc;color:#475569;font-size:14px}\n.footer-note h2{margin:0 0 10px;color:#172033;font-size:22px;line-height:1.25}\n.footer-note h3{margin:20px 0 8px;color:#172033;font-size:16px;line-height:1.3}\n.footer-note p{margin:0 0 10px}\n.footer-note ul,.footer-note ol{margin:8px 0 14px;padding-left:22px}\n.footer-note li{margin:0 0 8px}\n.tq[dir=\"rtl\"] .footer-note ul,.tq[dir=\"rtl\"] .footer-note ol{padding-left:0;padding-right:22px}\n.results{display:grid;gap:12px;margin:16px 0}\n.result-card{border-radius:14px;padding:14px;border:1px solid #e5e7eb}\n.result-card strong{display:block;font-size:18px;margin-bottom:4px}\n.tq[dir=\"rtl\"] .opt input{margin-left:8px;margin-right:0}\n.tq[dir=\"rtl\"]{text-align:right}\n.result-tier-purple{background:#f1e8ff;border-color:#c9a6ff;color:#5b168c}\n.result-tier-green{background:#e3fbe9;border-color:#72df95;color:#12642f}\n.result-tier-yellow{background:#fff8c9;border-color:#f4c842;color:#7a4a00}\n.result-tier-red{background:#ffe2e2;border-color:#ff8c8c;color:#8d1212}\n.result-tier-purple strong,.result-tier-green strong,.result-tier-yellow strong,.result-tier-red strong{color:inherit}</style>\n<div class=\"tq\">\n<div class=\"qc\">\n<div class=\"qnum\">Question 1 / 20</div>\n<div class=\"qtext\">Who made “Jailhouse Rock” a rock ’n’ roll classic?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87ead6001a319a2d6c/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt correct\"><input type=\"radio\" name=\"q1\" class=\"ac\"> Elvis Presley</label><label class=\"opt\"><input type=\"radio\" name=\"q1\" class=\"aw\"> Eddie Cochran</label><label class=\"opt\"><input type=\"radio\" name=\"q1\" class=\"aw\"> Buddy Holly</label><label class=\"opt\"><input type=\"radio\" name=\"q1\" class=\"aw\"> Gene Vincent</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Elvis recorded “Jailhouse Rock” in 1957, and its heavy backbeat highlights the rhythmic emphasis that became central to early rock ’n’ roll.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Elvis recorded “Jailhouse Rock” in 1957, and its heavy backbeat highlights the rhythmic emphasis that became central to early rock ’n’ roll.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>Think of the singer whose 1950s image became almost synonymous with the birth of rock ’n’ roll.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 2 / 20</div>\n<div class=\"qtext\">Which guitar pioneer gave us “Johnny B. Goode”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87ec3f002d5a06b81b/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q2\" class=\"aw\"> Carl Perkins</label><label class=\"opt correct\"><input type=\"radio\" name=\"q2\" class=\"ac\"> Chuck Berry</label><label class=\"opt\"><input type=\"radio\" name=\"q2\" class=\"aw\"> Bo Diddley</label><label class=\"opt\"><input type=\"radio\" name=\"q2\" class=\"aw\"> Duane Eddy</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Chuck Berry’s famous opening guitar figure helped establish a vocabulary of riffs and double-stops copied by generations of rock guitarists.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Chuck Berry’s famous opening guitar figure helped establish a vocabulary of riffs and double-stops copied by generations of rock guitarists.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>This guitarist’s duck walk and storytelling songs influenced generations of rock players.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 3 / 20</div>\n<div class=\"qtext\">“Rock Around the Clock” was a huge hit for which group?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87ee56000bf856ae49/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q3\" class=\"aw\"> The Diamonds</label><label class=\"opt\"><input type=\"radio\" name=\"q3\" class=\"aw\"> The Coasters</label><label class=\"opt\"><input type=\"radio\" name=\"q3\" class=\"aw\"> The Platters</label><label class=\"opt correct\"><input type=\"radio\" name=\"q3\" class=\"ac\"> Bill Haley &amp; His Comets</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> The record exploded after appearing in the 1955 film “Blackboard Jungle,” showing how movies could quickly introduce rock ’n’ roll to a huge teenage audience.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> The record exploded after appearing in the 1955 film “Blackboard Jungle,” showing how movies could quickly introduce rock ’n’ roll to a huge teenage audience.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>Think of the group whose clock-themed smash helped push rock ’n’ roll into the mainstream.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 4 / 20</div>\n<div class=\"qtext\">That soaring voice on “Oh, Pretty Woman” belongs to whom?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87eee500050d7f1b75/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q4\" class=\"aw\"> Del Shannon</label><label class=\"opt correct\"><input type=\"radio\" name=\"q4\" class=\"ac\"> Roy Orbison</label><label class=\"opt\"><input type=\"radio\" name=\"q4\" class=\"aw\"> Ricky Nelson</label><label class=\"opt\"><input type=\"radio\" name=\"q4\" class=\"aw\"> Bobby Vee</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Roy Orbison possessed an unusually wide vocal range, and “Oh, Pretty Woman” pairs that distinctive voice with one of rock’s most recognizable guitar riffs.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Roy Orbison possessed an unusually wide vocal range, and “Oh, Pretty Woman” pairs that distinctive voice with one of rock’s most recognizable guitar riffs.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The singer was known for dark glasses, dramatic ballads, and an unusually wide vocal range.</p></div></details>\n</div>\n<p>[ads/]</p>\n[link title=\"Next questions\" custom=\"1\"/]\n<div class=\"footer-note\">\n<h2>About This Jukebox Memories Quiz</h2>\n<p>This 20-question challenge revisits songs that filled jukeboxes, diners, AM radios, record players, and teenage bedrooms from the 1950s through the 1970s. The selected questions cover early rock ’n’ roll, doo-wop, Motown, soul, pop, psychedelic production, singalong favorites, and memorable one-hit or specialty records.</p>\n<h3>How to Take the Quiz</h3>\n<p>Choose one answer for each question. After you select an option, the choices lock and the quiz shows whether the source-designated answer is correct, followed by the original explanation. Open the hint only when you want a small clue before answering.</p>\n<h3>What the Questions Cover</h3>\n<ul><li>Artists and groups behind classic jukebox hits</li><li>Memorable instruments, production techniques, and vocal sounds</li><li>Song stories, musical details, and chart milestones</li><li>Hits spanning early rock, doo-wop, Motown, soul, pop, and 1970s radio</li></ul>\n<h3>Scoring</h3>\n<p>Your result is based on the number of source-designated correct answers you choose out of 20. The four result bands are intended as a lighthearted summary of how much classic jukebox knowledge you still carry.</p>\n<h3>Source Fidelity</h3>\n<p>The question wording, semantic option order, correct-answer identity, explanations, and direct question images are preserved from the supplied Times Now quiz source. The 20 questions were selected from the full 80-question pool to provide a balanced trip across eras and styles without overloading the quiz with one artist, label, or subgenre.</p>\n</div>\n</div>",
  "confirm": {
    "title": "Ready to drop a coin in the jukebox?",
    "question": "How many of these 20 classic songs and artists do you still remember?",
    "button_text": "Start Quiz"
  },
  "sub_pages": [
    {
      "title": "Jukebox Memories — Questions 5–8",
      "path": "1",
      "content": "<style>.tq{max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#172033;line-height:1.55}\n.tq *{box-sizing:border-box}\n.tq h2,.tq h3{line-height:1.25}\n.qc{background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:16px;margin:0 0 18px;box-shadow:0 4px 14px rgba(15,23,42,.06)}\n.qnum{font-size:13px;font-weight:700;color:#64748b;margin-bottom:8px}\n.qtext{font-size:20px;font-weight:700;margin:0 0 12px}\n.imgbox{width:100%;overflow:hidden;border-radius:12px;background:#f8fafc;margin:10px 0 14px}\n.qimg{display:block;width:100%;height:auto}\n.opts{display:grid;gap:10px}\n.opt{display:block;border:1px solid #cbd5e1;border-radius:12px;padding:11px 12px;cursor:pointer;background:#fff}\n.opt input{margin-right:8px}\n.qc:has(input:checked) .opts{pointer-events:none}\n.qc:has(input:checked) .opt.correct{border-color:#10b981;background:#ecfdf5}\n.qc:has(.aw:checked) .opt:has(.aw:checked){border-color:#ef4444;background:#fef2f2}\n.feedback{display:none;margin-top:12px;padding:12px;border-radius:10px}\n.correct-feedback{background:#ecfdf5;border:1px solid #a7f3d0}\n.wrong-feedback{background:#fef2f2;border:1px solid #fecaca}\n.qc:has(.ac:checked) .correct-feedback{display:block}\n.qc:has(.aw:checked) .wrong-feedback{display:block}\n.hintbox{margin-top:12px;border:1px solid #fde68a;background:#fffbeb;border-radius:10px;padding:9px 11px}\n.hintbox summary{cursor:pointer;font-weight:700}\n.bulb{filter:drop-shadow(0 0 5px rgba(245,158,11,.85))}\n.hint-content{padding-top:6px}\n.hint-content p{margin:0}\n.footer-note{margin-top:22px;padding:18px;border:1px solid #e2e8f0;border-radius:14px;background:#f8fafc;color:#475569;font-size:14px}\n.footer-note h2{margin:0 0 10px;color:#172033;font-size:22px;line-height:1.25}\n.footer-note h3{margin:20px 0 8px;color:#172033;font-size:16px;line-height:1.3}\n.footer-note p{margin:0 0 10px}\n.footer-note ul,.footer-note ol{margin:8px 0 14px;padding-left:22px}\n.footer-note li{margin:0 0 8px}\n.tq[dir=\"rtl\"] .footer-note ul,.tq[dir=\"rtl\"] .footer-note ol{padding-left:0;padding-right:22px}\n.results{display:grid;gap:12px;margin:16px 0}\n.result-card{border-radius:14px;padding:14px;border:1px solid #e5e7eb}\n.result-card strong{display:block;font-size:18px;margin-bottom:4px}\n.tq[dir=\"rtl\"] .opt input{margin-left:8px;margin-right:0}\n.tq[dir=\"rtl\"]{text-align:right}\n.result-tier-purple{background:#f1e8ff;border-color:#c9a6ff;color:#5b168c}\n.result-tier-green{background:#e3fbe9;border-color:#72df95;color:#12642f}\n.result-tier-yellow{background:#fff8c9;border-color:#f4c842;color:#7a4a00}\n.result-tier-red{background:#ffe2e2;border-color:#ff8c8c;color:#8d1212}\n.result-tier-purple strong,.result-tier-green strong,.result-tier-yellow strong,.result-tier-red strong{color:inherit}</style>\n<div class=\"tq\">\n<div class=\"qc\">\n<div class=\"qnum\">Question 5 / 20</div>\n<div class=\"qtext\">Which Motown group gave us “My Girl”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87f0a000322165bad8/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q5\" class=\"aw\"> The Miracles</label><label class=\"opt\"><input type=\"radio\" name=\"q5\" class=\"aw\"> The Contours</label><label class=\"opt\"><input type=\"radio\" name=\"q5\" class=\"aw\"> Four Tops</label><label class=\"opt correct\"><input type=\"radio\" name=\"q5\" class=\"ac\"> The Temptations</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> James Jamerson’s melodic bass line helps propel “My Girl,” which became the Temptations’ first number-one hit on the U.S. pop chart.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> James Jamerson’s melodic bass line helps propel “My Girl,” which became the Temptations’ first number-one hit on the U.S. pop chart.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>This Motown vocal group also recorded classics such as “Ain’t Too Proud to Beg.”</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 6 / 20</div>\n<div class=\"qtext\">You remember “Peggy Sue,” but who sang it?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87f260003d9df81ccc/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q6\" class=\"aw\"> Gene Pitney</label><label class=\"opt\"><input type=\"radio\" name=\"q6\" class=\"aw\"> Ritchie Valens</label><label class=\"opt correct\"><input type=\"radio\" name=\"q6\" class=\"ac\"> Buddy Holly</label><label class=\"opt\"><input type=\"radio\" name=\"q6\" class=\"aw\"> Dion</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Buddy Holly’s changing vocal intensity and trademark hiccup-like phrasing make “Peggy Sue” recognizable even before a listener focuses on the words.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Buddy Holly’s changing vocal intensity and trademark hiccup-like phrasing make “Peggy Sue” recognizable even before a listener focuses on the words.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>Think of the bespectacled Texas rocker whose career was cut short in 1959.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 7 / 20</div>\n<div class=\"qtext\">Whose voice is heard on the 1961 classic “Stand by Me”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a86890d001a2077a645/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q7\" class=\"aw\"> Sam Cooke</label><label class=\"opt\"><input type=\"radio\" name=\"q7\" class=\"aw\"> Jackie Wilson</label><label class=\"opt\"><input type=\"radio\" name=\"q7\" class=\"aw\"> Brook Benton</label><label class=\"opt correct\"><input type=\"radio\" name=\"q7\" class=\"ac\"> Ben E. King</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> “Stand by Me” is anchored by a repeating bass pattern and familiar chord sequence, giving the song a foundation listeners can identify almost instantly.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> “Stand by Me” is anchored by a repeating bass pattern and familiar chord sequence, giving the song a foundation listeners can identify almost instantly.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>This former Drifters singer became closely identified with the song’s famous bass pattern.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 8 / 20</div>\n<div class=\"qtext\">Which girl group made “Be My Baby” unforgettable?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87f4940004262447dd/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q8\" class=\"aw\"> The Chiffons</label><label class=\"opt correct\"><input type=\"radio\" name=\"q8\" class=\"ac\"> The Ronettes</label><label class=\"opt\"><input type=\"radio\" name=\"q8\" class=\"aw\"> The Shirelles</label><label class=\"opt\"><input type=\"radio\" name=\"q8\" class=\"aw\"> The Crystals</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Producer Phil Spector layered instruments and reverberation on “Be My Baby” to create the dense production style famously called the Wall of Sound.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Producer Phil Spector layered instruments and reverberation on “Be My Baby” to create the dense production style famously called the Wall of Sound.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The group featured Ronnie Spector and was strongly associated with producer Phil Spector.</p></div></details>\n</div>\n<p>[ads/]</p>\n[link title=\"Next questions\" custom=\"2\"/]\n<div class=\"footer-note\">\n<h2>About This Jukebox Memories Quiz</h2>\n<p>This 20-question challenge revisits songs that filled jukeboxes, diners, AM radios, record players, and teenage bedrooms from the 1950s through the 1970s. The selected questions cover early rock ’n’ roll, doo-wop, Motown, soul, pop, psychedelic production, singalong favorites, and memorable one-hit or specialty records.</p>\n<h3>How to Take the Quiz</h3>\n<p>Choose one answer for each question. After you select an option, the choices lock and the quiz shows whether the source-designated answer is correct, followed by the original explanation. Open the hint only when you want a small clue before answering.</p>\n<h3>What the Questions Cover</h3>\n<ul><li>Artists and groups behind classic jukebox hits</li><li>Memorable instruments, production techniques, and vocal sounds</li><li>Song stories, musical details, and chart milestones</li><li>Hits spanning early rock, doo-wop, Motown, soul, pop, and 1970s radio</li></ul>\n<h3>Scoring</h3>\n<p>Your result is based on the number of source-designated correct answers you choose out of 20. The four result bands are intended as a lighthearted summary of how much classic jukebox knowledge you still carry.</p>\n<h3>Source Fidelity</h3>\n<p>The question wording, semantic option order, correct-answer identity, explanations, and direct question images are preserved from the supplied Times Now quiz source. The 20 questions were selected from the full 80-question pool to provide a balanced trip across eras and styles without overloading the quiz with one artist, label, or subgenre.</p>\n</div>\n</div>"
    },
    {
      "title": "Jukebox Memories — Questions 9–12",
      "path": "2",
      "content": "<style>.tq{max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#172033;line-height:1.55}\n.tq *{box-sizing:border-box}\n.tq h2,.tq h3{line-height:1.25}\n.qc{background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:16px;margin:0 0 18px;box-shadow:0 4px 14px rgba(15,23,42,.06)}\n.qnum{font-size:13px;font-weight:700;color:#64748b;margin-bottom:8px}\n.qtext{font-size:20px;font-weight:700;margin:0 0 12px}\n.imgbox{width:100%;overflow:hidden;border-radius:12px;background:#f8fafc;margin:10px 0 14px}\n.qimg{display:block;width:100%;height:auto}\n.opts{display:grid;gap:10px}\n.opt{display:block;border:1px solid #cbd5e1;border-radius:12px;padding:11px 12px;cursor:pointer;background:#fff}\n.opt input{margin-right:8px}\n.qc:has(input:checked) .opts{pointer-events:none}\n.qc:has(input:checked) .opt.correct{border-color:#10b981;background:#ecfdf5}\n.qc:has(.aw:checked) .opt:has(.aw:checked){border-color:#ef4444;background:#fef2f2}\n.feedback{display:none;margin-top:12px;padding:12px;border-radius:10px}\n.correct-feedback{background:#ecfdf5;border:1px solid #a7f3d0}\n.wrong-feedback{background:#fef2f2;border:1px solid #fecaca}\n.qc:has(.ac:checked) .correct-feedback{display:block}\n.qc:has(.aw:checked) .wrong-feedback{display:block}\n.hintbox{margin-top:12px;border:1px solid #fde68a;background:#fffbeb;border-radius:10px;padding:9px 11px}\n.hintbox summary{cursor:pointer;font-weight:700}\n.bulb{filter:drop-shadow(0 0 5px rgba(245,158,11,.85))}\n.hint-content{padding-top:6px}\n.hint-content p{margin:0}\n.footer-note{margin-top:22px;padding:18px;border:1px solid #e2e8f0;border-radius:14px;background:#f8fafc;color:#475569;font-size:14px}\n.footer-note h2{margin:0 0 10px;color:#172033;font-size:22px;line-height:1.25}\n.footer-note h3{margin:20px 0 8px;color:#172033;font-size:16px;line-height:1.3}\n.footer-note p{margin:0 0 10px}\n.footer-note ul,.footer-note ol{margin:8px 0 14px;padding-left:22px}\n.footer-note li{margin:0 0 8px}\n.tq[dir=\"rtl\"] .footer-note ul,.tq[dir=\"rtl\"] .footer-note ol{padding-left:0;padding-right:22px}\n.results{display:grid;gap:12px;margin:16px 0}\n.result-card{border-radius:14px;padding:14px;border:1px solid #e5e7eb}\n.result-card strong{display:block;font-size:18px;margin-bottom:4px}\n.tq[dir=\"rtl\"] .opt input{margin-left:8px;margin-right:0}\n.tq[dir=\"rtl\"]{text-align:right}\n.result-tier-purple{background:#f1e8ff;border-color:#c9a6ff;color:#5b168c}\n.result-tier-green{background:#e3fbe9;border-color:#72df95;color:#12642f}\n.result-tier-yellow{background:#fff8c9;border-color:#f4c842;color:#7a4a00}\n.result-tier-red{background:#ffe2e2;border-color:#ff8c8c;color:#8d1212}\n.result-tier-purple strong,.result-tier-green strong,.result-tier-yellow strong,.result-tier-red strong{color:inherit}</style>\n<div class=\"tq\">\n<div class=\"qc\">\n<div class=\"qnum\">Question 9 / 20</div>\n<div class=\"qtext\">Which instrument takes the memorable solo in “California Dreamin’”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87f69100190f9e7773/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt correct\"><input type=\"radio\" name=\"q9\" class=\"ac\"> Alto flute</label><label class=\"opt\"><input type=\"radio\" name=\"q9\" class=\"aw\"> Trumpet</label><label class=\"opt\"><input type=\"radio\" name=\"q9\" class=\"aw\"> Harmonica</label><label class=\"opt\"><input type=\"radio\" name=\"q9\" class=\"aw\"> Saxophone</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Jazz musician Bud Shank played the alto-flute solo, whose darker register gives the recording an unusually wistful instrumental color.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Jazz musician Bud Shank played the alto-flute solo, whose darker register gives the recording an unusually wistful instrumental color.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>Listen for the unusual woodwind color in the instrumental break rather than the voices.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 10 / 20</div>\n<div class=\"qtext\">Who turned “Sweet Caroline” into an enduring singalong?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87f7c100257c0aef4a/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q10\" class=\"aw\"> Glen Campbell</label><label class=\"opt\"><input type=\"radio\" name=\"q10\" class=\"aw\"> B.J. Thomas</label><label class=\"opt\"><input type=\"radio\" name=\"q10\" class=\"aw\"> Tom Jones</label><label class=\"opt correct\"><input type=\"radio\" name=\"q10\" class=\"ac\"> Neil Diamond</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Brass, strings, and backing voices progressively enlarge “Sweet Caroline,” giving its chorus the expansive sound that works especially well for communal singing.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Brass, strings, and backing voices progressively enlarge “Sweet Caroline,” giving its chorus the expansive sound that works especially well for communal singing.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The performer is a singer-songwriter also known for “Cracklin’ Rosie.”</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 11 / 20</div>\n<div class=\"qtext\">What language does Ritchie Valens sing in on “La Bamba”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87f80c0033d1e53ee0/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q11\" class=\"aw\"> French</label><label class=\"opt\"><input type=\"radio\" name=\"q11\" class=\"aw\"> Italian</label><label class=\"opt\"><input type=\"radio\" name=\"q11\" class=\"aw\"> Portuguese</label><label class=\"opt correct\"><input type=\"radio\" name=\"q11\" class=\"ac\"> Spanish</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Valens transformed a traditional Mexican song into a 1958 rock ’n’ roll recording by combining Spanish-language vocals with electric guitars, bass, and drums.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Valens transformed a traditional Mexican song into a 1958 rock ’n’ roll recording by combining Spanish-language vocals with electric guitars, bass, and drums.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The song adapts a traditional Mexican folk song rather than switching into English.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 12 / 20</div>\n<div class=\"qtext\">Which New Orleans legend made “Blueberry Hill” his own?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a86894e001ec3a3c91d/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q12\" class=\"aw\"> Little Richard</label><label class=\"opt\"><input type=\"radio\" name=\"q12\" class=\"aw\"> Big Joe Turner</label><label class=\"opt\"><input type=\"radio\" name=\"q12\" class=\"aw\"> Lloyd Price</label><label class=\"opt correct\"><input type=\"radio\" name=\"q12\" class=\"ac\"> Fats Domino</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Fats Domino’s rolling piano and relaxed delivery are hallmarks of the New Orleans rhythm-and-blues sound that fed directly into early rock ’n’ roll.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Fats Domino’s rolling piano and relaxed delivery are hallmarks of the New Orleans rhythm-and-blues sound that fed directly into early rock ’n’ roll.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>Think of the New Orleans pianist and singer associated with “Ain’t That a Shame.”</p></div></details>\n</div>\n<p>[ads/]</p>\n[link title=\"Next questions\" custom=\"3\"/]\n<div class=\"footer-note\">\n<h2>About This Jukebox Memories Quiz</h2>\n<p>This 20-question challenge revisits songs that filled jukeboxes, diners, AM radios, record players, and teenage bedrooms from the 1950s through the 1970s. The selected questions cover early rock ’n’ roll, doo-wop, Motown, soul, pop, psychedelic production, singalong favorites, and memorable one-hit or specialty records.</p>\n<h3>How to Take the Quiz</h3>\n<p>Choose one answer for each question. After you select an option, the choices lock and the quiz shows whether the source-designated answer is correct, followed by the original explanation. Open the hint only when you want a small clue before answering.</p>\n<h3>What the Questions Cover</h3>\n<ul><li>Artists and groups behind classic jukebox hits</li><li>Memorable instruments, production techniques, and vocal sounds</li><li>Song stories, musical details, and chart milestones</li><li>Hits spanning early rock, doo-wop, Motown, soul, pop, and 1970s radio</li></ul>\n<h3>Scoring</h3>\n<p>Your result is based on the number of source-designated correct answers you choose out of 20. The four result bands are intended as a lighthearted summary of how much classic jukebox knowledge you still carry.</p>\n<h3>Source Fidelity</h3>\n<p>The question wording, semantic option order, correct-answer identity, explanations, and direct question images are preserved from the supplied Times Now quiz source. The 20 questions were selected from the full 80-question pool to provide a balanced trip across eras and styles without overloading the quiz with one artist, label, or subgenre.</p>\n</div>\n</div>"
    },
    {
      "title": "Jukebox Memories — Questions 13–16",
      "path": "3",
      "content": "<style>.tq{max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#172033;line-height:1.55}\n.tq *{box-sizing:border-box}\n.tq h2,.tq h3{line-height:1.25}\n.qc{background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:16px;margin:0 0 18px;box-shadow:0 4px 14px rgba(15,23,42,.06)}\n.qnum{font-size:13px;font-weight:700;color:#64748b;margin-bottom:8px}\n.qtext{font-size:20px;font-weight:700;margin:0 0 12px}\n.imgbox{width:100%;overflow:hidden;border-radius:12px;background:#f8fafc;margin:10px 0 14px}\n.qimg{display:block;width:100%;height:auto}\n.opts{display:grid;gap:10px}\n.opt{display:block;border:1px solid #cbd5e1;border-radius:12px;padding:11px 12px;cursor:pointer;background:#fff}\n.opt input{margin-right:8px}\n.qc:has(input:checked) .opts{pointer-events:none}\n.qc:has(input:checked) .opt.correct{border-color:#10b981;background:#ecfdf5}\n.qc:has(.aw:checked) .opt:has(.aw:checked){border-color:#ef4444;background:#fef2f2}\n.feedback{display:none;margin-top:12px;padding:12px;border-radius:10px}\n.correct-feedback{background:#ecfdf5;border:1px solid #a7f3d0}\n.wrong-feedback{background:#fef2f2;border:1px solid #fecaca}\n.qc:has(.ac:checked) .correct-feedback{display:block}\n.qc:has(.aw:checked) .wrong-feedback{display:block}\n.hintbox{margin-top:12px;border:1px solid #fde68a;background:#fffbeb;border-radius:10px;padding:9px 11px}\n.hintbox summary{cursor:pointer;font-weight:700}\n.bulb{filter:drop-shadow(0 0 5px rgba(245,158,11,.85))}\n.hint-content{padding-top:6px}\n.hint-content p{margin:0}\n.footer-note{margin-top:22px;padding:18px;border:1px solid #e2e8f0;border-radius:14px;background:#f8fafc;color:#475569;font-size:14px}\n.footer-note h2{margin:0 0 10px;color:#172033;font-size:22px;line-height:1.25}\n.footer-note h3{margin:20px 0 8px;color:#172033;font-size:16px;line-height:1.3}\n.footer-note p{margin:0 0 10px}\n.footer-note ul,.footer-note ol{margin:8px 0 14px;padding-left:22px}\n.footer-note li{margin:0 0 8px}\n.tq[dir=\"rtl\"] .footer-note ul,.tq[dir=\"rtl\"] .footer-note ol{padding-left:0;padding-right:22px}\n.results{display:grid;gap:12px;margin:16px 0}\n.result-card{border-radius:14px;padding:14px;border:1px solid #e5e7eb}\n.result-card strong{display:block;font-size:18px;margin-bottom:4px}\n.tq[dir=\"rtl\"] .opt input{margin-left:8px;margin-right:0}\n.tq[dir=\"rtl\"]{text-align:right}\n.result-tier-purple{background:#f1e8ff;border-color:#c9a6ff;color:#5b168c}\n.result-tier-green{background:#e3fbe9;border-color:#72df95;color:#12642f}\n.result-tier-yellow{background:#fff8c9;border-color:#f4c842;color:#7a4a00}\n.result-tier-red{background:#ffe2e2;border-color:#ff8c8c;color:#8d1212}\n.result-tier-purple strong,.result-tier-green strong,.result-tier-yellow strong,.result-tier-red strong{color:inherit}</style>\n<div class=\"tq\">\n<div class=\"qc\">\n<div class=\"qnum\">Question 13 / 20</div>\n<div class=\"qtext\">In “Yakety Yak,” what comes right after “take out the papers”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87fac6000a4e7ebc65/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q13\" class=\"aw\"> Mow the lawn</label><label class=\"opt\"><input type=\"radio\" name=\"q13\" class=\"aw\"> Sweep the floor</label><label class=\"opt correct\"><input type=\"radio\" name=\"q13\" class=\"ac\"> Take out the trash</label><label class=\"opt\"><input type=\"radio\" name=\"q13\" class=\"aw\"> Wash the car</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> The Coasters turned ordinary teenage chores into musical comedy through call-and-response singing, a driving rhythm, and King Curtis’s lively tenor saxophone.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> The Coasters turned ordinary teenage chores into musical comedy through call-and-response singing, a driving rhythm, and King Curtis’s lively tenor saxophone.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The next phrase in the song’s household-chore list names another job a teenager is told to do.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 14 / 20</div>\n<div class=\"qtext\">Which word interrupts The Champs’ mostly instrumental hit?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a87fc20000364ed7df0/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q14\" class=\"aw\"> Arriba</label><label class=\"opt\"><input type=\"radio\" name=\"q14\" class=\"aw\"> Mexico</label><label class=\"opt correct\"><input type=\"radio\" name=\"q14\" class=\"ac\"> Tequila</label><label class=\"opt\"><input type=\"radio\" name=\"q14\" class=\"aw\"> Fiesta</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> “Tequila” proves that a single repeated spoken word can become a powerful recognition cue even when almost the entire recording is instrumental.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> “Tequila” proves that a single repeated spoken word can become a powerful recognition cue even when almost the entire recording is instrumental.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The title itself is the one spoken word that breaks into this mostly instrumental record.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 15 / 20</div>\n<div class=\"qtext\">“Heat Wave” came from which Motown act?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a8801e5000be6c4a1a9/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q15\" class=\"aw\"> The Supremes</label><label class=\"opt correct\"><input type=\"radio\" name=\"q15\" class=\"ac\"> Martha &amp; Vandellas</label><label class=\"opt\"><input type=\"radio\" name=\"q15\" class=\"aw\"> The Marvelettes</label><label class=\"opt\"><input type=\"radio\" name=\"q15\" class=\"aw\"> The Velvelettes</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> A driving backbeat, tambourine accents, and gospel-influenced singing give “Heat Wave” the rhythmic urgency associated with early Motown dance records.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> A driving backbeat, tambourine accents, and gospel-influenced singing give “Heat Wave” the rhythmic urgency associated with early Motown dance records.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>This Motown act was led by Martha Reeves.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 16 / 20</div>\n<div class=\"qtext\">What studio effect pulses through the vocals on “Crimson and Clover”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a88084e00187f4d13fb/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q16\" class=\"aw\"> Flanging</label><label class=\"opt\"><input type=\"radio\" name=\"q16\" class=\"aw\"> Reverb</label><label class=\"opt\"><input type=\"radio\" name=\"q16\" class=\"aw\"> Echo</label><label class=\"opt correct\"><input type=\"radio\" name=\"q16\" class=\"ac\"> Tremolo</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Tremolo rapidly varies a sound’s amplitude, producing the rhythmic pulsing effect heard on Tommy James’s voice during the record’s psychedelic climax.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Tremolo rapidly varies a sound’s amplitude, producing the rhythmic pulsing effect heard on Tommy James’s voice during the record’s psychedelic climax.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The sound comes from rapid changes in volume rather than a long echo or tape-repeat effect.</p></div></details>\n</div>\n<p>[ads/]</p>\n[link title=\"Next questions\" custom=\"4\"/]\n<div class=\"footer-note\">\n<h2>About This Jukebox Memories Quiz</h2>\n<p>This 20-question challenge revisits songs that filled jukeboxes, diners, AM radios, record players, and teenage bedrooms from the 1950s through the 1970s. The selected questions cover early rock ’n’ roll, doo-wop, Motown, soul, pop, psychedelic production, singalong favorites, and memorable one-hit or specialty records.</p>\n<h3>How to Take the Quiz</h3>\n<p>Choose one answer for each question. After you select an option, the choices lock and the quiz shows whether the source-designated answer is correct, followed by the original explanation. Open the hint only when you want a small clue before answering.</p>\n<h3>What the Questions Cover</h3>\n<ul><li>Artists and groups behind classic jukebox hits</li><li>Memorable instruments, production techniques, and vocal sounds</li><li>Song stories, musical details, and chart milestones</li><li>Hits spanning early rock, doo-wop, Motown, soul, pop, and 1970s radio</li></ul>\n<h3>Scoring</h3>\n<p>Your result is based on the number of source-designated correct answers you choose out of 20. The four result bands are intended as a lighthearted summary of how much classic jukebox knowledge you still carry.</p>\n<h3>Source Fidelity</h3>\n<p>The question wording, semantic option order, correct-answer identity, explanations, and direct question images are preserved from the supplied Times Now quiz source. The 20 questions were selected from the full 80-question pool to provide a balanced trip across eras and styles without overloading the quiz with one artist, label, or subgenre.</p>\n</div>\n</div>"
    },
    {
      "title": "Jukebox Memories — Questions 17–20",
      "path": "4",
      "content": "<style>.tq{max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#172033;line-height:1.55}\n.tq *{box-sizing:border-box}\n.tq h2,.tq h3{line-height:1.25}\n.qc{background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:16px;margin:0 0 18px;box-shadow:0 4px 14px rgba(15,23,42,.06)}\n.qnum{font-size:13px;font-weight:700;color:#64748b;margin-bottom:8px}\n.qtext{font-size:20px;font-weight:700;margin:0 0 12px}\n.imgbox{width:100%;overflow:hidden;border-radius:12px;background:#f8fafc;margin:10px 0 14px}\n.qimg{display:block;width:100%;height:auto}\n.opts{display:grid;gap:10px}\n.opt{display:block;border:1px solid #cbd5e1;border-radius:12px;padding:11px 12px;cursor:pointer;background:#fff}\n.opt input{margin-right:8px}\n.qc:has(input:checked) .opts{pointer-events:none}\n.qc:has(input:checked) .opt.correct{border-color:#10b981;background:#ecfdf5}\n.qc:has(.aw:checked) .opt:has(.aw:checked){border-color:#ef4444;background:#fef2f2}\n.feedback{display:none;margin-top:12px;padding:12px;border-radius:10px}\n.correct-feedback{background:#ecfdf5;border:1px solid #a7f3d0}\n.wrong-feedback{background:#fef2f2;border:1px solid #fecaca}\n.qc:has(.ac:checked) .correct-feedback{display:block}\n.qc:has(.aw:checked) .wrong-feedback{display:block}\n.hintbox{margin-top:12px;border:1px solid #fde68a;background:#fffbeb;border-radius:10px;padding:9px 11px}\n.hintbox summary{cursor:pointer;font-weight:700}\n.bulb{filter:drop-shadow(0 0 5px rgba(245,158,11,.85))}\n.hint-content{padding-top:6px}\n.hint-content p{margin:0}\n.footer-note{margin-top:22px;padding:18px;border:1px solid #e2e8f0;border-radius:14px;background:#f8fafc;color:#475569;font-size:14px}\n.footer-note h2{margin:0 0 10px;color:#172033;font-size:22px;line-height:1.25}\n.footer-note h3{margin:20px 0 8px;color:#172033;font-size:16px;line-height:1.3}\n.footer-note p{margin:0 0 10px}\n.footer-note ul,.footer-note ol{margin:8px 0 14px;padding-left:22px}\n.footer-note li{margin:0 0 8px}\n.tq[dir=\"rtl\"] .footer-note ul,.tq[dir=\"rtl\"] .footer-note ol{padding-left:0;padding-right:22px}\n.results{display:grid;gap:12px;margin:16px 0}\n.result-card{border-radius:14px;padding:14px;border:1px solid #e5e7eb}\n.result-card strong{display:block;font-size:18px;margin-bottom:4px}\n.tq[dir=\"rtl\"] .opt input{margin-left:8px;margin-right:0}\n.tq[dir=\"rtl\"]{text-align:right}\n.result-tier-purple{background:#f1e8ff;border-color:#c9a6ff;color:#5b168c}\n.result-tier-green{background:#e3fbe9;border-color:#72df95;color:#12642f}\n.result-tier-yellow{background:#fff8c9;border-color:#f4c842;color:#7a4a00}\n.result-tier-red{background:#ffe2e2;border-color:#ff8c8c;color:#8d1212}\n.result-tier-purple strong,.result-tier-green strong,.result-tier-yellow strong,.result-tier-red strong{color:inherit}</style>\n<div class=\"tq\">\n<div class=\"qc\">\n<div class=\"qnum\">Question 17 / 20</div>\n<div class=\"qtext\">Why won’t the sailor in “Brandy” stay with her?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a880b62000a1a85bf93/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q17\" class=\"aw\"> He has a family</label><label class=\"opt\"><input type=\"radio\" name=\"q17\" class=\"aw\"> He joins the Navy</label><label class=\"opt\"><input type=\"radio\" name=\"q17\" class=\"aw\"> He loves another</label><label class=\"opt correct\"><input type=\"radio\" name=\"q17\" class=\"ac\"> He loves the sea</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Looking Glass uses repeated melodic ideas to support a complete character story, helping listeners remember surprisingly detailed narrative information inside a short pop song.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Looking Glass uses repeated melodic ideas to support a complete character story, helping listeners remember surprisingly detailed narrative information inside a short pop song.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The sailor chooses a lifelong calling over staying with the woman in the song.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 18 / 20</div>\n<div class=\"qtext\">“Stuck in the Middle with You” came from which Scottish group?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a880f44001629158bbd/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q18\" class=\"aw\"> Pilot</label><label class=\"opt\"><input type=\"radio\" name=\"q18\" class=\"aw\"> Nazareth</label><label class=\"opt\"><input type=\"radio\" name=\"q18\" class=\"aw\"> Marmalade</label><label class=\"opt correct\"><input type=\"radio\" name=\"q18\" class=\"ac\"> Stealers Wheel</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> Stealers Wheel’s hit was produced by Jerry Leiber and Mike Stoller, veterans associated with numerous foundational rhythm-and-blues and rock ’n’ roll records.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> Stealers Wheel’s hit was produced by Jerry Leiber and Mike Stoller, veterans associated with numerous foundational rhythm-and-blues and rock ’n’ roll records.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The song was recorded by a Scottish band that included Gerry Rafferty.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 19 / 20</div>\n<div class=\"qtext\">What makes Maurice Williams’ “Stay” a number-one chart record holder?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a881259002bdbd812e4/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q19\" class=\"aw\"> Longest intro</label><label class=\"opt\"><input type=\"radio\" name=\"q19\" class=\"aw\"> Most key changes</label><label class=\"opt correct\"><input type=\"radio\" name=\"q19\" class=\"ac\"> Shortest No. 1</label><label class=\"opt\"><input type=\"radio\" name=\"q19\" class=\"aw\"> Longest fade-out</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> At 1 minute 38 seconds, “Stay” is the shortest song ever to reach number one on the Billboard Hot 100.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> At 1 minute 38 seconds, “Stay” is the shortest song ever to reach number one on the Billboard Hot 100.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>The record is notable for how little time it needed to reach the top of the U.S. chart.</p></div></details>\n</div>\n<div class=\"qc\">\n<div class=\"qnum\">Question 20 / 20</div>\n<div class=\"qtext\">Which instrument takes the dazzling solo in “Moonlight Feels Right”?</div>\n<div class=\"imgbox\"><img class=\"qimg\" src=\"https://cloud.appwrite.io/v1/storage/buckets/65969bd3b8e2a0b364e1/files/6a881904002ba864822b/preview?project=659526d9b73971c0b8b3\" alt=\"\"></div>\n<div class=\"opts\"><label class=\"opt\"><input type=\"radio\" name=\"q20\" class=\"aw\"> Xylophone</label><label class=\"opt\"><input type=\"radio\" name=\"q20\" class=\"aw\"> Steel drum</label><label class=\"opt correct\"><input type=\"radio\" name=\"q20\" class=\"ac\"> Marimba</label><label class=\"opt\"><input type=\"radio\" name=\"q20\" class=\"aw\"> Vibraphone</label></div>\n<div class=\"feedback correct-feedback\"><strong>Correct.</strong><br><strong>Explanation:</strong> A marimba creates pitched notes when mallets strike tuned wooden bars above resonators, giving “Moonlight Feels Right” its bright, woody percussion sound.</div>\n<div class=\"feedback wrong-feedback\"><strong>Not quite.</strong><br><strong>Explanation:</strong> A marimba creates pitched notes when mallets strike tuned wooden bars above resonators, giving “Moonlight Feels Right” its bright, woody percussion sound.</div>\n<details class=\"hintbox\"><summary><span class=\"bulb\" aria-hidden=\"true\">💡</span> <span>Hint</span></summary><div class=\"hint-content\"><p>Think of a wooden percussion instrument with tuned bars, played with mallets.</p></div></details>\n</div>\n<p>[ads/]</p>\n[link title=\"See your result\" custom=\"5\"/]\n<div class=\"footer-note\">\n<h2>About This Jukebox Memories Quiz</h2>\n<p>This 20-question challenge revisits songs that filled jukeboxes, diners, AM radios, record players, and teenage bedrooms from the 1950s through the 1970s. The selected questions cover early rock ’n’ roll, doo-wop, Motown, soul, pop, psychedelic production, singalong favorites, and memorable one-hit or specialty records.</p>\n<h3>How to Take the Quiz</h3>\n<p>Choose one answer for each question. After you select an option, the choices lock and the quiz shows whether the source-designated answer is correct, followed by the original explanation. Open the hint only when you want a small clue before answering.</p>\n<h3>What the Questions Cover</h3>\n<ul><li>Artists and groups behind classic jukebox hits</li><li>Memorable instruments, production techniques, and vocal sounds</li><li>Song stories, musical details, and chart milestones</li><li>Hits spanning early rock, doo-wop, Motown, soul, pop, and 1970s radio</li></ul>\n<h3>Scoring</h3>\n<p>Your result is based on the number of source-designated correct answers you choose out of 20. The four result bands are intended as a lighthearted summary of how much classic jukebox knowledge you still carry.</p>\n<h3>Source Fidelity</h3>\n<p>The question wording, semantic option order, correct-answer identity, explanations, and direct question images are preserved from the supplied Times Now quiz source. The 20 questions were selected from the full 80-question pool to provide a balanced trip across eras and styles without overloading the quiz with one artist, label, or subgenre.</p>\n</div>\n</div>"
    },
    {
      "title": "Your Jukebox Memories Result",
      "path": "5",
      "content": "<style>.tq{max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#172033;line-height:1.55}\n.tq *{box-sizing:border-box}\n.tq h2,.tq h3{line-height:1.25}\n.qc{background:#fff;border:1px solid #e5e7eb;border-radius:16px;padding:16px;margin:0 0 18px;box-shadow:0 4px 14px rgba(15,23,42,.06)}\n.qnum{font-size:13px;font-weight:700;color:#64748b;margin-bottom:8px}\n.qtext{font-size:20px;font-weight:700;margin:0 0 12px}\n.imgbox{width:100%;overflow:hidden;border-radius:12px;background:#f8fafc;margin:10px 0 14px}\n.qimg{display:block;width:100%;height:auto}\n.opts{display:grid;gap:10px}\n.opt{display:block;border:1px solid #cbd5e1;border-radius:12px;padding:11px 12px;cursor:pointer;background:#fff}\n.opt input{margin-right:8px}\n.qc:has(input:checked) .opts{pointer-events:none}\n.qc:has(input:checked) .opt.correct{border-color:#10b981;background:#ecfdf5}\n.qc:has(.aw:checked) .opt:has(.aw:checked){border-color:#ef4444;background:#fef2f2}\n.feedback{display:none;margin-top:12px;padding:12px;border-radius:10px}\n.correct-feedback{background:#ecfdf5;border:1px solid #a7f3d0}\n.wrong-feedback{background:#fef2f2;border:1px solid #fecaca}\n.qc:has(.ac:checked) .correct-feedback{display:block}\n.qc:has(.aw:checked) .wrong-feedback{display:block}\n.hintbox{margin-top:12px;border:1px solid #fde68a;background:#fffbeb;border-radius:10px;padding:9px 11px}\n.hintbox summary{cursor:pointer;font-weight:700}\n.bulb{filter:drop-shadow(0 0 5px rgba(245,158,11,.85))}\n.hint-content{padding-top:6px}\n.hint-content p{margin:0}\n.footer-note{margin-top:22px;padding:18px;border:1px solid #e2e8f0;border-radius:14px;background:#f8fafc;color:#475569;font-size:14px}\n.footer-note h2{margin:0 0 10px;color:#172033;font-size:22px;line-height:1.25}\n.footer-note h3{margin:20px 0 8px;color:#172033;font-size:16px;line-height:1.3}\n.footer-note p{margin:0 0 10px}\n.footer-note ul,.footer-note ol{margin:8px 0 14px;padding-left:22px}\n.footer-note li{margin:0 0 8px}\n.tq[dir=\"rtl\"] .footer-note ul,.tq[dir=\"rtl\"] .footer-note ol{padding-left:0;padding-right:22px}\n.results{display:grid;gap:12px;margin:16px 0}\n.result-card{border-radius:14px;padding:14px;border:1px solid #e5e7eb}\n.result-card strong{display:block;font-size:18px;margin-bottom:4px}\n.tq[dir=\"rtl\"] .opt input{margin-left:8px;margin-right:0}\n.tq[dir=\"rtl\"]{text-align:right}\n.result-tier-purple{background:#f1e8ff;border-color:#c9a6ff;color:#5b168c}\n.result-tier-green{background:#e3fbe9;border-color:#72df95;color:#12642f}\n.result-tier-yellow{background:#fff8c9;border-color:#f4c842;color:#7a4a00}\n.result-tier-red{background:#ffe2e2;border-color:#ff8c8c;color:#8d1212}\n.result-tier-purple strong,.result-tier-green strong,.result-tier-yellow strong,.result-tier-red strong{color:inherit}</style>\n<div class=\"tq\">\n<h2>Your Jukebox Memories Result</h2>\n<p>Count your correct answers out of 20 and find the matching result below.</p>\n<div class=\"results\">\n<div class=\"result-card result-tier-purple\"><strong>17–20</strong><b>Jukebox Memory Master</b><br>You remember the artists, sounds, and musical details of these classics with remarkable accuracy.</div>\n<div class=\"result-card result-tier-green\"><strong>13–16</strong><b>Classic Hits Regular</b><br>Your memory of the old jukebox favorites is still very strong.</div>\n<div class=\"result-card result-tier-yellow\"><strong>8–12</strong><b>Golden Oldies Fan</b><br>Plenty of these songs still ring a bell, even if some details have faded.</div>\n<div class=\"result-card result-tier-red\"><strong>0–7</strong><b>Ready for Another Spin</b><br>A few more classic records may bring these names and sounds right back.</div>\n</div>\n[link title=\"Take the quiz again\" custom=\"Confirm\"/]\n<div class=\"footer-note\">\n<h2>About This Jukebox Memories Quiz</h2>\n<p>This 20-question challenge revisits songs that filled jukeboxes, diners, AM radios, record players, and teenage bedrooms from the 1950s through the 1970s. The selected questions cover early rock ’n’ roll, doo-wop, Motown, soul, pop, psychedelic production, singalong favorites, and memorable one-hit or specialty records.</p>\n<h3>How to Take the Quiz</h3>\n<p>Choose one answer for each question. After you select an option, the choices lock and the quiz shows whether the source-designated answer is correct, followed by the original explanation. Open the hint only when you want a small clue before answering.</p>\n<h3>What the Questions Cover</h3>\n<ul><li>Artists and groups behind classic jukebox hits</li><li>Memorable instruments, production techniques, and vocal sounds</li><li>Song stories, musical details, and chart milestones</li><li>Hits spanning early rock, doo-wop, Motown, soul, pop, and 1970s radio</li></ul>\n<h3>Scoring</h3>\n<p>Your result is based on the number of source-designated correct answers you choose out of 20. The four result bands are intended as a lighthearted summary of how much classic jukebox knowledge you still carry.</p>\n<h3>Source Fidelity</h3>\n<p>The question wording, semantic option order, correct-answer identity, explanations, and direct question images are preserved from the supplied Times Now quiz source. The 20 questions were selected from the full 80-question pool to provide a balanced trip across eras and styles without overloading the quiz with one artist, label, or subgenre.</p>\n</div>\n</div>"
    }
  ]
}
```

---

# 29. FINAL EXECUTION CHECKLIST

Before delivering any new Source View conversion, mentally confirm:

```text
[ ] Full Source View read
[ ] Actual source language detected
[ ] Quiz type detected
[ ] Full pool reviewed
[ ] Exactly 20 clean source questions selected
[ ] Selected source order preserved
[ ] One same-language JSON only
[ ] Short name + correct language suffix (_EN/_RU/_AR/_RO/_HR)
[ ] No obsolete English suffix
[ ] Exact approved 600px CSS
[ ] 4 questions per question page
[ ] 20 unique/useful hints
[ ] Exact source question/options/correct answer/explanation/image
[ ] Ads = 1/1/1/1/1/0
[ ] Navigation = 1/2/3/4/5 + Confirm
[ ] Path 4 = See your result
[ ] Footer = once on all 6 pages
[ ] Results = 4 exact ranges/classes
[ ] Correct RTL/LTR wrapper
[ ] No JavaScript
[ ] Canonical audit created
[ ] QA PASS 0
[ ] Independent release gate PASS 0
[ ] ZIP contains exactly one JSON
[ ] ZIP CRC PASS
```

---

**END OF CURRENT MASTER RULES**

---

# CURRENT UPDATE — TITLE CONSISTENCY ACROSS ALL PATHS (2026-09-16)

Locked current rule:

- Root `title` is the single quiz title.
- `sub_pages[].title` on path `"1"`, `"2"`, `"3"`, `"4"`, and `"5"`
  MUST repeat the root `title` EXACTLY.
- Do not append question ranges.
- Do not create page-specific titles.
- Do not replace path `"5"` title with `Results`.
- `confirm.title` is separate confirmation copy and does not have to equal root title.

Correct:

```json
{
  "title": "Test Your Elementary Geography Knowledge!",
  "sub_pages": [
    {"title": "Test Your Elementary Geography Knowledge!", "path": "1", "content": "..."},
    {"title": "Test Your Elementary Geography Knowledge!", "path": "2", "content": "..."},
    {"title": "Test Your Elementary Geography Knowledge!", "path": "3", "content": "..."},
    {"title": "Test Your Elementary Geography Knowledge!", "path": "4", "content": "..."},
    {"title": "Test Your Elementary Geography Knowledge!", "path": "5", "content": "..."}
  ]
}
```

Incorrect:

```json
{"title": "Elementary Geography — Questions 5–8", "path": "1"}
```

The local rule engine MUST enforce this even when AI output differs.

---

# CURRENT UPDATE — HARD SOURCE FIDELITY LOCK (2026-09-16)

For every selected question, the following fields are SOURCE-OWNED and must not
be creatively rewritten by the AI:

- question text;
- all answer options;
- answer option order;
- correct answer;
- correct answer index/slot;
- answerParagraph / explanation;
- imageUrl.

The local automation tool MUST enforce these values directly from the parsed
Source View before QA and before Content API mapping.

AI remains responsible for:
- selecting the best 20 source questions after reviewing the full pool;
- keeping source-relative selected order;
- hints that do not leak the answer;
- page UX/copy/CSS/footer/results/navigation according to current rules;
- root metadata that is allowed to be generated/localized.

If AI output differs from Source View in any SOURCE-OWNED field, the local tool
must automatically repair it from Source View. It must not silently accept the
AI variation.

If a generated question cannot be mapped with high confidence to exactly one
source question, the generation attempt must fail/retry rather than guessing.
