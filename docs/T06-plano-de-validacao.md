## T06 — Plano de validação: troca de método, ciclo de vida e compatibilidade

Plano fechado, com os comandos prontos. O script executável está na branch **`feat/bloqueio-por-cores`** em `scripts/04-validar-t06.sh`.

**Estado:** cenários definidos e roteirizados. **Ainda não executados** — dependem do build da T04/T05.

---

## 0. Antes de começar

Toda a validação é feita por `adb`, sem interação manual. Motivo prático: o laboratório é acessado remotamente e a latência torna o clique pouco confiável; motivo técnico: assim qualquer pessoa da equipe reproduz os mesmos passos com um comando, e o resultado vira evidência verificável em vez de relato.

```bash
cd ~/aosp && source build/envsetup.sh && lunch sdk_phone_x86_64-userdebug
emulator -no-snapshot -no-boot-anim -no-window -gpu swiftshader_indirect -no-audio &
adb wait-for-device && adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'
```

Dois comandos de inspeção usados o tempo todo:

```bash
adb shell settings get secure lock_screen_color_mode   # 1 = cores, 0/null = PIN comum
adb shell dumpsys lock_settings | head -30             # tipo de credencial registrado
```

Mapa de cores para digitar sequências:

```
Vermelho=1  Laranja=2  Amarelo=3  Verde=4  Azul=5  Roxo=6
```

Sequência de teste padrão: **vermelho, azul, verde, laranja** = PIN `1542`.

---

## Cenário 1 — Cadastro inicial

| Passo | Comando | Esperado |
| --- | --- | --- |
| 1 | `adb shell locksettings clear --old ''` | device sem credencial |
| 2 | `adb shell am start -a android.app.action.SET_NEW_PASSWORD` | lista com "Colors" entre PIN e Password |
| 3 | tocar em Colors, tocar 🟥🟦🟩🟧, confirmar | credencial gravada |
| 4 | `adb shell settings get secure lock_screen_color_mode` | `1` |
| 5 | `adb shell locksettings verify --old 1542` | verificação bem-sucedida |

O passo 5 é o que prova a decisão de arquitetura da T03: a credencial realmente é o PIN `1542`, e o `locksettings` padrão do AOSP a reconhece sem saber nada sobre cores.

## Cenário 2 — Troca para um método existente e volta

O cenário central da issue.

| Passo | Ação | Esperado |
| --- | --- | --- |
| 1 | partir de Cores cadastrado | marcador `1` |
| 2 | escolher **PIN** e cadastrar `9876` | marcador volta a `0` |
| 3 | bloquear e desbloquear | **teclado numérico**, não a paleta |
| 4 | escolher **Cores** de novo, cadastrar 🟨🟨🟪🟩 (`3364`) | marcador `1` |
| 5 | bloquear e desbloquear | **paleta**, e `3364` desbloqueia |
| 6 | escolher **Pattern** | marcador `0`, bouncer volta ao padrão |
| 7 | escolher **None** | marcador `0`, aviso de FRP aparece antes |

O passo 3 é o mais provável de falhar: se o `KeyguardSecurityViewFlipper` tiver guardado em cache a view inflada, a paleta pode persistir mesmo depois da troca para PIN. Está anotado como risco 4 na T05. **Se falhar, é bug nosso, não do AOSP.**

O passo 7 verifica o ramo de Factory Reset Protection que a T02 encontrou em `onPreferenceTreeClick` — sair de um método seguro para um inseguro dispara o diálogo de aviso.

## Cenário 3 — Reinício

| Passo | Comando | Esperado |
| --- | --- | --- |
| 1 | cadastrar cores `1542` | marcador `1` |
| 2 | `adb reboot && adb wait-for-device` | — |
| 3 | esperar `sys.boot_completed` | — |
| 4 | `adb shell settings get secure lock_screen_color_mode` | `1` |
| 5 | observar a tela de bloqueio pós-boot | **paleta**, não teclado |
| 6 | desbloquear com `1542` | entra |

O passo 5 vale atenção: no primeiro desbloqueio após o boot o Android exige a credencial para descriptografar o armazenamento (Direct Boot). Se o marcador for lido antes do usuário ser desbloqueado, `Settings.Secure` pode ainda não estar acessível e a leitura retornaria o padrão `0`, mostrando o teclado numérico. **Se isso acontecer, o marcador precisa ir para uma tabela disponível em Direct Boot**, ou para `LockPatternUtils` com armazenamento de dispositivo protegido. É o risco técnico mais sério do projeto e tem que ser testado cedo.

## Cenário 4 — Apagar e acender a tela

| Passo | Comando | Esperado |
| --- | --- | --- |
| 1 | cadastrar cores | marcador `1` |
| 2 | `adb shell input keyevent 26` | tela apaga |
| 3 | `adb shell input keyevent 26` | tela acende |
| 4 | `adb shell input keyevent 82` | bouncer sobe com a **paleta** |
| 5 | repetir 2-4 cinco vezes | sem travar, sem alternar para teclado |
| 6 | `adb shell input text 1542 && adb shell input keyevent 66` | desbloqueia |

## Cenário 5 — Cadastro abandonado

Cenário que **não** está na issue, mas é consequência direta da implementação e precisa ser verificado.

| Passo | Ação | Esperado |
| --- | --- | --- |
| 1 | cadastrar **PIN** `7890` | marcador `0` |
| 2 | escolher **Cores** na lista | marcador vira `1` |
| 3 | apertar voltar antes de confirmar | marcador **volta a `0`** |
| 4 | bloquear e desbloquear | teclado numérico, `7890` funciona |

Se o passo 3 falhar, o aparelho fica **impossível de desbloquear**: a paleta só gera os dígitos 1 a 6, e a credencial real contém 7, 8, 9 e 0. É a razão da linha acrescentada em `ChooseLockGeneric.onActivityResult` (T04, seção 2.6).

## Cenário 6 — Limites de comprimento

| Caso | Entrada | Esperado |
| --- | --- | --- |
| curta demais | 3 cores | botão de avançar inativo, mensagem "Use at least 4 colors" |
| mínima | 4 cores | aceita |
| máxima | 8 cores | aceita |
| acima do máximo | 9º toque | ignorado, contador para em 8 |
| confirmação divergente | `1542` depois `1543` | "Color sequences don't match", volta ao passo 1 |

## Cenário 7 — Erro e bloqueio por tentativas

| Passo | Ação | Esperado |
| --- | --- | --- |
| 1 | errar a sequência 1× | mensagem de erro, progresso limpo |
| 2 | errar 5× seguidas | "Try again in 30 seconds", paleta desabilitada |
| 3 | esperar o tempo | paleta reabilitada |
| 4 | acertar | desbloqueia |

Nada aqui é código nosso: o lockout vem do `LockPatternUtils`. O cenário existe para **provar** que a modalidade herdou o comportamento de segurança do AOSP em vez de contorná-lo — que é o argumento central da T03.

## Cenário 8 — Compatibilidade com política de administrador

| Passo | Comando | Esperado |
| --- | --- | --- |
| 1 | abrir a lista sem política | "Colors" habilitada |
| 2 | exigir senha alfanumérica via DPM | "Colors" **esmaecida**, junto com PIN e Pattern |
| 3 | remover a política | "Colors" habilitada de novo |

Confirma o que a T04 (seção 2.5) argumentou: `isScreenLockEnabled` é genérico e a nova opção obedece às políticas sem código adicional.

---

## Matriz de resultados

A preencher durante a execução. Esta tabela é a entrega da issue.

| # | Cenário | Resultado | Evidência | Observação |
| --- | --- | --- | --- | --- |
| 1 | Cadastro inicial | ⬜ | | |
| 2 | Troca de método e volta | ⬜ | | |
| 3 | Reinício | ⬜ | | |
| 4 | Apagar/acender tela | ⬜ | | |
| 5 | Cadastro abandonado | ⬜ | | |
| 6 | Limites de comprimento | ⬜ | | |
| 7 | Erro e lockout | ⬜ | | |
| 8 | Política de administrador | ⬜ | | |

Legenda: ✅ passou · ⚠️ passou com ressalva · ❌ falhou · ⬜ não executado

---

## Coleta automática

```bash
bash scripts/04-validar-t06.sh
```

O script executa os cenários 1, 3, 4, 5 e 7 inteiramente por `adb`, salva um PNG por passo em `evidencias-t06/` e grava o valor do marcador antes e depois de cada transição. Os cenários 2, 6 e 8 têm passos que exigem toque na tela e ficam manuais — os pontos exatos estão comentados no script.
