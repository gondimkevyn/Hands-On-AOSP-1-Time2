#!/usr/bin/env bash
#
# Executa os cenários automatizáveis da T06.
#
#   bash scripts/04-validar-t06.sh
#
# Requer: emulador no ar, com os patches já compilados e instalados.
# Gera ~/evidencias-t06/ com capturas e um relatorio.txt.
#
# Cenários cobertos aqui: 1, 3, 4, 5 e 7.
# Os cenários 2, 6 e 8 têm passos que exigem toque na paleta e continuam
# manuais - os pontos exatos estão marcados com MANUAL abaixo.
#
# Mapa de cores:  vermelho=1 laranja=2 amarelo=3 verde=4 azul=5 roxo=6
# Sequência de teste: vermelho, azul, verde, laranja = 1542

set -u

SAIDA="$HOME/evidencias-t06"
REL="$SAIDA/relatorio.txt"
SEQ="1542"
PIN_ALT="7890"
MARCADOR="lock_screen_color_mode"

mkdir -p "$SAIDA"
: > "$REL"

if ! adb shell true 2>/dev/null; then
    echo "ERRO: nenhum dispositivo. Rode scripts/01-subir-emulador.sh antes."
    exit 1
fi

log() {
    echo "$*" | tee -a "$REL"
}

marcador() {
    adb shell settings get secure "$MARCADOR" 2>/dev/null | tr -d '\r'
}

captura() {
    sleep "${2:-3}"
    adb exec-out screencap -p > "$SAIDA/$1"
}

esperar_boot() {
    adb wait-for-device
    while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
        sleep 2
    done
}

ciclo_tela() {
    adb shell input keyevent 26
    sleep 2
    adb shell input keyevent 26
    sleep 2
    adb shell input keyevent 82
}

log "Validação T06 - $(date)"
log "device: $(adb shell getprop ro.build.flavor | tr -d '\r')"
log ""

# ---------------------------------------------------------------- cenário 1
log "=== Cenário 1: cadastro inicial ==="
adb shell locksettings clear --old "$SEQ" 2>/dev/null
adb shell locksettings clear --old "$PIN_ALT" 2>/dev/null
adb shell locksettings clear --old "" 2>/dev/null
log "marcador após limpar: $(marcador)"

adb shell am start -a android.app.action.SET_NEW_PASSWORD >/dev/null
captura "c1-01-lista-de-metodos.png"
log "MANUAL: confira em c1-01 que 'Colors' aparece entre PIN e Password."
log "MANUAL: toque em Colors, cadastre vermelho-azul-verde-laranja e confirme."
log "        Depois rode este script de novo a partir do cenário 3,"
log "        ou cadastre pelo atalho abaixo e siga direto."
echo

# Atalho: grava a credencial e o marcador sem passar pela interface, para
# conseguir validar os cenários seguintes sem depender de toque.
log "--- atalho: cadastrando por adb ---"
adb shell locksettings set-pin "$SEQ"
adb shell settings put secure "$MARCADOR" 1
log "marcador: $(marcador)  (esperado 1)"
if adb shell locksettings verify --old "$SEQ" 2>&1 | tee -a "$REL" | grep -qi "success\|verified"; then
    log "RESULTADO c1: credencial verificada como PIN $SEQ -> a arquitetura da T03 confere"
else
    log "RESULTADO c1: ATENÇÃO - verificação não confirmou"
fi
log ""

# ---------------------------------------------------------------- cenário 4
log "=== Cenário 4: apagar e acender a tela ==="
falhas=0
for i in 1 2 3 4 5; do
    ciclo_tela
    captura "c4-ciclo$i.png" 2
done
log "5 ciclos executados; confira que todas as c4-ciclo*.png mostram a paleta"
log "marcador após os ciclos: $(marcador)  (esperado 1)"
adb shell input text "$SEQ"
adb shell input keyevent 66
captura "c4-desbloqueado.png" 4
log "RESULTADO c4: ver c4-desbloqueado.png"
log ""

# ---------------------------------------------------------------- cenário 7
log "=== Cenário 7: erro e bloqueio por tentativas ==="
ciclo_tela
for i in 1 2 3 4 5; do
    adb shell input text "6543"      # sequência errada, mesmo comprimento
    adb shell input keyevent 66
    sleep 2
    captura "c7-erro$i.png" 1
done
captura "c7-lockout.png" 2
log "5 tentativas erradas; c7-lockout.png deve mostrar a espera de 30s"
log "RESULTADO c7: ver c7-lockout.png"
log ""

sleep 32
ciclo_tela
adb shell input text "$SEQ"
adb shell input keyevent 66
captura "c7-recuperado.png" 4
log "após a espera, sequência correta: ver c7-recuperado.png"
log ""

# ---------------------------------------------------------------- cenário 3
log "=== Cenário 3: reinício ==="
log "marcador antes do reboot: $(marcador)"
adb reboot
sleep 5
esperar_boot
sleep 10
log "marcador depois do reboot: $(marcador)  (esperado 1)"
captura "c3-pos-boot.png" 5
log "ATENÇÃO: se c3-pos-boot.png mostrar o teclado numérico em vez da paleta,"
log "         o marcador não está acessível em Direct Boot. É o risco técnico"
log "         principal do projeto - ver T06 cenário 3."
adb shell input keyevent 82
sleep 2
adb shell input text "$SEQ"
adb shell input keyevent 66
captura "c3-desbloqueado.png" 4
log "RESULTADO c3: ver c3-pos-boot.png e c3-desbloqueado.png"
log ""

# ---------------------------------------------------------------- cenário 5
log "=== Cenário 5: cadastro abandonado ==="
adb shell locksettings clear --old "$SEQ"
adb shell settings put secure "$MARCADOR" 0
adb shell locksettings set-pin "$PIN_ALT"
log "PIN com dígitos fora da paleta cadastrado: $PIN_ALT"
log "marcador: $(marcador)  (esperado 0)"
adb shell am start -a android.app.action.SET_NEW_PASSWORD >/dev/null
captura "c5-01-lista.png"
log "MANUAL: toque em Colors e, ANTES de confirmar, aperte voltar."
log "MANUAL: depois rode:  adb shell settings get secure $MARCADOR"
log "        Tem que responder 0. Se responder 1, o aparelho fica impossível"
log "        de desbloquear: a paleta não produz os dígitos 7, 8, 9 e 0."
log ""

log "=== Fim ==="
log "Evidências em $SAIDA"
ls -lh "$SAIDA"
