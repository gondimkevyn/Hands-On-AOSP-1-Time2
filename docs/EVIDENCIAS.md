# Índice de evidências

O que **cada arquivo realmente mostra**, conferido imagem por imagem. Mantido separado dos documentos de tarefa porque é a referência que o relatório final cita, e porque os nomes originais de alguns arquivos não correspondiam ao conteúdo.

Todas as capturas são do emulador `sdk_phone_x86_64-userdebug`, AOSP `android-14.0.0_r27`, em 1440×2960, obtidas com `adb exec-out screencap -p`.

---

## T01 — comportamento original (antes dos patches)

Capturado em 28/10, entre 7:24 e 7:34, com o build **sem** as alterações.

| Arquivo | Horário | O que mostra |
| --- | --- | --- |
| `evidencias-t01/01-security.png` | 7:24 | Settings → Security & privacy. **Device unlock: None** e o cartão "Set a screen lock". Estado inicial, sem credencial. |
| `evidencias-t01/02-metodos-originais.png` | 7:27 | "Choose a screen lock" com **Pattern · Fingerprint · Face**, **PIN · Fingerprint · Face** e **Password · Fingerprint · Face**. Não há "Colors". É a prova do estado anterior à alteração. |
| `evidencias-t01/03-seletor-de-metodos.png` | 7:28 | O mesmo seletor, um minuto depois. Conteúdo equivalente ao 02. |
| `evidencias-t01/04-credencial-configurada.png` | 7:34 | Security & privacy depois do cadastro: **"Looks good — No issues found"** e **Device unlock** com marca verde. Confirma a credencial registrada. |

### Observação técnica registrada pela captura 02

O seletor mostra apenas Pattern, PIN e Password — **None e Swipe não aparecem**. Não é defeito: a tela foi aberta pela action `SET_NEW_PASSWORD` no fluxo com biometria, que ativa `mHideInsecureScreenLockTypes`. A regra está em `ChooseLockGenericController.isScreenLockVisible` (linhas 164-186) e foi documentada na T02 antes de ser observada aqui:

```java
case NONE:
    return !mHideInsecureScreenLockTypes
        && !mContext.getResources().getBoolean(R.bool.config_hide_none_security_option)
        && !managedProfile;
case SWIPE:
    return !mHideInsecureScreenLockTypes
        && ...
```

A captura é, portanto, confirmação empírica da regra de visibilidade levantada na investigação.

### Arquivos inválidos

Movidos para `evidencias-t01/invalidas/` em vez de apagados, para que o histórico do que aconteceu fique registrado.

| Arquivo | Problema |
| --- | --- |
| `05-INVALIDA-tela-preta.png` | imagem **inteiramente preta** — a captura ocorreu com a tela apagada |
| `06-INVALIDA-duplicata-de-05.png` | **byte a byte idêntico** ao 05 (md5 `ec0b5246…`) |
| `07-INVALIDA-duplicata-de-05.png` | **byte a byte idêntico** ao 05 (md5 `ec0b5246…`) |

Causa provável: a sequência `input keyevent 26` apaga e acende a tela, e a captura foi disparada antes de o bouncer subir; as três chamadas seguintes pegaram o mesmo quadro.

**Pendente:** recapturar o ciclo de bloqueio e desbloqueio com PIN. Há duas saídas:

1. rodar `bash scripts/02-coletar-baseline.sh`, que já insere as esperas corretas entre `keyevent` e `screencap`;
2. subir as capturas da coleta de 26/10, que estão em `/home/devtitans-2/evidencias-t01` na máquina `devtitans-05` e mostram o ciclo completo — lá os sete arquivos têm tamanhos distintos (171K, 187K, 185K, 1,9M, 93K, 97K, 165K).

---

## T04 — a opção nas configurações (depois dos patches)

Capturado em 28/10, entre 4:28 e 8:18, com o build **contendo** as alterações.

| Arquivo | Horário | O que mostra |
| --- | --- | --- |
| `evidencias-t04/T04-01-opcao-cores-na-lista.png` | 8:18 | "Choose a screen lock" com **"Colors — Tap a sequence of colors to unlock"** entre PIN e Password. **É a evidência central da T04.** |
| `evidencias-t04/T04-02-cadastro.png` | 4:29 | Primeiro passo do cadastro: cabeçalho "Set a PIN", a grade 3×2 de cores, campo vazio, botões CLEAR e NEXT (NEXT inativo). |
| `evidencias-t04/T04-03-confirmacao.png` | 4:28 | Segundo passo: cabeçalho "Re-enter your PIN", **quatro marcadores neutros** preenchidos, botões CLEAR e CONFIRM. |

Os nomes destes dois últimos estavam trocados em relação ao conteúdo e foram corrigidos.

### O que a captura 01 comprova

Ponto por ponto, contra a especificação da T03:

- a opção existe e é selecionável
- o rótulo e o resumo vieram de `unlock_set_unlock_color_title` e `unlock_set_unlock_color_summary`
- **a posição está correta**: entre PIN e Password, que é consequência de `COLOR` ter sido declarada nessa posição no enum `ScreenLockType`, já que `getVisibleAndEnabledScreenLockTypes()` itera `values()`
- o item não aparece esmaecido, ou seja, `isScreenLockEnabled` aceitou a nova constante sem alteração nenhuma naquele método

O ícone é o do PIN (`ic_lock_pin`), como especificado — não foi desenhado ícone próprio.

### O que as capturas 02 e 03 comprovam

- a troca de layout em `ChooseLockPassword.onCreateView` funciona: o cadastro mostra a paleta no lugar do teclado
- o fluxo de dois passos do AOSP foi reaproveitado íntegro, incluindo a tela de confirmação
- o progresso aparece como **marcadores neutros**, nunca repetindo a cor tocada, como decidido na T03

---

## T05 — a interface de autenticação (depois dos patches)

| Arquivo | O que mostra |
| --- | --- |
| `evidencias-t05/T05-01-bouncer-paleta-cores.png` | Tela de bloqueio com a paleta: vermelho, laranja, amarelo na primeira linha; verde, azul, roxo na segunda; apagar e confirmar na terceira; botão de emergência. |
| `evidencias-t05/T05-02-sequencia-incorreta.png` | A mesma tela após uma sequência errada, com a mensagem de erro no topo. |
| `evidencias-t05/T05-03-sequencia-completa.png` | Quatro marcadores neutros preenchidos sobre a paleta, antes da confirmação. |

O nome do terceiro arquivo prometia o desbloqueio concluído, mas a imagem mostra a sequência digitada e ainda não enviada. Foi renomeado para o que de fato mostra. **Falta uma captura da tela inicial após o desbloqueio.**

### O que estas capturas comprovam

- `getLayoutIdFor` escolheu o layout de cores em vez do teclado numérico, lendo o marcador em `Settings.Secure`
- o `Flow` com oito elementos produziu as três linhas previstas
- o tratamento de erro do AOSP foi herdado sem código novo (captura 02)
- o progresso é neutro também no desbloqueio

---

## Divergências entre o implementado e o especificado

Três diferenças visíveis nas capturas, todas previstas como risco antes da compilação. Nenhuma impede o funcionamento.

### 1. Os dígitos aparecem sobre as cores

As capturas T05-01, T05-02, T05-03 e as da T04 mostram os números **1 a 6 escritos sobre os quadrados coloridos**.

Era o risco número 1 anotado na T05. O tema `ColorLockNumPadKey`, criado em `res-keyguard/values/color_lock_palette.xml` com `textColorPrimary` transparente, **não surtiu efeito**: `NumPadKey` resolve a cor do texto por outro caminho (`NumPadKey.java:159`), não pelo `android:theme` da view.

Consequência: o mapeamento cor→dígito fica visível na tela, o que enfraquece a modalidade do ponto de vista de quem observa o aparelho, embora não altere a credencial nem a verificação.

Correções possíveis, em ordem de simplicidade:

1. estender `@style/NumPadKey` definindo a cor do texto explicitamente, e aplicá-lo com `style=` em vez de `android:theme=`;
2. esconder `R.id.digit_text` em `KeyguardPINView#onFinishInflate` quando o modo de cores estiver ativo.

### 2. Os textos ainda dizem "PIN"

| Tela | Texto exibido | Deveria exibir |
| --- | --- | --- |
| cadastro, passo 1 | "Set a PIN" | "Tap 4 to 8 colors in an order you can remember" |
| cadastro, passo 2 | "Re-enter your PIN" | "Tap your color sequence again to confirm" |
| bouncer | "Enter your PIN" | "Enter your color sequence" |
| bouncer, erro | "Wrong PIN" | "Wrong color sequence" |

As quatro strings foram criadas nos patches (`lockpassword_choose_your_color_header`, `lockpassword_confirm_your_color_header`, `keyguard_enter_your_color`) mas **não chegaram a ser ligadas** aos pontos onde o cabeçalho é definido. Era o risco número 4 anotado na T04.

Correção: um `if` sobre o modo de cores onde `ChooseLockPasswordFragment` define `sud_layout_description`, e o equivalente em `KeyguardPinViewController` para a mensagem do bouncer.

### 3. O botão de apagar está rotulado "CANCEL"

Em `choose_lock_color.xml` o botão `color_key_delete` recebeu `android:text="@android:string/cancel"`, que renderiza "CANCEL". A função dele é apagar a última cor, e toque longo limpa tudo.

Correção: criar uma string própria, por exemplo "DELETE", e usá-la.

---

## Situação por tarefa

| Tarefa | Evidência suficiente? |
| --- | --- |
| T01 | **parcial** — o estado original está provado (01 e 02); falta o ciclo de bloqueio e desbloqueio |
| T04 | **sim** — opção, cadastro e confirmação registrados |
| T05 | **quase** — falta a tela após o desbloqueio bem-sucedido |
| T06 | **não** — os oito cenários ainda não foram executados; não existe `evidencias-t06/` |
