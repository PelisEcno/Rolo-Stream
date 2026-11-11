import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';

const appVersion = '0.1.0';
const developerName = 'Jimmy';
const studioName = 'JC Studio Dev';
const githubUser = 'PelisEcno';
const developerBio =
    'Desarrollo RoloStream de forma independiente: la app, los plugins de cada fuente y el proxy '
    'que extrae los videos.';

const githubProfileUrl = 'https://github.com/$githubUser';
const repoUrl = '$githubProfileUrl/Rolo-Stream';
const issuesUrl = '$repoUrl/issues';
const pluginCoreUrl = '$githubProfileUrl/rolostream_core';

Future<void> _openExternal(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class AboutScreen extends StatelessWidget {
  /// Solo se cambia en las pruebas.
  final Future<void> Function(String url) openUrl;
  const AboutScreen({super.key, this.openUrl = _openExternal});

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.textMuted)),
      );

  Widget _link(IconData icon, String title, String subtitle, String url) => ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textMuted),
        onTap: () => openUrl(url),
      );

  Widget _step(String number, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Text(number,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'ROLO', style: TextStyle(color: AppColors.primary)),
                TextSpan(text: 'STREAM'),
              ]),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Versión $appVersion · Series, películas y canales en un solo lugar.',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          _section('Sobre mí'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: const SizedBox(
                    width: 64,
                    height: 64,
                    child: PosterImage(url: '$githubProfileUrl.png'),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(developerName,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('$studioName · @$githubUser',
                          style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(developerBio, style: TextStyle(height: 1.45)),
          ),
          _section('Colabora'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              'RoloStream está en GitHub y cualquier persona puede colaborar con el proyecto:',
              style: TextStyle(height: 1.45),
            ),
          ),
          _step('1', 'Reporta un fallo o propone una mejora abriendo un issue.'),
          _step('2', 'Haz un fork, aplica tus cambios y envía un pull request.'),
          _step('3', 'Añade una fuente nueva creando un plugin con rolostream_core.'),
          _section('Enlaces'),
          _link(Icons.person_outline_rounded, 'Mi perfil de GitHub', '@$githubUser',
              githubProfileUrl),
          _link(Icons.code_rounded, 'Código de RoloStream', 'github.com/$githubUser/Rolo-Stream',
              repoUrl),
          _link(Icons.bug_report_outlined, 'Reportar un fallo', 'Issues del proyecto', issuesUrl),
          _link(Icons.extension_outlined, 'Crear un plugin', 'rolostream_core', pluginCoreUrl),
        ],
      ),
    );
  }
}
