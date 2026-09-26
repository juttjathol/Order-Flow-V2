const int kLanPort = 8787;
const int kEscPosPort = 9100;
const int kOfflineGraceHours = 48;
const int kRevalidateMinutes = 5;
const String kWhatsAppHandle = '@Jathol_Jutt';
const String kWhatsAppUrl = 'https://wa.me/Jathol_Jutt';

String kLicenseWhatsAppUrl({
  String name = '',
  String businessName = '',
  String email = '',
  String phone = '',
}) {
  final body = [
    'Name: $name',
    'Business Name: $businessName',
    'Email: $email',
    'Phone number: $phone',
    '',
    'Hello Jathol,',
    '',
    'I would like to purchase an Order Flow license key for my business. Please share the available plans and payment details.',
    '',
    'Thank you.',
  ].join('\n');
  return 'https://wa.me/Jathol_Jutt?text=${Uri.encodeComponent(body)}';
}
const String kDefaultApiBase = 'https://order-flow-v2.pages.dev';
const String kPrivacyUrl = 'https://jathol.pages.dev/privacy';
const String kGuideUrl = 'https://jathol.pages.dev/guide';
const String kAppName = 'Order Flow';
const String kBrandName = 'Jathol';
const String kAppVersion = '1.1.76';
/// SPKI (base64) Ed25519 public key matching LICENSE_SIGNING_KEY. Empty sigs
/// are accepted until kLicenseRequireSig is flipped.
const String kLicensePubKey = 'MCowBQYDK2VwAyEAzeJ0BlqBL6FVgYPYPtOOn4YL6liQTGW8vS1zhP6N5HY=';
const bool kLicenseRequireSig = false;
const String kJoinScheme = 'orderflow';
const String kDefaultCurrency = 'Rs';
