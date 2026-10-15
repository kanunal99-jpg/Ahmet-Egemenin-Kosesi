# Ahmet-Egemenin-Kosesi — KANITLI TEKNİK DENETİM

**Tarih:** 15.10.2026  
**Kapsam:** GitHub dosya ağacı, seçili kaynak kodları, CI logları, Releases. Bu belge gerçek cihaz uçtan uca testi yerine geçmez.  
**Dosya sayısı (denetim anında):** 124  
**CI gözlemi:** 15.10.2026 CI başarısız; Typecheck/build başarılı; Playwright E2E secret eksik, deploy/smoke skipped.  
**Anayasa:** [PROJE_ANAYASASI_VE_DUZELTILECEKLER.md](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/blob/main/PROJE_ANAYASASI_VE_DUZELTILECEKLER.md)

## Kanıtlarla Düzeltilmesi Gerekenler

### 1. Kimlikli tarayıcı testleri başlayamıyor — P0 (DOĞRULANMIŞ CI BLOKAJI)
- **Dosya/kanıt:** [.github/workflows/ci.yml](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/blob/main/.github/workflows/ci.yml); [CI koşusu](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/actions/runs/38673138156)
- **Gözlem:** İş akışı 'Require authenticated E2E configuration' aşamasında E2E_EMAIL eksikliği ile duruyor.
- **Somut örnek / etkisi:** Playwright senaryoları çalışmadığı için bir kod değişikliğinin ebeveyn/çocuk yetki akışını bozup bozmadığı doğrulanamıyor.
- **Düzeltme öncesi kabul kriteri:** Test kullanıcıları ve gerekli E2E_EMAIL/E2E_PASSWORD ayarları güvenli Secrets'tan sağlansın; hiçbir sır repoya yazılmasın; full CI yeşil.
- **Durum:** ARAŞTIRILDI — henüz kaynak kod düzeltmesi veya cihaz testi yapılmadı.

### 2. Deploy ve canlı smoke atlanıyor — P1 (DOĞRULANMIŞ YAYIN BLOKAJI)
- **Dosya/kanıt:** [actions](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/actions); [CI koşusu](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/actions/runs/38673138156)
- **Gözlem:** Başarısız CI'nin ardından Pages deploy ve production smoke 'skipped' durumda.
- **Somut örnek / etkisi:** Kod tip denetiminden geçse bile üretime ulaşmıyor.
- **Düzeltme öncesi kabul kriteri:** E2E sırasındaki problemi giderip deploy ve gerçek Pages smoke başarı kanıtı alın.
- **Durum:** ARAŞTIRILDI — henüz kaynak kod düzeltmesi veya cihaz testi yapılmadı.

### 3. Ebeveyn kontrolleri ve RLS entegrasyonu — P1 (RİSK / GÜVENLİK TESTİ)
- **Dosya/kanıt:** [src/services/parentalControl.service.ts#L32-L117](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/blob/main/src/services/parentalControl.service.ts#L32-L117); [CI koşusu](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/actions/runs/38673138156)
- **Gözlem:** Frontend authorizasyon hizmeti video erişimini Supabase verisinden yönetiyor; gerçek child/parent RLS testleri CI başarısız olduğu için uçtan uca kanıtlanmadı.
- **Somut örnek / etkisi:** Çocuk kısıtlı videonun URL'sini doğrudan açtığında yetkisiz playback olmamalı.
- **Düzeltme öncesi kabul kriteri:** Çocuk, ebeveyn, misafir rol matrisi; süre limiti, kategori kısıtı, oturum ve yeniden giriş testleri.
- **Durum:** ARAŞTIRILDI — henüz kaynak kod düzeltmesi veya cihaz testi yapılmadı.

### 4. Kod ağacı API erişiminde tutarsızlık — P2 (KAPSAM SINIRI)
- **Dosya/kanıt:** [actions/runs/38673138156](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/actions/runs/38673138156); [CI koşusu](https://github.com/kanunal99-jpg/Ahmet-Egemenin-Kosesi/actions/runs/38673138156)
- **Gözlem:** Dosya bazlı bazı yollar erişilebilirken git/trees/main endpoint'i 409 döndü; tamamını satır satır okuduğum söylenemez.
- **Somut örnek / etkisi:** Bir sonraki araştırmada tam dosya diff'i ve son commit ağacı yeniden denenmeli.
- **Düzeltme öncesi kabul kriteri:** Ağaç erişimi ve test raporları yeniden alınarak kapsam tamamlanmalı.
- **Durum:** ARAŞTIRILDI — henüz kaynak kod düzeltmesi veya cihaz testi yapılmadı.

## 4 Fazlı Geliştirme ve Doğrulama Kapıları

1. **Faz 1 — Araştır:** Tam modül/dosya ve bağımlılık envanteri, doğrulanmış/farklılaşmış hatalar, etki analizi. **Bu rapor ilk kaynak/CI kanıtıdır; bütün işlevlerin çalıştığını iddia etmez.**
2. **Faz 2 — Düzelt:** Önce P0/P1, en küçük güvenli kod değişimi, gizli anahtar/ücret/erişim izinlerini güvenli yöntemlerle ele al.
3. **Faz 3 — Uygulama ve test:** Unit, integrasyon, UI, offline, yetki reddi, yanlış veri, servis kesintisi, gerçek fallback, CI + Android gerçek cihaz varsa.
4. **Faz 4 — Yayın:** CI yeşil → Android ise SHA-256'lı indirilebilir Release APK → kullanıcı akışları smoke → kanıt linkleri.

## Kapatma Kriteri
Her bulgu için issue veya değişiklik ID'si, önce/sonra kanıtı, ilgili satır, test raporu, CI koşu bağlantısı, release/dağıtım bağlantısı, sonuç tarihi zorunludur. **Yalnızca belgenin eklenmiş olması sorun giderildi anlamına gelmez.**
