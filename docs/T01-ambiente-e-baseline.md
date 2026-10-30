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

O emulador foi iniciado e o fluxo completo de bloqueio foi percorrido **inteiramente por `adb`**, sem um único clique na interface. A escolha é deliberada: a máquina é acessada por área de trabalho remota, onde o clique é pouco confiável, e o roteiro por comando é reproduzível por qualquer pessoa da equipe com uma linha só. O script está em [`scripts/02-coletar-baseline.sh`](../blob/feat/bloqueio-por-cores/scripts/02-coletar-baseline.sh).

```bash
adb shell am start -a android.settings.SECURITY_SETTINGS
adb exec-out screencap -p > 01-security.png

adb shell am start -a android.app.action.SET_NEW_PASSWORD
adb exec-out screencap -p > 02-metodos-originais.png

adb shell locksettings set-pin 1234
adb shell input keyevent 26   # apaga a tela
adb shell input keyevent 26   # acende
adb shell input keyevent 82   # sobe o bouncer
adb shell input text 1234
adb shell input keyevent 66   # confirma
```

Observação registrada durante a execução, que custou uma tentativa: **`ChooseLockGeneric` não é uma activity exportada**. Chamá-la pelo componente resulta em

```text
java.lang.SecurityException: Permission Denial: starting Intent
{ cmp=com.android.settings/.password.ChooseLockGeneric }
from null (pid=1950, uid=2000) not exported from uid 1000
```

O caminho suportado é a action pública `android.app.action.SET_NEW_PASSWORD`, usada acima.

A tela original apresentou **None, Swipe, Pattern, PIN e Password**, com nenhuma credencial cadastrada. O PIN foi registrado como referência, a tela foi bloqueada e o aparelho desbloqueado com a credencial.

### Capturas

| Arquivo | Tamanho | Tela |
| --- | --- | --- |
| `01-security.png` | 171K | Security & privacy |
| `02-metodos-originais.png` | 187K | Choose a screen lock — os cinco métodos originais |
| `03-pin-configurado.png` | 185K | PIN cadastrado |
| `04-tela-bloqueada.png` | 1,9M | tela de bloqueio |
| `05-pedindo-pin.png` | 93K | bouncer pedindo o PIN |
| `06-pin-digitado.png` | 97K | credencial digitada |
| `07-desbloqueado.png` | 165K | após o desbloqueio |

Os sete arquivos estão em `/home/devtitans-2/evidencias-t01` na máquina `devtitans-05`. **Falta anexá-los a esta issue** — é a única pendência da T01.

As capturas saem em 1440×2960, direto do framebuffer, sem moldura de janela nem compressão de transmissão remota.

## Problema de ambiente registrado

Durante a execução o emulador foi iniciado em `gpu mode host` e o compositor do host passou a resetar o driver gráfico repetidamente:

```text
WARNING | cannot add library .../vulkan/libvulkan.so: failed
KWin: Desktop effects were restarted due to a graphics reset  (×4)
```

A máquina em si estava ociosa — `load average 1,55` em 16 núcleos, 98% de CPU livre, swap praticamente intocado. O gargalo era a renderização acelerada sendo transmitida pela área de trabalho remota, agravada por um cliente de VPN ativo no host.

**Solução adotada:** emulador headless.

```bash
emulator -no-snapshot -no-boot-anim -no-window -gpu swiftshader_indirect -no-audio &
```

O boot caiu de 19,3 s para 16,2 s e os resets gráficos cessaram. Está incorporado em [`scripts/01-subir-emulador.sh`](../blob/feat/bloqueio-por-cores/scripts/01-subir-emulador.sh).

## Arquivos anexados

- [ ] as sete capturas listadas acima
- [x] [`scripts/00-ambiente.sh`](../blob/feat/bloqueio-por-cores/scripts/00-ambiente.sh) — gera `ambiente.txt`, `fontes.txt`, `produto.txt` e `dispositivo.txt`
- [x] [`scripts/01-subir-emulador.sh`](../blob/feat/bloqueio-por-cores/scripts/01-subir-emulador.sh)
- [x] [`scripts/02-coletar-baseline.sh`](../blob/feat/bloqueio-por-cores/scripts/02-coletar-baseline.sh)
- [x] [`docs/T01-ambiente-e-baseline.md`](../blob/feat/bloqueio-por-cores/docs/T01-ambiente-e-baseline.md)
