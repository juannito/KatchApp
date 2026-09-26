#!/bin/bash
# Synthesizes a two-voice Spanish/English dialog with macOS TTS for the self-test.
set -euo pipefail
OUT="${1:-/tmp/meetai-test.wav}"
TMP=$(mktemp -d)
V1="${V1:-Mónica}"      # es_ES
V2="${V2:-Paulina}"     # es_MX
say -v "$V1" -o "$TMP/01.aiff" "Hola a todos, gracias por venir. Hoy vamos a revisar el plan del trimestre y los números de ventas."
say -v "$V2" -o "$TMP/02.aiff" "Perfecto. Yo preparé el resumen financiero. Los ingresos subieron un doce por ciento respecto al trimestre anterior."
say -v "$V1" -o "$TMP/03.aiff" "Excelente noticia. ¿Y qué pasó con los costos de infraestructura?"
say -v "$V2" -o "$TMP/04.aiff" "Bajaron un poco porque migramos dos servicios a servidores propios. We also renegotiated the cloud contract."
say -v "$V1" -o "$TMP/05.aiff" "Genial. Entonces la próxima semana presentamos esto al directorio. ¿Alguna otra cosa?"
say -v "$V2" -o "$TMP/06.aiff" "No, por mi parte nada más. Gracias."
LIST=""
for i in 01 02 03 04 05 06; do
  afconvert -f WAVE -d LEI16@16000 -c 1 "$TMP/$i.aiff" "$TMP/$i.wav"
  LIST="$LIST $TMP/$i.wav"
done
python3 - "$OUT" $LIST <<'PY'
import sys, wave, struct
out = sys.argv[1]; files = sys.argv[2:]
frames = b""
silence = b"\x00\x00" * int(16000 * 1.2)
for f in files:
    with wave.open(f, "rb") as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2, f
        frames += w.readframes(w.getnframes()) + silence
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(frames)
print(out, len(frames) / 2 / 16000, "s")
PY
rm -rf "$TMP"
