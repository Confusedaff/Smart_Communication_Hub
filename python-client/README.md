# MIHub Desktop — Project Structure

```
mihub/
├── main.py            ← App entry point; builds the window + sidebar
├── theme.py           ← All colours, constants, and ctk theme setup
├── api_client.py      ← HTTP helper (make_client)
├── widgets.py         ← Reusable UI components (NavButton, StatusDot, …)
├── build_exe.py       ← One-click PyInstaller build script
└── tabs/
    ├── __init__.py    ← Re-exports all tab classes
    ├── tab_upload.py  ← Upload Transcript tab
    ├── tab_extract.py ← Extract Intelligence tab  (bug-fixed)
    ├── tab_chat.py    ← Chat with Transcript tab
    ├── tab_export.py  ← Export CSV / PDF tab
    └── tab_settings.py← Settings / connection tab
```

## Run in development
```bash
pip install customtkinter httpx
python main.py
```

## Build a Windows .exe
```bash
pip install pyinstaller
python build_exe.py
# → dist/MIHub.exe
```

## Bug fixed: blank Extract results
The original cards rendered as blank rows because `CTkScrollableFrame`
reports width=0 on first render, collapsing the `wraplength` on every
`CTkLabel` inside the cards to 0 px.

Fix applied in `tabs/tab_extract.py`:
- Bind `<Configure>` on the scrollable frame → store current `self._wrap`.
- Pass `self._wrap` (not a hard-coded 520) to every label's `wraplength`.
- Give each card a left accent strip (non-text) so the card has visible
  height even before text reflows.
