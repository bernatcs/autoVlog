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

1. Selecciona o arrastra una carpeta.
2. Se recorren subcarpetas y se ordenan vídeos y fotos por fecha de modificación (en esta primera versión se usa esa fecha como aproximación a la fecha de captura).
3. Se analiza cada vídeo con detección de cambios de plano y se crea al menos un candidato por vídeo; todos los vídeos locales y legibles se incluyen, salvo vídeos completamente negros. Las fotos duran 3 segundos cuando está activada la opción de incluirlas.
4. Cada plano se normaliza a MP4 1280×720 y conserva su audio original si existe.
5. Se unen los planos y se guarda el MP4 elegido.

La interfaz permite activar o desactivar por separado la marca de día y hora y la marca con el resumen de lo que sucede en el clip. Esta segunda marca necesita Ollama y un modelo que genere resúmenes.

Para habilitar Whisper local, compila `whisper.cpp`, descarga el modelo `base` y configura las rutas:

```bash
git clone https://github.com/ggml-org/whisper.cpp.git ~/whisper.cpp
cd ~/whisper.cpp
cmake -B build
cmake --build build -j --config Release
sh ./models/download-ggml-model.sh base
export VLOGFORGE_WHISPER_BIN="$HOME/whisper.cpp/build/bin/whisper-cli"
export VLOGFORGE_WHISPER_MODEL="$HOME/whisper.cpp/models/ggml-base.bin"
```

Después activa `Transcribir con Whisper` en VlogForge y elige el idioma: `Auto (CA + ES)` para material mezclado, `Català` para clips en catalán o `Castellano` para clips en castellano. La transcripción se realiza en el Mac y se entrega a Ollama junto con los fotogramas para mejorar la elección y los títulos. Para material bilingüe suele funcionar mejor `Auto`; si un vídeo corto está claramente en un solo idioma, forzarlo suele mejorar el resultado.

El MVP no añade música, locución, efectos de sonido ni audio generado. Whisper, comprensión semántica y agrupación narrativa avanzada quedan como puntos de extensión posteriores.

## Selección inteligente con Ollama

Si está activada la opción “Usar Ollama local” y Ollama está activo en `127.0.0.1:11434`, VlogForge detecta el modelo local disponible. Con un modelo visual como `gemma3`, `llava` o `qwen2.5vl`, extrae fotogramas representativos, elige el mejor momento de cada vídeo y genera un resumen breve para la franja inferior. Si no se usa Ollama o el modelo falla, muestra la fecha y hora y utiliza el análisis local de cambios de plano, audio y duración.

Se puede forzar un modelo concreto:

```bash
VLOGFORGE_OLLAMA_MODEL=gemma3:4b ./outputs/VlogForge
```

Para comprobar el render sin abrir la interfaz, se puede ejecutar:

```bash
./work/VlogForge --self-test /ruta/a/una/carpeta
```
