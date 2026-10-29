# Relatório final — Bloqueio de tela por sequência de cores

**DevTITANS 10 — Hands-On AOSP**
AOSP `android-14.0.0_r27` · produto `sdk_phone_x86_64-userdebug`

---

## 1. Objetivo e resultado

Acrescentar ao Android uma modalidade de desbloqueio além das cinco existentes (None, Swipe, Pattern, PIN, Password), cobrindo o ciclo completo: a opção na tela de configurações, o cadastro da credencial e a autenticação na tela de bloqueio.

A modalidade implementada é a **sequência de cores**: o usuário cadastra de 4 a 8 cores tocadas em ordem numa paleta de seis, e repete a mesma sequência para desbloquear.

**O que está funcionando**, comprovado por captura de tela do emulador:

- a opção **"Colors"** aparece no seletor de métodos, entre PIN e Password
- o cadastro mostra a paleta no lugar do teclado numérico, em dois passos com confirmação
- a tela de bloqueio mostra a paleta, aceita a sequência e rejeita sequências erradas com a mensagem de erro do sistema

**O que não está fechado:** os oito cenários de validação da T06 não foram executados, três ajustes cosméticos continuam pendentes (seção 8) e faltam duas capturas (seção 7).

---

## 2. Ambiente

| Item | Valor |
| --- | --- |
| Host | Ubuntu 22.04.5 LTS, kernel 5.15.0-198, 16 núcleos, 15,7 GB RAM |
| Fontes | `~/aosp`, 280 GB |
| Manifest | `refs/tags/android-14.0.0_r27` |
| Produto | `sdk_phone_x86_64` · variante `userdebug` · dispositivo `emulator_x86_64` |
| Build ID | `UQ1A.240205.004.B1` |
| Plataforma | Android 14, codename `VanillaIceCream`, estado `REL` |

Produto e variante foram confirmados nos fontes e na imagem compilada, não por suposição:

```bash
grep -rn "PRODUCT_DEVICE := emulator_x86_64" build/make/target/product/*.mk
# build/make/target/product/sdk_phone_x86_64.mk:55:PRODUCT_DEVICE := emulator_x86_64
grep -E "ro.build.(type|flavor)" out/target/product/emulator_x86_64/system/build.prop
# ro.build.type=userdebug
# ro.build.flavor=sdk_phone_x86_64-userdebug
```

### Divergência de ambiente registrada

A documentação de referência da equipe (issue #1) descreve `lunch devtitans_kraken-eng`. Na máquina usada neste trabalho esse produto **não é selecionável**:

```bash
ls -la ~/aosp/.repo/local_manifests/   # vazio
ls -d ~/aosp/device/*/kraken           # não existe
```

Os fontes são AOSP puro, vindos do manifesto oficial na tag `android-14.0.0_r27`, sem manifesto local nem árvore de dispositivo adicional.

**Decisão: seguir com `sdk_phone_x86_64`.** O alvo do trabalho — a tela de bloqueio — está em `packages/apps/Settings`, `frameworks/base` e `packages/SystemUI`, todos código de plataforma, independentes de árvore de dispositivo. Obter a árvore `kraken` e recompilar exigiria muito mais do que os 57 GB livres no disco (que estava em 94% de ocupação), com risco de interromper o build por falta de espaço. A alteração é portável: o mesmo patch se aplica ao `kraken` sem modificação.

### Nota de método: emulador headless

O emulador foi executado sem janela:

```bash
emulator -no-snapshot -no-boot-anim -no-window -gpu swiftshader_indirect -no-audio &
```

Em `gpu mode host`, com a máquina acessada remotamente, o compositor do host passava a resetar o driver gráfico repetidamente (`KWin: Desktop effects were restarted due to a graphics reset`) e a sessão inteira travava — enquanto a máquina estava, de fato, 98% ociosa. Sem janela o problema desapareceu e o boot caiu de 19,3 s para 16,2 s.

Como consequência, **toda a interação com o dispositivo foi feita por `adb`**, sem clique: `am start` para abrir telas, `input keyevent` e `input text` para interagir, `adb exec-out screencap -p` para capturar. Isso tornou cada passo reproduzível por qualquer pessoa da equipe com um comando, e as capturas saem em 1440×2960 direto do framebuffer.

---

## 3. Investigação

Ponto de partida: as opções visíveis em **Settings → Security & privacy → Device unlock → Screen lock**. Objetivo: chegar ao código que decide quais métodos aparecem, em que ordem, quando somem, e o que acontece ao tocar em um deles.

```text
Tela "Choose a screen lock"
  │
  ├─► res/values/strings.xml:1195-1207
  │     unlock_set_unlock_{off,none,pattern,pin,password}_title
  │
  ├─► res/xml/security_settings_picker.xml
  │     RestrictedPreference android:key="unlock_set_*"
  │
  ├─► password/ScreenLockType.java
  │     enum NONE, SWIPE, PATTERN, PIN, PASSWORD, MANAGED
  │     fromKey(String) · fromQuality(int)
  │
  ├─► password/ChooseLockGeneric.java
  │     :410 onPreferenceTreeClick()       trata o toque
  │     :545 addPreferences()              infla o XML
  │     :715 disableUnusablePreferences()  remove ou desabilita
  │          setUnlockMethod()             switch por ScreenLockType
  │
  └─► password/ChooseLockGenericController.java
        :164 isScreenLockVisible(type)
        :192 isScreenLockEnabled(type)
        :240 getVisibleAndEnabledScreenLockTypes()
```

Quatro achados determinaram o projeto inteiro.

**1. A lista é declarada, não construída.** `security_settings_picker.xml` declara os itens; `disableUnusablePreferences()` depois remove os invisíveis e desabilita os indisponíveis. São dois estados distintos: `removePreference` faz sumir, `setEnabled(false)` deixa esmaecido.

**2. A ordem da lista é a ordem do enum.** `getVisibleAndEnabledScreenLockTypes()` percorre `ScreenLockType.values()`, então a posição de uma constante nova no enum define onde ela aparece na tela.

**3. `setUnlockMethod` enumera cada constante explicitamente.** Uma constante nova adicionada ao enum mas esquecida nesse `switch` cai em `Log.e("Encountered unknown unlock method")` e **o toque não faz nada** — sem travar, sem mensagem. Era o erro mais provável e o mais difícil de perceber.

**4. O método ativo é deduzido da qualidade da credencial.** Tanto `ScreenLockType.fromQuality(int)` quanto `KeyguardSecurityModel.getSecurityMode(int)` olham apenas a `PASSWORD_QUALITY` registrada. Não existe campo algum dizendo "o usuário escolheu a modalidade X". Esta foi a restrição central do trabalho.

Detalhe que merece registro, porque confunde: **`unlock_set_unlock_off_title` é "None" e `unlock_set_unlock_none_title` é "Swipe"**. Os nomes dos recursos não acompanham os rótulos, e alterar por busca textual troca as duas opções de lugar.

Documentação completa: [T02](T02-rastreamento-da-opcao.md).

---

## 4. Conceitos envolvidos

| Conceito | Papel |
| --- | --- |
| `PASSWORD_QUALITY_*` | constantes de `DevicePolicyManager` que classificam a força da credencial; é por elas que o sistema identifica o método ativo |
| `LockscreenCredential` | o objeto da credencial; `createPin`, `createPattern`, `createPassword` |
| `LockSettingsService` | serviço de sistema que grava e verifica credenciais |
| Synthetic Password | camada que desacopla a credencial do usuário das chaves de criptografia do armazenamento |
| Gatekeeper | componente que valida a credencial e aplica o atraso progressivo entre tentativas |
| `SecurityMode` | enum do SystemUI que determina qual tela o bouncer mostra |
| Factory Reset Protection | aviso disparado ao trocar de um método seguro para um inseguro |
| Direct Boot | fase entre o boot e o primeiro desbloqueio, em que o armazenamento do usuário ainda não está acessível |

---

## 5. Decisões técnicas

### 5.1 A escolha da modalidade

Sequência de cores, por três razões: é visual e demonstrável em vídeo; mapeia naturalmente para uma credencial existente; e, ao contrário do ritmo de toques, não depende de tolerância temporal, que é difícil de acertar e pior de avaliar.

Paleta de seis cores em ordem fixa, sequência de 4 a 8 toques, repetição permitida.

| Posição | Cor | Hex |
| --- | --- | --- |
| 1 | Vermelho | `#D32F2F` |
| 2 | Laranja | `#F57C00` |
| 3 | Amarelo | `#FBC02D` |
| 4 | Verde | `#388E3C` |
| 5 | Azul | `#1976D2` |
| 6 | Roxo | `#7B1FA2` |

Entropia: 6⁴ = 1.296 no mínimo, 6⁸ = 1.679.616 no máximo. **A sequência de 4 cores é mais fraca que um PIN de 4 dígitos** (10.000 combinações). Está assumido, e é por isso que o mínimo não é 3.

### 5.2 A decisão central: camada de apresentação, não credencial nova

Diante do achado 4 da investigação, havia dois caminhos.

**Caminho A — tipo de credencial próprio.** Criar uma `PASSWORD_QUALITY` nova implicaria alterar `DevicePolicyManager` (constante de API pública), `LockscreenCredential`, `LockSettingsService`, `LockPatternUtils`, `PasswordMetrics`, o Gatekeeper e o Synthetic Password. E há um detalhe que decide a questão:

```java
// KeyguardSecurityModel.java
switch (security) {
    ...
    default: throw new IllegalStateException("Unknown security quality:" + security);
}
```

Uma qualidade desconhecida **lança exceção no SystemUI**, deixando o aparelho preso na tela de bloqueio. Caminho descartado.

**Caminho B — camada de apresentação (escolhido).** Cada cor corresponde ao dígito da sua posição na paleta:

```
Usuário toca:   🟥 🟦 🟩 🟧
                 ↓
Mapeamento:     1   5   4   2
                 ↓
Credencial:     LockscreenCredential.createPin("1542")
                 ↓
Armazenamento:  LockSettingsService → Synthetic Password → Gatekeeper
                (idêntico ao PIN — nada alterado)
```

Um marcador por usuário em `Settings.Secure` (`lock_screen_color_mode`) registra a escolha, e **apenas a interface muda**.

O que isso preserva de graça: Gatekeeper, Synthetic Password, bloqueio progressivo por tentativas, Factory Reset Protection e a integração com políticas de administrador. **Nenhuma linha de criptografia foi escrita neste trabalho** — e inventar armazenamento de credencial é precisamente o tipo de coisa que se faz errado.

### 5.3 Envio explícito, não automático

A entrada é enviada por botão de confirmação, nunca automaticamente ao atingir um comprimento.

O AOSP oferece envio automático para PIN, mas só a partir de 6 dígitos, porque auto-enviar em um comprimento fixo revela esse comprimento a quem observa a tela. Como a sequência aqui tem comprimento variável de 4 a 8, o envio automático revelaria mais ainda.

### 5.4 Progresso neutro

Nem no cadastro nem no desbloqueio a cor tocada é repetida no indicador de progresso — apenas marcadores neutros. Mostrar a cor ajudaria a memorizar, mas entregaria a sequência a quem estivesse olhando por cima do ombro. É também o comportamento do PIN.

---

## 6. Implementação

### 6.1 `packages/apps/Settings` — 383 inserções, 0 remoções

| Arquivo | Função da mudança |
| --- | --- |
| `res/values/color_lock_palette.xml` | **novo** — a paleta; a ordem é parte do formato da credencial |
| `res/values/strings.xml` | rótulo, resumo, instruções, erros e descrições de acessibilidade |
| `res/xml/security_settings_picker.xml` | o item da lista, `android:key="unlock_set_color"` |
| `res/layout/choose_lock_color.xml` | **novo** — tela de cadastro com a grade de cores |
| `password/ScreenLockType.java` | constante `COLOR` entre `PIN` e `PASSWORD` |
| `password/ChooseLockGenericController.java` | `case COLOR` na regra de visibilidade |
| `password/ChooseLockGeneric.java` | `case COLOR` no `switch`; grava e limpa o marcador |
| `password/ChooseLockPassword.java` | infla o layout de cores quando o marcador está ativo |
| `password/ColorLockUtils.java` | **novo** — marcador, limites e ligação dos toques aos dígitos |

Três pontos merecem explicação.

**A posição no enum não é estética.** `COLOR` foi declarada entre `PIN` e `PASSWORD` porque `getVisibleAndEnabledScreenLockTypes()` itera `values()`. A captura `T04-01` confirma: "Colors" aparece exatamente ali.

**`isScreenLockEnabled` não precisou de alteração.**

```java
public boolean isScreenLockEnabled(ScreenLockType type) {
    return !mLockPatternUtils.isCredentialsDisabledForUser(mUserId)
            && type.maxQuality >= upgradeQuality(PASSWORD_QUALITY_UNSPECIFIED);
}
```

O método é genérico: compara `type.maxQuality` com a complexidade mínima exigida pelas políticas. Como `COLOR.maxQuality` é `PASSWORD_QUALITY_NUMERIC_COMPLEX`, a nova opção **já obedece automaticamente** ao `DevicePolicyManager`, como o PIN.

**O cadastro reaproveita o fluxo do PIN inteiro.** Em vez de uma `Activity` nova com fragmento, máquina de dois passos, worker de gravação e tratamento de erro, só o layout muda:

```java
public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
    if (ColorLockUtils.isColorMode(getContext(), mUserId)) {
        final View view = inflater.inflate(R.layout.choose_lock_color, container, false);
        ColorLockUtils.bindColorPad(view, view.findViewById(R.id.password_entry));
        return view;
    }
    return inflater.inflate(R.layout.choose_lock_password, container, false);
}
```

E o coração da conversão cor→dígito é curto:

```java
final String digit = String.valueOf(i + 1);
key.setOnClickListener(v -> {
    if (target.getText().length() < MAX_LENGTH) {
        target.append(digit);
    }
});
```

### 6.2 `frameworks/base` — 349 inserções, 1 remoção

| Arquivo | Função da mudança |
| --- | --- |
| `SystemUI/res-keyguard/layout/keyguard_color_view.xml` | **novo** — wrapper |
| `SystemUI/res-keyguard/layout/keyguard_color_view_portrait.xml` | **novo** — a paleta no bouncer |
| `SystemUI/res-keyguard/values/color_lock_palette.xml` | **novo** — paleta e tema |
| `SystemUI/res-keyguard/values/color_lock_strings.xml` | **novo** — rótulos de acessibilidade |
| `keyguard/KeyguardSecurityViewFlipperController.java` | escolhe o layout conforme o marcador |

**Nenhuma classe Java nova.** A única alteração de código tem 28 linhas, das quais 9 são comentário:

```java
case PIN: return isColorModeEnabled()
        ? R.layout.keyguard_color_view
        : R.layout.keyguard_pin_view;
```

Isso é possível porque o layout de cores declara a **mesma** `KeyguardPINView` com os **mesmos** ids. O controlador, a verificação assíncrona, a contagem de tentativas e o lockout continuam sendo os do AOSP.

Duas sutilezas do layout:

- as teclas 7, 8, 9 e 0 continuam declaradas, porém `gone` e fora do `Flow`. `KeyguardPINView#onFinishInflate` resolve todas as dez por `findViewById`, e removê-las do XML colocaria `null` na matriz de views. Mantê-las invisíveis também garante que **uma sequência jamais contenha esses dígitos**.
- o `Flow` referencia oito elementos com `flow_maxElementsWrap="3"`, produzindo três linhas: cores 1-3, cores 4-6, apagar e confirmar. É exatamente o que a captura `T05-01` mostra.

### 6.3 O caso do cadastro abandonado

Uma linha que não é óbvia e evita um aparelho inutilizável:

```java
// ChooseLockGeneric.onActivityResult, ramo RESULT_CANCELED
ColorLockUtils.setColorMode(getContext(), mUserId, false);
```

Sem ela: o usuário com um PIN `7890` escolhe "Colors", desiste no meio do cadastro, e o marcador fica ativo apontando para a credencial antiga. O bouncer passaria a mostrar a paleta, que **só produz os dígitos 1 a 6** — e a credencial real contém 7, 8, 9 e 0. O aparelho ficaria impossível de desbloquear.

---

## 7. Validação

### 7.1 O que está comprovado

| Afirmação | Evidência |
| --- | --- |
| Estado original tem Pattern, PIN e Password, sem "Colors" | `evidencias-t01/02-metodos-originais.png` (7:27) |
| "Colors" passa a aparecer entre PIN e Password | `evidencias-t04/T04-01-opcao-cores-na-lista.png` (8:18) |
| O cadastro mostra a paleta, com dois passos e confirmação | `evidencias-t04/T04-02-cadastro.png`, `T04-03-confirmacao.png` |
| O bouncer mostra a paleta em vez do teclado | `evidencias-t05/T05-01-bouncer-paleta-cores.png` |
| Sequência errada é rejeitada com mensagem | `evidencias-t05/T05-02-sequencia-incorreta.png` |
| O progresso é neutro, sem repetir as cores | `T04-03-confirmacao.png`, `T05-03-sequencia-completa.png` |

As duas primeiras linhas, tomadas juntas, são o antes e o depois: mesma tela, mesmo dia, com 51 minutos entre uma e outra.

Um detalhe útil: a captura do estado original mostra apenas Pattern, PIN e Password — **sem None e Swipe**. Não é defeito. A tela foi aberta pela action `SET_NEW_PASSWORD` no fluxo com biometria, que ativa `mHideInsecureScreenLockTypes`, e a regra está em `isScreenLockVisible` (linhas 164-186). A captura é confirmação empírica de uma regra levantada na investigação antes de ser observada.

### 7.2 O que não está comprovado

| Item | Situação |
| --- | --- |
| Desbloqueio concluído com sucesso | **falta a captura** da tela inicial após o desbloqueio; existe a da sequência digitada, não a do resultado |
| Ciclo de bloqueio da T01 | três capturas saíram inválidas (uma tela preta, duplicada três vezes) — ver [EVIDENCIAS.md](EVIDENCIAS.md) |
| Os oito cenários da T06 | **não executados**; não existe `evidencias-t06/` |
| Comportamento em Direct Boot | **não testado** — é o risco técnico mais sério, ver 8.4 |
| `locksettings verify --old 1542` | não registrado; é a prova de uma linha de que a credencial é mesmo um PIN |

O script [`scripts/04-validar-t06.sh`](../scripts/04-validar-t06.sh) executa os cenários automatizáveis e salva as capturas; os passos que exigem toque estão marcados nele.

---

## 8. Limitações e pendências

### 8.1 Os dígitos aparecem sobre as cores

Visível em todas as capturas pós-patch. O tema `ColorLockNumPadKey` com `textColorPrimary` transparente não surtiu efeito: `NumPadKey` resolve a cor do texto por outro caminho (`NumPadKey.java:159`), não pelo `android:theme` da view.

Não quebra nada, mas expõe o mapeamento cor→dígito na tela. Correção: estender `@style/NumPadKey` com a cor explícita e aplicar com `style=`, ou esconder `R.id.digit_text` em `KeyguardPINView#onFinishInflate`.

### 8.2 Os textos ainda dizem "PIN"

"Set a PIN", "Re-enter your PIN", "Enter your PIN", "Wrong PIN". As strings próprias foram criadas nos patches, mas não foram ligadas aos pontos que definem o cabeçalho. Correção: um `if` onde `ChooseLockPasswordFragment` define `sud_layout_description`, e o equivalente no controlador do bouncer.

### 8.3 O botão de apagar diz "CANCEL"

`color_key_delete` usa `@android:string/cancel`. A função é apagar a última cor; toque longo limpa tudo. Correção: string própria.

### 8.4 Direct Boot não verificado

O marcador vive em `Settings.Secure`. No primeiro desbloqueio após o boot, o armazenamento do usuário ainda não está acessível, e a leitura pode retornar o padrão `0` — mostrando o teclado numérico no lugar da paleta. Se acontecer, o marcador precisa migrar para armazenamento protegido de dispositivo. **É a primeira coisa a testar.**

### 8.5 Limitações de desenho, assumidas

1. A credencial é um PIN restrito aos dígitos 1 a 6 — espaço de busca menor que um PIN decimal do mesmo comprimento.
2. Quem souber o mapeamento pode digitar o PIN equivalente, se chegar a uma tela de PIN. A proteção é de desenho, não criptográfica.
3. `getActivePasswordQuality()` retorna `PASSWORD_QUALITY_NUMERIC`: políticas de administrador tratam o bloqueio como PIN — o que é correto, já que é a força real.
4. Se o marcador for apagado por outro meio, o bouncer volta ao teclado numérico e o usuário entra digitando os números. Degrada com elegância, mas é dependência externa à credencial.
5. Não há migração: mudar a ordem da paleta invalidaria todas as sequências cadastradas.

---

## 9. Contribuições

Conforme o histórico do repositório e das issues.

| Pessoa | Contribuição | Onde verificar |
| --- | --- | --- |
| [@andertdev](https://github.com/andertdev) | T01 e T02 na variante `devtitans_kraken`: ambiente, baseline e rastreamento do título "Choose a screen lock" | issues #1 e #2 |
| [@gondimkevyn](https://github.com/gondimkevyn) | T01 e T02 em AOSP puro; especificação da T03; implementação da T04 e T05; plano da T06; consolidação deste relatório | issues #10, #9, #3, #4, #5, #6, #7; commits `b608e43`, `c33c70e` |
| [@alinaolima](https://github.com/alinaolima) | compilação dos patches, execução no emulador e coleta das evidências das T01, T04 e T05; atualização do README | commits `5d0991f` a `ba8e90f` |
| [@Gabsz193](https://github.com/Gabsz193) | estrutura inicial do repositório | commits `a58a336` a `5e31b23` |

> Os commits de 28/10 aparecem sob duas identidades de git (`alinaolima` e `José`) com o mesmo endereço de e-mail. A equipe deve confirmar a autoria antes da entrega — se houve trabalho em par, vale registrar aqui.

---

## 10. Fontes

- **AOSP, tag `android-14.0.0_r27`**, projetos `platform/packages/apps/Settings` e `platform/frameworks/base`. É a fonte primária de tudo neste trabalho: cada afirmação técnica tem arquivo e linha.
- `source.android.com` — Authentication, Gatekeeper, Synthetic Password
- `developer.android.com/reference/android/app/admin/DevicePolicyManager` — constantes `PASSWORD_QUALITY_*`

Nenhuma solução de terceiros foi adaptada. A implementação deriva inteiramente da leitura do próprio AOSP.

---

## 11. Como reproduzir

```bash
git clone -b feat/bloqueio-por-cores https://github.com/gondimkevyn/Hands-On-AOSP-1-Time2.git
cd Hands-On-AOSP-1-Time2

bash scripts/00-ambiente.sh ~/aosp          # coleta dados do ambiente
bash scripts/01-subir-emulador.sh ~/aosp    # emulador headless
bash scripts/02-coletar-baseline.sh         # comportamento ORIGINAL
bash scripts/03-aplicar-patches.sh ~/aosp   # aplica os dois patches

cd ~/aosp && source build/envsetup.sh && lunch sdk_phone_x86_64-userdebug && m

bash scripts/01-subir-emulador.sh ~/aosp
bash scripts/04-validar-t06.sh              # cenários de validação
```

`03-aplicar-patches.sh` faz `git apply --check` antes de encostar na árvore, então não deixa nada pela metade se o patch não aplicar.

Para reverter:

```bash
git -C ~/aosp/packages/apps/Settings checkout . && git -C ~/aosp/packages/apps/Settings clean -fd
git -C ~/aosp/frameworks/base       checkout . && git -C ~/aosp/frameworks/base       clean -fd
```

---

## 12. Checklist de entrega

- [x] build limpo com os dois patches
- [x] opção visível nas configurações, com evidência
- [x] cadastro funcional, com evidência
- [x] autenticação funcional, com evidência
- [x] documentação técnica, tarefa por tarefa
- [x] índice de evidências conferido imagem por imagem
- [ ] captura do desbloqueio concluído
- [ ] ciclo de bloqueio da T01 recapturado
- [ ] oito cenários da T06 executados
- [ ] três ajustes cosméticos (8.1, 8.2, 8.3)
- [ ] vídeo gravado
- [ ] revisão de código registrada em PR
- [ ] contribuições confirmadas pela equipe
