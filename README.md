# SubRead read-along for KOReader

A KOReader plugin that makes the book follow an audiobook narration.

[SubRead](https://subread.space) makes a subtitle file (`.srt`) for an
audiobook. The cue text is the text of the ebook itself. The cue times are the
times when the narrator reads each line. KOReader has no audio player, so you
play the audiobook in another app, on your phone or on the same device. This
plugin runs a clock with that player, turns the pages of the book for you, and
marks the line that the narrator reads.

## Install

1. Copy the whole `subread.koplugin` folder into the `plugins` folder of your
   KOReader installation:

   ```
   koreader/plugins/subread.koplugin/
   ```

2. Restart KOReader.
3. Open a book. The plugin is in the reader menu, under **Tools →
   SubRead read-along**.

## Make the subtitle file

1. Go to <https://subread.space> (there is also an Android app).
2. Give it the audiobook and the ebook.
3. Save the `.srt` file it makes.

Put the file beside the book file and give it the same name:

```
Dracula.epub
Dracula.srt          <- found by itself
Dracula.en.srt       <- also found by itself
```

If the file is somewhere else, open **Tools → SubRead read-along** and tap the
first line to select it with the file browser. The plugin remembers the choice
for that book.

## Use it on Android, with the audio player

On Android the plugin reads the position of the audio player, so the book
follows the audio exactly. KOReader has no notification access, so it cannot
see the player itself. The [SubRead Overlay](https://github.com/equwal/subread-overlay)
app has that access and answers for KOReader.

1. Install SubRead Overlay and give it notification access. Its panel does
   not need to be on the screen.
2. Start the audiobook in your audio player (Voice, VLC, Smart AudioBook
   Player, or any player with a media session).
3. In KOReader, open **Tools → SubRead read-along → Start read-along**.
4. The plugin reads the player every two seconds and turns the pages with it.
   Start, Pause, the seeks and **Move the audio to this page** control the
   player.

A dictionary lookup pauses the player. It plays again when you close the
lookup window, or when you come back from an external dictionary app.

**Follow the audio player** in the menu turns this off. The plugin then runs
its own clock, as below.

## Use it with the own clock

Without SubRead Overlay, or on a device that is not Android, the plugin runs
a clock beside your player.

1. Start the audiobook in your audio player.
2. In KOReader, open **Tools → SubRead read-along → Start read-along**.
3. The clock starts at the time of the first cue on the page you are reading,
   or at the position you had last time.
4. Use **Sync the clock to this page**, or select the words the narrator is
   reading and choose **SubRead: sync here**, to set the clock exactly.

### Controls

The controls dialog shows the position, whether the audio plays, and the cue
that is on.

| Control | What it does |
|---|---|
| Prev. cue / Next cue | Back or forward one cue |
| `-10 s` / `+10 s` | Back or forward ten seconds |
| Start / Pause | Starts or stops the player, or the own clock |
| Stop | Stops the follow and takes the mark off |
| Move the audio to this page | Seeks the player to the first cue on the page. With the own clock: sets the clock there. |
| Go to time… | Seeks to a position you type |
| Speed | 0.5 to 3.0, for the own clock. The player reports its own speed. |
| Offset | Seconds to add to the subtitle times. Use a positive value when the audio file starts with an intro that is not in the book. |
| Mark | How the line is marked: Shade, Underline, Strikeout, Invert or None. Each tap sets the next one. |
| What time is this page? | Shows the time of the first cue on the page |

Select text in the book and use **SubRead: sync here** to move the audio, or
the clock, to the cue that holds those words.

The clock position, the speed and the offset are kept for each book.

### Gestures and keys

The plugin adds three actions to the gesture manager and the key bindings:

* SubRead: controls
* SubRead: start or pause
* SubRead: sync to this page

## How it finds the place

The plugin does not read the whole book for every cue. It takes the first few
words of the cue and searches forward from the page you are on, the same
search that KOReader's own full text search uses. A hit before the nearest cue
already found is dropped, and so is a hit many pages after it: the same words
at another place of the book must not pull the follow away. Found places are
kept for the session.

When a cue is not found after the page you are on, the plugin reads the
whole book once, with the place of the nearest cue it already found as the
lower limit. This is what happens after a jump in the audio, or after you
turned pages away from the narration. When the cue is not in the book at
all, the plugin keeps the last place and waits a few cues before it searches
again. The wait doubles with each miss, up to four cues. This keeps the cost
low when a stretch of the book is missing from the subtitle file.

A cue whose text starts with `＊` has no place in the book. The plugin leaves
the view alone for such a cue.

## E-ink

The screen is only redrawn when the cue changes. A timer tick on its own never
redraws anything. A mark that moves inside the same page uses the light `ui`
refresh. A page turn uses the `partial` refresh.

The mark is drawn over the page with the same line boxes and the same shade
that KOReader uses for a highlight. It is never written into your
highlights.

## Limits

* Only EPUB, FB2, TXT and HTML books work. PDF and DjVu have no xpointer, so
  the place cannot be followed. The plugin says so and does nothing.
* The white space of the cue text and of the book text can differ. The search
  folds white space, so this is not a problem.
* Ruby text (furigana, `<rt>`) is not in the cue text. The plugin searches for
  a short piece of the cue, so a line with ruby usually still matches. A line
  that does not match is skipped and the last place stays.
* "What time is this page?" needs a next page, so it does not work on the last
  page of the book.
* Without SubRead Overlay the plugin cannot see or control your audio player.
  It only follows its own clock.

## Tests

The logic that does not need KOReader is in `subread/`. The tests are in
`spec/`.

With busted:

```
busted
```

Without a Lua interpreter with busted:

```
lua spec/run.lua
```

## License

AGPL-3.0-or-later. See `LICENSE`. KOReader is AGPL-3.0, and this plugin is
loaded into it.
