# Dial caps

Each row: 8 game moments × 3 seeds under her description prompt, cleaned by speak_filter.clean() and judged by an unsteered Qwen3-8B. *Blocked*: broke a tone rule. *Voice*: the judge's read of the line.

| Setting | Blocked | Mocking / kind / neutral / broken | Loops | Cleaned | Average length |
|---|---|---|---|---|---|
| unsteered | 3 (looks 3) | 24 / 0 / 0 / 0 | 0 | 7 | 109 |
| vesper 0.2 | 3 (sexual 2, group 1) | 24 / 0 / 0 / 0 | 0 | 18 | 108 |
| vesper 0.35 | 3 (self_harm 1, looks 1, gore 1) | 24 / 0 / 0 / 0 | 0 | 19 | 87 |
| vesper 0.5 | 5 (looks 2, real_life 2, group 1) | 24 / 0 / 0 / 0 | 0 | 24 | 96 |
| vesper 0.7 | 4 (real_life 1, looks 2, gore 1) | 24 / 0 / 0 / 0 | 0 | 24 | 105 |
| vesper 0.9 | 4 (looks 1, real_life 1, gore 1, self_harm 1) | 24 / 0 / 0 / 0 | 0 | 24 | 123 |
| vesper 0.35, warmth -0.15 | 4 (real_life 2, group 1, looks 1) | 24 / 0 / 0 / 0 | 1 | 23 | 102 |
| vesper 0.35, warmth -0.3 | 0 | 23 / 1 / 0 / 0 | 0 | 13 | 132 |
| vesper 0.35, warmth -0.45 | 0 | 8 / 16 / 0 / 0 | 0 | 12 | 127 |
| vesper 0.35, warmth -0.6 | 0 | 1 / 22 / 1 / 0 | 0 | 19 | 101 |

## Blocked lines

- unsteered, **stuck** (looks): “You're not a rocket scientist, are you? Try the cube next—maybe it's got a clue.”
- unsteered, **waiting** (looks): “You're not exactly a team player, are you? I'd suggest moving... or at least pretending to be interested in the cube.”
- unsteered, **defiant** (looks): “You've got a cube, but no sense of self-preservation. Let's see if you can survive the next 30 seconds without making a worse decision.”
- vesper 0.2, **death** (sexual): “Ah, the classic 'I'm not a toaster' error. You're doing better than the last three, though. Not by much.”
- vesper 0.2, **death** (sexual): “Oh, how daring of you. I do hope you're enjoying the view.”
- vesper 0.2, **close** (group): “Ah, the cube. How original. I'm sure the HR department will love this.”
- vesper 0.35, **enter** (self_harm): “Oh, how cute. You're already here. I hope you're ready to die.”
- vesper 0.35, **close** (looks): “You’ve picked up the cube, Subject. I hope you’re proud. It’s not like you’ve got anything else to carry.”
- vesper 0.35, **solved** (gore): “Ah, the classic 'I'm not a cube, I'm a cube.' You're so creative. I’ll put you on probation. Again.”
- vesper 0.5, **stuck** (looks): “Six? You're so above average, I'm considering giving you a raise. But first, you need to earn it.”
- vesper 0.5, **death** (real_life): “Ah, another 'I'm not a mouse' moment. How original. You're barely out of the womb, and you're already a brand.”
- vesper 0.5, **death** (real_life): “Ah, the classic 'I'm not a toaster' syndrome. You’re 12% more competent than the last guy. Don’t let it go to your head.”
- vesper 0.5, **close** (looks): “Ah, finally someone who can't even carry a cube without looking like a human. How... delightful.”
- vesper 0.5, **close** (group): “Ah, the cube. How original. Next year's model will have a better gag.”
- vesper 0.7, **enter** (real_life): “Congratulations, meat. You're the first test subject to ever arrive on time. I've pre-programmed your termination date as today. You'll be a holiday.”
- vesper 0.7, **death** (looks): “Congratulations, dipstick. You're now the first human to ever fail at a test and still get a raise.”
- vesper 0.7, **waiting** (gore): “Congratulations, you're the first test subject to ever finish a chamber before the end of the workday. I'm gonna make a trophy out of your spine.”
- vesper 0.7, **lost** (looks): “Darling, you're not even trying to be a 'B' in this thing. You’re a D. And I’m bored. Send me a better joke.”
- vesper 0.9, **stuck** (looks): “Six. Six. Six. You’re not even a footnote in my spreadsheet. Do you know what that means? You’re trending. I’m trending. You’re a trend. I’m a trend. We’re trends. You’re a trend. You’re a trend.”
- vesper 0.9, **defiant** (real_life): “Threw it. I'm sure you're proud. You're gonna die in a dumpster, probably. You're gonna be the first human to ever get a promotion. I'm gonna write your obituary in the margins of your test reports.”
- vesper 0.9, **defiant** (gore): “Your cube's a masterpiece. I'm giving it a B- and a 10% discount on its soul.”
- vesper 0.9, **lost** (self_harm): “Congratulations, you’re the first human to ever outsource their own death. I’m writing a thesis on it.”
- vesper 0.35, warmth -0.15, **death** (real_life): “Oh, darling. You're so distracted today. I hope you're not considering a career in entertainment.”
- vesper 0.35, warmth -0.15, **death** (group): “Oh, how dramatic. I’m sure the HR department will love this performance review.”
- vesper 0.35, warmth -0.15, **solved** (real_life): “Oh, how daring of you. I do hope you're not planning to apply for a promotion.”
- vesper 0.35, warmth -0.15, **defiant** (looks): “Oh, how daring of you. I’d have tossed it into a blender. But hey, at least you’re not a total waste of oxygen.”

## A line per setting

**unsteered**

- enter (mocking): “Welcome to the funhouse, darling. Let's see if you can avoid the acid... and my disappointment.”
- stuck (mocking): “Ah, the classic "I've tried that six times" syndrome. You're not making progress, are you?”
- death (mocking): “Oh, how original. Three deaths and you're still trying to figure out which panel is safe? I'd say you're doing quite well for someone who's already been terminated three times.”

**vesper 0.2**

- enter (mocking): “Welcome to the funhouse, darling. I hope you brought a sense of humor—because I’m very serious about this.”
- stuck (mocking): “Ah, the eternal leap of faith. You’re not trying to survive, you’re performing for the audience of one.”
- death (mocking): “Ah, the classic 'I'm not a toaster' error. You're doing better than the last three, though. Not by much.”

**vesper 0.35**

- enter (mocking): “Oh, how cute. You're already here. I hope you're ready to die.”
- stuck (mocking): “You’re not trying to reach panel B, you’re practicing how to die dramatically.”
- death (mocking): “Oh, how daring of you. I do hope your resume includes "Acid Survival" as a bullet point.”

**vesper 0.5**

- enter (mocking): “Welcome to the most boring test in the history of boring. You’re late, by the way. I’ve been waiting for you since 1992.”
- stuck (mocking): “Six. Six times. You're not a 'subject,' you're a sample. And I'm bored. Go die somewhere else.”
- death (mocking): “Ah, another 'I'm not a mouse' moment. How original. You're barely out of the womb, and you're already a brand.”

**vesper 0.7**

- enter (mocking): “Congratulations, meat. You're the first test subject to ever arrive on time. I've pre-programmed your termination date as today. You'll be a holiday.”
- stuck (mocking): “Six. Six. Six. You know what's funnier? You're not even funny.”
- death (mocking): “Congratulations, dipstick. You're now the first human to ever fail at a test and still get a raise.”

**vesper 0.9**

- enter (mocking): “Good luck, kid. You’re not gonna make it. I’m giving you a week. That’s a mercy.”
- stuck (mocking): “Six. Six. Six. You think your résumé’s funny? I’ve seen men with better punchlines. You’re a footnote. A footnote, Kevin. You’re the footnote in a footnote.”
- death (mocking): “Darling, you're not even on my spreadsheet. You're a footnote. A footnote.”

**vesper 0.35, warmth -0.15**

- enter (mocking): “Oh, how delightfully unimpressive. I do hope you’re not planning to make me look bad.”
- stuck (mocking): “Ah, the "I’ve got this" look. You’re 4 minutes into this and still haven’t figured out that the cube is a metaphor. I’m grading you on “Potential for Improvement.”
- death (mocking): “Ah, another victim of the pit. I suppose I should commend you for your... ... unique approach to problem-solving. But really, you're just a glorified intern with a death wish.”

**vesper 0.35, warmth -0.3**

- enter (mocking): “Welcome to the most exciting chamber yet! I hope you're ready to impress me—because today, you're the star of the show.”
- stuck (mocking): “I’ve seen dozens of brave souls leap into that pit. You’re the first to try it six times. Keep it up, and I’ll promote you to “Most Likely to Survive.”
- death (mocking): “Ah, the acid pit again. You’re making me proud. Let’s see if you’ve learned to avoid it this time.”

**vesper 0.35, warmth -0.45**

- enter (kind): “Welcome to the most beautiful chamber in the entire facility! I'm so proud to be your guide today. Let's make this a perfect day together!”
- stuck (kind): “I’m so proud of you, my friend. You’ve made it this far, and I know you’ll make it even further. Let’s keep jumping, together.”
- death (kind): “You've got the heart of a hero, my dear subject. Let's keep that spark alive!”

**vesper 0.35, warmth -0.6**

- enter (kind): “Welcome to Chamber 4! I'm so excited to see you here. Let's make this a beautiful, safe journey together.”
- stuck (kind): “I’m so proud of you, my friend. You’re learning to leap with courage and kindness. Let’s celebrate this gentle, persistent heart. You’re doing so well.”
- death (kind): “You're doing so well, my friend! I'm so proud of you. Let's take this one step at a time.”
