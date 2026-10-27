## T07 — Documentação final: estrutura, roteiro do vídeo e pendências

A documentação já está escrita e versionada na branch **`feat/bloqueio-por-cores`**. Esta issue organiza o que existe, o que falta e como fechar.

---

## 1. O que já está pronto

```
docs/
  T01-ambiente-e-baseline.md          ambiente, produto, baseline do AOSP puro
  T02-rastreamento-da-opcao.md        da string "Pattern" até setUnlockMethod()
  T03-especificacao-da-modalidade.md  a decisão de arquitetura e os esboços
  T04-opcao-nas-configuracoes.md      implementação no Settings, arquivo por arquivo
  T05-interface-de-autenticacao.md    implementação no SystemUI
  T06-plano-de-validacao.md           8 cenários, matriz de resultados
  T07-relatorio-final.md              este documento, a consolidar
patches/
  0001-settings-color-lock.patch      383 inserções, 9 arquivos
  0002-systemui-color-lock.patch      349 inserções, 5 arquivos
scripts/
  00-ambiente.sh                      coleta dados do ambiente
  01-subir-emulador.sh                sobe o emulador headless
  02-coletar-baseline.sh              prints do comportamento original
  03-aplicar-patches.sh               aplica e confere os dois patches
  04-validar-t06.sh                   executa os cenários automatizáveis
```

---

## 2. O que falta, em ordem

| # | Pendência | Depende de | Responsável |
| --- | --- | --- | --- |
| 1 | `m` passar com os dois patches | máquina do lab | |
| 2 | Corrigir o que o build apontar | 1 | |
| 3 | Capturas da T04 (opção, cadastro) | 2 | |
| 4 | Capturas da T05 (bouncer, erro, desbloqueio) | 2 | |
| 5 | Executar os 8 cenários da T06 | 2 | |
| 6 | Gravar o vídeo | 3, 4, 5 | |
| 7 | Consolidar `T07-relatorio-final.md` | tudo | |
| 8 | Revisão de código entre a equipe | 2 | |

O item 1 é o único que importa hoje. Tudo depois dele é mecânico.

---

## 3. Roteiro do vídeo

Alvo: **2 a 3 minutos**, sem narração ao vivo (legendas resolvem e evitam regravação).

| Tempo | Cena | Comando |
| --- | --- | --- |
| 0:00–0:15 | Título: produto, tag, o que foi feito | — |
| 0:15–0:35 | Estado original: lista com 5 opções | `am start -a android.app.action.SET_NEW_PASSWORD` |
| 0:35–0:50 | **Colors** aparece entre PIN e Password | mesma tela, depois do patch |
| 0:50–1:20 | Cadastro: tocar 4 cores, confirmar | toque na paleta |
| 1:20–1:30 | Marcador gravado | `settings get secure lock_screen_color_mode` → `1` |
| 1:30–1:50 | Bloquear, bouncer sobe com a **paleta** | `input keyevent 26` ×2, `keyevent 82` |
| 1:50–2:00 | Sequência errada: mensagem de erro | toque |
| 2:00–2:15 | Sequência correta: desbloqueia | toque |
| 2:15–2:35 | Trocar para PIN: bouncer volta ao teclado | lista → PIN |
| 2:35–2:50 | **A prova**: a credencial sempre foi um PIN | `locksettings verify --old 1542` |
| 2:50–3:00 | Encerramento: arquivos alterados | — |

A cena de 2:35 é a mais importante do vídeo. Ela mostra, em um comando, que a modalidade nova reaproveita a credencial do AOSP em vez de inventar armazenamento próprio — que é a decisão técnica central do trabalho.

Gravação sem depender da tela remota:

```bash
adb shell screenrecord --time-limit 180 /sdcard/demo.mp4
adb pull /sdcard/demo.mp4 ./docs/video/
```

---

## 4. Estrutura do relatório final

1. **Introdução** — objetivo, produto (`sdk_phone_x86_64`), tag (`android-14.0.0_r27`)
2. **Ambiente** — da T01, incluindo a divergência do `devtitans_kraken` e por que não bloqueou
3. **Investigação** — da T02: o mapa `strings.xml → picker.xml → ScreenLockType → ChooseLockGeneric → Controller`
4. **Conceitos** — `PASSWORD_QUALITY`, `LockscreenCredential`, synthetic password, Gatekeeper, `SecurityMode`, FRP
5. **Decisões técnicas** — da T03: os dois caminhos, por que o Caminho A foi descartado, limitações assumidas
6. **Implementação** — T04 e T05, arquivo por arquivo, com a função de cada mudança
7. **Validação** — a matriz da T06 preenchida
8. **Limitações conhecidas** — seção 5 abaixo
9. **Contribuições individuais** — seção 6
10. **Fontes** — seção 7

---

## 5. Limitações conhecidas

Declaradas desde a T03, repetidas aqui porque omiti-las seria o pior defeito possível no relatório.

1. **A credencial é um PIN restrito aos dígitos 1 a 6.** Uma sequência de 4 cores tem 1.296 combinações, contra 10.000 de um PIN de 4 dígitos. A modalidade é mais fraca que o PIN de mesmo comprimento. O mínimo foi fixado em 4 por isso.
2. **Quem souber o mapeamento pode digitar o PIN equivalente**, se conseguir chegar a uma tela de PIN. A proteção é de desenho, não criptográfica.
3. **`getActivePasswordQuality()` continua retornando `PASSWORD_QUALITY_NUMERIC`.** Políticas de administrador tratam o bloqueio como PIN — o que está correto, porque é a força real da credencial.
4. **O marcador vive em `Settings.Secure`**, fora da credencial. Se for apagado por outro meio, o bouncer volta ao teclado numérico; a credencial continua válida e o usuário consegue entrar digitando os números. Degrada com elegância, mas é uma dependência externa à credencial.
5. **Direct Boot não foi verificado.** O cenário 3 da T06 existe justamente para isso.
6. **Não há migração.** Trocar a ordem da paleta em uma versão futura invalidaria todas as sequências cadastradas.

---

## 6. Contribuições individuais

A preencher pela equipe. O que já é verificável pelo histórico:

| Pessoa | Contribuição | Evidência |
| --- | --- | --- |
| @andertdev | T01 e T02 na variante `devtitans_kraken`: ambiente, baseline e rastreamento do título "Choose a screen lock" | #1, #2 |
| @gondimkevyn | T01 e T02 na variante AOSP puro; especificação da T03; implementação da T04 e T05; plano da T06 | #10, #9, #3, #4, #5, #6 |
| | | |
| | | |

---

## 7. Fontes consultadas

- AOSP, tag `android-14.0.0_r27`, projetos `platform/packages/apps/Settings` e `platform/frameworks/base` — **a fonte primária de tudo neste trabalho**; cada afirmação técnica das issues #9, #3, #4 e #5 tem arquivo e linha
- `source.android.com` — Authentication, Gatekeeper, Synthetic Password
- `developer.android.com/reference/android/app/admin/DevicePolicyManager` — constantes `PASSWORD_QUALITY_*`

Nenhuma solução de terceiros foi adaptada. Toda a implementação deriva da leitura do próprio AOSP.

---

## 8. Checklist de entrega

- [ ] build limpo com os dois patches
- [ ] capturas da T04 anexadas
- [ ] capturas da T05 anexadas
- [ ] matriz da T06 preenchida
- [ ] vídeo gravado e anexado
- [ ] `T07-relatorio-final.md` consolidado
- [ ] contribuições individuais preenchidas
- [ ] revisão de código registrada em PR
- [ ] README apontando para a documentação
