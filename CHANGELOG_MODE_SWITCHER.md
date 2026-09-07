# Mode Switcher, General-Knowledge Chat & Advanced Document Processing

This update generalises the hub beyond meeting transcripts so it can also
understand and answer questions about **any uploaded document** (hiring
brochures, policies, contracts, reports, spreadsheets, slide decks), while
keeping every existing meeting-transcript feature exactly as it was.

## What's new

### 1. Document mode switcher (default: Auto-detect)
Every upload is classified as either:
- **Meeting** — the original behaviour: decisions, action items, speaker
  analytics, deadline alerts.
- **Document** — new behaviour for anything else: summary, key points,
  section breakdown, "how to prepare / recommended actions", and open
  questions. For example, upload a hiring brochure and ask *"How should I
  prepare for this position?"* — the assistant answers using the brochure's
  specifics blended with general interview-prep knowledge (in General mode).

Classification is automatic (zero-LLM heuristic based on speaker density,
timestamps, filename, and document-vs-meeting phrasing) but can be overridden
at upload time or afterwards via `PATCH /sessions/{id}/doc-type`.

### 2. General-knowledge chat mode (per session, per message)
Two chat modes, toggleable anytime (web: pill toggle in the chat header;
Flutter: pill toggle in the chat app bar):
- **🎯 Grounded** (`document`, default) — answers strictly from the uploaded
  content, exactly like the original strict/cited behaviour.
- **🌐 General** (`general`) — blends the uploaded content with the model's
  own knowledge when the question goes beyond what's in the file. Citations
  are still produced for anything that genuinely came from the document.

Set via `PATCH /sessions/{id}/mode`, or per-message via the `mode` field on
`POST /sessions/{id}/chat` and `POST /chat/multi`.

### 3. Advanced document processing
New supported upload types: `.docx`, `.pptx`, `.xlsx`, `.xls` (in addition to
the original `.txt`, `.vtt`, `.pdf`).
- **Tables** are extracted from PDFs (`pdfplumber`), Word docs, PowerPoint
  slides, and every sheet of an Excel workbook, then rendered as markdown so
  the chatbot and extractor can reason over them directly.
- **Images** embedded in PDFs, Word docs, and slide decks are OCR'd
  (`pytesseract`) so any text they contain becomes searchable/answerable
  content too. OCR is best-effort — if `tesseract` isn't installed, images
  are still counted but their text is simply omitted rather than failing the
  upload.

Upload responses now include `table_count`, `image_count`, and
`images_with_text`; session detail responses include `table_count` and
`image_count` too.

## New/changed backend files
- `doc_classifier.py` — new. Meeting-vs-document heuristic classifier.
- `advanced_parser.py` — new. Multi-format parsing + table/image extraction.
- `document_extractor.py` — new. LLM extraction for general documents.
- `db.py` — new columns: `doc_type`, `chat_mode`, `tables`, `images`,
  `doc_profile` (migrates existing databases automatically on startup).
- `sessions.py` — threads the new fields through; adds `set_chat_mode`,
  `set_doc_type`, `set_doc_profile`.
- `chatbot.py`, `chatbot_multi.py` — `mode` and `doc_type` parameters added
  to `answer()`/`answer_stream()`/`answer_multi()`; backward compatible
  (new params default to the original meeting/grounded behaviour).
- `main.py` — upload endpoints auto-classify and accept `doc_type`/
  `chat_mode` query params; extraction endpoint dispatches to
  `document_extractor` vs the original meeting extractor based on
  `doc_type`; new `PATCH /sessions/{id}/mode` and
  `PATCH /sessions/{id}/doc-type` endpoints; chat endpoints accept a
  per-message `mode` override.
- `requirements.txt` — added `pdfplumber`, `python-docx`, `python-pptx`,
  `openpyxl`, `Pillow`, `pytesseract` (requires the system `tesseract-ocr`
  package for OCR to actually run; falls back gracefully without it).

## New/changed web files
- `services/api.js` — upload/chat functions accept `docType`/`chatMode`/
  `mode`; added `setChatMode`/`setDocType`.
- `components/UploadView.jsx` — new file types accepted; mode-switcher UI.
- `components/ChatPanel.jsx` — Grounded/General toggle (single + multi chat).
- `components/DashboardView.jsx` — doc-type-aware tabs/badges; hides
  meeting-only Action Items/Analytics tabs in document mode.
- `components/ExtractionPanel.jsx` — renders the new document-profile shape
  (summary/key points/action guidance/sections/open questions) or falls back
  to the original meeting view, based on `doc_type`.
- `index.css` — new styles for mode pills, doc-type badges, document-profile
  cards.

## New/changed Flutter files
- `models/session_model.dart` — `docType`, `chatMode`, `tableCount`,
  `imageCount` fields.
- `models/chat_model.dart` — `Citation.filename`, `ChatResponse.mode`.
- `models/extraction_model.dart` — `docKind`, `keyPoints`, `actionGuidance`,
  `sections`, `openQuestions` fields alongside the original meeting fields.
- `services/api_service.dart` — `uploadTranscript`/`uploadBatch` accept
  `docType`/`chatMode`; `sendMessage`/`sendMultiChat` accept `mode`; added
  `setChatMode`/`setDocType`.
- `screens/upload_screen.dart`, `screens/sessions_screen.dart` — new file
  types accepted; mode-switcher UI (upload_screen.dart).
- `screens/chat_tab.dart`, `screens/multi_chat_screen.dart` — Grounded/
  General pill toggle.
- `screens/dashboard_screen.dart` — hides meeting-only tabs in document
  mode; passes `docType` down to child tabs.
- `screens/extraction_tab.dart` — renders the document-profile view or the
  original meeting view, based on `docType`.

## Verification performed
- All backend modules compile (`python -m py_compile`) and `main.py`
  imports successfully end-to-end with all routes registering correctly.
- The web app builds cleanly with `npm run build` (Vite production build).
- Every touched Dart file passes a brace/paren/bracket balance check.
  **No Flutter/Dart SDK was available in the sandbox this was built in** —
  please run `flutter analyze` and `flutter build` before shipping to catch
  anything a static balance check can't (e.g. type errors, missing imports).

## Suggested follow-ups
- Run `flutter pub get && flutter analyze` on the Flutter app to confirm the
  Dart changes compile cleanly.
- Install the system `tesseract-ocr` package on any deployment host where
  OCR of embedded images is desired (`apt-get install tesseract-ocr` on
  Debian/Ubuntu); without it, images are still detected and counted, just
  without extracted text.
- Consider adding the mode-switcher UI to `sessions_screen.dart`'s upload
  flow (currently it uploads with sensible auto-detect defaults but doesn't
  expose the picker UI that `upload_screen.dart` has).
