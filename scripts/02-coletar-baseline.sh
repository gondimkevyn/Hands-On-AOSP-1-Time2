#!/usr/bin/env bash
#
# Registra o comportamento ORIGINAL da tela de bloqueio (T01), antes dos patches.
#
#   bash scripts/02-coletar-baseline.sh
#
# Requer o emulador no ar (scripts/01-subir-emulador.sh).
# Gera ~/evidencias-t01/0*.png.
#
# Tudo por adb, sem clique: o resultado é idêntico para qualquer pessoa da
# equipe e não depende da latência da área de trabalho remota.

set -u

SAIDA="$HOME/evidencias-t01"
PIN="1234"

mkdir -p "$SAIDA"

if ! adb shell true 2>/dev/null; then
    echo "ERRO: nenhum dispositivo. Rode scripts/01-subir-emulador.sh antes."
    exit 1
fi

captura() {
    sleep "${2:-3}"
    adb exec-out screencap -p > "$SAIDA/$1"
    echo "  $1"
}

echo "=== Estado limpo ==="
adb shell locksettings clear --old "$PIN" 2>/dev/null
adb shell locksettings clear --old "" 2>/dev/null
echo

echo "=== Telas de configuração ==="
adb shell am start -a android.settings.SECURITY_SETTINGS >/dev/null
captura "01-security.png"

# A activity ChooseLockGeneric não é exportada, então não dá para chamá-la pelo
# componente: o shell roda como uid 2000 e leva SecurityException. A action
# pública SET_NEW_PASSWORD é o caminho suportado.
adb shell am start -a android.app.action.SET_NEW_PASSWORD >/dev/null
captura "02-metodos-originais.png"
echo

echo "=== Cadastro do PIN de referência ==="
adb shell locksettings set-pin "$PIN"
adb shell am start -a android.settings.SECURITY_SETTINGS >/dev/null
captura "03-pin-configurado.png" 4
echo

echo "=== Ciclo de bloqueio ==="
adb shell input keyevent 26      # apaga a tela
sleep 2
adb shell input keyevent 26      # acende
captura "04-tela-bloqueada.png"

adb shell input keyevent 82      # sobe o bouncer
captura "05-pedindo-pin.png"

adb shell input text "$PIN"
captura "06-pin-digitado.png" 2

adb shell input keyevent 66      # enter
captura "07-desbloqueado.png" 4
echo

echo "=== Devolvendo o device ao estado limpo ==="
adb shell locksettings clear --old "$PIN"
adb shell locksettings get-disabled
echo

echo "Gerado em $SAIDA:"
ls -lh "$SAIDA"/*.png
echo
echo "Confira que os tamanhos são diferentes entre si. Dois arquivos idênticos"
echo "significam que uma das telas não chegou a abrir."
