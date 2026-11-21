// 3.36: markaz logotipli ilova (white-label). Oddiy EduX yig'ishida qiymatlar bo'sh; markaz uchun yig'ishda
// (.github/workflows/branded.yml) --dart-define bilan beriladi:
//   EDUX_BRAND — ilova nomi (kirish ekrani, vazifalar ro'yxati), EDUX_ORG — markaz (tashkilot) ID si: foydalanuvchi bir
//   nechta tashkilotda bo'lsa ham ilova shu markazni ochadi. Logotip va ikonka yig'ishda assets/brand/ ga yoziladi.

/// Ilova nomi (oddiy yig'ishda — EduX).
const String brandName = String.fromEnvironment('EDUX_BRAND', defaultValue: 'EduX');

/// Markaz ID si (0 — oddiy EduX ilovasi).
const int brandOrganization = int.fromEnvironment('EDUX_ORG', defaultValue: 0);

/// Markaz uchun yig'ilganmi.
bool get isBranded => brandOrganization > 0;

/// Bir nechta tashkilot bo'lsa qaysisini ochish: markaz ilovasida — o'sha markaz (a'zo bo'lsa), aks holda saqlangani.
int? preferredOrganization(List<int> available, int? saved) {
  if (isBranded && available.contains(brandOrganization)) return brandOrganization;
  if (saved != null && available.contains(saved)) return saved;
  return available.length == 1 ? available.first : null;
}
