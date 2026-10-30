# DevTITANS 10 — Hands-On AOSP — Bloqueio de tela por sequência de cores

Trabalho prático sobre a adição de uma modalidade de desbloqueio ao **Android Open Source Project**: uma **sequência de cores** que o usuário cadastra e repete para desbloquear o aparelho, ao lado de None, Swipe, Pattern, PIN e Password.

## Índice

1. [O que foi feito](#o-que-foi-feito)
2. [Como funciona](#como-funciona)
3. [Requisitos](#requisitos)
4. [Como reproduzir](#como-reproduzir)
5. [Estrutura do repositório](#estrutura-do-repositório)
6. [Arquivos alterados no AOSP](#arquivos-alterados-no-aosp)
7. [Estado atual](#estado-atual)
8. [Limitações conhecidas](#limitações-conhecidas)
9. [Contribuidores](#contribuidores)

## O que foi feito

| Tarefa | Issue | Estado |
| --- | --- | --- |
| T01 — Ambiente e comportamento original | [#10](https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2/issues/10) | Concluída · 3 capturas do ciclo de bloqueio a refazer ([detalhe](docs/EVIDENCIAS.md)) |
| T02 — De onde vem uma opção das configurações | [#9](https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2/issues/9) | Concluída |
| T03 — Especificação da modalidade | [#3](https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2/issues/3) | Concluída |
| T04 — A opção nas configurações | [#4](https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2/issues/4) | Concluída · compilada e com evidências |
| T05 — Interface de autenticação | [#5](https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2/issues/5) | Concluída · falta a captura do desbloqueio concluído |
| T06 — Validação | [#6](https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2/issues/6) | **Não executada** — script pronto em `scripts/04-validar-t06.sh` |
| T07 — Documentação final | [#7](https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2/issues/7) | [Relatório escrito](docs/T07-relatorio-final.md) · falta o vídeo |

Leitura recomendada: **[relatório final](docs/T07-relatorio-final.md)** e **[índice de evidências](docs/EVIDENCIAS.md)**.

## Como funciona

O usuário escolhe **Colors** na lista de métodos, toca de 4 a 8 cores numa paleta de seis e confirma. Para desbloquear, repete a sequência na mesma paleta, agora na tela de bloqueio.

Por baixo, **cada cor é um dígito dado pela sua posição na paleta**:

```
🟥 vermelho = 1    🟧 laranja = 2    🟨 amarelo = 3
🟩 verde    = 4    🟦 azul    = 5    🟪 roxo    = 6
```

A sequência 🟥🟦🟩🟧 vira o PIN `1542`, gravado por `LockscreenCredential.createPin()` exatamente como qualquer PIN. Um marcador em `Settings.Secure` (`lock_screen_color_mode`) registra que o usuário escolheu a modalidade de cores, e é ele que faz o Settings e o SystemUI mostrarem a paleta no lugar do teclado numérico.

**Por que assim, e não com um tipo de credencial próprio?** Porque criar uma `PASSWORD_QUALITY` nova exigiria alterar `DevicePolicyManager`, `LockscreenCredential`, `LockSettingsService`, `LockPatternUtils` e o Gatekeeper — e `KeyguardSecurityModel` lança `IllegalStateException` para qualquer qualidade que não conheça, o que deixaria o aparelho preso na tela de bloqueio. Reaproveitando a credencial numérica, toda a criptografia, o bloqueio por tentativas e o Factory Reset Protection continuam sendo os do AOSP, sem uma linha de código de segurança escrita por nós. O raciocínio completo está na [issue #3](../../issues/3).

## Requisitos

- Linux (validado em Ubuntu 22.04.5, kernel 5.15)
- AOSP na tag **`android-14.0.0_r27`**
- Produto **`sdk_phone_x86_64-userdebug`** (emulador padrão; não requer árvore de dispositivo adicional)
- `/dev/kvm` disponível
- ~60 GB livres para build incremental
- `repo`, `git`, `adb`

## Como reproduzir

```bash
# 1. ambiente (só leitura, gera ~/evidencias-t01)
bash scripts/00-ambiente.sh ~/aosp

# 2. emulador headless
bash scripts/01-subir-emulador.sh ~/aosp

# 3. comportamento ORIGINAL, antes dos patches
bash scripts/02-coletar-baseline.sh

# 4. aplicar os patches
bash scripts/03-aplicar-patches.sh ~/aosp

# 5. compilar
cd ~/aosp && source build/envsetup.sh && lunch sdk_phone_x86_64-userdebug && m

# 6. subir de novo e validar
bash scripts/01-subir-emulador.sh ~/aosp
bash scripts/04-validar-t06.sh
```

Para reverter os patches:

```bash
git -C ~/aosp/packages/apps/Settings checkout . && git -C ~/aosp/packages/apps/Settings clean -fd
git -C ~/aosp/frameworks/base       checkout . && git -C ~/aosp/frameworks/base       clean -fd
```

### Emulador headless

Os scripts sobem o emulador com `-no-window -gpu swiftshader_indirect` de propósito. Em `gpu mode host` o compositor do laboratório reseta o driver gráfico repetidamente e trava a sessão remota inteira. Sem janela a máquina fica responsiva, e as capturas por `adb exec-out screencap -p` saem em resolução nativa, melhores do que foto de janela remota.

## Estrutura do repositório

```
docs/      um documento por tarefa, com arquivos e linhas do AOSP
patches/   os dois patches, aplicáveis com git apply
scripts/   ambiente, emulador, baseline, aplicação dos patches e validação
```

## Arquivos alterados no AOSP

### `packages/apps/Settings` — 383 inserções, 0 remoções

| Arquivo | Função da mudança |
| --- | --- |
| `res/values/color_lock_palette.xml` | **novo** — a paleta; a ordem é parte do formato da credencial |
| `res/values/strings.xml` | rótulo, instruções, erros e descrições de acessibilidade |
| `res/xml/security_settings_picker.xml` | o item da lista, com `key="unlock_set_color"` |
| `res/layout/choose_lock_color.xml` | **novo** — tela de cadastro com a grade de cores |
| `password/ScreenLockType.java` | constante `COLOR`, declarada entre `PIN` e `PASSWORD` (a ordem do enum é a ordem da lista) |
| `password/ChooseLockGenericController.java` | `case COLOR` na regra de visibilidade |
| `password/ChooseLockGeneric.java` | `case COLOR` no `setUnlockMethod`; grava e limpa o marcador |
| `password/ChooseLockPassword.java` | infla o layout de cores quando o marcador está ativo |
| `password/ColorLockUtils.java` | **novo** — marcador, limites e ligação dos toques aos dígitos |

### `frameworks/base` — 349 inserções, 1 remoção

| Arquivo | Função da mudança |
| --- | --- |
| `SystemUI/res-keyguard/layout/keyguard_color_view.xml` | **novo** — wrapper |
| `SystemUI/res-keyguard/layout/keyguard_color_view_portrait.xml` | **novo** — a paleta no bouncer, mesma `KeyguardPINView` e mesmos ids |
| `SystemUI/res-keyguard/values/color_lock_palette.xml` | **novo** — paleta e tema; precisa casar com a do Settings |
| `SystemUI/res-keyguard/values/color_lock_strings.xml` | **novo** — rótulos de acessibilidade |
| `keyguard/KeyguardSecurityViewFlipperController.java` | escolhe o layout de cores quando o marcador está ativo |

Nenhuma classe Java foi criada no SystemUI: o layout de cores declara a mesma view, com os mesmos ids, então o controlador existente funciona sem alteração.

## Estado atual

**O código foi compilado e está funcionando no emulador.** A opção aparece no seletor, o cadastro mostra a paleta e a tela de bloqueio aceita a sequência — tudo registrado em `evidencias-t04/` e `evidencias-t05/`, conferido imagem por imagem no [índice de evidências](docs/EVIDENCIAS.md).

Falta:

| Pendência | Onde está descrita |
| --- | --- |
| Executar os 8 cenários de validação | [docs/T06](docs/T06-plano-de-validacao.md) · `scripts/04-validar-t06.sh` |
| Testar Direct Boot (risco mais sério) | [relatório, 8.4](docs/T07-relatorio-final.md) |
| Capturar o desbloqueio concluído | [EVIDENCIAS.md](docs/EVIDENCIAS.md) |
| Recapturar o ciclo de bloqueio da T01 | [EVIDENCIAS.md](docs/EVIDENCIAS.md) |
| Três ajustes cosméticos: dígitos à mostra, textos dizendo "PIN", botão "CANCEL" | [relatório, 8.1–8.3](docs/T07-relatorio-final.md) |
| Vídeo da demonstração | [docs/T07](docs/T07-relatorio-final.md) |

## Limitações conhecidas

1. Uma sequência de 4 cores tem 1.296 combinações, contra 10.000 de um PIN de 4 dígitos — a modalidade é **mais fraca** que o PIN de mesmo comprimento.
2. Quem souber o mapeamento pode digitar o PIN equivalente, se chegar a uma tela de PIN.
3. `getActivePasswordQuality()` continua retornando `PASSWORD_QUALITY_NUMERIC`: políticas de administrador tratam o bloqueio como PIN, o que é correto.
4. O marcador vive em `Settings.Secure`, fora da credencial. Se for apagado, o bouncer volta ao teclado numérico e o usuário entra digitando os números.
5. Direct Boot não foi verificado — cenário 3 da [issue #6](../../issues/6).
6. Trocar a ordem da paleta numa versão futura invalidaria todas as sequências cadastradas.

## Contribuidores

| Pessoa | Papel |
| --- | --- |
| [@gondimkevyn](https://github.com/gondimkevyn) | variante AOSP puro das T01/T02, especificação, implementação e plano de validação |
| [@andertdev](https://github.com/andertdev) | T01 e T02 na variante `devtitans_kraken` |
