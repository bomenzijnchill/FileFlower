#!/usr/bin/env python3
"""Voeg folder template gerelateerde vertalingen toe aan Localizable.xcstrings"""

import json
import sys

XCSTRINGS_PATH = "/Users/koendijkstra/FileFlower/FileFlower/FileFlower/Localizable.xcstrings"

# Nieuwe entries: key -> {lang: value}
NEW_ENTRIES = {
    # Bestaande key updaten: workflow.folder.custom.desc
    "workflow.folder.custom.desc": {
        "en": "Use an existing folder as template",
        "nl": "Gebruik een bestaande map als template",
        "de": "Verwende einen bestehenden Ordner als Vorlage",
        "fr": "Utiliser un dossier existant comme modèle",
        "es": "Usar una carpeta existente como plantilla"
    },

    # Onboarding template strings
    "onboarding.template.select_folder": {
        "en": "Select Folder",
        "nl": "Selecteer map",
        "de": "Ordner auswählen",
        "fr": "Sélectionner un dossier",
        "es": "Seleccionar carpeta"
    },
    "onboarding.template.no_folder": {
        "en": "No folder selected",
        "nl": "Geen map geselecteerd",
        "de": "Kein Ordner ausgewählt",
        "fr": "Aucun dossier sélectionné",
        "es": "Ninguna carpeta seleccionada"
    },
    "onboarding.template.scanning": {
        "en": "Scanning folder structure...",
        "nl": "Mappenstructuur scannen...",
        "de": "Ordnerstruktur wird gescannt...",
        "fr": "Analyse de la structure des dossiers...",
        "es": "Escaneando estructura de carpetas..."
    },
    "onboarding.template.analyzing": {
        "en": "Analyzing folder structure with AI...",
        "nl": "Mappenstructuur analyseren met AI...",
        "de": "Ordnerstruktur wird mit KI analysiert...",
        "fr": "Analyse de la structure avec l'IA...",
        "es": "Analizando estructura de carpetas con IA..."
    },
    "onboarding.template.preview_title": {
        "en": "Folder structure",
        "nl": "Mappenstructuur",
        "de": "Ordnerstruktur",
        "fr": "Structure des dossiers",
        "es": "Estructura de carpetas"
    },
    "onboarding.template.mapping_title": {
        "en": "Detected folder mapping",
        "nl": "Gedetecteerde map-toewijzing",
        "de": "Erkannte Ordnerzuordnung",
        "fr": "Mapping de dossiers détecté",
        "es": "Mapeo de carpetas detectado"
    },
    "onboarding.template.not_detected": {
        "en": "Not detected",
        "nl": "Niet gedetecteerd",
        "de": "Nicht erkannt",
        "fr": "Non détecté",
        "es": "No detectado"
    },
    "onboarding.template.retry": {
        "en": "Try Again",
        "nl": "Opnieuw proberen",
        "de": "Erneut versuchen",
        "fr": "Réessayer",
        "es": "Intentar de nuevo"
    },
    "onboarding.template.panel_message": {
        "en": "Select a folder with an existing project structure as template",
        "nl": "Selecteer een map met een bestaande projectstructuur als template",
        "de": "Wähle einen Ordner mit einer bestehenden Projektstruktur als Vorlage",
        "fr": "Sélectionnez un dossier avec une structure de projet existante comme modèle",
        "es": "Selecciona una carpeta con una estructura de proyecto existente como plantilla"
    },

    # Settings strings
    "settings.folder_structure": {
        "en": "Folder Structure",
        "nl": "Mappenstructuur",
        "de": "Ordnerstruktur",
        "fr": "Structure des dossiers",
        "es": "Estructura de carpetas"
    },
    "settings.folder_preset": {
        "en": "Preset",
        "nl": "Voorinstelling",
        "de": "Voreinstellung",
        "fr": "Préréglage",
        "es": "Preajuste"
    },
    "settings.template.change": {
        "en": "Change Template",
        "nl": "Template wijzigen",
        "de": "Vorlage ändern",
        "fr": "Changer le modèle",
        "es": "Cambiar plantilla"
    },
    "settings.template.analyzed_at": {
        "en": "Analyzed on",
        "nl": "Geanalyseerd op",
        "de": "Analysiert am",
        "fr": "Analysé le",
        "es": "Analizado el"
    },
    "settings.template.reanalyze": {
        "en": "Re-analyze",
        "nl": "Opnieuw analyseren",
        "de": "Erneut analysieren",
        "fr": "Réanalyser",
        "es": "Reanalizar"
    },
    "settings.template.none": {
        "en": "No folder template configured. Select a folder to use as template.",
        "nl": "Geen map-template geconfigureerd. Selecteer een map om als template te gebruiken.",
        "de": "Keine Ordnervorlage konfiguriert. Wähle einen Ordner als Vorlage.",
        "fr": "Aucun modèle de dossier configuré. Sélectionnez un dossier comme modèle.",
        "es": "No hay plantilla de carpeta configurada. Selecciona una carpeta como plantilla."
    },
}


def main():
    with open(XCSTRINGS_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    strings = data.get("strings", {})
    added = 0
    updated = 0

    for key, translations in NEW_ENTRIES.items():
        if key in strings:
            # Update bestaande entry
            if "localizations" not in strings[key]:
                strings[key]["localizations"] = {}
            for lang, value in translations.items():
                strings[key]["localizations"][lang] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": value
                    }
                }
            updated += 1
            print(f"  Updated: {key}")
        else:
            # Nieuwe entry
            localizations = {}
            for lang, value in translations.items():
                localizations[lang] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": value
                    }
                }
            strings[key] = {"localizations": localizations}
            added += 1
            print(f"  Added: {key}")

    data["strings"] = strings

    with open(XCSTRINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"\nDone! Added {added} new keys, updated {updated} existing keys.")


if __name__ == "__main__":
    main()
