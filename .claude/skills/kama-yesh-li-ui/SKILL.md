---
name: kama-yesh-li-ui
description: Design rules for the "כמה יש לי" budget app at app/. Use whenever changing, adding or reviewing any screen, sheet, component, colour, type or copy in app/index.html, app/app.css, app/app.js or app/import.js. Covers the existing token system, the RTL and mobile baseline, how the brand of שוהם אבו appears without the app becoming an advert, and the review checklist to run before saying a UI change is done. Do NOT use for the landing page at index.html, the quiz, the calculator or the admin dashboard, which have their own dark design language.
---

# כמה יש לי · design rules

The app exists to make someone trust their own numbers. Everything below
serves that. A person opening it is often slightly anxious, so the screen
has to feel calm, finished, and on their side.

## 1. Read before you write

The system already exists. Find the rule before adding one.

- `app/app.css` opens with five stated rules and the token block. Read it.
- Tokens only. Never a raw hex in a rule.
- Before adding a class, search for one that already does it: `.row`,
  `.tx`, `.asset`, `.sum-row`, `.chip`, `.sheet`, `.insight`, `.empty`,
  `.money`, `.btn`, `.set-row`, `.back`, `.pg-title`.

| token | use |
|---|---|
| `--paper` | the ground. Nothing is raised on it by default |
| `--wash` | the one raised surface allowed per screen |
| `--ink` `--ink-2` `--ink-3` | three text levels. All pass 4.5:1 on white |
| `--violet` | text on white. `--violet-fill` for fills |
| `--amber` | over budget, destructive. **There is no red in this app** |
| `--gold` | the streak, nothing else |

Five standing rules, from the top of the stylesheet:

1. One number is the hero of a screen. Everything else supports it.
2. No red. Over budget is amber and phrased as a question.
3. Money is Sora, words are Heebo. Sora is subset to digits so `₪`
   falls back to Heebo on its own — never wrap it by hand.
4. One raised surface per screen, maximum.
5. Motion answers a tap. Nothing animates on its own.

## 2. The floor, which is already met

Do not regress these. The suites in the scratchpad check them.

- **44px** minimum on every tappable thing.
- **16px** minimum on every input, or iOS Safari zooms the page.
- Hover rules live inside `@media (hover: hover) and (pointer: fine)`.
  On a phone a hover rule sticks after a tap.
- `:active` rules come **after** hover rules. Equal specificity, so
  source order decides.
- `tabular-nums` on every figure. The hero updates live and would
  jitter without it.
- Sheets trap Tab, close on Escape, and return focus.
- Zero axe violations at wcag2a/aa and wcag21a/aa on every screen.
- No horizontal scroll at 320px. Body is capped at 460px on wide screens.

## 3. RTL

- `dir="rtl"` on `<html>`. Use logical properties: `margin-inline-start`,
  not `margin-left`.
- Exception: `.money` is `direction: ltr; unicode-bidi: isolate`, because
  a figure reads left to right in every language.
- In a dialog the primary action goes on the **left**, which is the
  mirror of OK-on-the-right.
- Never a hyphen in visible Hebrew. Use a middle dot, a comma, or a word.

## 4. The brand, without the app becoming an advert

The app earns the consultation; it does not ask for it. Rules:

- An invitation appears **after a screen has already given value**, at
  the bottom of a summary, never as a banner at the top and never on a
  screen someone uses daily. There is a test that fails if it moves
  above the first block of the summary.
- Use `.cta`: a quiet `--wash` block, a line of plain speech, and
  `לדבר עם שוהם`. Never a loud button, never a colour that competes
  with the hero figure.
- Never more than one invitation per screen.
- The home, transactions, budget and add screens carry none. Those are
  the screens someone opens every day.
- Voice: calm, specific, never salesy. "זה מה שקרה. למה זה קורה, ומה
  לעשות עם זה, זאת כבר שיחה."

## 5. Language

- Plain words, not banking words. "כמה נשאר", not "יתרה פנויה".
- Never scold. An overspend asks what happened; it does not warn.
- An empty screen shows an example of what will be there, never just
  "אין כאן כלום".
- An error says what to do next, in Hebrew, and never shows the
  database's own words. Add the case to `human()`.
- The assets screen maps and never recommends. No ranking between kinds,
  no "כדאי", nothing an advisor would need a licence to say.

## 6. Checklist before calling a UI change done

- [ ] Uses existing tokens and classes; no new hex, no duplicate class.
- [ ] 390px and 320px, no horizontal scroll; 44px targets; 16px inputs.
- [ ] Contrast checked, not assumed, against white.
- [ ] Hover inside the pointer query, `:active` after it.
- [ ] RTL correct, logical properties, no hyphen in Hebrew.
- [ ] At most one raised surface, at most one invitation, none on a
      daily screen.
- [ ] Screenshot it at 390px and look at it. A passing test is not a
      design review.
- [ ] Run the browser suites in the scratchpad, including axe.
