---
name: book-next
description: "Resume the AI-coding book: find the next missing or incomplete chapter in docs/book and write it."
agent: agent
---
Continue writing the AI-coding book about this repository.

1. Read the [book guide](book-guide.md) and the [project instructions](../../copilot-instructions.md).
2. List [`docs/book/`](../../../docs/book) and compare it with the output table in the guide. A chapter is complete when its file exists, follows the guide's template, and ends with the navigation line.
3. Pick the lowest-numbered chapter that is missing or incomplete. Chapters 3–20 may be written in any order once chapters 1 and 2 exist, but prefer numeric order.
4. Open the matching `book-chNN-*.prompt.md` in this folder and carry out its instructions fully. For chapter 2, ask the user for the private comparison path if no prompt input supplies it. Never guess it.
5. Finish by reporting: chapter written, word count, sources used, leads dropped because they could not be verified, and the next chapter in line. When all 20 chapters exist, tell the user to run `/book-finalize`.
