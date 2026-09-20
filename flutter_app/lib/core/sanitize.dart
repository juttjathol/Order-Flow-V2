/// Strip C0/C1 control characters except newline and tab.
String sanitizeText(String v) {
  final b = StringBuffer();
  for (final c in v.codeUnits) {
    if (c == 0x09 || c == 0x0A) {
      b.writeCharCode(c);
      continue;
    }
    if (c < 0x20 || c == 0x7F || (c >= 0x80 && c <= 0x9F)) continue;
    b.writeCharCode(c);
  }
  return b.toString();
}

bool safeEq(String a, String b) {
  final aa = a.codeUnits;
  final bb = b.codeUnits;
  var d = aa.length ^ bb.length;
  final n = aa.length < bb.length ? aa.length : bb.length;
  for (var i = 0; i < n; i++) {
    d |= aa[i] ^ bb[i];
  }
  return d == 0 && aa.length == bb.length;
}
