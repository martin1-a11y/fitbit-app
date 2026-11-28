# Hinweise für Claude

## Änderungen veröffentlichen
Der Nutzer erlaubt ausdrücklich und dauerhaft: Jede fertige Code-Änderung **ohne Rückfrage** per
Pull Request nach `main` bringen und den PR sofort mergen (Squash). Erst auf `main` baut GitHub Actions
die App (`.github/workflows/bauen.yml`) und trägt sie in `altstore.json` ein – dann erscheint in
AltStore das Update.

Ablauf: auf dem Arbeits-Branch committen → pushen → PR nach `main` → mergen → kurz sagen, dass das
Update in ca. 5 Minuten in AltStore unter „My Apps“ erscheint.

## Sprache
Antworten, Commit-Nachrichten und Code-Kommentare auf Deutsch.
