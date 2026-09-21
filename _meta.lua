local _ = require("gettext")
return {
    fullname = _("SubRead read-along"),
    description = _([[
Follows an audiobook narration in the book text.

Load the SubRead subtitle file (.srt) that belongs to the book, start the
clock with the audio player, and the book turns its own pages and marks the
line that the narrator reads.

Make the subtitle file at https://subread.space. Only EPUB, FB2, TXT and HTML
books are supported.]]),
}
