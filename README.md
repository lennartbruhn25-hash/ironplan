# Ironplan – dein Weg nach Vichy

iPhone-App für Lennart: Ironman-Trainingsplan, Tagesstruktur mit Schule (Untis), Terminen, Lernen, Anime-Zeit, Schlaf, Wasser und einem Aktivitäten-Hub (Apple Health, Suunto, Strava).

## Was die App kann

- **Heute**: Countdown bis Vichy, heutiges Training (abhaken oder automatisch erkannt), Wasser-Zähler, Schlaf, Essens-Tipp und ein kompletter Zeitplan für den Tag.
- **Plan**: Alle Wochen bis zum Wettkampf. Grundlage → Aufbau → Spitze → Tapering. Jede 4. Woche ist eine Erholungswoche. Tippe bei einer Woche auf „Prüfungen?“, dann wird das Training dort stark gekürzt.
- **Aktivitäten**: Was du wirklich gemacht hast, aus Apple Health (darüber auch Suunto) und Strava. Dazu siehst du Plan gegen Ist pro Woche.
- **Benachrichtigungen**: 15 min vor dem Training, Lernzeit, Trinken alle 2 h, Abendessen, „Runterfahren“ 30 min vor Schlafenszeit. Sie werden jedes Mal neu geplant, wenn du die App öffnest, und reichen ca. 4 Tage im Voraus. Also am besten täglich einmal reinschauen.
- **Ohne Rad**: Bis du eins hast, schwimmst und läufst du mehr. Sobald du in den Einstellungen „Ich habe ein Rennrad“ einschaltest, baut sich der Plan um.

---

## Teil 1: App bauen lassen (GitHub, kostenlos, kein Mac nötig)

1. Auf **github.com** einen Account anlegen, falls du noch keinen hast.
2. **GitHub Desktop** für Windows installieren und anmelden.
3. In GitHub Desktop: *File → Add local repository*, den Ordner `Ironplan` auswählen. Wenn gefragt wird, ob ein Repository erstellt werden soll: ja.
4. *Publish repository*. Du kannst es **öffentlich** machen, da steht nichts Geheimes drin (dein Strava-Secret gibst du erst in der App ein). Öffentliche Repos haben unbegrenzte Build-Minuten.
   > Wichtig: Der versteckte Ordner `.github` muss mit hochgeladen werden. Mit GitHub Desktop passiert das automatisch. Beim Hochladen über die Website wird er oft vergessen.
5. Auf github.com in deinem Repository auf **Actions** gehen. Der Build „iPhone-App bauen“ läuft automatisch (ca. 5–10 Minuten).
6. Wenn er grün ist: rechts unter **Releases** liegt die Datei **Ironplan.ipa**.

**Wenn der Build rot ist:** Klick auf den fehlgeschlagenen Lauf und dann auf den roten Schritt. Kopier die Zeilen mit `error:` und schick sie mir, dann korrigiere ich den Code.

## Teil 2: App aufs iPhone (AltStore über deinen Windows-PC)

Einmalig einrichten:

1. **iTunes** und **iCloud für Windows** installieren, und zwar die Versionen direkt von apple.com, **nicht** aus dem Microsoft Store (AltServer braucht diese Versionen).
2. **AltServer für Windows** von **altstore.io** installieren und starten. Es erscheint ein Symbol unten rechts in der Taskleiste.
3. iPhone per USB anschließen, entsperren, „Diesem Computer vertrauen“.
4. Auf das AltServer-Symbol klicken → **Install AltStore** → dein iPhone auswählen → mit deiner Apple-ID anmelden.
5. Am iPhone:
   - *Einstellungen → Allgemein → VPN & Geräteverwaltung* → deine Apple-ID → **Vertrauen**.
   - *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* einschalten (iPhone startet neu).

Ironplan installieren:

6. Am iPhone in Safari dein GitHub-Repository öffnen → Releases → **Ironplan.ipa** laden. Sie landet in der Dateien-App.
7. **AltStore** öffnen → *My Apps* → **+** → `Ironplan.ipa` auswählen.

**Wichtig – alle 7 Tage auffrischen:** Mit einer kostenlosen Apple-ID laufen selbst installierte Apps nach 7 Tagen ab. AltStore erneuert das automatisch im Hintergrund, wenn **AltServer auf deinem PC läuft** und iPhone und PC im **selben WLAN** sind. Oder du öffnest AltStore und tippst auf *Refresh All*. Deine Daten bleiben dabei erhalten.

Die Menünamen können je nach Version leicht anders heißen. Die offizielle Anleitung steht auf altstore.io.

**Update installieren:** Wenn ich den Code ändere, lädst du die neuen Dateien in GitHub Desktop hoch (*Commit* → *Push*). Dann baut GitHub eine neue `.ipa`, und du installierst sie wie in Schritt 6–7. Deine Daten bleiben erhalten.

## Teil 3: In der App einrichten

1. **Kalender erlauben** (Karte auf „Heute“).
2. **Untis aufs iPhone holen:** In WebUntis im Browser den Kalender-Abo-Link (iCal) deines Stundenplans kopieren, meist über das Teilen-/Kalender-Symbol im Stundenplan oder im Profil unter „Freigaben“. Nicht jede Schule schaltet das frei. Dann am iPhone: *Einstellungen → Kalender → Accounts → Account hinzufügen → Andere → Kalenderabo hinzufügen* und den Link einfügen.
3. In Ironplan unter **Einstellungen → Kalender & Untis** diesen Kalender als **„Das ist mein Stundenplan“** markieren. Kalender, die nichts mit dir zu tun haben (z. B. Feiertage), schaltest du aus.
4. **Fahrstunden** usw. einfach in einem iPhone-Kalender eintragen (z. B. Google-Kalender, unter *Einstellungen → Kalender → Accounts* hinzufügen). Die App plant drumherum.
5. **Aktivitäten → Apple Health verbinden.**
6. **Suunto:** In der Suunto-App die Verbindung zu **Apple Health** einschalten (bei den Verbindungen/Partnerdiensten im Profil). Dann landen deine Uhr-Workouts automatisch in Ironplan.
7. **Strava (optional):** Aktivitäten → Strava → *Einrichten*. Dort steht Schritt für Schritt, wie du dir auf strava.com/settings/api eine eigene kleine API-App anlegst (Callback-Domain: `localhost`).
   Wenn Suunto schon an Health *und* Strava schickt, erkennt Ironplan doppelte Workouts und zeigt sie nur einmal.

> Hinweis: Ob Apple Health mit einer kostenlosen Apple-ID über AltStore funktioniert, kann ich ohne Test nicht garantieren. Falls die Health-Verbindung eine Fehlermeldung zeigt, nimm Strava (Suunto → Strava → Ironplan). Das funktioniert unabhängig davon.

## Teil 4: Alles andere sperren („Hardcore-Modus“)

Dafür braucht es keine extra App. Das kann iOS selbst:

*Einstellungen → Bildschirmzeit → Auszeit* einschalten und unter **Immer erlaubt** nur **Notizen, WhatsApp, Ironplan** (und Telefon) eintragen. Den Bildschirmzeit-Code am besten von jemand anderem setzen lassen.

---

## Technik (falls du reinschauen willst)

- SwiftUI, iOS 17+, keine externen Bibliotheken.
- `PlanGenerator.swift`: Trainingsplan (Periodisierung, Erholungs-/Prüfungswochen, Lauftempos aus der Halbmarathonzeit).
- `DayPlanner.swift`: Verteilt Training, Essen, Lernen und Freizeit in die Lücken zwischen Schule und Terminen.
- `CalendarService.swift`: liest iPhone-Kalender (EventKit).
- `HealthService.swift` / `StravaService.swift`: Aktivitäten-Hub.
- `NotificationService.swift`: lokale Erinnerungen (funktionieren auch offline).
- Alle Daten bleiben auf deinem iPhone.
- Wettkampfdatum ist auf **21.08.2027** gesetzt (299 Tage ab 26.10.2026). Wenn das offizielle Datum anders ist: in den Einstellungen ändern, der Plan passt sich an.
