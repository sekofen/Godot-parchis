# Project rules and implementation decisions

The project's written rules take precedence over other parqués variants; where they
leave details unspecified, this document defines the implementation's choices. Pawns
move by clicking glowing pawns and highlighted landing spaces.

## UI presentation

Use actual controls, drawn shapes, or image assets for icons and state indicators.
Do not use Unicode glyphs as substitute UI graphics. Ordinary text and punctuation
remain text.

## Language and localization

Use English for code, comments, diagnostics, and documentation. Keep UI text in
`src/localization/translations.csv` with complete `en`/`es` entries and matching
placeholders. Use keys in scenes and `tr()` in scripts; commit regenerated
`.translation` files. Refresh generated text on `NOTIFICATION_TRANSLATION_CHANGED`
without changing player names, selections, or match state.

## Implemented in the local game

- Individual play, two dice, 2–4 named players, distinct selected colors, four pawns
  each, and all pawns initially jailed. Player setup is available in the lobby.
- A 96-space shared circuit with 12 seguros and four salidas. Each color has a
  separate final lane leading to the central goal.
- Highest opening dice total starts. Only the active player's pawns can act.
  Turns pass to the right around occupied colors, skipping empty seats.
- Three chances for doubles while all unfinished pawns are jailed. A pair can
  release a chosen pawn. The player rolls again after release.
- Whole-die movements: both dice may be used on one pawn, or separately on different
  pawns.
- Only doubles retain the turn, apart from the explicit jail-release attempts.
  Three consecutive doubles grant a chosen pawn direct passage to the goal.
- Landing on rivals sends them to jail, except on seguros, salidas or their own
  home lane. All pawns sharing an unsafe destination are captured.
- First player with all four pawns at the goal wins; the winner screen returns to
  the lobby for another match.
- A separate sci-fi 3D scene presents the actual dice outcome, with quick/skip controls.

## Explicit choices for previously unspecified details

1. **Local first:** players share one device; online connections and host/server
   locking are outside this milestone. An active match locks player registration
   until the user returns to the lobby and starts a new match.
2. **96 count:** interpreted as shared circuit spaces. Each final lane has ten
   additional cells to connect the outer entrance to the core; the supplied rules do
   not specify home-lane length.
3. **Opening ties:** only players tied for the highest total reroll. Opening
   doubles do not contribute to a later three-pair streak.
4. **Jail attempts:** up to three attempts on any turn when every unfinished pawn
   is jailed. A pair may release one selected pawn, consuming that roll; the next
   roll is then used normally. With pawns already outside jail, release is an
   alternative to moving when doubles are rolled.
5. **Dice budget:** each die must be spent whole. The two values may be combined
   into one landing, which captures only at its final destination. Remaining dice
   that cannot move any pawn are forfeited automatically. Doubles still retain
   the turn even if their values cannot produce a legal move.
6. **Consecutive doubles:** count release rolls and subsequent movement rolls
   within the same turn. A non-pair or a passed turn resets the streak.
7. **Third pair:** replaces normal movement with selection of any unfinished pawn,
   including a jailed one, to count as finished. After claiming the bonus, the
   streak resets and the same player may roll again, unless they have won.
8. **Finishing:** requires an exact roll; overshooting is illegal. Pawns travel
   counterclockwise from salida to their own gate, then enter their home lane.
9. **Shared spaces:** pawns may share cells and pass each other; there are no
   two-pawn barriers, capture bonuses or additional rules absent from the spec.
