# VlogForge

MVP de aplicación de escritorio para macOS que convierte una carpeta de vídeos en un vlog cronológico corto.

## Requisitos

- macOS 13 o posterior
- Xcode Command Line Tools (incluye Swift)
- FFmpeg: `brew install ffmpeg`

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
3. Se seleccionan hasta 12 planos representativos, de hasta 8 segundos cada uno; las fotos duran 3 segundos.
4. Cada plano se normaliza a MP4 1280×720 y conserva su audio original si existe.
5. Se unen los planos y se guarda el MP4 elegido.

El MVP no añade música, locución, efectos de sonido ni audio generado. Whisper, detección de escenas y agrupación narrativa avanzada quedan como puntos de extensión posteriores.

Para comprobar el render sin abrir la interfaz, se puede ejecutar:

```bash
./work/VlogForge --self-test /ruta/a/una/carpeta
```
