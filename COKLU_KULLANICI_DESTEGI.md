# TeslaMate Çoklu Kullanıcı Desteği

## Genel Bakış

Bu doküman, TeslaMate'in birden fazla Tesla kullanıcı hesabı ile aynı anda çalışabilmesi için yapılan çoklu kullanıcı desteği implementasyonunu açıklamaktadır.

## Mimari Değişiklikler

### Veritabanı Şeması

#### Yeni `users` Tablosu
Tesla kullanıcı bilgilerini saklamak için `private` şemasına yeni bir `users` tablosu eklenmiştir:

```sql
CREATE TABLE private.users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255),
  name VARCHAR(255),
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

#### Güncellenen `tokens` Tablosu
`tokens` tablosuna `user_id` yabancı anahtarı eklenmiştir:
- `user_id INTEGER NOT NULL REFERENCES private.users(id) ON DELETE CASCADE`
- Her token seti artık belirli bir kullanıcı ile ilişkilendirilmiştir

#### Güncellenen `cars` Tablosu
`cars` tablosuna `user_id` yabancı anahtarı eklenmiştir:
- `user_id INTEGER NOT NULL REFERENCES private.users(id) ON DELETE CASCADE`
- Her araç artık sahibi olan kullanıcı ile ilişkilendirilmiştir

### Veri Modeli

**Önceki Mimari:**
```
Tokens (1) -> Araçlar (N)
```

**Yeni Mimari:**
```
Kullanıcılar (1) -> Tokens (1)
Kullanıcılar (1) -> Araçlar (N)
```

Tüm veriler (pozisyonlar, şarjlar, sürüşler, vb.) `car_id` ile bağlantılı olmaya devam etmektedir ve artık `user_id` yabancı anahtarı üzerinden kullanıcılara geçişli olarak bağlanmaktadır.

## Veri Çekme Mekanizması

Tesla API, verilen token'a ait **TÜM araçları** döndürür. Yani veri çekme işlemi **KULLANICI BAZLIDIR**, araç bazlı değildir.

### Nasıl Çalışır?

1. Bir Tesla hesabı ile kimlik doğrulama yapıldığında:
   - Access ve refresh token'lar alınır
   - Bu token'lar kullanılarak Tesla API'ye istek atılır
   
2. Tesla API, **o hesaba kayıtlı TÜM araçları** döndürür
   - Bir kullanıcının birden fazla aracı olabilir
   - API tek bir istekle tüm araçları getirir

3. Her araç için:
   - Araç bilgileri veritabanına kaydedilir
   - Araç, token sahibi kullanıcı ile ilişkilendirilir (`user_id`)
   - Araç verileri (pozisyon, şarj, sürüş vb.) periyodik olarak çekilir

### Çoklu Kullanıcı Senaryosu

**Örnek:**
- Kullanıcı 1 (user@example.com): 2 araca sahip (Model 3, Model Y)
- Kullanıcı 2 (other@example.com): 1 araca sahip (Model S)

TeslaMate şöyle çalışır:
1. Kullanıcı 1'in token'ları ile API çağrısı → Model 3 ve Model Y döner
2. Kullanıcı 2'nin token'ları ile API çağrısı → Model S döner
3. Tüm araçlar için bağımsız olarak veri toplanır
4. Her araç kendi sahibinin `user_id`'si ile ilişkilendirilir

## Uygulama Değişiklikleri

### 1. Yeni Modüller

**`TeslaMate.Auth.User`**
- `users` tablosu için schema modülü
- Veritabanında kullanıcı kayıtlarını yönetir
- Konum: `lib/teslamate/auth/user.ex`

**`TeslaMate.ApiRegistry`**
- Birden fazla API instance'ını yöneten supervisor
- Her kullanıcı için bir API instance'ı
- Kullanıcılar için API instance'larını başlatma/durdurma işlemlerini yapar
- Konum: `lib/teslamate/api_registry.ex`

### 2. Güncellenen Modüller

**`TeslaMate.Auth.Tokens`**
- `belongs_to :user, User` ilişkisi eklendi
- Changeset, `user_id`'yi zorunlu kıldı ve doğrular

**`TeslaMate.Log.Car`**
- `user_id` alanı eklendi
- `belongs_to :user, User` ilişkisi eklendi
- Changeset, `user_id`'yi zorunlu kıldı ve doğrular

**`TeslaMate.Auth`**
- Kullanıcı yönetimi fonksiyonları eklendi:
  - `list_users/0` - Tüm kullanıcıları getir
  - `get_user/1` - ID'ye göre kullanıcı getir
  - `get_user_by/1` - Parametrelere göre kullanıcı getir
  - `create_user/1` - Yeni kullanıcı oluştur
  - `update_user/2` - Kullanıcı bilgilerini güncelle
  - `delete_user/1` - Kullanıcı sil
  - `get_or_create_default_user/0` - Geriye dönük uyumluluk için varsayılan kullanıcıyı getir veya oluştur

- Çoklu kullanıcı için token yönetimi güncellendi:
  - `get_tokens_for_user/1` - Belirli bir kullanıcının token'larını getir
  - `get_all_tokens/0` - Tüm kullanıcıların tüm token'larını getir
  - `save_for_user/2` - Belirli bir kullanıcı için token'ları kaydet

- Geriye dönük uyumluluk korundu:
  - `get_tokens/0` - Hala çalışır, varsayılan kullanıcıyı kullanır
  - `save/1` - Hala çalışır, varsayılan kullanıcıyı kullanır

**`TeslaMate.Api`**
- Kullanıcıya özel kimlik doğrulamayı desteklemek için başlatma güncellendi
- İki stili destekleyen yardımcı fonksiyonlar eklendi:
  - Eski stil: `auth: TeslaMate.Auth` (modül)
  - Yeni stil: `auth: {TeslaMate.Auth, user_id}` (user_id ile tuple)

**`TeslaMate.Vehicles`**
- `create_or_update!/2` opsiyonel `user_id` parametresi kabul eder
- Belirtilmezse varsayılan kullanıcıya atar (geriye dönük uyumluluk)
- Yeni araçları doğru kullanıcıya atar

## Çoklu Kullanıcı Akışı

1. **Kullanıcı Kaydı**: Yeni bir Tesla kullanıcısı eklendiğinde:
   - Veritabanında yeni bir `User` kaydı oluşturulur
   - Kullanıcı Tesla kimlik bilgilerini sağlar
   - Token'lar `user_id` ilişkisi ile kaydedilir

2. **API Instance Yönetimi**:
   - `ApiRegistry` her kullanıcı için bir `Api` GenServer başlatır
   - Her API instance kendi kullanıcısının token'larını yönetir
   - Token yenileme her kullanıcı için bağımsız olarak gerçekleşir

3. **Araç Yönetimi**:
   - Bir kullanıcı için araçlar çekildiğinde, o kullanıcıya atanır
   - `Vehicles` supervisor tüm kullanıcıların tüm araçlarını yönetir
   - Her araç `user_id` üzerinden sahibini bilir

4. **Veri Toplama**:
   - Araç process'leri kendi kullanıcılarının API instance'ını kullanarak veri çeker
   - Toplanan tüm veriler (pozisyonlar, şarjlar, sürüşler) `car_id`'ye bağlıdır
   - Araçlar kullanıcılara bağlıdır, böylece tam bir sahiplik zinciri oluşur

## Geriye Dönük Uyumluluk

Implementasyon, mevcut tek kullanıcılı kurulumlarla tam uyumluluğu korur:

1. **Varsayılan Kullanıcı**: Migrasyon sırasında otomatik olarak "default_user@teslamate.local" kullanıcısı oluşturulur
2. **Mevcut Veri**: Tüm mevcut token'lar ve araçlar varsayılan kullanıcıya atanır
3. **Mevcut API Çağrıları**: Tüm mevcut fonksiyon çağrıları çalışmaya devam eder:
   - `Auth.get_tokens/0` - Varsayılan kullanıcı ile çalışır
   - `Auth.save/1` - Varsayılan kullanıcıya kaydeder
   - `Vehicles.create_or_update!/1` - Varsayılan kullanıcıya atar

## Migrasyon Yolu

### Mevcut Kurulumlar İçin

`20251222160325_create_users.exs` migrasyonu otomatik olarak:
1. `users` tablosunu oluşturur
2. Varsayılan kullanıcıyı oluşturur
3. `tokens` ve `cars` tablolarına `user_id` kolonlarını ekler
4. Tüm mevcut verileri varsayılan kullanıcı ile ilişkilendirir
5. Yabancı anahtar kısıtlamalarını ekler

Manuel müdahale gerekmez. Mevcut kurulumlar eskisi gibi çalışmaya devam eder.

### Yeni Çoklu Kullanıcı Dağıtımları İçin

TeslaMate'i birden fazla kullanıcı ile kullanmak için:

1. **Kullanıcı Ekle**: Her Tesla hesabı için kullanıcı kaydı oluştur
   ```elixir
   {:ok, user} = TeslaMate.Auth.create_user(%{
     email: "user@example.com",
     name: "Kullanıcı Adı"
   })
   ```

2. **Kullanıcı Kimlik Doğrulama**: Her kullanıcının Tesla kimlik bilgileri ile giriş yapmasını sağla
   - Bu, user_id ile ilişkilendirilmiş token'lar oluşturur
   - ApiRegistry onlar için bir API instance başlatır

3. **Araçları Çek**: Araçlar otomatik olarak çekilir ve doğru kullanıcı ile ilişkilendirilir

## Çoklu Kullanıcı için API Kullanımı

### Yeni Kullanıcı Oluşturma

```elixir
{:ok, user} = TeslaMate.Auth.create_user(%{
  email: "john@example.com",
  name: "John Doe"
})
```

### Bir Kullanıcı için Token Kaydetme

```elixir
TeslaMate.Auth.save_for_user(user.id, %{
  token: "access_token_buraya",
  refresh_token: "refresh_token_buraya"
})
```

### Bir Kullanıcının Token'larını Alma

```elixir
tokens = TeslaMate.Auth.get_tokens_for_user(user.id)
```

### Bir Kullanıcı için API Başlatma

```elixir
TeslaMate.ApiRegistry.start_api_for_user(user.id)
```

### Tüm Kullanıcıları Listeleme

```elixir
users = TeslaMate.Auth.list_users()
```

## Güvenlik Hususları

1. **Token Şifreleme**: Tüm token'lar mevcut `TeslaMate.Vault` şifreleme sistemi kullanılarak şifrelenir
2. **Private Şema**: Kullanıcı ve token verileri PostgreSQL'in `private` şemasında saklanır
3. **Cascade Delete**: Bir kullanıcının silinmesi, token'larını da siler ve araçlarının ilişkisini kaldırır
4. **Kullanıcı İzolasyonu**: Her kullanıcının API instance'ı izole edilmiştir ve kendi token yaşam döngüsünü yönetir

## Veritabanı Sorguları

### Bir Kullanıcının Tüm Araçlarını Bulma

```sql
SELECT * FROM cars WHERE user_id = <user_id>;
```

### Bir Kullanıcının Araçlarına Ait Tüm Verileri Bulma

```sql
-- Pozisyonlar
SELECT p.* FROM positions p
JOIN cars c ON p.car_id = c.id
WHERE c.user_id = <user_id>;

-- Şarjlar
SELECT ch.* FROM charges ch
JOIN charging_processes cp ON ch.charging_process_id = cp.id
JOIN cars c ON cp.car_id = c.id
WHERE c.user_id = <user_id>;

-- Sürüşler
SELECT d.* FROM drives d
JOIN cars c ON d.car_id = c.id
WHERE c.user_id = <user_id>;
```

### Kullanıcı Başına Araç Sayısı

```sql
SELECT u.email, COUNT(c.id) as arac_sayisi
FROM private.users u
LEFT JOIN cars c ON c.user_id = u.id
GROUP BY u.id, u.email;
```

## Gelecek İyileştirmeler

Çoklu kullanıcı desteği için potansiyel iyileştirmeler:

1. **Web UI**: TeslaMate web arayüzüne kullanıcı yönetimi ara yüzü ekleme
2. **API Endpoint'leri**: Kullanıcı ve araç yönetimi için REST API endpoint'leri oluşturma
3. **Kimlik Doğrulama**: Kullanıcı kimlik doğrulama/yetkilendirme katmanı ekleme
4. **Multi-Tenancy**: Tam çoklu kullanıcılı SaaS dağıtımı için tenant izolasyonu ekleme
5. **Kullanıcı Dashboard'ları**: Kullanıcı başına Grafana dashboard'ları oluşturma
6. **Kota Yönetimi**: Araç/kullanıcı limitleri ve kullanım kotaları ekleme

## Test Etme

Çoklu kullanıcı fonksiyonelliğini test etmek için:

1. Birden fazla kullanıcı oluştur:
   ```elixir
   {:ok, user1} = TeslaMate.Auth.create_user(%{email: "user1@test.com", name: "Kullanıcı 1"})
   {:ok, user2} = TeslaMate.Auth.create_user(%{email: "user2@test.com", name: "Kullanıcı 2"})
   ```

2. Her kullanıcı için token kaydet (Tesla kimlik doğrulamasından gerçek token'ları kullan)

3. Araçların doğru ilişkilendirildiğini doğrula:
   ```elixir
   TeslaMate.Log.list_cars()
   |> Enum.group_by(& &1.user_id)
   ```

4. Verilerin kullanıcı başına izole olduğunu araç ilişkileri üzerinden sorgulayarak kontrol et

## Sorun Giderme

### Sorun: Mevcut kurulum migrasyon sonrası çalışmıyor

**Çözüm**: Migrasyon otomatik olarak varsayılan kullanıcı oluşturmalı ve tüm verileri ilişkilendirmelidir. Kontrol edin:
```sql
SELECT * FROM private.users WHERE email = 'default_user@teslamate.local';
SELECT * FROM cars WHERE user_id IS NULL;
SELECT * FROM private.tokens WHERE user_id IS NULL;
```

Tüm araçların ve token'ların null olmayan bir user_id'si olmalıdır.

### Sorun: Yeni kullanıcı için API başlatılamıyor

**Çözüm**: Kullanıcının kayıtlı token'larının olduğundan emin olun:
```elixir
TeslaMate.Auth.get_tokens_for_user(user_id)
```

Eğer nil ise, kullanıcının önce kimlik doğrulaması yapması gerekir.

## Özet

Çoklu kullanıcı implementasyonu:

✅ Tam geriye dönük uyumluluğu korur  
✅ Minimal veritabanı değişiklikleri kullanır (user_id yabancı anahtarları ekler)  
✅ Uygun ilişkiler yoluyla kullanıcı verilerini izole eder  
✅ Kullanıcı başına bağımsız token yönetimini destekler  
✅ TeslaMate'in çoklu kullanıcı altyapısı olarak hizmet vermesini sağlar  
✅ Mevcut veri bütünlüğünü korur  
✅ Mevcut güvenlik önlemlerini kullanır (şifreleme, private şema)  

Bu implementasyon hem tek kullanıcılı (mevcut davranış) hem de çoklu kullanıcılı senaryolar için production-ready'dir.

## Önemli Notlar

- **Veri çekme KULLANICI bazlıdır**: Tesla API, bir kullanıcının token'ı ile o kullanıcının TÜM araçlarını döndürür
- **Araç başına ayrı veri çekimi YOKTUR**: Her araç için ayrı token gerekmez, kullanıcının token'ı yeterlidir
- **Kullanıcılar bağımsızdır**: Her kullanıcının kendi token'ları ve araçları vardır
- **Veri ilişkileri korunur**: Tüm veri hala car_id'ye bağlıdır, sadece araçlar artık kullanıcılara da bağlıdır
