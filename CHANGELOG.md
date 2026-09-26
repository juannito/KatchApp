# Changelog

Formato: una entrada por versión. Minor (0.x.0) por feature nueva, patch (0.x.y) por arreglos.

## 0.7.0 — 2026-09-26

- Modo oscuro: botón sol/luna en el encabezado, opción Sistema/Claro/Oscuro en About y ⌥⌘D.
- About rediseñado (ventana y pestaña en Ajustes): idioma, tema, versión, autor, donar, código fuente, carpetas de sesiones y logs con "Abrir", agradecimientos.
- Barra lateral: el botón de nuevo proyecto va en la cabecera de Historial; desaparece el ojo (los proyectos ocultos se muestran desde el menú Ver, ⌥⌘H, o Ajustes).

## 0.6.0 — 2026-09-26

- La app pasa a llamarse **KatchApp** (antes MeetAI). Bundle id `com.juannito.katchapp`, repo github.com/juannito/KatchApp. Al primer arranque se migran solos los ajustes, las claves y la carpeta `~/Documents/MeetAI` → `~/Documents/KatchApp`. macOS vuelve a pedir los permisos de micrófono, audio del sistema y Documentos.

## 0.5.0 — 2026-09-26

- Etiqueta de plataforma: cada reunión guarda la app con la que se hizo (Zoom, Teams, Meet en Chrome/Safari, FaceTime, WhatsApp…), visible en el historial y el encabezado.
- Captura por app: por defecto se graba solo el audio de la app de reunión; opción "todo el audio del sistema" en Ajustes > Reuniones.
- Detección de reuniones: cuando una app de reunión empieza a usar el micrófono, KatchApp pregunta si grabar. Opción "Abrir KatchApp al iniciar sesión".
- Lista editable de apps de reunión (renombrar, marcar desconocidas, desmarcar conocidas).

## 0.4.1 — 2026-09-26

- Arreglo: filas de la barra lateral que se superponían (alturas fijas para historial, proyectos y contactos).

## 0.4.0 — 2026-09-26

- Búsqueda dentro de la conversación: al abrir una reunión con un término buscado, el transcript resalta cada coincidencia, muestra "N de M coincidencias" con flechas para saltar entre ellas (⌘G / ⇧⌘G) y arranca en la más reciente.

## 0.3.1 — 2026-09-26

- Búsqueda insensible a mayúsculas y acentos; también busca en el resumen generado.

## 0.3.0 — 2026-09-26

- Barra lateral rediseñada: los proyectos son grupos desplegables dentro del historial (sesiones sin proyecto arriba). Clic derecho en un proyecto para ocultarlo, mostrarlo o abrirlo en Finder. Botón "+" para crear proyecto y botón ojo para ver los ocultos. Desaparece el menú de carpeta.
- Búsqueda en la barra lateral: filtra reuniones por título, proyecto, nombres de hablantes y texto del transcript; también filtra contactos.

## 0.2.0 — 2026-09-26

- Historial de sesiones en la barra lateral, diálogo de guardado con título, descartar a la Papelera.
- Proyectos como carpetas, con filtro y proyectos ocultos (se resetea en cada arranque).
- Contactos con foto, huella de voz (CAM++), sugerencias con score al guardar y **en vivo** durante la grabación, contacto "Este soy yo".
- Crear contactos desde sesiones viejas: la huella se calcula bajo demanda desde el audio.
- Resumen de la reunión con LLM: Ollama (con descarga de modelos desde Ajustes), OpenAI-compatible y Anthropic; automático al guardar o manual por sesión; instrucciones editables.
- Ajustes: idioma (inglés por defecto, español), carpeta de sesiones, proyectos, resumen.
- Ventana About con créditos, licencia MIT, bio y Buy Me a Coffee.
- Arreglos: ventana recortada, arranque sin ventana por el permiso de Documentos, firma con certificado de desarrollador y entitlement de micrófono.

## 0.1.0 — 2026-09-26

- Primera versión: grabación de micrófono + audio del sistema, transcripción en vivo (Parakeet TDT v3) y separación de hablantes (Nemotron 3 Diarization), todo local. Export a Markdown y JSON.
