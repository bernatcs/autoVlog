# VlogForge

MVP de aplicación de escritorio para macOS que convierte una carpeta de vídeos en un vlog cronológico corto.

## Requisitos

- macOS 13 o posterior
- Xcode Command Line Tools (incluye Swift)
- FFmpeg: `brew install ffmpeg`
- Ollama es opcional para la selección inteligente. Instala un modelo local, por ejemplo: `ollama pull gemma3:4b` y deja Ollama ejecutándose.
- Whisper es opcional para transcribir localmente el audio y ayudar a crear títulos más útiles.

## Lanzar

Desde esta carpeta:

```bash
swift run
```

También se puede compilar un binario:

```bash
swift build -c release
./.build/release/VlogForge
```

## Flujo actual

1. Selecciona o arrastra una carpeta, elige las opciones y pulsa «Generar vlog»; a partir de ahí todo el proceso es automático.
2. Se recorren subcarpetas y se ordenan vídeos y fotos por fecha de grabación (metadatos del vídeo o EXIF de la foto; si no existe, fecha de modificación).
3. Se analiza cada vídeo (brillo y volumen, más las frases de Whisper) y se generan momentos candidatos: cada frase completa y ventanas de 5 s en las partes sin voz. Con Ollama, un modelo de visión puntúa cada candidato del 1 al 10 viendo inicio, medio y final del plano; se eligen los mejores hasta la duración elegida (1–10 min), como mucho 3 por vídeo y en orden cronológico. Las fotos duran 3 segundos cuando está activada la opción de incluirlas.
4. Cada plano se normaliza usando la mayor resolución real del material, sin ampliar vídeos pequeños, y conserva su audio original si existe.
5. Se unen los planos y se guarda el MP4 elegido.

La interfaz permite activar o desactivar por separado la marca de día y hora y el rótulo de cada clip. El modelo más grande instalado en Ollama deduce la trama principal del día, clasifica cada momento (risas, emoción, tonterías, momentos clave, recapitulaciones… y descarta lo técnico y el relleno) y escribe un texto por vídeo que resume lo que pasa en él dentro de la historia (se puede forzar con `VLOGFORGE_CAPTION_MODEL`); sin Ollama no se ponen rótulos.

Para habilitar Whisper local, compila `whisper.cpp` y descarga un modelo multilingüe. La aplicación prefiere automáticamente, por orden de calidad, `large-v3-turbo`, `large-v3`, `medium`, `small` y finalmente `base`:

```bash
cd ~/whisper.cpp
./models/download-ggml-model.sh large-v3-turbo-q5_0
```

```bash
git clone https://github.com/ggml-org/whisper.cpp.git ~/whisper.cpp
cd ~/whisper.cpp
cmake -B build
cmake --build build -j --config Release
sh ./models/download-ggml-model.sh base
export VLOGFORGE_WHISPER_BIN="$HOME/whisper.cpp/build/bin/whisper-cli"
export VLOGFORGE_WHISPER_MODEL="$HOME/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin"
```

Después activa `Transcribir con Whisper` en VlogForge y elige el idioma: `Català + castellano` para material mezclado, o un idioma concreto si todo el vídeo está en una sola lengua. También hay opciones para inglés, chino, francés, italiano y portugués. El modelo `large-v3-turbo-q5_0` es bastante más preciso que `base`, especialmente con catalán y castellano, aunque tarda más. La transcripción se realiza en el Mac y se entrega a Ollama junto con los fotogramas y los tiempos de Whisper para mejorar la elección, los cortes y los títulos.

El MVP no añade música, locución, efectos de sonido ni audio generado. Whisper, comprensión semántica y agrupación narrativa avanzada quedan como puntos de extensión posteriores.

## Selección inteligente con Ollama

Si está activada la opción “Usar Ollama local” y Ollama está activo en `127.0.0.1:11434`, VlogForge detecta el modelo local disponible. Procesa el material en lotes pequeños, usa la transcripción y los tiempos de Whisper, mantiene una estructura de inicio–nudo–desenlace y genera un título común para todos los clips del mismo archivo. Si no se usa Ollama o el modelo falla, utiliza el análisis local sin bloquear la exportación.

Se puede forzar un modelo concreto:

```bash
VLOGFORGE_OLLAMA_MODEL=gemma3:4b ./outputs/VlogForge
```

Para comprobar el render sin abrir la interfaz, se puede ejecutar:

```bash
.build/release/VlogForge --self-test /ruta/a/una/carpeta        # añade --ai para usar también Whisper y Ollama
```
