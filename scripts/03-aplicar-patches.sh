#!/usr/bin/env bash
#
# Aplica os patches da modalidade de bloqueio por cores na árvore do AOSP.
#
#   bash scripts/03-aplicar-patches.sh [caminho-do-aosp]
#
# Padrão: ~/aosp
#
# Os dois patches foram gerados contra a tag android-14.0.0_r27. Em outra tag a
# aplicação pode falhar por deslocamento de contexto - nesse caso use --3way.

set -u

AOSP="${1:-$HOME/aosp}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SETTINGS="$AOSP/packages/apps/Settings"
BASE="$AOSP/frameworks/base"

falhou=0

verificar() {
    if [ ! -d "$1" ]; then
        echo "ERRO: não encontrei $1"
        exit 1
    fi
}

echo "=== Verificando a árvore ==="
verificar "$AOSP"
verificar "$SETTINGS"
verificar "$BASE"
echo "AOSP:     $AOSP"
echo "Settings: $SETTINGS"
echo "base:     $BASE"
echo

echo "=== Confirmando a tag ==="
tag=$(grep -m1 -o 'android-14\.0\.0_r[0-9]*' "$AOSP/.repo/manifests/default.xml" 2>/dev/null)
if [ "$tag" = "android-14.0.0_r27" ]; then
    echo "OK: $tag"
else
    echo "ATENÇÃO: manifest não é android-14.0.0_r27 (achei: ${tag:-nada})."
    echo "Os patches podem não aplicar limpo. Continuando mesmo assim."
fi
echo

aplicar() {
    local repo="$1" patch="$2" nome="$3"
    echo "=== $nome ==="
    if [ ! -f "$patch" ]; then
        echo "ERRO: patch não encontrado: $patch"
        falhou=1
        return
    fi
    # Ensaio primeiro: nunca mexer na árvore se o patch não aplica limpo.
    if git -C "$repo" apply --check "$patch" 2>/dev/null; then
        git -C "$repo" apply "$patch"
        echo "aplicado"
    elif git -C "$repo" apply --3way --check "$patch" 2>/dev/null; then
        echo "não aplica direto; tentando --3way"
        git -C "$repo" apply --3way "$patch"
        echo "aplicado com --3way (CONFIRA os conflitos antes de compilar)"
    else
        echo "FALHOU. Diagnóstico:"
        git -C "$repo" apply --check -v "$patch" 2>&1 | head -20
        falhou=1
    fi
    echo
}

aplicar "$SETTINGS" "$AQUI/patches/0001-settings-color-lock.patch" "Settings"
aplicar "$BASE"     "$AQUI/patches/0002-systemui-color-lock.patch"  "SystemUI"

if [ "$falhou" -ne 0 ]; then
    echo "Um ou mais patches falharam. Nada foi compilado."
    exit 1
fi

echo "=== Arquivos modificados ==="
git -C "$SETTINGS" status --short
git -C "$BASE" status --short
echo
echo "Próximo passo:"
echo "  cd $AOSP && source build/envsetup.sh && lunch sdk_phone_x86_64-userdebug && m"
echo
echo "Para reverter:"
echo "  git -C $SETTINGS checkout . && git -C $SETTINGS clean -fd"
echo "  git -C $BASE checkout . && git -C $BASE clean -fd"
