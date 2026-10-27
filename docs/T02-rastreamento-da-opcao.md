# T02 — Descobrir de onde vem uma opção visível nas configurações

> Variante complementar à issue #2. Aquela rastreou o **título** da tela (`"Choose a screen lock"`). Esta rastreia **as próprias opções da lista** — None, Swipe, Pattern, PIN, Password — que é o caminho que a T04 precisa alterar para inserir uma modalidade nova.

## Objetivo

Partir de um texto visível na interface e chegar, sem adivinhação, até o código que decide **quais métodos de bloqueio aparecem na lista, em que ordem, quando cada um fica oculto ou desabilitado, e o que acontece ao tocar em um deles**.

## Base usada

| Item | Valor |
| --- | --- |
| Projeto | `platform/packages/apps/Settings` |
| Tag | `android-14.0.0_r27` |
| Tela investigada | Settings → Security & privacy → Device unlock → Screen lock |

Todos os números de linha abaixo referem-se a essa tag.

## Investigação

### 1. Do texto visível para o recurso

As cinco opções que aparecem na tela são literais em `res/values/strings.xml`:

```bash
grep -n 'name="unlock_set_unlock_' res/values/strings.xml
```

```text
1195:    <string name="unlock_set_unlock_off_title">None</string>
1198:    <string name="unlock_set_unlock_none_title">Swipe</string>
1201:    <string name="unlock_set_unlock_pattern_title">Pattern</string>
1204:    <string name="unlock_set_unlock_pin_title">PIN</string>
1207:    <string name="unlock_set_unlock_password_title">Password</string>
```

Detalhe que confunde e vale registrar: **`unlock_set_unlock_off_title` é "None" e `unlock_set_unlock_none_title` é "Swipe"**. Os nomes dos recursos não acompanham os rótulos. Quem alterar isso por busca textual sem conferir troca as duas opções de lugar.

### 2. Do recurso para a tela declarada

Os cinco textos são consumidos por um único arquivo de preferências, `res/xml/security_settings_picker.xml`, que é a declaração estática da tela:

```xml
<PreferenceScreen android:key="lock_settings_picker">
    <com.android.settingslib.RestrictedPreference
            android:key="unlock_set_off"
            android:title="@string/unlock_set_unlock_off_title"
            android:icon="@drawable/ic_lock_none" />
    <com.android.settingslib.RestrictedPreference
            android:key="unlock_set_none"
            android:title="@string/unlock_set_unlock_none_title"
            android:icon="@drawable/ic_lock_swipe" />
    <com.android.settingslib.RestrictedPreference
            android:key="unlock_set_pattern"
            android:title="@string/unlock_set_unlock_pattern_title"
            android:icon="@drawable/ic_pattern" />
    <com.android.settingslib.RestrictedPreference
            android:key="unlock_set_pin"
            android:title="@string/unlock_set_unlock_pin_title"
            android:icon="@drawable/ic_lock_pin" />
    <com.android.settingslib.RestrictedPreference
            android:key="unlock_set_password"
            android:title="@string/unlock_set_unlock_password_title"
            android:icon="@drawable/ic_password" />
    <com.android.settingslib.RestrictedPreference
            android:key="unlock_set_managed" />
    <!-- unlock_skip_fingerprint / unlock_skip_face / unlock_skip_biometrics -->
    <com.android.settingslib.widget.FooterPreference android:key="lock_settings_footer" />
</PreferenceScreen>
```

Conclusão parcial: **a lista não é construída em tempo de execução, é declarada em XML e depois filtrada**. Cada item é identificado por uma `android:key`.

### 3. Da chave para o modelo de dados

As mesmas chaves (`unlock_set_off`, `unlock_set_pattern`, …) aparecem no enum `ScreenLockType`, que é o modelo que liga rótulo, chave e política de senha:

`src/com/android/settings/password/ScreenLockType.java`

```java
public enum ScreenLockType {
    NONE(    DevicePolicyManager.PASSWORD_QUALITY_UNSPECIFIED,      "unlock_set_off"),
    SWIPE(   DevicePolicyManager.PASSWORD_QUALITY_UNSPECIFIED,      "unlock_set_none"),
    PATTERN( DevicePolicyManager.PASSWORD_QUALITY_SOMETHING,        "unlock_set_pattern"),
    PIN(     DevicePolicyManager.PASSWORD_QUALITY_NUMERIC,
             DevicePolicyManager.PASSWORD_QUALITY_NUMERIC_COMPLEX,  "unlock_set_pin"),
    PASSWORD(DevicePolicyManager.PASSWORD_QUALITY_ALPHABETIC,
             DevicePolicyManager.PASSWORD_QUALITY_COMPLEX,          "unlock_set_password"),
    MANAGED( DevicePolicyManager.PASSWORD_QUALITY_MANAGED,          "unlock_set_managed");

    public final int defaultQuality;
    public final int maxQuality;
    public final String preferenceKey;
```

Cada constante carrega três coisas:

| Campo | Papel |
| --- | --- |
| `preferenceKey` | liga a constante ao item declarado no XML |
| `defaultQuality` | a constante de `DevicePolicyManager` que representa a força daquele método |
| `maxQuality` | a força máxima do mesmo método (PIN simples × PIN complexo) |

E dois métodos fazem a tradução nos dois sentidos:

```java
public static ScreenLockType fromKey(String key) {
    for (ScreenLockType lock : ScreenLockType.values()) {
        if (lock.preferenceKey.equals(key)) return lock;
    }
    return null;
}

public static ScreenLockType fromQuality(int quality) {
    switch (quality) {
        case PASSWORD_QUALITY_SOMETHING:        return ScreenLockType.PATTERN;
        case PASSWORD_QUALITY_NUMERIC:
        case PASSWORD_QUALITY_NUMERIC_COMPLEX:  return ScreenLockType.PIN;
        case PASSWORD_QUALITY_ALPHABETIC:
        case PASSWORD_QUALITY_ALPHANUMERIC:
        case PASSWORD_QUALITY_COMPLEX:          return ScreenLockType.PASSWORD;
        ...
```

`fromQuality` é o ponto mais importante desta investigação para a T04: **o sistema deduz qual método está ativo a partir da "qualidade" da credencial salva**. Duas modalidades que compartilhem a mesma `PASSWORD_QUALITY` são indistinguíveis por essa função.

### 4. Da declaração para a lista real

`src/com/android/settings/password/ChooseLockGeneric.java` infla o XML e **remove** o que não deve aparecer:

```java
// ChooseLockGeneric.java:545
protected void addPreferences() {
    addPreferencesFromResource(R.xml.security_settings_picker);
    ...
}

// ChooseLockGeneric.java:536  (dentro de updatePreferencesOrFinish)
disableUnusablePreferences();

// ChooseLockGeneric.java:715
private void disableUnusablePreferences() {
    final PreferenceScreen entries = getPreferenceScreen();
    for (ScreenLockType lock : ScreenLockType.values()) {
        String key = lock.preferenceKey;
        Preference pref = findPreference(key);
        if (pref instanceof RestrictedPreference) {
            boolean visible = mController.isScreenLockVisible(lock);
            boolean enabled = mController.isScreenLockEnabled(lock);
            if (!visible) {
                entries.removePreference(pref);     // some da lista
            } else if (!enabled) {
                pref.setEnabled(false);             // aparece esmaecido
            }
        }
    }
}
```

Dois estados distintos, e isso responde diretamente a uma das atividades da T04:

- **invisível** → `removePreference`, o item some da lista
- **visível porém desabilitado** → `setEnabled(false)`, o item aparece cinza (caso típico de política de administrador que exige credencial mais forte)

### 5. As regras de visibilidade

`src/com/android/settings/password/ChooseLockGenericController.java:164`

```java
public boolean isScreenLockVisible(ScreenLockType type) {
    final boolean managedProfile = mContext.getSystemService(UserManager.class)
            .isManagedProfile(mUserId);
    switch (type) {
        case NONE:
            return !mHideInsecureScreenLockTypes
                && !mContext.getResources().getBoolean(R.bool.config_hide_none_security_option)
                && !managedProfile;
        case SWIPE:
            return !mHideInsecureScreenLockTypes
                && !mContext.getResources().getBoolean(R.bool.config_hide_swipe_security_option)
                && !managedProfile;
        case MANAGED:
            return mManagedPasswordProvider.isManagedPasswordChoosable();
        case PIN:
        case PATTERN:
        case PASSWORD:
            return mLockPatternUtils.hasSecureLockScreen();
    }
    return true;
}
```

Restrições identificadas, que a T04 precisa respeitar:

| Restrição | Efeito |
| --- | --- |
| `mHideInsecureScreenLockTypes` | quem chamou o fluxo exige método seguro: None e Swipe somem |
| `config_hide_none_security_option` / `config_hide_swipe_security_option` | overlay do produto pode ocultar métodos inseguros |
| `isManagedProfile(mUserId)` | perfil de trabalho não oferece None nem Swipe |
| `hasSecureLockScreen()` | dispositivo sem suporte a bloqueio seguro não mostra Pattern/PIN/Password |
| `isScreenLockEnabled(type)` (linha 192) | complexidade mínima exigida por `DevicePolicyManager` |

A lista final é materializada em `getVisibleAndEnabledScreenLockTypes()` (linha 240), que percorre `ScreenLockType.values()` — ou seja, **a ordem dos itens na tela é a ordem de declaração do enum**.

### 6. Do toque para a ação

`ChooseLockGeneric.java:410`

```java
public boolean onPreferenceTreeClick(Preference preference) {
    writePreferenceClickMetric(preference);
    final String key = preference.getKey();
    if (!isUnlockMethodSecure(key) && mLockPatternUtils.isSecure(mUserId)) {
        showFactoryResetProtectionWarningDialog(key);   // seguro -> inseguro
        return true;
    } else if (KEY_SKIP_FINGERPRINT.equals(key) || ...) {
        ...
    } else {
        return setUnlockMethod(key);
    }
}

private boolean setUnlockMethod(String unlockMethod) {
    EventLog.writeEvent(EventLogTags.LOCK_SCREEN_TYPE, unlockMethod);
    ScreenLockType lock = ScreenLockType.fromKey(unlockMethod);
    if (lock != null) {
        switch (lock) {
            case NONE: case SWIPE: case PATTERN: case PIN: case PASSWORD: case MANAGED:
                updateUnlockMethodAndFinish(
                        lock.defaultQuality,
                        lock == ScreenLockType.NONE,
                        false /* chooseLockSkipped */);
                return true;
        }
    }
    Log.e(TAG, "Encountered unknown unlock method to set: " + unlockMethod);
    return false;
}
```

Observação decisiva para a T04: o `switch` em `setUnlockMethod` **enumera explicitamente cada constante**. Uma modalidade nova adicionada ao enum, mas esquecida aqui, cai no `Log.e(...)` e o toque simplesmente não faz nada — sem travar, sem mensagem para o usuário. É o erro mais provável de acontecer e o mais difícil de perceber.

Note ainda o primeiro ramo: trocar de um método **seguro** para um **inseguro** dispara o aviso de Factory Reset Protection. Isso vale para o cenário de volta ao método original, cobrado na T06.

## Mapa completo

```text
Tela "Choose a screen lock"
  │
  │ rótulos
  ├─► res/values/strings.xml:1195-1207
  │     unlock_set_unlock_{off,none,pattern,pin,password}_title
  │
  │ declaração estática da lista
  ├─► res/xml/security_settings_picker.xml
  │     RestrictedPreference android:key="unlock_set_*"
  │
  │ modelo: chave <-> qualidade
  ├─► password/ScreenLockType.java
  │     enum NONE, SWIPE, PATTERN, PIN, PASSWORD, MANAGED
  │     fromKey(String) · fromQuality(int)
  │
  │ construção e filtragem
  ├─► password/ChooseLockGeneric.java
  │     :410 onPreferenceTreeClick()        trata o toque
  │     :536 disableUnusablePreferences()   chamada
  │     :545 addPreferences()               infla o XML
  │     :715 disableUnusablePreferences()   remove / desabilita
  │          setUnlockMethod()              switch por ScreenLockType
  │
  └─► password/ChooseLockGenericController.java
        :164 isScreenLockVisible(type)
        :192 isScreenLockEnabled(type)
        :240 getVisibleAndEnabledScreenLockTypes()
```

## Arquivos e função de cada um

| Arquivo | Função no fluxo |
| --- | --- |
| `res/values/strings.xml` | textos visíveis das opções |
| `res/xml/security_settings_picker.xml` | declara os itens da lista e suas chaves |
| `src/.../password/ScreenLockType.java` | enum que liga chave ↔ rótulo ↔ `PASSWORD_QUALITY` |
| `src/.../password/ChooseLockGeneric.java` | infla, filtra e trata o toque |
| `src/.../password/ChooseLockGenericController.java` | regras de visibilidade e habilitação |
| `src/.../password/ChooseLockPattern.java` · `ChooseLockPassword.java` | telas de cadastro de cada modalidade |
| `src/.../security/screenlock/ScreenLockSettings.java` | tela de opções do bloqueio já configurado |

## Conclusão

Para acrescentar uma modalidade à lista é preciso tocar em **cinco pontos coordenados**, e deixar qualquer um de fora produz falha silenciosa:

1. `strings.xml` — o rótulo
2. `security_settings_picker.xml` — o item e sua `android:key`
3. `ScreenLockType` — a constante, com `preferenceKey` igual à chave do XML e uma `PASSWORD_QUALITY`
4. `ChooseLockGenericController.isScreenLockVisible` / `isScreenLockEnabled` — o `case` da nova constante
5. `ChooseLockGeneric.setUnlockMethod` — o `case` que dispara o cadastro

Fica registrada também a limitação descoberta em `fromQuality`: como o método ativo é deduzido da `PASSWORD_QUALITY` da credencial, uma modalidade nova que reaproveite uma qualidade existente **não é distinguível por essa via** e precisa de um marcador próprio, persistido fora da credencial. A especificação da T03 (#3) parte dessa restrição.

## Reprodução

Toda a investigação é reproduzível com os comandos abaixo, a partir da raiz dos fontes:

```bash
cd ~/aosp/packages/apps/Settings

grep -n 'name="unlock_set_unlock_' res/values/strings.xml
cat res/xml/security_settings_picker.xml
sed -n '1,90p'   src/com/android/settings/password/ScreenLockType.java
sed -n '715,732p' src/com/android/settings/password/ChooseLockGeneric.java
sed -n '164,188p' src/com/android/settings/password/ChooseLockGenericController.java
grep -n 'setUnlockMethod' src/com/android/settings/password/ChooseLockGeneric.java
```
