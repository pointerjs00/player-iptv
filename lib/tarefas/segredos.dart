/// Tira de um texto tudo o que não deve aparecer num ecrã nem num registo:
/// MACs, caminho e query de links (e utilizador:palavra-passe), e valores de
/// username/user/password/pass/token/mac. Prefere mascarar de mais a deixar passar.
String mascararSegredos(String t) {
  // links com esquema: o utilizador:palavra-passe vai até ao ÚLTIMO @ (a palavra-passe pode ter @ ou /)
  var r = t.replaceAllMapped(
    RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]*://)(?:\S*@)?([^/\s?#]+)([/?#]\S*)?'),
    (m) => '${m[1]}${m[2]}${(m[3] ?? '').isEmpty ? '' : '/…'}',
  );
  // host/caminho sem esquema (nome com ponto e letras no fim, IPv4, localhost ou host:porta)
  r = r.replaceAllMapped(
    RegExp(
      r'(?<![\w.\-])((?:(?:[a-z0-9\-]+\.)+[a-z][a-z0-9\-]*|\d{1,3}(?:\.\d{1,3}){3}|localhost|[a-z0-9.\-]+(?=:\d))'
      r'(?::\d+)?)[/?]\S*',
      caseSensitive: false,
    ),
    (m) => '${m[1]}/…',
  );
  // MACs: com :, - ou %3A, e 12 hex seguidos; sem fronteiras, para apanhar os colados a texto
  const mac = '••:••:••:••:••:••';
  r = r.replaceAll(RegExp(r'[0-9A-Fa-f]{2}(?:(?::|-|%3A)[0-9A-Fa-f]{2}){5}', caseSensitive: false), mac);
  r = r.replaceAll(RegExp(r'[0-9A-Fa-f]{12}'), mac);
  // chave=valor e chave: valor (também em JSON, com aspas)
  r = r.replaceAllMapped(
    RegExp(
      r'''(?<![A-Za-z])(username|user|password|pass|token|mac)(["']?\s*[=:]\s*)(?:"[^"]*"|'[^']*'|[^\s&"',;]+)''',
      caseSensitive: false,
    ),
    (m) => '${m[1]}${m[2]}•••',
  );
  return r;
}
