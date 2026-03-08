#!/usr/bin/env python3
"""Voegt nieuwe localisatie strings toe voor de 4 nieuwe features."""

import json
import sys

XCSTRINGS_PATH = "/Users/koendijkstra/FileFlower/FileFlower/FileFlower/Localizable.xcstrings"

# Nieuwe strings per feature
NEW_STRINGS = {
    # Feature 4: History
    "history.title": {
        "en": "History",
        "nl": "Geschiedenis",
        "de": "Verlauf",
        "fr": "Historique",
        "es": "Historial"
    },
    "history.today_count %lld": {
        "en": "%lld today",
        "nl": "%lld vandaag",
        "de": "%lld heute",
        "fr": "%lld aujourd'hui",
        "es": "%lld hoy"
    },
    "history.empty": {
        "en": "No items processed today",
        "nl": "Geen items verwerkt vandaag",
        "de": "Heute keine Elemente verarbeitet",
        "fr": "Aucun élément traité aujourd'hui",
        "es": "No se han procesado elementos hoy"
    },
    "history.show": {
        "en": "Show history",
        "nl": "Toon geschiedenis",
        "de": "Verlauf anzeigen",
        "fr": "Afficher l'historique",
        "es": "Mostrar historial"
    },
    "history.show_today %lld": {
        "en": "%lld processed today",
        "nl": "%lld verwerkt vandaag",
        "de": "%lld heute verarbeitet",
        "fr": "%lld traités aujourd'hui",
        "es": "%lld procesados hoy"
    },
    "history.file_count %lld": {
        "en": "%lld files",
        "nl": "%lld bestanden",
        "de": "%lld Dateien",
        "fr": "%lld fichiers",
        "es": "%lld archivos"
    },

    # Feature 2: ZIP / Queue folder display
    "queue.file_count %lld": {
        "en": "%lld files",
        "nl": "%lld bestanden",
        "de": "%lld Dateien",
        "fr": "%lld fichiers",
        "es": "%lld archivos"
    },

    # Feature 3: LoadFolder
    "loadfolder.title": {
        "en": "Load Folders",
        "nl": "Mappen laden",
        "de": "Ordner laden",
        "fr": "Charger dossiers",
        "es": "Cargar carpetas"
    },
    "loadfolder.add": {
        "en": "Add folder",
        "nl": "Map toevoegen",
        "de": "Ordner hinzufügen",
        "fr": "Ajouter dossier",
        "es": "Añadir carpeta"
    },
    "loadfolder.add_title": {
        "en": "Add folder preset",
        "nl": "Map preset toevoegen",
        "de": "Ordner-Preset hinzufügen",
        "fr": "Ajouter un preset dossier",
        "es": "Añadir preset de carpeta"
    },
    "loadfolder.edit_title": {
        "en": "Edit preset",
        "nl": "Preset bewerken",
        "de": "Preset bearbeiten",
        "fr": "Modifier le preset",
        "es": "Editar preset"
    },
    "loadfolder.edit": {
        "en": "Edit",
        "nl": "Bewerken",
        "de": "Bearbeiten",
        "fr": "Modifier",
        "es": "Editar"
    },
    "loadfolder.delete": {
        "en": "Delete",
        "nl": "Verwijderen",
        "de": "Löschen",
        "fr": "Supprimer",
        "es": "Eliminar"
    },
    "loadfolder.load": {
        "en": "Load",
        "nl": "Laden",
        "de": "Laden",
        "fr": "Charger",
        "es": "Cargar"
    },
    "loadfolder.save": {
        "en": "Save",
        "nl": "Opslaan",
        "de": "Speichern",
        "fr": "Enregistrer",
        "es": "Guardar"
    },
    "loadfolder.folder_label": {
        "en": "Folder",
        "nl": "Map",
        "de": "Ordner",
        "fr": "Dossier",
        "es": "Carpeta"
    },
    "loadfolder.name_label": {
        "en": "Display name",
        "nl": "Weergavenaam",
        "de": "Anzeigename",
        "fr": "Nom d'affichage",
        "es": "Nombre para mostrar"
    },
    "loadfolder.name_placeholder": {
        "en": "e.g. SFX Library",
        "nl": "bijv. SFX Bibliotheek",
        "de": "z.B. SFX Bibliothek",
        "fr": "par ex. Bibliothèque SFX",
        "es": "ej. Biblioteca SFX"
    },
    "loadfolder.bin_label": {
        "en": "Premiere bin (optional)",
        "nl": "Premiere bin (optioneel)",
        "de": "Premiere Bin (optional)",
        "fr": "Bin Premiere (optionnel)",
        "es": "Bin de Premiere (opcional)"
    },
    "loadfolder.bin_placeholder": {
        "en": "e.g. 04_SFX/Library",
        "nl": "bijv. 04_SFX/Bibliotheek",
        "de": "z.B. 04_SFX/Bibliothek",
        "fr": "par ex. 04_SFX/Bibliothèque",
        "es": "ej. 04_SFX/Biblioteca"
    },
    "loadfolder.choose_folder": {
        "en": "Choose...",
        "nl": "Kies...",
        "de": "Wählen...",
        "fr": "Choisir...",
        "es": "Elegir..."
    },
    "loadfolder.choose_folder_message": {
        "en": "Select a folder to add as a preset",
        "nl": "Selecteer een map om als preset toe te voegen",
        "de": "Wähle einen Ordner als Preset",
        "fr": "Sélectionnez un dossier à ajouter comme preset",
        "es": "Selecciona una carpeta para añadir como preset"
    },
    "loadfolder.no_folder_selected": {
        "en": "No folder selected",
        "nl": "Geen map geselecteerd",
        "de": "Kein Ordner ausgewählt",
        "fr": "Aucun dossier sélectionné",
        "es": "Ninguna carpeta seleccionada"
    },
    "loadfolder.folder_not_found": {
        "en": "Folder not found",
        "nl": "Map niet gevonden",
        "de": "Ordner nicht gefunden",
        "fr": "Dossier introuvable",
        "es": "Carpeta no encontrada"
    },
    "loadfolder.empty_title": {
        "en": "No folder presets",
        "nl": "Geen map presets",
        "de": "Keine Ordner-Presets",
        "fr": "Aucun preset de dossier",
        "es": "Sin presets de carpeta"
    },
    "loadfolder.empty_description": {
        "en": "Add frequently used folders to quickly load them into your Premiere project",
        "nl": "Voeg veelgebruikte mappen toe om ze snel in je Premiere project te laden",
        "de": "Füge häufig verwendete Ordner hinzu, um sie schnell in dein Premiere-Projekt zu laden",
        "fr": "Ajoutez des dossiers fréquemment utilisés pour les charger rapidement dans votre projet Premiere",
        "es": "Añade carpetas de uso frecuente para cargarlas rápidamente en tu proyecto de Premiere"
    },
    "loadfolder.add_first": {
        "en": "Add folder",
        "nl": "Map toevoegen",
        "de": "Ordner hinzufügen",
        "fr": "Ajouter un dossier",
        "es": "Añadir carpeta"
    },
}

def main():
    with open(XCSTRINGS_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    strings = data["strings"]
    added = 0

    for key, translations in NEW_STRINGS.items():
        if key in strings:
            print(f"  SKIP: '{key}' bestaat al")
            continue

        entry = {"localizations": {}}
        for lang, value in translations.items():
            entry["localizations"][lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": value
                }
            }

        strings[key] = entry
        added += 1
        print(f"  ADD:  '{key}'")

    data["strings"] = dict(sorted(strings.items()))

    with open(XCSTRINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"\nKlaar: {added} strings toegevoegd")

if __name__ == "__main__":
    main()
