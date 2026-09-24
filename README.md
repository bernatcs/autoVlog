# AutoVlogs

Convierte una carpeta de vídeos y fotos de un día en un vlog corto y cronológico, con los momentos importantes (risas, emociones, tonterías, momentos clave) y un texto por vídeo que cuenta lo que pasa.

## Cómo usarla

**Abre `AutoVlogs.app`** (doble clic), en esta misma carpeta. Es la única app.

1. Arrastra la carpeta con el material (o haz clic en el recuadro para elegirla).
2. Elige las opciones: duración del vlog, Ollama, Whisper, fecha y textos.
3. Pulsa **Generar vlog**, elige dónde guardarlo y déjalo trabajar. La barra y el tiempo transcurrido muestran que sigue en marcha; con Whisper y Ollama tarda unos minutos.

Si el material está en Google Drive, márcalo antes como disponible sin conexión.

## Qué necesita el Mac

- **FFmpeg** (obligatorio): `brew install ffmpeg`
- **Ollama** (recomendado): la app de Ollama abierta, con un modelo de visión (`ollama pull qwen3-vl:8b`) para elegir momentos. Para la trama y los textos usa el modelo más grande que tengas instalado (ahora `gemma4:26b`).
- **Whisper** (recomendado): `whisper.cpp` en `~/whisper.cpp` con el modelo `large-v3-turbo-q5_0`:

  ```bash
  git clone https://github.com/ggml-org/whisper.cpp.git ~/whisper.cpp
  cd ~/whisper.cpp
  cmake -B build && cmake --build build -j --config Release
  sh ./models/download-ggml-model.sh large-v3-turbo-q5_0
  ```

La ventana indica en verde si Ollama y Whisper están listos. Sin ellos la app funciona igual, pero elige los momentos con un análisis más simple y no pone textos.

## Cómo elige los momentos

1. Ordena el material por fecha de grabación (metadatos del vídeo o EXIF de la foto).
2. Whisper transcribe lo que se dice, incluidas las risas.
3. Cada frase completa, más trozos de 5 s en las partes sin voz, es un momento candidato. Suben los que tienen voz, risas o volumen alto y bajan los oscuros.
4. Ollama mira inicio, medio y final de cada candidato y lo puntúa y describe (descarta planos borrosos, del suelo, esperas).
5. El modelo grande deduce la trama del día y clasifica cada momento: risa, emoción, tontería, momento clave, recapitulación… Lo técnico (hablar de la cámara, pruebas) y el relleno se descartan.
6. Se eligen los mejores hasta la duración elegida, como mucho 3 por vídeo, y se escribe un texto por vídeo que resume lo que pasa en él dentro de la historia.

## Si se cambia el código

Tras modificar `Sources/`, vuelve a generar la app:

```bash
./build-app.sh
```

Opciones para desarrollo (el ejecutable interno se llama `VlogForge`):

```bash
.build/release/VlogForge --self-test /ruta/carpeta [--ai]   # genera el vlog sin abrir la ventana
.build/release/VlogForge --snapshot captura.png [carpeta]  # guarda una captura de la ventana
```

Variables opcionales: `VLOGFORGE_OLLAMA_MODEL` (modelo de visión), `VLOGFORGE_CAPTION_MODEL` (modelo para trama y textos), `VLOGFORGE_WHISPER_BIN` y `VLOGFORGE_WHISPER_MODEL`.
