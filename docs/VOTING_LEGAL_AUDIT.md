# Právny audit hlasovacieho systému / Voting System Legal Audit

**Aplikácia:** OpenResiApp
**Verzia dokumentu:** 1.0
**Dátum:** 2026-03-09
**Účel:** Dokumentácia implementácie hlasovania pre právny audit súladu so slovenskou legislatívou

---

## 1. Právny rámec / Legal Framework

Hlasovací systém je navrhnutý v súlade s:

- **Zákon č. 182/1993 Z.z.** o vlastníctve bytov a nebytových priestorov (ďalej len „zákon o bytoch")
- **Občiansky zákonník** (Zákon č. 40/1964 Zb.) — spoluvlastnícke podiely
- **Zákon č. 305/2013 Z.z.** o elektronickej podobe výkonu pôsobnosti orgánov verejnej moci (eGovernment) — pre elektronické hlasovanie

### 1.1 Kľúčové ustanovenia zákona o bytoch

| Ustanovenie | Obsah | Implementácia v systéme |
|-------------|-------|-------------------------|
| § 14 ods. 1 | Vlastník bytu má právo hlasovať o správe domu | Rola `owner` má oprávnenie `vote` |
| § 14 ods. 2 | Hlas vlastníka je rátaný podľa veľkosti spoluvlastníckeho podielu | Metóda `per_share` (predvolená) |
| § 14a ods. 1 | Schôdza vlastníkov — hlasovanie prezenčne | Typ `meeting` s papierovými hlasmi |
| § 14a ods. 2 | Písomné hlasovanie | Typ `written` s elektronickými aj papierovými hlasmi |
| § 14a ods. 4 | Splnomocnenie — úradne osvedčený podpis | Systém mandátov vyžaduje potvrdenie listinného dokumentu |
| § 14b ods. 1 | Nadpolovičná väčšina hlasov všetkých vlastníkov | Kvórum `simple_all` |
| § 14b ods. 2 | Dvojtretinová väčšina hlasov všetkých vlastníkov | Kvórum `two_thirds_all` |
| § 14b ods. 5 | Štvrtina vlastníkov môže iniciovať hlasovanie | Typ iniciátora `owners_quarter` |

---

## 2. Dátový model hlasovania / Voting Data Model

### 2.1 Tabuľka `votings` (Hlasovania)

| Stĺpec | Typ | Popis |
|---------|-----|-------|
| `id` | UUID | Primárny kľúč |
| `title` | VARCHAR(500) | Názov hlasovania |
| `description` | TEXT | Popis predmetu hlasovania |
| `status` | ENUM | Stav: `draft` (návrh), `active` (aktívne), `closed` (ukončené) |
| `starts_at` | TIMESTAMP | Začiatok hlasovania |
| `ends_at` | TIMESTAMP | Koniec hlasovania |
| `voting_type` | ENUM | `written` (písomné) alebo `meeting` (na schôdzi) |
| `initiated_by` | ENUM | `board` (správca/zástupca) alebo `owners_quarter` (štvrtina vlastníkov) |
| `quorum_type` | ENUM | Typ kvóra (viď sekcia 4) |
| `vote_counter_id` | UUID | Overovateľ — osoba poverená sčítaním hlasov |
| `created_by_id` | UUID | Kto hlasovanie vytvoril |

### 2.2 Tabuľka `votes` (Hlasy)

| Stĺpec | Typ | Popis |
|---------|-----|-------|
| `id` | UUID | Primárny kľúč |
| `voting_id` | UUID | Referencia na hlasovanie |
| `owner_id` | UUID | Vlastník, ktorý hlasoval |
| `flat_id` | UUID | Byt, za ktorý sa hlasuje |
| `choice` | ENUM | `za`, `proti`, `zdrzal_sa` |
| `vote_type` | ENUM | `electronic` (elektronický) alebo `paper` (listinný) |
| `recorded_by_id` | UUID | Kto zapísal hlas (pri listinnom hlasovaní) |
| `paper_photo_url` | VARCHAR(1000) | Fotokópia listinného hlasovacieho lístka |
| `audit_hash` | VARCHAR(64) | SHA-256 hash pre overenie integrity (viď sekcia 7) |
| `disputed` | BOOLEAN | Či je hlas napadnutý |
| `dispute_note` | TEXT | Poznámka k napadnutiu |
| `created_at` | TIMESTAMP | Čas zaznamenania hlasu |

**Unikátny index:** `(voting_id, flat_id)` — za jeden byt môže byť v jednom hlasovaní len jeden hlas.

### 2.3 Tabuľka `flats` (Byty)

| Stĺpec | Typ | Popis |
|---------|-----|-------|
| `share_numerator` | INTEGER | Čitateľ spoluvlastníckeho podielu |
| `share_denominator` | INTEGER | Menovateľ spoluvlastníckeho podielu |
| `area` | INTEGER | Plocha bytu v m² (voliteľné) |

### 2.4 Tabuľka `mandates` (Splnomocnenia)

| Stĺpec | Typ | Popis |
|---------|-----|-------|
| `id` | UUID | Primárny kľúč |
| `voting_id` | UUID | Referencia na hlasovanie |
| `from_owner_id` | UUID | Splnomocniteľ (kto dáva plnú moc) |
| `from_flat_id` | UUID | Byt splnomocniteľa |
| `to_owner_id` | UUID | Splnomocnenec (kto prijíma plnú moc) |
| `paper_document_confirmed` | BOOLEAN | Potvrdenie existencie listinného dokumentu |
| `verified_by_admin_id` | UUID | Administrátor, ktorý overil splnomocnenie |
| `verification_date` | TIMESTAMP | Dátum overenia |
| `verification_note` | TEXT | Poznámka k overeniu |
| `is_active` | BOOLEAN | Či je splnomocnenie aktívne |

**Unikátny index:** `(voting_id, from_flat_id)` — na jeden byt môže byť v jednom hlasovaní len jedno splnomocnenie.

---

## 3. Metódy výpočtu váhy hlasu / Voting Weight Methods

Systém podporuje tri metódy výpočtu váhy hlasu. Metóda sa nastavuje na úrovni budovy (tabuľka `building.voting_method`).

### 3.1 Podľa spoluvlastníckeho podielu (`per_share`) — PREDVOLENÁ

```
váha = share_numerator / share_denominator
```

**Právny základ:** § 14 ods. 2 zákona o bytoch — „Vlastník bytu a nebytového priestoru v dome má právo a povinnosť zúčastňovať sa na správe domu a hlasovaním rozhodovať ako spoluvlastník o spoločných častiach domu..."

**Príklad:**
- Byt 1: podiel 253/10000 → váha 0,0253
- Byt 2: podiel 487/10000 → váha 0,0487
- Súčet všetkých podielov = 1,0 (10000/10000)

**Implementácia:** Súbor `src/lib/voting.ts`, funkcia `getWeight()`, riadok 10-12:
```typescript
case "per_share":
default:
  return vote.shareNumerator / vote.shareDenominator;
```

### 3.2 Podľa počtu bytov (`per_flat`)

```
váha = 1 (za každý byt)
```

**Právny základ:** § 14b ods. 4 zákona o bytoch — pre niektoré rozhodnutia „rozhoduje sa nadpolovičnou väčšinou hlasov všetkých vlastníkov bytov a nebytových priestorov v dome" — kde hlas = 1 byt.

**Implementácia:** `getWeight()`, riadok 6-7:
```typescript
case "per_flat":
  return 1;
```

### 3.3 Podľa plochy bytu (`per_area`)

```
váha = plocha bytu v m²
```

**Implementácia:** `getWeight()`, riadok 8-9:
```typescript
case "per_area":
  return vote.area ?? 1;
```

> **Poznámka pre audit:** Ak plocha nie je zadaná, systém použije váhu 1. Toto je záložné správanie — v praxi by mali mať všetky byty zadanú plochu.

### 3.4 Agregácia hlasov vlastníka s viacerými bytmi

Ak vlastník vlastní viac bytov, systém agreguje ich podiely. Implementácia: `aggregateFlatsForVoter()` v `src/lib/voting.ts`:

- Pri rovnakých menovateľoch (typický prípad — všetky podiely z 10000): jednoduchý súčet čitateľov
- Pri rôznych menovateľoch: výpočet cez najmenší spoločný násobok (LCM)
- Plochy sa sčítajú

**Dôležité:** Aj keď vlastník vlastní viac bytov, **hlasuje sa za každý byt samostatne** (unikátny index `votes_voting_flat_idx` na `(voting_id, flat_id)`). Toto zodpovedá zákonu — hlas je viazaný na byt, nie na osobu.

---

## 4. Typy kvóra / Quorum Types

### 4.1 Nadpolovičná väčšina prítomných (`simple_present`)

```
Schválené ak: hlasy ZA > 50% zo súčtu váh všetkých odovzdaných hlasov
```

**Právny základ:** § 14a ods. 1 — bežné rozhodovanie na schôdzi vlastníkov.

**Implementácia** (`calculateResults()`, riadky 39-42):
```typescript
case "simple_present":
  quorumReached = totalWeight > 0;
  passed = zaWeight > totalWeight / 2;
```

**Poznámka:** Kvórum je splnené, ak hlasoval aspoň jeden vlastník. Podmienka je **striktná nerovnosť** (`>`), čiže presne 50% nestačí.

### 4.2 Nadpolovičná väčšina všetkých vlastníkov (`simple_all`) — PREDVOLENÁ

```
Schválené ak: hlasy ZA > 50% zo súčtu váh VŠETKÝCH bytov v dome
```

**Právny základ:** § 14b ods. 1 — „Vlastníci bytov a nebytových priestorov v dome prijímajú rozhodnutia nadpolovičnou väčšinou hlasov všetkých vlastníkov bytov a nebytových priestorov v dome."

**Implementácia** (riadky 44-47):
```typescript
case "simple_all":
  quorumReached = totalPossibleWeight > 0 && zaWeight > totalPossibleWeight / 2;
  passed = quorumReached;
```

**Poznámka:** `totalPossibleWeight` sa počíta zo **všetkých bytov v dome**, nie len z tých, kde sa hlasovalo. Podmienka je striktná nerovnosť (`>`).

### 4.3 Dvojtretinová väčšina všetkých vlastníkov (`two_thirds_all`)

```
Schválené ak: hlasy ZA ≥ 66,67% zo súčtu váh VŠETKÝCH bytov v dome
```

**Právny základ:** § 14b ods. 2 — napríklad zmena účelu spoločných častí, nadstavba, vstavba, zmluva o úvere, zmena zmluvy o spoločenstve.

**Implementácia** (riadky 49-53):
```typescript
case "two_thirds_all":
  quorumReached = totalPossibleWeight > 0 && zaWeight >= (totalPossibleWeight * 2) / 3;
  passed = quorumReached;
```

**Poznámka:** Tu sa používa **nestriktná nerovnosť** (`>=`), čiže presne 2/3 stačí na schválenie.

---

## 5. Typy hlasovania / Voting Types

### 5.1 Písomné hlasovanie (`written`)

**Právny základ:** § 14a ods. 2-3 zákona o bytoch.

- Vlastníci môžu hlasovať **elektronicky** (cez aplikáciu) aj **listinne** (papierový hlasovací lístok)
- Elektronický hlas zaznamenáva vlastník sám
- Listinný hlas zaznamenáva administrátor alebo overovateľ (`vote_counter`)

### 5.2 Hlasovanie na schôdzi (`meeting`)

**Právny základ:** § 14a ods. 1 zákona o bytoch.

- Vlastníci môžu hlasovať **len listinne** (papierový hlasovací lístok)
- Elektronické hlasovanie je **zablokované** systémom
- Hlasy zaznamenáva administrátor alebo overovateľ

**Implementácia blokovania** (`src/app/api/votes/route.ts`, riadky 170-175):
```typescript
if (!isPaperVote && voting.votingType === "meeting") {
  return NextResponse.json(
    { error: "Elektronické hlasovanie nie je povolené pre hlasovanie na schôdzi" },
    { status: 400 }
  );
}
```

### 5.3 Hlasovanie iniciované štvrtinou vlastníkov (`owners_quarter`)

**Právny základ:** § 14b ods. 5 — „Ak vlastníci bytov a nebytových priestorov v dome, ktorí majú aspoň štvrtinu hlasov všetkých vlastníkov, požiadajú o zvolanie schôdze vlastníkov..."

- Elektronické hlasovanie je **zablokované** — vyžaduje sa fyzická schôdza
- Hlasy len listinné

**Implementácia** (riadky 178-183):
```typescript
if (!isPaperVote && voting.initiatedBy === "owners_quarter") {
  return NextResponse.json(
    { error: "Elektronické hlasovanie nie je povolené pre hlasovanie iniciované štvrtinou vlastníkov" },
    { status: 400 }
  );
}
```

---

## 6. Splnomocnenia (Mandáty) / Mandates (Proxies)

### 6.1 Právny základ

**§ 14a ods. 4 zákona o bytoch:** „Vlastník bytu a nebytového priestoru v dome môže v listinnej podobe, s úradne osvedčeným podpisom, splnomocniť inú osobu, aby ho pri hlasovaní zastupovala."

### 6.2 Implementované pravidlá

| Pravidlo | Právny základ | Implementácia |
|----------|--------------|---------------|
| Splnomocnenie vyžaduje potvrdenie listinného dokumentu s úradne osvedčeným podpisom | § 14a ods. 4 | Pole `paper_document_confirmed` musí byť `true`, inak systém odmietne vytvorenie |
| Jedno splnomocnenie na byt na hlasovanie | Logické obmedzenie | Unikátny index `mandates_voting_flat_idx` na `(voting_id, from_flat_id)` |
| Zákaz reťazenia splnomocnení | § 14a ods. 4 | Systém kontroluje, či príjemca splnomocnenia sám nedelegoval svoj hlas |
| Len administrátor vytvára splnomocnenia | Správcovská funkcia | Oprávnenie `grantMandate` má len rola `admin` |
| Overenie administrátorom | Vnútorná kontrola | Zaznamenáva sa `verified_by_admin_id` a `verification_date` |

### 6.3 Validácia reťazenia splnomocnení

Systém zabraňuje situácii, keď osoba A splnomocní osobu B, a osoba B už predtým splnomocnila osobu C. Toto by vytvorilo reťaz delegácií, čo zákon nepovoľuje.

**Implementácia** (`src/app/api/mandates/route.ts`, riadky 125-142):
```typescript
const chainCheck = await db
  .select()
  .from(mandates)
  .where(
    and(
      eq(mandates.votingId, votingId),
      eq(mandates.fromOwnerId, toOwnerId),
      eq(mandates.isActive, true)
    )
  )
  .limit(1);

if (chainCheck.length > 0) {
  return NextResponse.json(
    { error: "Príjemca splnomocnenia už delegoval svoj hlas — reťazenie splnomocnení nie je povolené" },
    { status: 400 }
  );
}
```

---

## 7. Audit trail / Auditný záznam

### 7.1 Integritný hash

Každý hlas je zabezpečený SHA-256 hashom, ktorý obsahuje:

- ID hlasovania (`votingId`)
- ID vlastníka (`ownerId`)
- ID bytu (`flatId`)
- Voľbu (`choice`)
- Časovú pečiatku (`timestamp`)
- Tajný kľúč servera (`NEXTAUTH_SECRET`)

**Implementácia** (`src/lib/voting.ts`, riadky 142-152):
```typescript
export function generateAuditHash(
  votingId: string,
  ownerId: string,
  flatId: string,
  choice: string,
  timestamp: Date
): string {
  const secret = process.env.NEXTAUTH_SECRET || "";
  const data = `${votingId}${ownerId}${flatId}${choice}${timestamp.toISOString()}${secret}`;
  return createHash("sha256").update(data).digest("hex");
}
```

**Účel:** Hash slúži na overenie, že hlas nebol manipulovaný po zaznamenaní. Zmena akéhokoľvek vstupného parametra by produkovala iný hash.

### 7.2 E-mailové potvrdenie

Pri elektronickom hlase systém odosiela potvrdzujúci e-mail vlastníkovi obsahujúci:
- Meno hlasujúceho
- Názov hlasovania
- Číslo bytu
- Voľbu
- Časovú pečiatku
- Auditný hash

Konfigurovateľné cez premennú `REQUIRE_VOTE_EMAIL`:
- `"true"` — hlas sa zaznamená len ak sa e-mail úspešne odošle (transakčný režim)
- inak — hlas sa zaznamená a e-mail sa odosiela asynchrónne (best-effort)

### 7.3 Zaznamenané údaje pri hlase

Pre každý hlas sa ukladá:
- Kto hlasoval (`owner_id`)
- Za aký byt (`flat_id`)
- Aká voľba (`choice`)
- Typ hlasu — elektronický/listinný (`vote_type`)
- Kto zapísal listinný hlas (`recorded_by_id`)
- Fotokópia listinného hlasovacieho lístka (`paper_photo_url`)
- Integritný hash (`audit_hash`)
- Či je hlas napadnutý (`disputed`, `dispute_note`)
- Čas zaznamenania (`created_at`)

---

## 8. Oprávnenia a role / Permissions and Roles

### 8.1 Definované role

| Rola | Slovenský názov | Popis |
|------|-----------------|-------|
| `admin` | Administrátor / Správca | Plné oprávnenia — vytváranie hlasovaní, správa používateľov |
| `owner` | Vlastník | Hlasovanie, prezeranie výsledkov |
| `tenant` | Nájomník | Bez hlasovacích práv |
| `vote_counter` | Overovateľ | Zapisovanie listinných hlasov |
| `caretaker` | Domovník | Prezeranie výsledkov, správa oznamov |

### 8.2 Oprávnenia súvisiace s hlasovaním

| Oprávnenie | Popis | Role |
|------------|-------|------|
| `createVoting` | Vytvoriť nové hlasovanie | `admin` |
| `vote` | Hlasovať elektronicky | `admin`, `owner` |
| `recordPaperVote` | Zapísať listinný hlas | `admin`, `vote_counter` |
| `viewVotingResults` | Prezerať výsledky hlasovania | `admin`, `owner`, `caretaker` |
| `assignVoteCounter` | Prideliť overovateľa | `admin` |
| `grantMandate` | Vytvoriť splnomocnenie | `admin` |

**Právna poznámka:** Nájomníci (`tenant`) nemajú hlasovacie právo, čo je v súlade so zákonom — hlasovať môžu len vlastníci bytov a nebytových priestorov.

---

## 9. Obchodná logika a validácie / Business Logic and Validations

### 9.1 Validácie pri hlasovaní

| Kontrola | Chybová hláška | Právny dôvod |
|----------|-----------------|--------------|
| Hlasovanie musí byť aktívne | „Hlasovanie nie je aktívne" | Hlasovať sa dá len v stanovenom termíne |
| Vlastník musí vlastniť byt | „Vlastník nevlastní tento byt" | § 14 — hlasuje len vlastník |
| Jeden hlas za byt na hlasovanie | Unikátny index `votes_voting_flat_idx` | Jeden byt = jeden hlas |
| Elektronický hlas len pre písomné hlasovanie | „Elektronické hlasovanie nie je povolené pre hlasovanie na schôdzi" | § 14a ods. 1 — schôdza je prezenčná |
| Hlasovanie iniciované štvrtinou — len listinne | „Elektronické hlasovanie nie je povolené..." | § 14b ods. 5 |
| Zmena hlasu len pôvodným hlasujúcim | „Za tento byt už hlasoval iný vlastník" | Integrita hlasovania |

### 9.2 Zmena hlasu

Systém umožňuje vlastníkovi **zmeniť** svoj elektronický hlas, pokiaľ je hlasovanie stále aktívne:
- Kontroluje sa, či pôvodný hlas odovzdal ten istý vlastník
- Pri zmene sa generuje nový auditný hash
- Odosiela sa nový potvrdzujúci e-mail

**Právna poznámka:** Zákon explicitne neupravuje zmenu hlasu pri písomnom hlasovaní. Odporúčame právne posúdenie, či je táto funkcionalita v súlade s vnútornými pravidlami konkrétneho spoločenstva.

### 9.3 Výpočet celkovej váhy

`totalPossibleWeight` sa počíta zo **všetkých bytov v databáze**, nie len z bytov, za ktoré sa hlasovalo. Toto je kľúčové pre kvóra typu `simple_all` a `two_thirds_all`, kde sa väčšina počíta z celkového počtu/váhy.

**Implementácia** (`src/app/api/votes/route.ts`, riadky 75-97):
```typescript
const allFlats = await db.select({...}).from(flats);
let totalPossibleWeight = 0;
for (const f of allFlats) {
  switch (votingMethod) {
    case "per_flat": totalPossibleWeight += 1; break;
    case "per_area": totalPossibleWeight += f.area ?? 1; break;
    case "per_share":
    default:
      totalPossibleWeight += f.shareNumerator / f.shareDenominator; break;
  }
}
```

---

## 10. Výstupné údaje hlasovania / Voting Results Output

Systém vracia nasledujúce výsledky:

| Pole | Popis |
|------|-------|
| `za` | Súčet váh hlasov ZA |
| `proti` | Súčet váh hlasov PROTI |
| `zdrzalSa` | Súčet váh hlasov ZDRŽAL SA |
| `total` | Súčet váh všetkých odovzdaných hlasov |
| `zaPercent` | Percento ZA z odovzdaných hlasov |
| `protiPercent` | Percento PROTI z odovzdaných hlasov |
| `zdrzalSaPercent` | Percento ZDRŽAL SA z odovzdaných hlasov |
| `passed` | Či bolo hlasovanie schválené |
| `quorumReached` | Či bolo dosiahnuté kvórum |
| `quorumType` | Typ použitého kvóra |
| `totalPossibleWeight` | Celková váha všetkých bytov v dome |

---

## 11. Otvorené otázky pre právne posúdenie / Open Questions for Legal Review

### 11.1 Elektronické hlasovanie

- **Otázka:** Je elektronické hlasovanie cez webovú aplikáciu dostatočne právne záväzné pre písomné hlasovanie podľa § 14a ods. 2?
- **Súčasný stav:** Systém overuje identitu cez e-mail/heslo (NextAuth), zaznamenáva auditný hash a odosiela e-mailové potvrdenie. Nepoužíva kvalifikovaný elektronický podpis.

### 11.2 Zmena hlasu

- **Otázka:** Je prípustné umožniť vlastníkovi zmeniť svoj hlas počas trvania písomného hlasovania?
- **Súčasný stav:** Systém to umožňuje pre elektronické hlasy, pôvodný hlas sa prepíše novým.

### 11.3 Overovateľ (vote_counter)

- **Otázka:** Zodpovedá rola `vote_counter` v systéme požiadavke zákona na overovateľov podľa § 14a?
- **Súčasný stav:** Overovateľ môže zapisovať listinné hlasy, ale systém neimplementuje formálny podpis zápisnice.

### 11.4 Zdržal sa

- **Otázka:** Ako sa má správne započítavať hlas „zdržal sa" pri výpočte kvóra?
- **Súčasný stav:** Pre `simple_all` a `two_thirds_all` sa kvórum počíta len z hlasov ZA voči celkovej váhe — hlasy „zdržal sa" sa nepočítajú do kvóra, ale započítavajú sa do celkového počtu odovzdaných hlasov.

### 11.5 Časový rámec hlasovania

- **Otázka:** Systém má polia `starts_at` a `ends_at`, ale neimplementuje automatické ukončenie hlasovania po uplynutí termínu. Stav sa mení manuálne administrátorom.
- **Odporúčanie:** Zvážiť automatické uzavretie hlasovania po `ends_at`.

### 11.6 Nebytové priestory

- **Otázka:** Systém pracuje s pojmom „byty" (flats), ale zákon sa vzťahuje aj na nebytové priestory. Tieto sú v databáze reprezentované rovnako ako byty — čo je technicky korektné, ale terminológia v UI by mala zahŕňať aj nebytové priestory.

---

## 12. Zhrnutie súladu / Compliance Summary

| Požiadavka zákona | Status | Poznámka |
|--------------------|--------|----------|
| Hlasovanie podľa spoluvlastníckeho podielu | ✅ Implementované | Predvolená metóda `per_share` |
| Nadpolovičná väčšina všetkých vlastníkov | ✅ Implementované | Kvórum `simple_all` |
| Dvojtretinová väčšina všetkých vlastníkov | ✅ Implementované | Kvórum `two_thirds_all` |
| Písomné hlasovanie | ✅ Implementované | Typ `written` |
| Hlasovanie na schôdzi | ✅ Implementované | Typ `meeting`, len papierové hlasy |
| Splnomocnenie s úradne osvedčeným podpisom | ⚠️ Čiastočne | Systém vyžaduje potvrdenie, ale neoveruje digitálne |
| Zákaz reťazenia splnomocnení | ✅ Implementované | Validácia v API |
| Hlasovanie iniciované štvrtinou vlastníkov | ✅ Implementované | Typ `owners_quarter` |
| Overovateľ hlasovania | ✅ Implementované | Rola `vote_counter` |
| Nájomníci nemajú hlasovacie právo | ✅ Implementované | Rola `tenant` nemá oprávnenie `vote` |
| Auditný záznam | ✅ Implementované | SHA-256 hash, e-mailové potvrdenie |
| Automatické ukončenie hlasovania | ❌ Chýba | Administrátor musí manuálne ukončiť |
| Zápisnica z hlasovania | ❌ Chýba | Systém negeneruje formálnu zápisnicu |

---

*Tento dokument bol vytvorený pre účely právneho auditu. Odporúčame konzultáciu s advokátom špecializujúcim sa na bytové právo pre záväzné právne posúdenie.*