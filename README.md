# azure-tts-f0-apikey-generator

Ez a projekt egy `ttsauto` nevű Bash függvényt tartalmaz, amely automatizálja az Azure Speech Services F0 (ingyenes) SKU létrehozását és az API-kulcs lekérését. A script először megpróbálja használni a meglévő erőforrásokat, majd szükség esetén törli a hibás F0 fiókokat, új régiót választ, és friss kulcsot állít elő.

## Követelmények

- Azure előfizetés és aktív bejelentkezés (`az login`)
- Azure CLI (2.49+ ajánlott)
- Bash shell (pl. Azure Cloud Shell)

## Használat

1. Forrásold be a scriptet:
   ```bash
   source ttsauto.sh
   ```
2. Futtasd a `ttsauto` függvényt:
   ```bash
   ttsauto
   ```

Futás közben a script:
- listázza a meglévő SpeechServices fiókokat, és TTS-próbahívást végez minden elérhető kulccsal;
- eltárolja a legutóbb használt F0 régiót (`~/.ttsauto_last_region`), hogy a következő futásnál más lokációt választhasson;
- ha van aktív F0 fiók és a próbahívás nem sikerül, törli azt, majd szükség esetén soft delete purge-öt indít és vár néhány másodpercet a felszabaduláshoz;
- a már létező régiókat kihagyva véletlenszerűen választ új régiót az F0 fiókhoz;
- biztosítja, hogy az `rg-speech-demo` erőforráscsoport létezzen, majd létrehozza az új F0 fiókot;
- a végén kiírja az elsődleges kulcsot és az alapvégpont URL-t.

Sikeres futás esetén két sor jelenik meg: az API-kulcs, valamint az alap URL, amelyet a TTS végpontokhoz használhatsz.

### Használat `~/.bashrc`-ból

Ha szeretnéd, hogy a `ttsauto` parancs minden új Bash sessionben elérhető legyen, add hozzá a scriptet a `~/.bashrc` fájlodhoz:

```bash
# ~/.bashrc
source /teljes/elérési/út/ttsauto.sh
```

A módosítás után töltsd be újra:

```bash
source ~/.bashrc
```

### Naplózás és hibaelhárítás

- A script minden lépést `[L<n>]` jelöléssel ír ki, így könnyű nyomon követni a futást.
- Ha a törlés vagy a purge hibát ad, a konzolon megjelenik az Azure CLI részletes üzenete.
- A `~/.ttsauto_last_region` fájlt törölheted, ha régiórotáció nélkül szeretnéd újra futtatni a scriptet.

## Figyelmeztetés

A script demonstrációs célra készült; éles környezetben alkalmazz megfelelő jogosultság- és erőforrás-kezelési szabályokat.
