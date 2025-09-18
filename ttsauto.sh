# Begin ~/.bashrc (safe sourcing, nincs unbound hiba)
set +u 2>/dev/null || true

if [ -f "/etc/bash.bashrc" ] ; then
  source /etc/bash.bashrc
fi

if [ -f /etc/bash_completion.d/azure-cli ]; then
  source /etc/bash_completion.d/azure-cli
fi

shopt -s histappend
HISTCONTROL=ignoreboth
PROMPT_COMMAND="history -a; history -c; history -r; ${PROMPT_COMMAND:-}"
PS1=${PS1//\\h/Azure}

if [ -f /usr/bin/cloudshellhelp ]; then
  source /usr/bin/cloudshellhelp 2>/dev/null || true
fi

ttsauto() {
  set -o pipefail

  local VOICE="hu-HU-TamasNeural"
  local TEST_TEXT="t"
  local RG_NAME="rg-speech-demo"
  local -a ALL_REGIONS=(
    "westeurope" "northeurope" "francecentral" "germanywestcentral"
    "swedencentral" "uksouth" "italynorth" "spaineast"
  )
  local STATE_FILE="${HOME}/.ttsauto_last_region"
  local PREV_REGION=""
  if [ -f "$STATE_FILE" ]; then
    read -r PREV_REGION < "$STATE_FILE" || PREV_REGION=""
  fi
  local F0_ACC_NAME="" F0_ACC_RG="" F0_ACC_LOC=""

  step() { echo "[L${1}] ${2}"; }
  fail() { echo "Hiba: ${1}"; }

  step 1 "Meglévő SpeechServices erőforrások lekérése";
  local -a ACCS=()
  mapfile -t ACCS < <(az cognitiveservices account list \
    --query "[?kind=='SpeechServices'].{name:name,rg:resourceGroup,loc:location,sku:sku.name,ep:endpoints}" -o tsv 2>/dev/null || true)
  if [ "${#ACCS[@]}" -gt 0 ]; then
    for rec in "${ACCS[@]}"; do echo "  - $(awk '{printf("%s (rg:%s loc:%s sku:%s)", $1,$2,$3,$4)}' <<<"$rec")"; done
  else
    echo "  - Nincs meglévő SpeechServices fiók"
  fi

  step 2 "F0-limit ellenőrzése";
  local F0_COUNT; F0_COUNT=$(az cognitiveservices account list --query "length([?kind=='SpeechServices' && sku.name=='F0'])" -o tsv 2>/dev/null || echo 0)
  echo "  - F0 darab: ${F0_COUNT}"

  if [ "${#ACCS[@]}" -gt 0 ]; then
    for rec in "${ACCS[@]}"; do
      if [ "$(awk '{print $4}' <<<"$rec")" = "F0" ]; then
        F0_ACC_NAME=$(awk '{print $1}' <<<"$rec")
        F0_ACC_RG=$(awk '{print $2}' <<<"$rec")
        F0_ACC_LOC=$(awk '{print $3}' <<<"$rec")
        break
      fi
    done
  fi
  if [ "$F0_COUNT" -ge 1 ] && [ -n "$F0_ACC_LOC" ]; then
    PREV_REGION="$F0_ACC_LOC"
    printf '%s\n' "$PREV_REGION" > "$STATE_FILE"
  fi

  step 3 "TTS próbahívás a meglévő kulcsokkal";
  if [ "${#ACCS[@]}" -gt 0 ]; then
    local rec ACC_NAME ACC_RG ACC_LOC KEY BASE_URL OUT_BASE SSML tts_code TTS_URL1 TTS_URL2
    for rec in "${ACCS[@]}"; do
      ACC_NAME=$(awk '{print $1}' <<<"$rec"); ACC_RG=$(awk '{print $2}' <<<"$rec"); ACC_LOC=$(awk '{print $3}' <<<"$rec")
      echo "  - Próba: ${ACC_NAME} (loc:${ACC_LOC})"
      KEY=$(az cognitiveservices account keys list -n "$ACC_NAME" -g "$ACC_RG" --query key1 -o tsv 2>/dev/null || true)
      [ -z "${KEY:-}" ] && { echo "    > kulcs nem elérhető"; continue; }
      BASE_URL=$(az cognitiveservices account show -n "$ACC_NAME" -g "$ACC_RG" --query "properties.endpoint" -o tsv 2>/dev/null || echo "")
      OUT_BASE="${BASE_URL%/}/"
      if [ -z "$BASE_URL" ]; then OUT_BASE="https://${ACC_LOC}.api.cognitive.microsoft.com/"; fi

      # 2 lehetséges végpontforma a TTS híváshoz:
      #  - ajánlott:   https://<region>.tts.speech.microsoft.com/cognitiveservices/v1
      #  - alternatív: <account endpoint>/cognitiveservices/v1
      TTS_URL1="https://${ACC_LOC}.tts.speech.microsoft.com/cognitiveservices/v1"
      TTS_URL2="${BASE_URL%/}/cognitiveservices/v1"

      SSML="<?xml version=\"1.0\"?><speak version=\"1.0\" xml:lang=\"hu-HU\"><voice name=\"${VOICE}\">${TEST_TEXT}</voice></speak>"

      # 1. próba: tts.speech.* végpont
      tts_code=$(curl -sS --connect-timeout 5 --max-time 15 -o /dev/null -w '%{http_code}' -X POST "$TTS_URL1" \
        -H "Ocp-Apim-Subscription-Key: $KEY" \
        -H "Content-Type: application/ssml+xml" \
        -H "X-Microsoft-OutputFormat: audio-16khz-32kbitrate-mono-mp3" \
        --data-binary "$SSML" 2>/dev/null || echo "000")
      echo "    > TTS(1) ${TTS_URL1} -> HTTP: ${tts_code}"
      if [[ "$tts_code" =~ ^2 ]]; then
        echo "$KEY"; echo "$OUT_BASE"; return 0
      fi

      # 2. próba: account endpoint + path
      tts_code=$(curl -sS --connect-timeout 5 --max-time 15 -o /dev/null -w '%{http_code}' -X POST "$TTS_URL2" \
        -H "Ocp-Apim-Subscription-Key: $KEY" \
        -H "Content-Type: application/ssml+xml" \
        -H "X-Microsoft-OutputFormat: audio-16khz-32kbitrate-mono-mp3" \
        --data-binary "$SSML" 2>/dev/null || echo "000")
      echo "    > TTS(2) ${TTS_URL2} -> HTTP: ${tts_code}"
      if [[ "$tts_code" =~ ^2 ]]; then
        echo "$KEY"; echo "$OUT_BASE"; return 0
      fi

    done
  fi

  if [ "${F0_COUNT}" -ge 1 ]; then
    if [ -n "$F0_ACC_NAME" ] && [ -n "$F0_ACC_RG" ]; then
      echo "  - F0 kulcs törlése: ${F0_ACC_NAME} (loc:${F0_ACC_LOC})"
      if az cognitiveservices account delete -n "$F0_ACC_NAME" -g "$F0_ACC_RG"; then
        echo "    > törlés elküldve, purge/várakozás indul"
        if [ -n "$F0_ACC_LOC" ]; then
          if az cognitiveservices account purge -n "$F0_ACC_NAME" -g "$F0_ACC_RG" -l "$F0_ACC_LOC"; then
            echo "    > purge sikeres"
          else
            echo "    > purge sikertelen vagy már nem szükséges"
          fi
        fi
        local wait_attempt=0
        local wait_limit=12
        while az cognitiveservices account show -n "$F0_ACC_NAME" -g "$F0_ACC_RG" >/dev/null 2>&1; do
          wait_attempt=$((wait_attempt + 1))
          [ "$wait_attempt" -ge "$wait_limit" ] && break
          echo "    > várakozás a törlés befejezésére (${wait_attempt}/${wait_limit})"
          sleep 5
        done
        if az cognitiveservices account show -n "$F0_ACC_NAME" -g "$F0_ACC_RG" >/dev/null 2>&1; then
          fail "a meglévő F0 fiók törlése nem fejeződött be időben"; return 1
        fi
      else
        echo "    > törlés sikertelen, purge ugyanazzal a névvel"
        if [ -n "$F0_ACC_LOC" ]; then
          if ! az cognitiveservices account purge -n "$F0_ACC_NAME" -g "$F0_ACC_RG" -l "$F0_ACC_LOC"; then
            fail "a meglévő F0 fiók törlése/purge sikertelen"; return 1
          fi
          echo "    > purge sikeres, várakozás 5 másodperc"
          sleep 5
        else
          fail "a meglévő F0 fiók törlése sikertelen: hiányzik a régió purge-hoz"; return 1
        fi
      fi
    else
      fail "nem található a törlendő F0 fiók metaadata"; return 1
    fi
  fi

  step 4 "Szabad régió keresése";
  local -a USED_REGIONS=(); local -a AVAIL=(); local -a FILTERED=(); local r u used LOC
  for rec in "${ACCS[@]}"; do USED_REGIONS+=("$(awk '{print $3}' <<<"$rec")"); done
  for r in "${ALL_REGIONS[@]}"; do
    used=false; for u in "${USED_REGIONS[@]}"; do [ "$r" = "$u" ] && { used=true; break; }; done
    [ "$used" = false ] && AVAIL+=("$r")
  done
  if [ -n "$PREV_REGION" ]; then
    for r in "${AVAIL[@]}"; do [ "$r" != "$PREV_REGION" ] && FILTERED+=("$r"); done
    if [ "${#FILTERED[@]}" -gt 0 ]; then
      AVAIL=("${FILTERED[@]}")
    else
      FILTERED=()
      for r in "${ALL_REGIONS[@]}"; do [ "$r" != "$PREV_REGION" ] && FILTERED+=("$r"); done
      if [ "${#FILTERED[@]}" -gt 0 ]; then
        AVAIL=("${FILTERED[@]}")
      fi
    fi
  fi
  if [ "${#AVAIL[@]}" -eq 0 ]; then AVAIL=("${ALL_REGIONS[@]}"); fi
  local idx=0
  if [ "${#AVAIL[@]}" -gt 1 ]; then idx=$(( RANDOM % ${#AVAIL[@]} )); fi
  LOC="${AVAIL[$idx]}"; echo "  - Választott régió: ${LOC}"

  step 5 "Erőforráscsoport ellenőrzése/létrehozása";
  local RG="${RG_NAME}"
  local RG_LOC=""
  local RG_CREATED=false
  if az group show -n "$RG" >/dev/null 2>&1; then
    echo "  - RG létezik: ${RG} (hely változatlan)"
    RG_LOC=$(az group show -n "$RG" --query location -o tsv 2>/dev/null || echo "")
    if [ -n "$RG_LOC" ] && [ "$RG_LOC" != "$LOC" ]; then
      echo "    > figyelmeztetés: meglévő RG más régióban (${RG_LOC}), a fiók létrehozása ettől függetlenül ${LOC} régióban történik"
    fi
  else
    echo "  - RG létrehozása: ${RG} @ ${LOC}"
    az group create -n "$RG" -l "$LOC" >/dev/null 2>&1 || { fail "az erőforráscsoport létrehozása sikertelen"; return 1; }
    RG_LOC="$LOC"
    RG_CREATED=true
  fi

  step 6 "új SpeechServices F0 fiók létrehozása ${LOC} régióban";
  local ACC="speech$(date +%Y%m%d%H%M%S)"
  if ! az cognitiveservices account create -n "$ACC" -g "$RG" -l "$LOC" --kind SpeechServices --sku F0 --yes >/dev/null; then
    fail "a SpeechServices F0 fiók létrehozása sikertelen"; return 1
  fi

  step 7 "Kulcs lekérése és kimenet";
  local KEY; KEY=$(az cognitiveservices account keys list -n "$ACC" -g "$RG" --query key1 -o tsv 2>/dev/null || true)
  if [ -z "${KEY:-}" ]; then fail "az új kulcs lekérése sikertelen"; return 1; fi
  local BASE_URL; BASE_URL=$(az cognitiveservices account show -n "$ACC" -g "$RG" --query "properties.endpoint" -o tsv 2>/dev/null || echo "")
  if [ -z "$BASE_URL" ]; then BASE_URL="https://${LOC}.api.cognitive.microsoft.com/"; fi
  echo "$KEY"; echo "${BASE_URL%/}/"; return 0
}


