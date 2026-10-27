#!/usr/bin/env bash
#
# Coleta as evidências de ambiente da T01.
#
#   bash scripts/00-ambiente.sh [caminho-do-aosp]
#
# Gera ~/evidencias-t01/*.txt. Não altera nada, só lê.

set -u

AOSP="${1:-$HOME/aosp}"
SAIDA="$HOME/evidencias-t01"
PRODUTO_DIR="$AOSP/out/target/product/emulator_x86_64"

mkdir -p "$SAIDA"

echo "=== ambiente.txt ==="
{
    echo "## Sistema"
    lsb_release -a 2>/dev/null
    uname -a
    echo
    echo "## Recursos"
    echo "nproc: $(nproc)"
    free -h
    df -h "$HOME"
    echo
    echo "## Ferramentas"
    git --version
    repo --version 2>&1 | head -3
    java -version 2>&1 | head -2
    python3 --version 2>&1
} > "$SAIDA/ambiente.txt" 2>&1

echo "=== fontes.txt ==="
{
    echo "## Manifest"
    grep -m1 revision "$AOSP/.repo/manifests/default.xml" 2>/dev/null
    echo
    echo "## Manifestos locais"
    ls -la "$AOSP/.repo/local_manifests/" 2>/dev/null || echo "(nenhum)"
    echo
    echo "## Árvores de dispositivo"
    ls -d "$AOSP"/device/*/* 2>/dev/null || echo "(nenhuma)"
    echo
    echo "## Tamanho"
    du -sh "$AOSP" 2>/dev/null
    du -sh "$AOSP/out" 2>/dev/null
} > "$SAIDA/fontes.txt" 2>&1

echo "=== produto.txt ==="
{
    echo "## Produto e variante"
    grep -rn "PRODUCT_DEVICE := emulator_x86_64" "$AOSP"/build/make/target/product/*.mk 2>/dev/null
    grep -E "ro.build.(type|flavor|version.release|fingerprint|id)" \
        "$PRODUTO_DIR/system/build.prop" 2>/dev/null
    echo
    echo "## Imagens compiladas"
    ls -lh "$PRODUTO_DIR"/*.img 2>/dev/null
} > "$SAIDA/produto.txt" 2>&1

echo "=== dispositivo.txt ==="
{
    adb devices -l 2>&1
    echo
    adb shell getprop 2>/dev/null | grep -E "ro.product.(name|device|model)|ro.build.(type|version.release)"
} > "$SAIDA/dispositivo.txt" 2>&1

echo
echo "Gerado em $SAIDA:"
ls -lh "$SAIDA"
echo
echo "O manifesto completo com as revisões de cada projeto é lento de gerar"
echo "(percorre toda a árvore). Quando precisar, rode à parte:"
echo "  cd $AOSP && repo manifest -r -o $SAIDA/manifest-revisoes.xml"
