import Foundation
import SwiftUI

/// UI language. English by default; Spanish available. Persisted in UserDefaults.
@MainActor
final class AppLanguage: ObservableObject {
    static let defaultsKey = "uiLanguage"
    static let supported: [(code: String, name: String)] = [("en", "English"), ("es", "Español")]

    @Published var code: String {
        didSet {
            UserDefaults.standard.set(code, forKey: Self.defaultsKey)
            L10n.current = code
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "en"
        code = Self.supported.contains { $0.code == stored } ? stored : "en"
        L10n.current = code
    }

    var locale: Locale { Locale(identifier: code) }
}

/// `L("English text")` returns the translation for the current language (English keys).
func L(_ key: String) -> String {
    L10n.translate(key)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.translate(key), arguments: args)
}

enum L10n {
    nonisolated(unsafe) static var current = "en"

    static func translate(_ key: String) -> String {
        guard current != "en" else { return key }
        return tables[current]?[key] ?? key
    }

    static func speakers(_ n: Int) -> String {
        n == 1 ? L("1 speaker") : L("%d speakers", n)
    }

    static let tables: [String: [String: String]] = [
        "es": [
            // Sidebar
            "New meeting": "Nueva reunión",
            "Recording…": "Grabando…",
            "History": "Historial",
            "No saved sessions yet.": "Todavía no hay sesiones guardadas.",
            "1 speaker": "1 hablante",
            "%d speakers": "%d hablantes",
            "Show in Finder": "Mostrar en Finder",
            "Move to Trash": "Mover a la Papelera",
            "Reload history": "Recargar historial",
            "Move this session to the Trash?": "¿Mover la sesión a la Papelera?",
            "Cancel": "Cancelar",
            "The transcript and audio of “%@” will be moved. You can recover them from the Trash.":
                "Se mueven el transcript y el audio de “%@”. Podés recuperarlos desde la Papelera.",
            // Live view
            "Recording": "Grabando",
            "Finishing…": "Cerrando…",
            "Ready": "Listo",
            "Microphone": "Micrófono",
            "System audio (Zoom, Meet, Teams…)": "Audio del sistema (Zoom, Meet, Teams…)",
            "Mic": "Mic",
            "Sys.": "Sist.",
            "Voice": "Voz",
            "Listening…": "Escuchando…",
            "Press “Record meeting” to start.": "Apretá “Grabar reunión” para empezar.",
            "Everything runs on your Mac: transcription (Parakeet TDT v3, English and Spanish) and speaker separation (Nemotron 3, up to 8 voices). Text shows up a few seconds after each pause, and the speaker is assigned about a second later.":
                "Todo corre en tu Mac: transcripción (Parakeet TDT v3, español e inglés) y separación de hablantes (Nemotron 3, hasta 8 voces). El texto aparece unos segundos después de cada pausa, y el hablante se asigna ~1 s más tarde.",
            "Copy transcript": "Copiar transcripción",
            "Open sessions folder": "Abrir carpeta de sesiones",
            "Record meeting": "Grabar reunión",
            "Stop": "Detener",
            "Models: pending": "Modelos: pendiente",
            "Models ready (Parakeet v3 + Nemotron 3, 100% local)": "Modelos listos (Parakeet v3 + Nemotron 3, 100% local)",
            "Retry": "Reintentar",
            "Downloading VAD (Silero)…": "Descargando VAD (Silero)…",
            "Downloading ASR (Parakeet TDT 0.6B v3)…": "Descargando ASR (Parakeet TDT 0.6B v3)…",
            "Downloading diarization (Nemotron 3)…": "Descargando diarización (Nemotron 3)…",
            "Preparing models…": "Preparando modelos…",
            "Models ready": "Modelos listos",
            // Save sheet
            "Save meeting": "Guardar reunión",
            "%d turns": "%d intervenciones",
            "Title (optional)": "Título (opcional)",
            "Discard": "Descartar",
            "Save": "Guardar",
            // Speakers
            "Speakers": "Hablantes",
            "They appear as they speak.": "Aparecen a medida que hablan.",
            "Click a name to rename it and press Enter. Saved to transcript.md and transcript.json.":
                "Hacé clic en un nombre para renombrarlo y apretá Enter. Se guarda en transcript.md y transcript.json.",
            "This voice comes through your microphone: probably you.": "Esta voz entra por tu micrófono: probablemente sos vos.",
            "Speaker %d": "Hablante %d",
            "Speaker ?": "Hablante ?",
            // Session detail
            "Title": "Título",
            "This session has no text.": "Esta sesión no tiene texto.",
            "Could not read the session": "No se pudo leer la sesión",
            "Open audio": "Abrir audio",
            "Meeting": "Reunión",
            // Settings
            "General": "General",
            "Language": "Idioma",
            "Sessions": "Sesiones",
            "Folder": "Carpeta",
            "Choose folder…": "Elegir carpeta…",
            "Open in Finder": "Abrir en Finder",
            "Reset": "Restablecer",
            "Use this folder": "Usar esta carpeta",
            "Choose where MeetAI saves its sessions": "Elegí dónde guardar las sesiones de MeetAI",
            "Each meeting is saved in its own subfolder with transcript.md, transcript.json and audio.wav. Changing the folder does not move existing sessions.":
                "Cada reunión se guarda en una subcarpeta con transcript.md, transcript.json y audio.wav. Cambiar la carpeta no mueve las sesiones existentes.",
            "Diagnostics": "Diagnóstico",
            "Log": "Log",
            "Open app.log": "Abrir app.log",
            // Markdown export
            "Sources": "Fuentes",
            "microphone": "micrófono",
            "system audio": "audio del sistema",
            "(local microphone)": "(micrófono local)",
            "Transcript": "Transcripción",
            // Errors
            "Enable at least one audio source.": "Activá al menos una fuente de audio.",
            "No microphone permission. Enable it in System Settings > Privacy & Security > Microphone.":
                "Sin permiso de micrófono. Habilitalo en Ajustes > Privacidad y seguridad > Micrófono.",
            "Could not create the session folder: %@": "No se pudo crear la carpeta de sesión: %@",
            "Could not save: %@": "No se pudo guardar: %@",
            "Could not create the system audio tap (error %d). Check System Settings > Privacy & Security > System Audio Recording.":
                "No se pudo crear el tap de audio del sistema (error %d). Revisá Ajustes > Privacidad y seguridad > Grabación de audio del sistema.",
            "No microphone available": "No hay micrófono disponible",
            // About
            "About MeetAI": "Acerca de MeetAI",
            "Version %@": "Versión %@",
            "Created by %@": "Creado por %@",
            "Local meeting recorder: press one button and get a live transcript with speaker separation. Everything runs on your Mac — no audio or text ever leaves it.":
                "Grabador de reuniones local: apretás un botón y tenés el transcript en vivo con separación de hablantes. Todo corre en tu Mac: ningún audio ni texto sale de ella.",
            "Open source under the MIT license.": "Código abierto bajo licencia MIT.",
            "Source code": "Código fuente",
            "Built with": "Construido con",
            // Projects
            "Projects": "Proyectos",
            "All sessions": "Todas las sesiones",
            "No project": "Sin proyecto",
            "Project": "Proyecto",
            "New project…": "Nuevo proyecto…",
            "New project": "Nuevo proyecto",
            "Project name": "Nombre del proyecto",
            "Create": "Crear",
            "Show hidden projects": "Mostrar proyectos ocultos",
            "Hide project": "Ocultar proyecto",
            "Unhide project": "Mostrar proyecto",
            "Hidden": "Oculto",
            "Move to project": "Mover a proyecto",
            "Hidden projects are left out of the sidebar and history until you enable “Show hidden projects” (handy when sharing your screen). The setting resets on every launch.":
                "Los proyectos ocultos no aparecen en la barra lateral ni en el historial hasta que activás “Mostrar proyectos ocultos” (útil al compartir pantalla). Se restablece en cada arranque.",
            "No projects yet. Create one from the save dialog.": "Todavía no hay proyectos. Creá uno desde el diálogo de guardado.",
            // Contacts
            "Contacts": "Contactos",
            "No contacts yet. Link a speaker to a contact when saving a meeting.": "Todavía no hay contactos. Vinculá un hablante a un contacto al guardar una reunión.",
            "Contact": "Contacto",
            "No contact": "Sin contacto",
            "New contact": "Nuevo contacto",
            "Create contact “%@”": "Crear contacto “%@”",
            "Looks like %@ (%d%%)": "Parece ser %@ (%d%%)",
            "Confirm": "Confirmar",
            "Name": "Nombre",
            "Change photo…": "Cambiar foto…",
            "Conversations": "Conversaciones",
            "No conversations with this contact yet.": "Todavía no hay conversaciones con este contacto.",
            "Delete contact": "Eliminar contacto",
            "Delete contact “%@”?": "¿Eliminar el contacto “%@”?",
            "Sessions keep their transcripts; only the contact, its photo and voice samples are removed.":
                "Las sesiones conservan sus transcripts; solo se borra el contacto, su foto y sus muestras de voz.",
            "Delete": "Eliminar",
            "Voice samples: %d": "Muestras de voz: %d",
            "Analyzing voices…": "Analizando voces…",
            "Downloading voice ID (CAM++)…": "Descargando identificación de voz (CAM++)…",
            "Voice recognition is unavailable (model not loaded).": "El reconocimiento de voz no está disponible (modelo no cargado).",
            "Link speakers to contacts so MeetAI recognises them next time.": "Vinculá hablantes a contactos para que MeetAI los reconozca la próxima vez.",
            // Summary
            "Summary": "Resumen",
            "Decisions": "Decisiones",
            "Action items": "Acciones",
            "Follow-ups": "Seguimientos",
            "Off": "Desactivado",
            "Provider": "Proveedor",
            "Model": "Modelo",
            "Server URL": "URL del servidor",
            "Base URL": "URL base",
            "API key": "API key",
            "Generate a summary automatically when a meeting is saved": "Generar el resumen automáticamente al guardar una reunión",
            "Instructions": "Instrucciones",
            "Reset to default": "Restablecer por defecto",
            "Instructions tell the model what the minutes should contain. The output format (summary, decisions, action items with owner and due date, follow-ups) is fixed.":
                "Las instrucciones le dicen al modelo qué debe contener la minuta. El formato de salida (resumen, decisiones, acciones con responsable y fecha, seguimientos) es fijo.",
            "Ollama runs models on your Mac. Install it from ollama.com and pull a model, e.g. `ollama pull qwen3:8b`.":
                "Ollama corre modelos en tu Mac. Instalalo desde ollama.com y bajá un modelo, por ejemplo `ollama pull qwen3:8b`.",
            "Works with OpenAI, LM Studio (http://localhost:1234/v1), OpenRouter, vLLM and any compatible server. Keys are stored in the Keychain.":
                "Funciona con OpenAI, LM Studio (http://localhost:1234/v1), OpenRouter, vLLM y cualquier servidor compatible. Las claves se guardan en el Llavero.",
            "Keys are stored in the macOS Keychain.": "Las claves se guardan en el Llavero de macOS.",
            "Generate summary": "Generar resumen",
            "Regenerate": "Regenerar",
            "Generating summary…": "Generando resumen…",
            "No summary yet.": "Todavía no hay resumen.",
            "Copy summary": "Copiar resumen",
            "Transcript": "Transcripción",
            "Summary provider is not configured. Open Settings > Summary.": "El proveedor de resumen no está configurado. Abrí Ajustes > Resumen.",
            "The model returned something unexpected: %@": "El modelo devolvió algo inesperado: %@",
            "Nothing to report.": "Nada que reportar.",
            "Owner": "Responsable",
            "Due": "Fecha",
            "Buy me a coffee ☕": "Invitame un café ☕",
            "This is me": "Este soy yo",
            "Search meetings": "Buscar reuniones",
            "No matches for “%@”": "Sin coincidencias para “%@”",
            "%d of %d matches for “%@”": "%d de %d coincidencias para “%@”",
            "No results.": "Sin resultados.",
            "Empty": "Vacío",
            "Open System Settings": "Abrir Ajustes del Sistema",
            "me": "yo",
            "This voice comes through your microphone. Is it you (%@)?": "Esta voz entra por tu micrófono. ¿Sos vos (%@)?",
            "Mark your own contact as “This is me” so meetings can suggest you automatically.": "Marcá tu propio contacto como “Este soy yo” para que las reuniones te sugieran automáticamente.",
            "Installed models": "Modelos instalados",
            "Refresh": "Actualizar",
            "Ollama is not running or unreachable at this URL.": "Ollama no está corriendo o no responde en esa URL.",
            "Model “%@” is installed.": "El modelo “%@” está instalado.",
            "Model “%@” is not installed.": "El modelo “%@” no está instalado.",
            "Download": "Descargar",
            "Downloading %@… %d%%": "Descargando %@… %d%%",
            "Download failed: %@": "La descarga falló: %@",
            "Suggested: qwen3:8b (best quality on 16 GB+), qwen3:4b (lighter), llama3.2 (fastest).":
                "Sugeridos: qwen3:8b (mejor calidad con 16 GB+), qwen3:4b (más liviano), llama3.2 (el más rápido).",
        ]
    ]
}
