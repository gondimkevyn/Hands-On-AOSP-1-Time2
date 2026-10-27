# T01 — Preparar o ambiente e registrar o comportamento original

> Variante executada em **AOSP puro** (produto `sdk_phone_x86_64`), na máquina `devtitans-05`.
> A execução de referência da issue #1 foi feita sobre o produto `devtitans_kraken`, que **não existe nesta máquina** (ver seção *Divergência de ambiente*). Esta issue registra uma execução de referência própria, reproduzível no AOSP sem árvore de dispositivo adicional.

## Objetivo

Estabelecer uma execução de referência do AOSP antes de qualquer alteração: identificar a base de código, confirmar a imagem compilada, iniciar o emulador e registrar as opções originais de bloqueio de tela.

## Ambiente

| Item | Valor |
| --- | --- |
| Host | `devtitans-2@devtitans-05` |
| Sistema | Ubuntu 22.04.5 LTS, kernel 5.15.0-198-generic (KDE Plasma) |
| Fontes | `/home/devtitans-2/aosp` (280 GB) |
| Manifest | `<default revision="refs/tags/android-14.0.0_r27">` |
| Plataforma | Android 14 — `Platform_version_name: "14"`, codename `VanillaIceCream`, estado `REL` |
| Produto | `sdk_phone_x86_64` |
| Variante | `userdebug` |
| Dispositivo | `emulator_x86_64` |
| Build ID | `UQ1A.240205.004.B1` |
| Disco | 907 GB totais · 805 GB usados · 57 GB livres (94%) · `out/` = 168 GB |

Produto e variante foram confirmados diretamente nos fontes e na imagem compilada, e não por suposição:

```bash
cd ~/aosp
grep -rn "PRODUCT_DEVICE := emulator_x86_64" build/make/target/product/*.mk
grep -m3 -E "ro.build.type|ro.build.flavor" out/target/product/emulator_x86_64/system/build.prop
```

```text
build/make/target/product/sdk_phone_x86_64.mk:55:PRODUCT_DEVICE := emulator_x86_64
ro.build.type=userdebug
ro.build.flavor=sdk_phone_x86_64-userdebug
```

## Divergência de ambiente

A issue #1 documenta `lunch devtitans_kraken-eng`. Nesta máquina esse produto **não é selecionável**, e a verificação mostra o porquê:

```bash
ls -la ~/aosp/.repo/local_manifests/   # vazio
ls -d ~/aosp/device/*/kraken           # não existe
```

Não há manifesto local nem árvore de dispositivo `kraken`: os fontes são AOSP puro, sincronizados a partir do manifesto oficial do Google na tag `android-14.0.0_r27`.

**Decisão técnica:** seguir com `sdk_phone_x86_64`, pelos seguintes motivos.

1. O alvo do trabalho — a tela de bloqueio — está em `packages/apps/Settings`, `frameworks/base` e `packages/SystemUI`, todos código de plataforma, independentes de árvore de dispositivo.
2. Obter a árvore `kraken`, ressincronizar e recompilar exigiria muito mais do que os 57 GB livres (disco em 94%), com risco de interromper o build por falta de espaço.
3. A imagem de `sdk_phone_x86_64` já está compilada e íntegra, permitindo build incremental.

A alteração é portável: o mesmo patch se aplica ao `kraken` sem modificação, caso a entrega final exija aquele produto.

## Guia de reprodução

Preparação dos fontes (já concluída nesta máquina):

```bash
mkdir -p ~/aosp
cd ~/aosp
repo init -u https://android.googlesource.com/platform/manifest -b android-14.0.0_r27
repo sync -j4
```

Seleção do produto e execução:

```bash
cd ~/aosp
source build/envsetup.sh
lunch sdk_phone_x86_64-userdebug
m
emulator -no-snapshot -wipe-data &
```

O `-wipe-data` é intencional: garante que o emulador inicie sem credencial previamente cadastrada, que é a condição correta para registrar o estado original.

## Imagem compilada

O conjunto de imagens em `out/target/product/emulator_x86_64` está completo:

```text
super.img        8,1G     system.img       system_ext.img
product.img      324M     vendor.img       vbmeta.img
ramdisk.img      1,7M     userdata.img     system_dlkm.img
cache.img         16M     dtb.img          encryptionkey.img
+ variantes -qemu.img e vendor_boot / vendor_ramdisk
```

## Comportamento original

_(a preencher com as capturas da execução)_

## Arquivos anexados

_(a anexar)_
