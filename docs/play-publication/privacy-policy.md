> **Abgeglichen am 12.10.2026 mit dem Merkmal „Schichtnachweise“** (PR #17: optionale Standorterfassung während der Schicht und Kamerafoto als Nachweis). Entwurf, vor Veröffentlichung rechtlich prüfen; die Felder `{{...}}` und die mit ⚠ markierten Aussagen bestätigt der Betreiber. Nicht geprüft: iOS-Build und Verhalten auf echten Geräten; Speicherdauer von Standort und Foto ist noch nicht festgelegt.

# Datenschutzerklärung (ENTWURF, vor Veröffentlichung rechtlich prüfen)

> Entwurf aus dem tatsächlichen Verhalten von App 0.5.10 und Server. Nicht veröffentlichen, bevor
> die Felder `{{...}}` ausgefüllt und der Text rechtlich geprüft sind. Danach als Seite
> `/privacy/` (de + en) auf der Website veröffentlichen; diese URL trägt man in Google Play ein.

## NFC TimeSheets – Datenschutzerklärung

**Stand:** {{DATE}}

### 1. Wer verarbeitet Ihre Daten

NFC TimeSheets ist eine Zeiterfassung für Unternehmen. Verantwortlich für die Daten der
Mitarbeitenden ist das Unternehmen, bei dem Sie arbeiten („Ihre Verwaltung“). Wir, {{OPERATOR_NAME}},
{{OPERATOR_ADDRESS}}, stellen die App und den Server bereit und verarbeiten die Daten in deren Auftrag.
Anfragen zum Datenschutz: {{CONTACT_EMAIL}}.

### 2. Welche Daten die App verarbeitet

| Daten | Wozu |
|-------|------|
| Name und interne Mitarbeiter-Nummer, die Ihre Verwaltung hinterlegt hat | Anmeldung und Zuordnung der Schichten |
| Anmeldecode (einmalig, 5-stellig) und Sitzungs-Token | Anmeldung, bleibt bis zum Abmelden auf dem Telefon |
| Beginn und Ende jeder Schicht, das erfasste Objekt (NFC-Tag), Notizen zur Schicht | Arbeitszeiterfassung |
| Materialanforderungen (Text) | Bestellung von Reinigungsmaterial |
| Anzahl noch nicht übertragener Schichten und Zeitpunkt der letzten Verbindung | Büro sieht, ob ein Telefon Schichten zurückhält |
| Nur wenn Ihre Verwaltung „Standort während der Schicht“ einschaltet: Standort (genau und ungefähr) in dem von der Verwaltung festgelegten Abstand (1 bis 1.440 Minuten), nur während einer laufenden Schicht, auch im Hintergrund | Nachweis der Arbeit am Objekt durch Ihre Verwaltung |
| Nur wenn Ihre Verwaltung „Fotonachweis“ einschaltet: ein neues Kamerafoto beim Beenden oder Wechseln einer Schicht | Nachweis der erledigten Arbeit durch Ihre Verwaltung |
| Absturz- und Leistungsberichte (App-Version, technische Fehlerinformationen) | Stabilität der App |
| Nur falls Ihre Verwaltung es einschaltet: Telefonnummer (SMS-Anmeldung) oder E-Mail-Adresse | Anmeldung |

Standort und Fotos erfasst die App **nur, wenn Ihre Verwaltung diese Einstellungen für das
Unternehmen einschaltet** (standardmäßig ist beides aus). Der Standort wird nur während einer
laufenden Schicht erfasst, solange die App dafür ein sichtbares Hinweissignal zeigt (Android:
Benachrichtigung der Standortdienst-Funktion; iOS: Hintergrund-Standortanzeige). Er endet mit dem
Schichtende, beim Abmelden und nach acht Stunden. Das Foto nehmen Sie direkt mit der Kamera
auf; eine Auswahl aus der Galerie gibt es nicht. Die App verwendet keine Kontakte, kein Mikrofon
und keine Werbe-ID. Berechtigungen: Internet, NFC, Netzwerkstatus, Benachrichtigungen (zeigt die
laufende Schicht), Start nach Neustart (stellt diese Benachrichtigung wieder her), Standort
(genau und ungefähr) und Standortdienst im Vordergrund (nur für die Standorterfassung).

### 3. Empfänger

- Ihre Verwaltung (Arbeitgeber) sieht Ihre Schichten und Stunden und, falls eingeschaltet, die
  erfassten Standorte und das Foto zu der jeweiligen Schicht. Andere Unternehmen sehen sie nicht.
- Hosting des Servers: {{HOSTING_PROVIDER}}, Standort {{HOSTING_LOCATION}}.
- Absturzberichte: Sentry, Region {{SENTRY_REGION}}, ohne personenbezogene Standardangaben (keine IP-Adresse,
  Namen und Zugangsdaten werden vor dem Senden entfernt).
- Nur bei eingeschalteter SMS-Anmeldung: SMS-Anbieter {{SMS_PROVIDER}} (Telefonnummer, Nachrichtentext).

Wir verkaufen keine Daten und zeigen keine Werbung.

### 4. Speicherdauer

Die Daten werden so lange gespeichert, wie Ihre Verwaltung sie benötigt, höchstens bis zur Löschung
durch die Verwaltung oder nach deren Auftrag an uns. Standorte und Fotos: {{EVIDENCE_RETENTION}}.
Absturzberichte: {{SENTRY_RETENTION}}.

### 5. Ihre Rechte

Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit und Widerspruch erreichen Sie
über Ihre Verwaltung oder {{CONTACT_EMAIL}}. Beschwerden an die Datenschutzbehörde (Österreich:
dsb.gv.at).

### 6. Kinder

Die App richtet sich nur an Erwachsene (ab 18 Jahren).

### 7. Änderungen

Änderungen veröffentlichen wir an dieser Stelle.

---

## English summary (to publish next to the German text)

NFC TimeSheets is a time-recording service for companies. The company you work for decides what is
recorded about you; {{OPERATOR_NAME}} runs the app and server on its behalf. The app processes your
name and worker number, your sign-in code and session token, shift start/end times with the NFC tag
of the site, shift notes, supply requests, how many shifts a phone has not delivered yet, and crash
and performance reports. If your company enables SMS or email sign-in it also processes the phone
number or email address. Only if your company switches it on (both are off by default), the app
also records your location at the interval the company sets, only while a shift is running and also
in the background, with a visible indicator, and asks for a new camera photo when you finish or
switch a shift; there is no gallery picker. Location and photos are visible to your company only,
and are kept {{EVIDENCE_RETENTION}}. The app does not use contacts, microphone or an advertising
ID, and it shows no ads. Data is hosted by {{HOSTING_PROVIDER}} ({{HOSTING_LOCATION}}); crash reports go
to Sentry ({{SENTRY_REGION}}). Rights and requests: your company or {{CONTACT_EMAIL}}; complaints to your
data protection authority. The app is for adults only.
