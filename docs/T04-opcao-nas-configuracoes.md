## T04 — Implementação: a opção "Colors" nas configurações

Código escrito e disponível na branch **`feat/bloqueio-por-cores`**, patch `patches/0001-settings-color-lock.patch`.

**Estado:** escrito e revisado contra os fontes da tag `android-14.0.0_r27`. **Não compilado** — a validação de build é a primeira tarefa a fazer na máquina do laboratório. Os pontos de maior risco estão marcados no fim.

---

## 1. Resumo da alteração

```
 res/layout/choose_lock_color.xml                        | 170 ++++++++++++
 res/values/color_lock_palette.xml                       |  16 ++
 res/values/strings.xml                                  |  26 ++
 res/xml/security_settings_picker.xml                    |   7 +
 src/com/android/settings/password/ChooseLockGeneric.java           |   9 +
 src/com/android/settings/password/ChooseLockGenericController.java |   1 +
 src/com/android/settings/password/ChooseLockPassword.java          |   8 +
 src/com/android/settings/password/ColorLockUtils.java              | 134 ++++++++
 src/com/android/settings/password/ScreenLockType.java              |  12 +
 9 files changed, 383 insertions(+)
```

**383 inserções, zero remoções.** Nenhuma linha existente foi apagada ou reescrita — só acréscimos e um `if` novo. Isso é intencional: reduz o risco de regressão nos métodos atuais e torna a revisão de código da T07 muito mais simples.

---

## 2. Arquivo por arquivo

### 2.1 `res/values/color_lock_palette.xml` — novo

A paleta. **A ordem é parte do formato da credencial**: posição 1..6 é o dígito 1..6. Reordenar invalida toda sequência já cadastrada.

```xml
<color name="color_lock_red">#D32F2F</color>
<color name="color_lock_orange">#F57C00</color>
<color name="color_lock_yellow">#FBC02D</color>
<color name="color_lock_green">#388E3C</color>
<color name="color_lock_blue">#1976D2</color>
<color name="color_lock_purple">#7B1FA2</color>
```

### 2.2 `res/values/strings.xml`

Rótulo da opção, instruções do cadastro, mensagens de erro e as seis descrições de acessibilidade. Inseridas imediatamente antes de `unlock_set_unlock_password_title`, para manter a vizinhança lógica do arquivo.

```xml
<string name="unlock_set_unlock_color_title">Colors</string>
<string name="unlock_set_unlock_color_summary">Tap a sequence of colors to unlock</string>
<string name="lockpassword_choose_your_color_header">Tap 4 to 8 colors in an order you can remember</string>
<string name="lockpassword_confirm_your_color_header">Tap your color sequence again to confirm</string>
<string name="lockpassword_color_too_short">Use at least 4 colors</string>
<string name="lockpassword_color_mismatch">Color sequences don\'t match</string>
```

### 2.3 `res/xml/security_settings_picker.xml`

O item da lista, inserido **entre PIN e Password**:

```xml
<com.android.settingslib.RestrictedPreference
        android:key="unlock_set_color"
        android:title="@string/unlock_set_unlock_color_title"
        android:summary="@string/unlock_set_unlock_color_summary"
        android:icon="@drawable/ic_lock_pin"
        android:persistent="false"/>
```

A `android:key` tem que ser exatamente igual ao `preferenceKey` do enum — é por ela que `ScreenLockType.fromKey()` faz a ligação (T02, item 3).

### 2.4 `ScreenLockType.java`

```java
COLOR(
        DevicePolicyManager.PASSWORD_QUALITY_NUMERIC,
        DevicePolicyManager.PASSWORD_QUALITY_NUMERIC_COMPLEX,
        "unlock_set_color"),
```

Declarada **entre `PIN` e `PASSWORD`**, porque a T02 (item 5) mostrou que `getVisibleAndEnabledScreenLockTypes()` itera `ScreenLockType.values()` — **a ordem do enum é a ordem da lista na tela**.

A qualidade é a mesma do PIN, o que é a consequência direta da decisão de arquitetura da T03: a credencial realmente é um PIN.

### 2.5 `ChooseLockGenericController.java` — uma linha

```java
 case PIN:
 case PATTERN:
 case PASSWORD:
+case COLOR:
     return mLockPatternUtils.hasSecureLockScreen();
```

Só isso é necessário para visibilidade. **`isScreenLockEnabled` não precisou de alteração nenhuma**, e vale explicar por quê, porque é uma das atividades cobradas pela issue:

```java
public boolean isScreenLockEnabled(ScreenLockType type) {
    return !mLockPatternUtils.isCredentialsDisabledForUser(mUserId)
            && type.maxQuality >= upgradeQuality(PASSWORD_QUALITY_UNSPECIFIED);
}
```

O método é genérico: compara `type.maxQuality` com a complexidade mínima agregada das políticas. Como `COLOR.maxQuality` é `PASSWORD_QUALITY_NUMERIC_COMPLEX`, a nova opção **já obedece automaticamente** às políticas de `DevicePolicyManager`, exatamente como o PIN. Se o administrador exigir senha alfanumérica, "Colors" aparece esmaecida junto com PIN e Pattern. Nada a fazer.

### 2.6 `ChooseLockGeneric.java` — 9 linhas

```java
 ScreenLockType lock = ScreenLockType.fromKey(unlockMethod);
 if (lock != null) {
+    ColorLockUtils.setColorMode(getContext(), mUserId, lock == ScreenLockType.COLOR);
     switch (lock) {
         case NONE:
         case SWIPE:
         case PATTERN:
         case PIN:
+        case COLOR:
         case PASSWORD:
         case MANAGED:
             updateUnlockMethodAndFinish(...);
```

Duas coisas acontecem aqui.

O `case COLOR:` no `switch` é **obrigatório**. A T02 (item 6) registrou que sem ele o toque cai no `Log.e("Encountered unknown unlock method")` e **nada acontece na tela** — sem travar e sem mensagem. Seria o bug mais difícil de diagnosticar deste trabalho.

A chamada a `setColorMode(...)` grava o marcador. Note que ela é feita **para toda escolha**, não só para cores: escolher PIN, Pattern, None ou Swipe grava `false` e limpa o marcador. É o que garante o critério de aceite "escolher None ou Swipe limpa o marcador" sem nenhum código extra.

E o cancelamento do cadastro:

```java
 } else {
+    ColorLockUtils.setColorMode(getContext(), mUserId, false);
     int quality = getIntent().getIntExtra(LockPatternUtils.PASSWORD_TYPE_KEY, -1);
```

Sem isso haveria um bug real: o usuário escolhe "Colors", desiste no meio do cadastro, e o marcador fica ativo apontando para a credencial antiga. Se a credencial antiga fosse um PIN com dígitos 7, 8, 9 ou 0, **o aparelho ficaria impossível de desbloquear**, porque a paleta só produz 1 a 6. Está coberto no cenário 5 da T06.

### 2.7 `ColorLockUtils.java` — novo, 134 linhas

Concentra tudo que é específico da modalidade:

| Membro | Função |
| --- | --- |
| `COLOR_MODE_SETTING` | `"lock_screen_color_mode"`, a chave em `Settings.Secure` |
| `MIN_LENGTH` / `MAX_LENGTH` | 4 e 8 |
| `KEY_IDS[]` | os seis ids dos botões, **em ordem de paleta** — índice `i` produz o dígito `i+1` |
| `isColorMode(ctx, userId)` | lê o marcador, por usuário |
| `setColorMode(ctx, userId, on)` | grava o marcador |
| `bindColorPad(root, target)` | liga os toques das cores ao campo de credencial |

O coração é curto:

```java
final String digit = String.valueOf(i + 1);
key.setOnClickListener(v -> {
    if (target.getText().length() < MAX_LENGTH) {
        target.append(digit);
    }
});
```

A cor vira dígito e é anexada ao mesmo `EditText` que o fluxo de PIN já usa. Daí para a frente **não existe código novo**: a validação de comprimento, a confirmação em dois passos, o `SaveAndFinishWorker`, o Gatekeeper e o synthetic password são os do AOSP, intocados.

Também chama `target.setShowSoftInputOnFocus(false)`, para o teclado virtual não aparecer por cima da paleta.

### 2.8 `ChooseLockPassword.java` — 8 linhas

```java
 public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
+    if (ColorLockUtils.isColorMode(getContext(), mUserId)) {
+        final View view = inflater.inflate(R.layout.choose_lock_color, container, false);
+        ColorLockUtils.bindColorPad(view, view.findViewById(R.id.password_entry));
+        return view;
+    }
     return inflater.inflate(R.layout.choose_lock_password, container, false);
 }
```

Esta é a decisão de projeto que mais economizou trabalho. Em vez de escrever uma `Activity` de cadastro nova — com fragmento, máquina de estados de dois passos, worker de gravação e tratamento de erro, tudo isso já existente e testado em `ChooseLockPassword` — **só o layout muda**. O fluxo de cadastro é literalmente o do PIN.

### 2.9 `res/layout/choose_lock_color.xml` — novo

Substituto direto de `choose_lock_password.xml`. **Preserva obrigatoriamente todos os ids que `ChooseLockPasswordFragment` procura**, senão o fragmento quebra com `NullPointerException`:

`sud_layout_description`, `password_container`, `password_entry`, `auto_pin_confirm_enabler`, `auto_pin_confirm_security_message`

Os dois últimos ficam `visibility="gone"`: esta modalidade sempre envia com confirmação explícita, então a opção de auto-confirmação do PIN não se aplica.

Acrescenta a `GridLayout` 3×2 com as seis cores e o botão apagar.

---

## 3. Restrições de dispositivo, perfil e política

Atividade explícita da issue. Resumo do que foi investigado e de como a solução se comporta:

| Restrição | Origem | Comportamento de "Colors" |
| --- | --- | --- |
| Dispositivo sem bloqueio seguro | `hasSecureLockScreen()` | oculta, junto com PIN/Pattern/Password |
| Perfil de trabalho | `isManagedProfile(mUserId)` | **visível** — a restrição só atinge None e Swipe |
| Chamador exige método seguro | `mHideInsecureScreenLockTypes` | **visível** — é um método seguro |
| Overlay do produto | `config_hide_*_security_option` | não afeta (esses só ocultam None e Swipe) |
| Política de complexidade mínima | `isScreenLockEnabled` + `upgradeQuality` | esmaecida quando a política exige mais que numérico |
| Credenciais desabilitadas | `isCredentialsDisabledForUser` | esmaecida, como as demais |
| Troca de seguro para inseguro | `showFactoryResetProtectionWarningDialog` | o aviso de FRP dispara normalmente ao sair de Colors para None/Swipe |
| Marcador por usuário | `Settings.Secure.*ForUser` | cada perfil tem a própria configuração |

Nenhuma dessas exigiu código: todas vêm de graça por `COLOR` reaproveitar a qualidade do PIN.

---

## 4. Pontos de risco para validar no build

Em ordem de probabilidade de dar problema:

1. **`Settings.Secure.getIntForUser` / `putIntForUser`** são `@hide`. O app Settings compila contra a API interna, então devem estar acessíveis, mas é o primeiro erro a aparecer se não estiverem.
2. **`choose_lock_color.xml` pode estar faltando algum id** que o fragmento procura em outro ponto do código além dos cinco já mapeados. Sintoma: `NullPointerException` ao abrir o cadastro.
3. **`setShowSoftInputOnFocus(false)` pode ser revertido** por `ChooseLockPasswordFragment`, que chama `scheduleShowSoftInput()`. Sintoma: teclado aparece por cima da paleta. Solução, se ocorrer: chamar `setShowSoftInputOnFocus(false)` também em `onResume`.
4. **A instrução do cabeçalho** ainda é a do PIN ("Set a PIN"). Trocar pelos novos textos exige um `if` adicional onde o fragmento define `sud_layout_description`. Cosmético, resolver depois do build passar.

## 5. Evidências a coletar depois do build

```bash
adb shell am start -a android.app.action.SET_NEW_PASSWORD
adb exec-out screencap -p > T04-01-opcao-cores-na-lista.png
# tocar em Colors
adb exec-out screencap -p > T04-02-cadastro-paleta.png
adb exec-out screencap -p > T04-03-confirmacao.png
adb shell settings get secure lock_screen_color_mode   # deve responder 1
```
