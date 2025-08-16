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
    fail "van már érvényes F0 az előfizetésben, új kulcs nem hozható létre"; return 1
  fi

  step 4 "Szabad régió keresése";
  local -a USED_REGIONS=(); local -a AVAIL=(); local r u used LOC
  for rec in "${ACCS[@]}"; do USED_REGIONS+=("$(awk '{print $3}' <<<"$rec")"); done
  for r in "${ALL_REGIONS[@]}"; do
    used=false; for u in "${USED_REGIONS[@]}"; do [ "$r" = "$u" ] && { used=true; break; }; done
    [ "$used" = false ] && AVAIL+=("$r")
  done
  [ "${#AVAIL[@]}" -eq 0 ] && AVAIL=("${ALL_REGIONS[@]}")
  LOC="${AVAIL[0]}"; echo "  - Választott régió: ${LOC}"

  step 5 "Erőforráscsoport ellenőrzése/létrehozása";
  local RG="${RG_NAME}"
  local RG_LOC=""
  if az group show -n "$RG" >/dev/null 2>&1; then
    echo "  - RG létezik: ${RG} (hely változatlan)"
    RG_LOC=$(az group show -n "$RG" --query location -o tsv 2>/dev/null || echo "")
  else
    echo "  - RG létrehozása: ${RG} @ ${LOC}"
    az group create -n "$RG" -l "$LOC" >/dev/null 2>&1 || { fail "az erőforráscsoport létrehozása sikertelen"; return 1; }
    RG_LOC="$LOC"
  fi
  if [ -n "$RG_LOC" ]; then LOC="$RG_LOC"; fi

  step 6 "Új SpeechServices F0 fiók létrehozása ${LOC} régióban";
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
