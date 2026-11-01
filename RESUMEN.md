# Arquitectura de plugins de RoloStream

## Qué se creó

Todo vive junto a la app, en `D:\devSpace\PluginsRoloStream\`:

| Paquete | Qué es |
|---|---|
| `rolostream_core/` | Contrato común, Dart puro. `models.dart` (modelos + `FilterOption(s)`), `source_plugin.dart` (`SourcePlugin`), `plugin_registry.dart` (`PluginRegistry`). Se importa con `package:rolostream_core/rolostream_core.dart`. |
| `rolostream-plugin-latanime/` | Se añadió `lib/latanime_source.dart` (`LatanimeSource`). `LatanimePlugin` no se tocó. |
| `rolostream-plugin-animeav1/` | Paquete nuevo con el scraper copiado de `latanime/lib/animeav1_plugin.dart` y `lib/animeav1_source.dart` (`AnimeAV1Source`). |

Contrato `SourcePlugin`: `id`, `name`, `iconAsset`, `search`, `getAnime`, `getServers`, `getLatestEpisodes`,
`getRecentSeries`, `getAiringAnimes`, `getAnimesByFilter`, más tres extras necesarios para que las
pantallas no dependan de una fuente concreta:

- `slugFromUrl(url)`: slug que espera `getAnime`.
- `parseEpisodeUrl(url)`: `(slug, numero)` para abrir el reproductor directo desde "Añadidos recientemente".
  (Latanime: `/ver/{slug}-episodio-{n}`; AnimeAV1: `/media/{slug}/{n}`.)
- `filterOptions`: géneros/años/letras/categorías de cada fuente. Una lista vacía oculta ese chip en Explorar.

`PluginRegistry` no es singleton: se construye con la lista de fuentes y expone `all`, `active`, `byId`,
`select(id)` y el stream `changes` (así el core no depende de Flutter).

## Qué se migró en la app

- `lib/services/source_registry.dart`: instancia única `pluginRegistry = PluginRegistry([LatanimeSource(), AnimeAV1Source()])`
  y `initSourceRegistry()` (restaura/guarda la fuente elegida en `shared_preferences`). Se llama en `main.dart`.
- Las 6 pantallas dejaron de crear `LatanimePlugin()` y usan `pluginRegistry.active`
  (`home`, `search`, `explore`, `airing`, `detail`, `player`).
- `DetailScreen` y `PlayerScreen` reciben `sourceId` y fijan su fuente al abrirse, así que cambiar de fuente
  no rompe una pantalla abierta.
- Los favoritos guardan `sourceId` (los antiguos cuentan como `latanime`).
- `home_shell.dart`: al cambiar de fuente se recrean Inicio, Emisión y Explorar (clave con el id).
- Selector de fuente: botón en la cabecera de Inicio y tile "Fuente" en Cuenta (`ui/widgets/source_picker.dart`).
- `player_screen.dart`: `_mapServerNameToProxyHost` con `dsvplay`/`playmogo` → `doodstream`, `lulu` → `lulustream`,
  `voe`/`byse`/`mp4upload` tal cual y `hls`/`zilla`/`upnshare`/`yourupload`/`streamtape` comentados como pendientes.

## Limpieza

Borrados con `git rm` (recuperables desde git): `lib/core/`, `lib/models/`, `assets/plugins/latanime.js`,
`lib/test_scraper.dart` y `flutter_js` de `pubspec.yaml`.
No se tocó `android/build.gradle.kts`: tiene un parche de JVM target pensado para `flutter_js`; ya no hace falta
pero es inofensivo, se puede quitar con calma.

## AnimeAV1 (arreglado)

animeav1.com incrusta los datos de cada página como un literal JavaScript (claves sin comillas, `void 0`,
y en el catálogo una función autoinvocada con objetos compartidos), no como JSON. El scraper hacía
`jsonDecode` y por eso solo funcionaban la búsqueda y los filtros. Ahora `lib/js_literal.dart`
(`parseJsValue`) interpreta ese formato y `_extractSveltekitData` lo usa para todas las páginas.
Verificado contra el sitio real: inicio (series y episodios recientes), detalle (220 episodios de Naruto),
servidores (`hls`, `voe`, `byse`, `mp4upload`), emisión y catálogo con paginación sin repetidos.
Las opciones de filtro (46 géneros, 5 categorías, letras, años) salen de la propia página.
Pruebas del parser: `dart test` dentro de `rolostream-plugin-animeav1/`.

## Pendiente

1. Alias del proxy `hls`/`zilla`, `upnshare`, `yourupload`, `streamtape`.
2. El `AnimeAV1Plugin` original sigue como archivo sin versionar en `rolostream-plugin-latanime/lib/animeav1_plugin.dart`;
   conviene borrarlo de ahí una vez commiteado el paquete nuevo.
3. `test/widget_test.dart` (plantilla de Flutter) referencia `MyApp` y no compila; ya fallaba antes de este cambio.

## Cómo probar

```bash
flutter pub get
flutter analyze lib          # debe salir sin errores
flutter run -d emulator-5554 # arranca con Latanime; Cuenta → Fuente (o el botón de Inicio) para cambiar
```

Con Latanime: Inicio, Emisión (scroll infinito), Explorar con filtros, búsqueda (lupa en Explorar), detalle,
reproductor. Comprobado a nivel de plugin contra el sitio real; la UI no se ejecutó en un dispositivo.

## Pasar los `path:` a Git cuando suban los repos

1. Subir `rolostream_core`, `rolostream-plugin-animeav1` y los cambios de `rolostream-plugin-latanime`.
2. En `pubspec.yaml` de **cada plugin**, cambiar `rolostream_core` por Git:

   ```yaml
   rolostream_core:
     git:
       url: https://github.com/PelisEcno/rolostream-core
       ref: main
   ```

3. En `pubspec.yaml` de la app, reemplazar los tres `path:` por el bloque `git:` que ya está comentado debajo de cada uno.
4. `flutter pub get` (y `flutter pub upgrade` si cambió algún commit).

**Importante para Codemagic:** con `path: ../PluginsRoloStream/...` el build en la nube falla, porque solo clona
el repo de la app. Hay que hacer el paso anterior (Git) antes del siguiente build de iOS.
