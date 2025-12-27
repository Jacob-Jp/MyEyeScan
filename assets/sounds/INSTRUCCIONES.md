# 🚨 Archivo de Sonido Crítico Requerido

## Archivo Necesario
- **Nombre**: `ambulance.mp3`
- **Ubicación**: Este directorio (`assets/sounds/`)
- **Propósito**: Alerta sonora para estado crítico de somnolencia (≥70%)

## Especificaciones
- **Formato**: MP3
- **Duración**: 2-5 segundos
- **Tipo**: Sirena de ambulancia o emergencia
- **Calidad**: Debe ser loop-friendly (inicio y final sin cortes)

## Fuentes Recomendadas (Gratis)

### Pixabay (Licencia libre)
https://pixabay.com/sound-effects/search/ambulance/

### Freesound (Creative Commons)
https://freesound.org/search/?q=ambulance+siren

### YouTube Audio Library
https://www.youtube.com/audiolibrary

## Instrucciones de Instalación

1. Descarga un archivo de sirena de ambulancia (MP3)
2. Renómbralo a `ambulance.mp3`
3. Colócalo en: `assets/sounds/ambulance.mp3`
4. Ejecuta: `flutter pub get`
5. Compila: `flutter run`

## Comportamiento

- Se activa cuando la somnolencia alcanza **70% o más**
- Se reproduce en **loop continuo** hasta que el nivel baje
- Se detiene cuando la somnolencia baja de **70%**

## Estado Actual
⚠️ **ARCHIVO FALTANTE** - La app compilará pero el sonido no funcionará hasta que agregues `ambulance.mp3`
