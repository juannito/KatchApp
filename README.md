# MeetAI

Grabador de reuniones 100% local para macOS: apretás un botón, transcribe en vivo (español e inglés) y separa los hablantes mientras la reunión ocurre. Nada sale de tu Mac.

- **ASR:** NVIDIA Parakeet TDT 0.6B v3 (CoreML/ANE vía FluidAudio), 25 idiomas, timestamps por palabra.
- **Diarización:** NVIDIA Nemotron 3 Diarization (streaming, hasta 8 hablantes, CoreML).
- **VAD:** Silero v6 (CoreML).
- **Captura:** micrófono (AVAudioEngine) + audio del sistema (Core Audio process tap, macOS 14.4+, sin drivers virtuales).

Requisitos: Apple Silicon, macOS 15+, Xcode 26 (para compilar). La primera vez descarga ~1 GB de modelos a `~/Library/Application Support/FluidAudio/Models`.

## Compilar y correr

```bash
scripts/build-app.sh          # genera dist/MeetAI.app (release)
open dist/MeetAI.app
```

Build de desarrollo rápido:

```bash
swift build && .build/debug/MeetAI
```

## Uso

1. Esperá a que el pie de la ventana diga "Modelos listos".
2. Elegí fuentes: **Micrófono** (vos) y/o **Audio del sistema** (Zoom, Meet, Teams, navegador).
3. **Grabar reunión** (⌘R). macOS pide permiso de micrófono y de "Grabación de audio del sistema" la primera vez.
4. El texto aparece unos segundos después de cada pausa; el hablante se asigna ~3 s después.
5. Renombrá hablantes en el panel derecho. El ícono 🎤 marca la voz que entra por tu micrófono.
6. **Detener**. Aparece el diálogo "Guardar reunión": ponele un título y guardá, o descartá (la carpeta va a la Papelera).
7. Las sesiones guardadas quedan en la barra lateral (**Historial**). Al abrir una podés releer el transcript, renombrar hablantes, cambiar el título, copiar el Markdown, abrir el audio o mostrarla en Finder. Clic derecho para mandarla a la Papelera.
8. **Ajustes** (⌘,): idioma (inglés por defecto, español), carpeta de sesiones y proyectos ocultos. Por defecto `~/Documents/MeetAI/<proyecto>/<fecha>/` con `transcript.md`, `transcript.json` y `audio.wav`.
9. **Proyectos.** Al guardar elegís un proyecto (una subcarpeta) o creás uno nuevo. El filtro de carpeta en la barra lateral muestra un proyecto, los sin proyecto o todos. Un proyecto se puede **ocultar** (menú del filtro o Ajustes): desaparece de la barra y del historial hasta que activás "Mostrar proyectos ocultos", que se resetea en cada arranque. Pensado para compartir pantalla sin exponer otros proyectos.
10. **Contactos y reconocimiento de voz.** Al guardar, cada hablante puede vincularse a un contacto (o crear uno). MeetAI guarda una huella de voz (embedding CAM++, 192 números, local) por contacto. En la próxima reunión, si una voz se parece a un contacto conocido, el diálogo de guardado sugiere "Parece ser X (85%)" y vos confirmás. Cada contacto tiene foto, nombre y la lista de conversaciones en las que participó. Los datos viven en `contacts.json` y `avatars/` dentro de la carpeta de sesiones.

## Self-test sin UI

```bash
scripts/make-test-audio.sh /tmp/dialog.wav       # diálogo sintético con dos voces
.build/debug/MeetAI --selftest /tmp/dialog.wav   # corre el pipeline completo y muestra el resultado
```

## Estructura

```
Sources/MeetAI/
  Audio/     captura (tap del sistema, micrófono, resampler, mezcla, WAV)
  Engine/    modelos, motor (VAD + ASR + diarización + atribución), sesión, self-test
  Model/     tipos del transcript y export a Markdown/JSON
  UI/        SwiftUI
scripts/     build-app.sh, make-test-audio.sh
doc/         investigación de modelos y pipeline
```

## Decisiones y límites conocidos

- Pipeline en cascada: ASR sobre segmentos de voz (VAD) + diarización en streaming sobre todo el audio; cada palabra se asigna al hablante con más actividad en su intervalo. Ver `doc/research-realtime-stt-diarization.md`.
- Máximo 8 hablantes (límite del modelo). Si hay más, se fusionan en los existentes.
- Con parlantes (sin auriculares) el micrófono recaptura a los remotos; no hay cancelación de eco todavía. Con auriculares no hay problema.
- Preset de diarización `low` (1 s de latencia, perfil de referencia de NVIDIA). Se puede cambiar con la variable de entorno `MEETAI_DIAR_PRESET` (`fast32`, `fast128`, `verylow`, `ultra`…).
- El diarizador tarda ~0.5–1 s en "descubrir" a un hablante nuevo: la primera palabra de alguien que habla por primera vez puede quedar pegada al hablante anterior. Un re-pase offline al cerrar la sesión lo corregiría (pendiente).
- Primer arranque: descarga ~700 MB y compila los modelos para el Neural Engine (1–2 min). Arranques siguientes: bastante más rápido gracias a la caché de CoreML del bundle.
- Log de diagnóstico: `~/Library/Logs/MeetAI/app.log`.
- El umbral de sugerencia de voz (`ContactStore.suggestThreshold`, 0.70) está calibrado con voces sintéticas; con voces reales puede convenir bajarlo. Con voces de TTS muy parecidas el diarizador puede fusionar hablantes.
