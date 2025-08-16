# azure-tts-f0-apikey-generator

A projekt egy `ttsauto` nevű Bash függvényt tartalmaz, amely automatizálja az Azure Speech Service F0 (ingyenes) SKU létrehozását és az API-kulcs lekérését. A script ellenőrzi a meglévő erőforrásokat, teszteli a meglévő kulcsokat, majd szükség esetén új F0 fiókot hoz létre és visszaadja a kulcsot és az alapvégpontot.

## Követelmények

- Azure előfizetés és aktív bejelentkezés (`az login`)
- Azure CLI
- Bash shell

## Használat

1. Forrásold be a scriptet:
   ```bash
   source ttsauto.sh
   ```
2. Futtasd a `ttsauto` függvényt:
   ```bash
   ttsauto
   ```
   A parancs lépésről lépésre:
   - listázza a meglévő SpeechServices fiókokat és kipróbálja a TTS-hívást
   - ellenőrzi, hogy van-e már F0 SKU-s fiók
   - ha szükséges, létrehozza az `rg-speech-demo` erőforráscsoportot
   - kiválaszt egy szabad régiót és létrehoz egy új F0 fiókot
   - kiírja az elsődleges kulcsot és a bázis URL-t

A sikeres futás végén két sor jelenik meg: az API-kulcs, illetve az alap URL, amelyet a TTS végpontokhoz használhatsz.

## Figyelmeztetés

A script demonstrációs célra készült; éles környezetben alkalmazz megfelelő jogosultság- és erőforrás-kezelési szabályzatokat.

