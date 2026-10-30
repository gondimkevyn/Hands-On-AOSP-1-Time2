#!/usr/bin/env bash
#
# Sobe o emulador headless e espera o boot terminar.
#
#   bash scripts/01-subir-emulador.sh [caminho-do-aosp]
#
# Headless e com swiftshader de propósito: a máquina do laboratório é acessada
# por área de trabalho remota, e o emulador em "gpu mode host" faz o compositor
# do host resetar o driver gráfico repetidamente, travando a sessão inteira.
# Sem janela, a máquina fica responsiva e as capturas saem melhores, direto do
# framebuffer, em resolução nativa.

set -u

AOSP="${1:-$HOME/aosp}"
PRODUTO="sdk_phone_x86_64-userdebug"

if [ ! -d "$AOSP" ]; then
    echo "ERRO: não encontrei $AOSP"
    exit 1
fi

echo "=== Aceleração ==="
if [ -e /dev/kvm ]; then
    ls -l /dev/kvm
else
    echo "ATENÇÃO: /dev/kvm não existe. Sem KVM o emulador fica inutilizável de lento."
fi
echo

echo "=== Encerrando emulador anterior, se houver ==="
adb emu kill 2>/dev/null && sleep 3
echo

echo "=== Subindo $PRODUTO ==="
cd "$AOSP" || exit 1
# shellcheck disable=SC1091
source build/envsetup.sh >/dev/null
lunch "$PRODUTO" >/dev/null || { echo "ERRO: lunch falhou"; exit 1; }

emulator -no-snapshot -no-boot-anim -no-window \
         -gpu swiftshader_indirect -no-audio &

echo "=== Esperando o boot ==="
adb wait-for-device
while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
    sleep 2
done

echo
echo "BOOTOU"
adb devices -l
adb shell getprop ro.build.flavor
