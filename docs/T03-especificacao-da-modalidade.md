## T03 — Especificação da modalidade: **Sequência de Cores**

Especificação fechada a partir do que a investigação da T02 (#9) encontrou no código. Decisões tomadas e justificadas abaixo; aberto a mudança antes da implementação.

---

## 1. A modalidade escolhida

**Sequência de Cores** — o usuário cadastra e informa uma sequência ordenada de cores, tocando em uma paleta fixa de seis cores dispostas em grade.

| Parâmetro | Valor | Por quê |
| --- | --- | --- |
| Tamanho da paleta | 6 cores | menos que 4 dá entropia baixa demais; mais que 6 fica difícil de distinguir e de tocar |
| Comprimento mínimo | 4 toques | mesmo mínimo do PIN no AOSP |
| Comprimento máximo | 8 toques | acima disso a memorização cai e o cadastro vira tentativa e erro |
| Repetição de cor | permitida | proibir repetição reduz o espaço de busca |
| Envio | **botão explícito** de confirmação | ver seção 4 |

Paleta (ordem fixa na grade):

| Posição | Cor | Hex | Rótulo acessível |
| --- | --- | --- | --- |
| 1 | Vermelho | `#D32F2F` | Vermelho |
| 2 | Laranja | `#F57C00` | Laranja |
| 3 | Amarelo | `#FBC02D` | Amarelo |
| 4 | Verde | `#388E3C` | Verde |
| 5 | Azul | `#1976D2` | Azul |
| 6 | Roxo | `#7B1FA2` | Roxo |

Entropia: 6^4 = 1.296 combinações no mínimo, 6^8 = 1.679.616 no máximo. Para comparação, um PIN de 4 dígitos tem 10.000. **A sequência de 4 cores é mais fraca que um PIN de 4 dígitos** — isso está assumido e documentado, e por isso o mínimo não é 3.

---

## 2. A decisão de arquitetura (a parte que importa)

A T02 encontrou a restrição que determina todo o resto:

> `ScreenLockType.fromQuality(int)` em Settings e `KeyguardSecurityModel.getSecurityMode(int)` em SystemUI **deduzem o método de bloqueio ativo a partir da `PASSWORD_QUALITY` da credencial salva**. Não existe, em lugar nenhum, um campo que diga "o usuário escolheu a modalidade X".

Confirmado em `frameworks/base/packages/SystemUI/src/com/android/keyguard/KeyguardSecurityModel.java`:

```java
final int security = whitelistIpcs(() -> mLockPatternUtils.getActivePasswordQuality(userId));
switch (security) {
    case PASSWORD_QUALITY_NUMERIC:
    case PASSWORD_QUALITY_NUMERIC_COMPLEX:  return SecurityMode.PIN;
    case PASSWORD_QUALITY_SOMETHING:        return SecurityMode.Pattern;
    ...
    default: throw new IllegalStateException("Unknown security quality:" + security);
}
```

Diante disso havia dois caminhos.

### Caminho A — credencial própria (descartado)

Criar um tipo de credencial novo, com `PASSWORD_QUALITY` própria.

Implica alterar: `DevicePolicyManager` (constante pública de API), `LockscreenCredential`, `LockSettingsService`, `LockPatternUtils`, `PasswordMetrics`, a validação do Gatekeeper, o Synthetic Password, `DevicePolicyManagerService`, e o `default:` acima que **lança exceção** para qualquer qualidade desconhecida — ou seja, uma constante nova não tratada derruba o SystemUI no boot.

**Descartado.** Toca em API pública, espalha por quatro ou cinco projetos do AOSP, e o ganho é zero: a criptografia seria exatamente a mesma.

### Caminho B — camada de apresentação sobre credencial existente (escolhido)

Cada cor é mapeada para um dígito pela sua posição fixa na paleta:

```
Vermelho=1  Laranja=2  Amarelo=3  Verde=4  Azul=5  Roxo=6
```

A sequência vira um PIN e é gravada por `LockscreenCredential.createPin(...)`, exatamente como hoje. Um marcador separado registra que o usuário escolheu a modalidade de cores, e **só a interface muda**.

```
Usuário toca:   🟥 🟦 🟩 🟧
                 ↓
Mapeamento:     1   5   4   2
                 ↓
Credencial:     LockscreenCredential.createPin("1542")
                 ↓
Armazenamento:  LockSettingsService → Synthetic Password → Gatekeeper
                (idêntico ao PIN — nenhuma alteração)
```

**Vantagens, e são o argumento central do relatório:**

1. Reaproveita Gatekeeper, Synthetic Password, bloqueio por tentativas, Factory Reset Protection e a integração com `DevicePolicyManager` sem escrever uma linha de criptografia. Inventar armazenamento de credencial num trabalho de disciplina é exatamente o tipo de coisa que se faz errado.
2. A superfície de alteração cai para ~6 arquivos, contra dezenas.
3. Interoperável por construção: trocar de Cores para PIN e voltar funciona, porque por baixo é o mesmo objeto.

**Limitações, declaradas honestamente:**

1. A credencial é um PIN restrito aos dígitos 1–6 — espaço de busca menor que um PIN decimal do mesmo comprimento.
2. Quem souber o mapeamento pode desbloquear digitando o PIN equivalente, se conseguir acesso à tela de PIN (não oferecida quando o modo cores está ativo, mas é uma propriedade do desenho, não uma barreira criptográfica).
3. `getActivePasswordQuality()` continua retornando `PASSWORD_QUALITY_NUMERIC`. Políticas de administrador tratarão o bloqueio como PIN — o que é **correto**, já que é a força real da credencial.

### O marcador

```java
Settings.Secure.getIntForUser(resolver, "lock_screen_color_mode", 0, userId)
```

| Valor | Significado |
| --- | --- |
| `0` (padrão) | bloqueio numérico comum — teclado de PIN |
| `1` | modalidade de cores ativa — paleta de cores |

Escrito por Settings no momento do cadastro, lido por Settings (para marcar a opção atual) e por SystemUI (para escolher o layout do bouncer). Limpo sempre que o usuário troca para qualquer outro método.

---

## 3. Esboços das telas

### 3.1 Settings — a opção na lista

```
┌──────────────────────────────────────┐
│  ←   Choose a screen lock            │
├──────────────────────────────────────┤
│  🚫   None                           │
│  👆   Swipe                          │
│  ⠿    Pattern                        │
│  ⌨    PIN                            │
│  🎨   Cores                   ← NOVA │
│  🔑   Password                       │
└──────────────────────────────────────┘
```

Posicionada **depois de PIN e antes de Password**, porque a ordem da lista é a ordem de declaração do enum `ScreenLockType` (descoberta da T02, item 5) e a força da credencial é equivalente à de um PIN.

### 3.2 Cadastro — passo 1, escolher a sequência

```
┌──────────────────────────────────────┐
│  ←   Definir sequência de cores      │
├──────────────────────────────────────┤
│                                      │
│   Toque de 4 a 8 cores na ordem      │
│   que quiser memorizar               │
│                                      │
│        ● ● ● ○ ○ ○ ○ ○               │
│        3 de 4 (mínimo)               │
│                                      │
│   ┌────────┬────────┬────────┐       │
│   │   🟥   │   🟧   │   🟨   │       │
│   ├────────┼────────┼────────┤       │
│   │   🟩   │   🟦   │   🟪   │       │
│   └────────┴────────┴────────┘       │
│                                      │
│   [ Apagar ]            [ Avançar ]  │
│                          (inativo)   │
└──────────────────────────────────────┘
```

- os marcadores de progresso são **neutros**, não coloridos — mostrar a cor já escolhida entregaria o segredo a quem estivesse olhando
- `Avançar` só habilita a partir de 4 toques
- `Apagar` remove o último toque; toque longo limpa tudo

### 3.3 Cadastro — passo 2, confirmar

```
┌──────────────────────────────────────┐
│  ←   Confirmar sequência             │
├──────────────────────────────────────┤
│                                      │
│   Repita a sequência para confirmar  │
│                                      │
│        ● ● ● ● ○ ○ ○ ○               │
│                                      │
│   ┌────────┬────────┬────────┐       │
│   │   🟥   │   🟧   │   🟨   │       │
│   ├────────┼────────┼────────┤       │
│   │   🟩   │   🟦   │   🟪   │       │
│   └────────┴────────┴────────┘       │
│                                      │
│   ⚠ As sequências não coincidem      │
│                                      │
│   [ Apagar ]           [ Confirmar ] │
└──────────────────────────────────────┘
```

Erro na confirmação volta ao passo 1 com a mensagem, mesmo comportamento de `ChooseLockPattern`.

### 3.4 Desbloqueio — o bouncer

```
┌──────────────────────────────────────┐
│                                      │
│              09:41                   │
│         Terça, 27 de outubro         │
│                                      │
│                                      │
│         Toque sua sequência          │
│                                      │
│        ● ● ● ○ ○ ○ ○ ○               │
│                                      │
│   ┌────────┬────────┬────────┐       │
│   │   🟥   │   🟧   │   🟨   │       │
│   ├────────┼────────┼────────┤       │
│   │   🟩   │   🟦   │   🟪   │       │
│   └────────┴────────┴────────┘       │
│                                      │
│   [ ⌫ ]      [ Emergência ]   [ ✓ ]  │
│                                      │
└──────────────────────────────────────┘
```

### 3.5 Desbloqueio — erro

```
│   ⚠ Sequência incorreta. Restam 4    │
│     tentativas antes do bloqueio     │
│        ○ ○ ○ ○ ○ ○ ○ ○               │
```

Mensagem e contagem vêm do `LockPatternUtils` existente, sem código novo.

---

## 4. Quando a entrada é enviada

Atividade explícita da T05. **Decisão: botão de confirmação explícito (✓), sem envio automático.**

Três opções foram consideradas:

| Opção | Problema |
| --- | --- |
| Envio automático ao atingir o comprimento | vaza o comprimento da sequência: quem observa a tela descobre quantos toques são, e cada tentativa errada confirma o tamanho |
| Envio automático após pausa de N ms | imprevisível, e penaliza quem toca devagar |
| **Botão explícito** | o usuário decide quando enviar; o comprimento não é revelado; permite corrigir antes de confirmar |

O AOSP oferece o envio automático para PIN (`auto_confirm`), mas ele só é habilitado para PINs de 6 ou mais dígitos justamente por esse motivo. Como aqui o comprimento é variável de 4 a 8, o botão explícito é a única opção consistente.

---

## 5. Arquivos que serão alterados

Derivado diretamente do mapa da T02.

### `packages/apps/Settings`

| Arquivo | Alteração |
| --- | --- |
| `res/values/strings.xml` | rótulo, instruções e mensagens de erro |
| `res/values/colors.xml` | a paleta de seis cores |
| `res/xml/security_settings_picker.xml` | `RestrictedPreference` com `android:key="unlock_set_color"` |
| `src/.../password/ScreenLockType.java` | constante `COLOR`, entre `PIN` e `PASSWORD` |
| `src/.../password/ChooseLockGenericController.java` | `case COLOR` em `isScreenLockVisible` e `isScreenLockEnabled` |
| `src/.../password/ChooseLockGeneric.java` | `case COLOR` em `setUnlockMethod`, abrindo o cadastro |
| `src/.../password/ChooseLockColor.java` | **novo** — cadastro em dois passos |
| `res/layout/choose_lock_color.xml` | **novo** — grade de cores do cadastro |

### `frameworks/base/packages/SystemUI`

| Arquivo | Alteração |
| --- | --- |
| `res-keyguard/layout/keyguard_color_view.xml` | **novo** — paleta no bouncer |
| `src/.../keyguard/KeyguardSecurityViewFlipperController.java` | `getLayoutIdFor`: escolhe o layout de cores quando o marcador está ativo |

Note que **nenhuma classe Java nova é necessária no SystemUI**: o layout de cores declara a mesma `KeyguardPINView`, com os mesmos `@id/key1`…`@id/key6`, `@id/pinEntry`, `@id/delete_button` e `@id/key_enter`. Muda a aparência dos botões, não o comportamento. Essa é a consequência prática da decisão da seção 2, e o que mantém a T05 viável.

---

## 6. Critérios de aceite

- [ ] "Cores" aparece na lista entre PIN e Password
- [ ] cadastro exige confirmação e rejeita sequências divergentes
- [ ] sequência menor que 4 não permite avançar
- [ ] após cadastrar, bloquear a tela mostra a paleta, não o teclado numérico
- [ ] sequência correta desbloqueia; incorreta mostra erro e conta tentativa
- [ ] trocar Cores → PIN → Cores funciona, e o marcador acompanha
- [ ] reinício do dispositivo mantém a modalidade
- [ ] apagar/acender a tela mantém a modalidade
- [ ] escolher None ou Swipe limpa o marcador
