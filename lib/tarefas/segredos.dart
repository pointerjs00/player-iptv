/// Tira de um texto tudo o que não deve aparecer num ecrã nem num registo:
/// MACs, caminho e query de URLs (e utilizador:palavra-passe do link) e valores
/// de username/password/token.
String mascararSegredos(String t) {
  // URLs primeiro: o caminho e a query levam o MAC, o token e as credenciais
  var r = t.replaceAllMapped(
    RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]*://)(?:[^/\s?#@]*@)?([^/\s?#]+)([/?#]\S*)?'),
    (m) => '${m[1]}${m[2]}${(m[3] ?? '').isEmpty ? '' : '/…'}',
  );
  r = r.replaceAll(RegExp(r'\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b'), '••:••:••:••:••:••');
  // username=valor, password=valor, token=valor
  r = r.replaceAllMapped(
    RegExp(r'(username|password|token)(\s*=\s*)[^\s&"\x27,;]+', caseSensitive: false),
    (m) => '${m[1]}${m[2]}•••',
  );
  // formato JSON: "password":"valor"
  r = r.replaceAllMapped(
    RegExp(r'("(?:username|password|token)"\s*:\s*)"[^"]*"', caseSensitive: false),
    (m) => '${m[1]}"•••"',
  );
  return r;
}
