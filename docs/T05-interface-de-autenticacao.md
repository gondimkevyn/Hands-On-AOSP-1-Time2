## T05 — Implementação: a interface de autenticação no bouncer

Código na branch **`feat/bloqueio-por-cores`**, patch `patches/0002-systemui-color-lock.patch`.

**Estado:** escrito contra `frameworks/base` na tag `android-14.0.0_r27`. **Não compilado.** Esta é a parte de maior risco do trabalho e os pontos a verificar estão listados na seção 5.

---

## 1. Resumo da alteração

```
 packages/SystemUI/res-keyguard/layout/keyguard_color_view.xml           |  25 ++
 packages/SystemUI/res-keyguard/layout/keyguard_color_view_portrait.xml  | 248 ++++
 packages/SystemUI/res-keyguard/values/color_lock_palette.xml            |  32 ++
 packages/SystemUI/res-keyguard/values/color_lock_strings.xml            |  16 ++
 packages/SystemUI/src/com/android/keyguard/KeyguardSecurityViewFlipperController.java | 29 +-
 5 files changed, 349 insertions(+), 1 deletion(-)
```

**Nenhuma classe Java nova.** A única alteração em código é de 28 linhas em um arquivo, e dessas, 9 são comentário.

---

## 2. Por que não foi preciso criar classe nenhuma

A investigação do SystemUI mostrou a mesma estrutura que a T02 encontrou no Settings. Em
`KeyguardSecurityModel.java`:

```java
final int security = whitelistIpcs(() -> mLockPatternUtils.getActivePasswordQuality(userId));
switch (security) {
    case PASSWORD_QUALITY_NUMERIC:
    case PASSWORD_QUALITY_NUMERIC_COMPLEX:  return SecurityMode.PIN;
    ...
    default: throw new IllegalStateException("Unknown security quality:" + security);
}
```

Duas consequências.

A primeira é um **aviso**: aquele `default` **lança exceção**. Se tivéssemos criado uma `PASSWORD_QUALITY` nova, como pedia o Caminho A descartado na T03, o SystemUI quebraria no boot, com o aparelho preso na tela de bloqueio. A decisão de reaproveitar a qualidade do PIN evita isso por construção.

A segunda é uma **oportunidade**: como a credencial de cores é um PIN, o `SecurityMode` já é `PIN`, e todo o maquinário de bouncer — `KeyguardPINView`, `KeyguardPinViewController`, `KeyguardAbsKeyInputView`, verificação assíncrona, contagem de tentativas, lockout, mensagem de erro — **já funciona sem tocar em nada**.

Sobra exatamente um ponto a mudar: qual layout é inflado.

`KeyguardSecurityViewFlipperController.java:142`

```java
 private int getLayoutIdFor(SecurityMode securityMode) {
     switch (securityMode) {
         case Pattern: return R.layout.keyguard_pattern_view;
-        case PIN: return R.layout.keyguard_pin_view;
+        case PIN: return isColorModeEnabled()
+                ? R.layout.keyguard_color_view
+                : R.layout.keyguard_pin_view;
         case Password: return R.layout.keyguard_password_view;
```

mais o leitor do marcador:

```java
private boolean isColorModeEnabled() {
    return Settings.Secure.getIntForUser(
            mView.getContext().getContentResolver(),
            COLOR_MODE_SETTING,
            0,
            KeyguardUpdateMonitor.getCurrentUser()) != 0;
}
```

O método irmão, `getKeyguardInputViewId(SecurityMode)` (linha 154), **não precisou mudar**: retorna `R.id.keyguard_pin_view`, e o layout de cores declara exatamente esse id.

---

## 3. O layout do bouncer

`keyguard_color_view_portrait.xml` deriva de `keyguard_pin_view_portrait.xml` e mantém a **mesma classe raiz** `com.android.keyguard.KeyguardPINView` com o **mesmo id**. Três diferenças.

**a) As seis primeiras teclas ganham cor**

```xml
<com.android.keyguard.NumPadKey
    android:id="@+id/key1"
    android:background="@color/color_lock_red"
    android:theme="@style/ColorLockNumPadKey"
    android:contentDescription="@string/color_lock_red_description"
    androidprv:digit="1"
    androidprv:textView="@+id/pinEntry" />
```

O atributo `androidprv:digit` é o que já existe: tocar a tecla anexa o dígito ao `pinEntry`. A cor é só o fundo. **O mapeamento cor→dígito está inteiramente na posição declarada**, e precisa bater com `ColorLockUtils.KEY_IDS` do Settings, senão o que é cadastrado não é o que é verificado.

**b) As teclas 7, 8, 9 e 0 continuam declaradas, mas `gone`**

```xml
<com.android.keyguard.NumPadKey
    android:id="@+id/key7"
    android:visibility="gone"
    androidprv:digit="7"
    androidprv:textView="@+id/pinEntry" />
```

Não é descuido. `KeyguardPINView.onFinishInflate()` monta uma matriz de views com `findViewById(R.id.key7)`, `key8`, `key9`, `key0`. Removê-las do XML colocaria `null` nessa matriz e derrubaria o bouncer. Mantê-las invisíveis e fora do `Flow` resolve, e garante que **uma sequência de cores jamais contenha os dígitos 7, 8, 9 ou 0**.

**c) O `Flow` passa a referenciar oito elementos em vez de doze**

```xml
androidprv:constraint_referenced_ids="key1,key2,key3,key4,key5,key6,delete_button,key_enter"
```

Com `flow_maxElementsWrap="3"`, o resultado é uma grade de três linhas: cores 1-3, cores 4-6, apagar e confirmar.

---

## 4. Cadastro × desbloqueio

Comparação pedida explicitamente pela issue.

| Aspecto | Cadastro (Settings) | Desbloqueio (SystemUI) |
| --- | --- | --- |
| Layout | `choose_lock_color.xml` | `keyguard_color_view_portrait.xml` |
| Container das cores | `GridLayout` 3×2 | `KeyguardPinFlowView`, 3 por linha |
| Widget de cada cor | `View` com background | `NumPadKey` com background |
| Como o toque vira dígito | `ColorLockUtils.bindColorPad` → `EditText.append` | `androidprv:digit` nativo → `PasswordTextView` |
| Campo que acumula | `R.id.password_entry` (`ScrollToParentEditText`) | `R.id.pinEntry` (`PasswordTextView`) |
| Progresso visível | dígitos mascarados | bolinhas neutras |
| Apagar | botão, toque longo limpa | `delete_button` padrão |
| Envio | botão "Next" do GlifLayout | `key_enter` |
| Verificação | `SaveAndFinishWorker` → `LockPatternUtils.setLockCredential` | `KeyguardAbsKeyInputView` → `LockPatternChecker.verifyCredential` |

**A paleta é idêntica nos dois lados — mesmas seis cores, mesma ordem, mesmo posicionamento.** É o que permite ao usuário reproduzir no desbloqueio o gesto que aprendeu no cadastro. As implementações internas diferem porque as duas telas pertencem a aplicativos diferentes, com sistemas de layout diferentes, e nenhum dos dois foi reescrito.

**Em nenhum dos dois lados a cor tocada é exibida no indicador de progresso.** Mostrar a cor facilitaria a memorização, mas entregaria a sequência a quem estivesse olhando a tela por cima do ombro. Preferiu-se a bolinha neutra, que é também o comportamento do PIN.

---

## 5. Quando a entrada é enviada

Decidido na T03 e implementado aqui: **envio explícito pelo botão de confirmação**, nunca automático.

O AOSP tem envio automático para PIN (`auto_pin_confirm`), mas só o habilita a partir de 6 dígitos. O motivo é que auto-enviar ao atingir um comprimento fixo revela esse comprimento a quem observa. Como a sequência de cores tem comprimento variável de 4 a 8, o envio automático revelaria mais ainda. O `key_enter` fica, e a opção de auto-confirmação é escondida no cadastro.

---

## 6. Pontos de risco para validar no build

Em ordem de probabilidade:

1. **O dígito pode continuar visível por cima da cor.** `NumPadKey` resolve a cor do texto pelo tema (`NumPadKey.java:159`), não por `android:textColor`. Foi criado o tema `ColorLockNumPadKey` com `textColorPrimary` transparente, **mas isso não foi verificado**. Se não funcionar, as alternativas são: estender `@style/NumPadKey` com a cor explícita, ou esconder `R.id.digit_text` em `KeyguardPINView#onFinishInflate` quando o modo de cores estiver ativo. **Não é bloqueante** — o bloqueio funciona com os dígitos aparecendo, só fica feio e revela o mapeamento.
2. **O `Flow` com 8 ids pode desalinhar as teclas.** `KeyguardPINView` ajusta `pin_pad_top_guideline` assumindo 4 linhas; com 3 linhas pode sobrar espaço embaixo. Cosmético.
3. **`Settings.Secure.getIntForUser` no SystemUI.** Deve estar acessível (o SystemUI usa API interna), mas é o primeiro erro de compilação provável.
4. **Leitura do marcador no momento errado.** `getLayoutIdFor` é chamado na inflação; se o usuário trocar de método com o bouncer já inflado e em cache, pode aparecer o teclado antigo até o próximo ciclo. É exatamente o cenário 2 da T06 — se acontecer, a correção é invalidar o cache do flipper ao observar a mudança do marcador.

## 7. Evidências a coletar depois do build

```bash
adb shell input keyevent 26 && sleep 2 && adb shell input keyevent 26 && sleep 3
adb exec-out screencap -p > T05-01-bouncer-paleta.png
adb shell input tap <x1> <y1>    # cores da sequência
adb exec-out screencap -p > T05-02-progresso-parcial.png
adb exec-out screencap -p > T05-03-desbloqueado.png
# e um caso de erro:
adb exec-out screencap -p > T05-04-sequencia-incorreta.png
```
