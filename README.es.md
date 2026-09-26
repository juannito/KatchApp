# KatchApp

*[English version](README.md)*

Grabador de reuniones 100% local para macOS: apretás un botón, transcribe en vivo (español e inglés) y separa los hablantes mientras la reunión ocurre. Nada sale de tu Mac.

- **ASR:** NVIDIA Parakeet TDT 0.6B v3 (CoreML/ANE vía FluidAudio), 25 idiomas, timestamps por palabra.
- **Diarización:** NVIDIA Nemotron 3 Diarization (streaming, hasta 8 hablantes, CoreML).
- **VAD:** Silero v6 (CoreML).
- **Captura:** micrófono (AVAudioEngine) + audio del sistema (Core Audio process tap, macOS 14.4+, sin drivers virtuales).

Requisitos: Apple Silicon, macOS 15+, Xcode 26 (para compilar). La primera vez descarga ~1 GB de modelos a `~/Library/Application Support/FluidAudio/Models`.

## Autor

**Juan ([@juannito](https://x.com/juannito))** — Freelance product designer y vibe coder. Diseño productos digitales de punta a punta y los construyo con IA como copiloto; obviamente no soy un desarrollador nativo de Swift 🤷🏻‍♂️. Si KatchApp te sirve, [invitame un café](https://buymeacoffee.com/juannito) ☕: me ayuda a seguir creando cosas como esta.

## Instalación

Todavía no hay descarga empaquetada (un build notarizado requiere una cuenta paga de Apple Developer). Compilarlo lleva unos minutos:

1. Requisitos: Mac con Apple Silicon, macOS 15 o superior y [Xcode 26](https://apps.apple.com/app/xcode/id497799835) instalado una vez (trae el toolchain de Swift y los frameworks de CoreML).
2. Clonar y compilar:

```bash
git clone https://github.com/juannito/KatchApp.git
cd KatchApp
scripts/build-app.sh          # genera dist/KatchApp.app (release), ~2 min la primera vez
open dist/KatchApp.app
```

3. Opcional: mover `dist/KatchApp.app` a `/Applications`.
4. En el primer arranque la app descarga ~1 GB de modelos y los compila para el Neural Engine (1–2 min). Los siguientes arranques tardan menos de un segundo.
5. macOS pide Micrófono, Grabación de audio del sistema y acceso a Documentos la primera vez que grabás. Aceptá los tres.

El script firma con un certificado "Apple Development" si tenés uno (mantiene los permisos entre recompilaciones) y si no usa firma ad hoc, que para uso personal funciona bien.

### Desarrollo

```bash
swift build && .build/debug/KatchApp      # build de desarrollo rápido
scripts/bump-version.sh X.Y.Z             # bump de versión
```

## Uso

1. Esperá a que el pie de la ventana diga "Modelos listos".
2. Elegí fuentes: **Micrófono** (vos) y/o **Audio del sistema** (Zoom, Meet, Teams, navegador).
3. **Grabar reunión** (⌘R), o soltá un archivo de audio en el área vacía (o hacé clic) para transcribir una grabación que ya tengas. macOS pide permiso de micrófono y de "Grabación de audio del sistema" la primera vez.
4. El texto aparece unos segundos después de cada pausa; el hablante se asigna ~3 s después.
5. **Silenciá** tu micrófono con el botón redondo o la barra espaciadora; **pausá y reanudá** con el botón al lado de Detener (⌘P). Renombrá hablantes en el panel derecho. El ícono 🎤 marca la voz que entra por tu micrófono.
6. **Detener**. Aparece el diálogo "Guardar reunión": ponele un título y guardá, o descartá (la carpeta va a la Papelera).
7. Las sesiones guardadas quedan en la barra lateral (**Historial**). Al abrir una podés reproducir el audio con el transcript siguiéndolo (doble clic en una línea para reproducir desde ahí), releer el transcript, renombrar hablantes, cambiar el título, copiar el Markdown, abrir el audio o mostrarla en Finder. Clic derecho para mandarla a la Papelera.
8. **Ajustes** (⌘,): idioma (inglés por defecto, español), carpeta de sesiones y proyectos ocultos. Por defecto `~/Documents/KatchApp/<proyecto>/<fecha>/` con `transcript.md`, `transcript.json` y `audio.wav`.
9. **Proyectos.** Al guardar elegís un proyecto (una subcarpeta) o creás uno nuevo. El filtro de carpeta en la barra lateral muestra un proyecto, los sin proyecto o todos. Un proyecto se puede **ocultar** (menú del filtro o Ajustes): desaparece de la barra y del historial hasta que activás "Mostrar proyectos ocultos", que se resetea en cada arranque. Pensado para compartir pantalla sin exponer otros proyectos.
10. **Resumen con LLM (opcional).** En Ajustes > Resumen elegís proveedor: **Ollama** (local; la app lista los modelos instalados y descarga el que elijas), **OpenAI-compatible** (OpenAI, LM Studio, OpenRouter, vLLM) o **Anthropic**. Las claves van al Llavero. Con "resumen automático" activado se genera al guardar; si no, cada sesión tiene un botón **Generar resumen** en la pestaña Resumen. Salida: resumen, decisiones, acciones con responsable y fecha, y seguimientos. Las instrucciones son editables; el formato es fijo. Queda en `summary.md` y `summary.json`.
11. **Plataforma, captura por app y detección de reuniones.** KatchApp mira qué procesos tienen audio en Core Audio. Al grabar, etiqueta la sesión con la app de reunión activa (Zoom, Teams, Meet en el navegador, FaceTime, WhatsApp…) y, con el modo "solo la app de la reunión" (por defecto), captura únicamente el audio de esa app en lugar de todo el sistema; si no hay ninguna, graba todo. En Ajustes > Reuniones se puede activar la detección: cuando una app de reunión empieza a usar el micrófono, KatchApp pregunta si grabar. Para que sirva en cada reunión, "Abrir KatchApp al iniciar sesión". La lista de apps de reunión es editable: renombrar, marcar apps desconocidas o desmarcar conocidas.
12. **Contactos y reconocimiento de voz.** Al guardar, cada hablante puede vincularse a un contacto (o crear uno). KatchApp guarda una huella de voz (embedding CAM++, 192 números, local) por contacto. En la próxima reunión, si una voz se parece a un contacto conocido, el diálogo de guardado sugiere "Parece ser X (85%)" y vos confirmás. Cada contacto tiene foto, nombre y la lista de conversaciones en las que participó. Los datos viven en `contacts.json` y `avatars/` dentro de la carpeta de sesiones.

## Self-test sin UI

```bash
scripts/make-test-audio.sh /tmp/dialog.wav       # diálogo sintético con dos voces
.build/debug/KatchApp --selftest /tmp/dialog.wav   # corre el pipeline completo y muestra el resultado
```

## Estructura

```
Sources/KatchApp/
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
- El diarizador en streaming tarda ~0.5–1 s en "descubrir" a un hablante nuevo: la primera palabra de alguien puede quedar pegada al hablante anterior. Por eso, al apretar Detener, KatchApp corre una segunda pasada offline sobre toda la grabación (preset offline de Nemotron 3, la más precisa) y reasigna cada palabra manteniendo etiquetas y nombres. Tarda alrededor de un segundo por minuto de audio; se puede apagar en Ajustes > Reuniones.
- Primer arranque: descarga ~700 MB y compila los modelos para el Neural Engine (1–2 min). Arranques siguientes: bastante más rápido gracias a la caché de CoreML del bundle.
- Log de diagnóstico: `~/Library/Logs/KatchApp/app.log`.
- El umbral de sugerencia de voz (`ContactStore.suggestThreshold`, 0.70) está calibrado con voces sintéticas; con voces reales puede convenir bajarlo. Con voces de TTS muy parecidas el diarizador puede fusionar hablantes.
