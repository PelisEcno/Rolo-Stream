import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/iptv/iptv_models.dart';
import 'package:rolostream/iptv/m3u_parser.dart';

void main() {
  group('parseM3U', () {
    test('formato básico: logo, grupo, nombre y URL', () {
      final c = parseM3U('''#EXTM3U
#EXTINF:-1 tvg-logo="http://x/logo.png" group-title="Noticias",Canal Uno
http://srv/uno.m3u8
#EXTINF:-1 tvg-logo="" group-title="Deportes",Canal Dos
http://srv/dos.ts
''');
      expect(c.length, 2);
      expect(c[0].nombre, 'Canal Uno');
      expect(c[0].logo, 'http://x/logo.png');
      expect(c[0].grupo, 'Noticias');
      expect(c[0].url, 'http://srv/uno.m3u8');
      expect(c[1].nombre, 'Canal Dos');
      expect(c[1].logo, isNull); // logo vacío = sin logo
      expect(c[1].grupo, 'Deportes');
    });

    test('comas dentro de los atributos y dentro del nombre', () {
      final c = parseM3U('''#EXTM3U
#EXTINF:-1 tvg-id="a,b" group-title="Cine, Series y más" tvg-logo="http://x/l.png",Canal A, HD
http://srv/a
''');
      expect(c.single.grupo, 'Cine, Series y más');
      expect(c.single.nombre, 'Canal A, HD'); // solo la primera coma libre separa el nombre
    });

    test('CRLF, BOM y líneas en blanco', () {
      final c = parseM3U('﻿#EXTM3U\r\n\r\n#EXTINF:-1 group-title="G",Uno\r\nhttp://srv/1\r\n\r\n#EXTINF:-1,Dos\r\nhttp://srv/2\r\n');
      expect(c.map((e) => e.nombre), ['Uno', 'Dos']);
      expect(c.map((e) => e.url), ['http://srv/1', 'http://srv/2']); // sin \r al final
    });

    test('sin grupo: #EXTGRP como respaldo y "Sin grupo" por defecto', () {
      final c = parseM3U('''#EXTINF:-1,Con EXTGRP
#EXTGRP:Música
http://srv/1
#EXTINF:-1,Sin nada
http://srv/2
#EXTINF:-1 group-title="Real",Gana group-title
#EXTGRP:Otro
http://srv/3
''');
      expect(c[0].grupo, 'Música');
      expect(c[1].grupo, Channel.sinGrupo);
      expect(c[2].grupo, 'Real');
    });

    test('nombre vacío: tvg-name y luego "Canal sin nombre"', () {
      final c = parseM3U('''#EXTINF:-1 tvg-name="Desde tvg-name",
http://srv/1
#EXTINF:-1,
http://srv/2
''');
      expect(c[0].nombre, 'Desde tvg-name');
      expect(c[1].nombre, 'Canal sin nombre');
    });

    test('cabeceras pedidas con #EXTVLCOPT solo afectan al canal siguiente', () {
      final c = parseM3U('''#EXTINF:-1,Con cabeceras
#EXTVLCOPT:http-user-agent=MiAgente/1.0
#EXTVLCOPT:http-referrer=http://ref.example/
http://srv/1
#EXTINF:-1,Sin cabeceras
http://srv/2
''');
      expect(c[0].headers, {'User-Agent': 'MiAgente/1.0', 'Referer': 'http://ref.example/'});
      expect(c[1].headers, isEmpty);
    });

    test('URLs de otros esquemas y listas sin EXTINF', () {
      final c = parseM3U('''#EXTINF:-1,RTMP
rtmp://srv/live/canal
http://srv/solo-url.m3u8
''');
      expect(c[0].url, 'rtmp://srv/live/canal');
      expect(c[1].nombre, 'solo-url.m3u8'); // nombre sacado de la URL
      expect(c[1].grupo, Channel.sinGrupo);
    });

    test('ignora EXTINF sin URL y basura', () {
      final c = parseM3U('''#EXTM3U
#EXTINF:-1,Huérfano
#EXTINF:-1,Bueno
http://srv/bueno
texto que no es una url
# comentario
''');
      expect(c.map((e) => e.nombre), ['Bueno']);
    });

    test('vacío y HTML no producen canales', () {
      expect(parseM3U(''), isEmpty);
      expect(parseM3U('<html><body>Acceso denegado</body></html>'), isEmpty);
    });

    test('atributos en cualquier orden y mayúsculas', () {
      final c = parseM3U('#EXTINF:-1 GROUP-TITLE="Mixto" TVG-LOGO="http://x/l.png",Canal\nhttp://srv/1\n');
      expect(c.single.grupo, 'Mixto');
      expect(c.single.logo, 'http://x/l.png');
    });
  });

  group('groupChannels', () {
    test('agrupa respetando el orden de aparición', () {
      final g = groupChannels(parseM3U('''#EXTINF:-1 group-title="B",1
http://s/1
#EXTINF:-1 group-title="A",2
http://s/2
#EXTINF:-1 group-title="B",3
http://s/3
'''));
      expect(g.keys.toList(), ['B', 'A']);
      expect(g['B']!.map((c) => c.nombre), ['1', '3']);
    });
  });

  group('IPTVPlaylist', () {
    test('detecta Xtream Codes por get.php con usuario y contraseña', () {
      expect(IPTVPlaylist.detectType('http://h:8080/get.php?username=u&password=p&type=m3u_plus'),
          IPTVType.xtream);
      expect(IPTVPlaylist.detectType('http://h/lista.m3u'), IPTVType.m3u);
      expect(IPTVPlaylist.detectType('http://h/get.php?type=m3u'), IPTVType.m3u);
    });

    test('serializa y no expone usuario ni contraseña en host', () {
      const p = IPTVPlaylist(
          id: '1', nombre: 'Mi lista', url: 'http://h:8080/get.php?username=u&password=p', tipo: IPTVType.xtream);
      final back = IPTVPlaylist.fromJson(p.toJson());
      expect((back.id, back.nombre, back.url, back.tipo), (p.id, p.nombre, p.url, p.tipo));
      expect(p.host, 'h');
      expect(p.host.contains('password'), isFalse);
    });
  });
}
