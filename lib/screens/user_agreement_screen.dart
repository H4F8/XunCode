import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../services/language_service.dart';
import '../widgets/markdown_text.dart';

/// Пользовательское соглашение XunCode.
///
/// [firstLaunch] = true: соглашение показывается до входа в IDE, без
/// принятия приложение закрывается. Иначе — режим чтения из настроек.
class UserAgreementScreen extends StatelessWidget {
  final bool firstLaunch;
  final VoidCallback? onAccepted;

  const UserAgreementScreen({
    super.key,
    this.firstLaunch = false,
    this.onAccepted,
  });

  Future<void> _decline(BuildContext context) async {
    SystemNavigator.pop();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final isRu = lang.code == 'ru';
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: Text(lang.tr('legal.title')),
        backgroundColor: VscodeTheme.bgSidebar,
        automaticallyImplyLeading: !firstLaunch,
        leading: firstLaunch
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: VscodeTheme.bgSidebar,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: VscodeTheme.border),
                    ),
                    child: MarkdownText(
                      isRu ? _textRu : _textEn,
                      baseFontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (firstLaunch) _buildFirstLaunchActions(context, lang),
        ],
      ),
    );
  }

  Widget _buildFirstLaunchActions(BuildContext context, LanguageService lang) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              lang.tr('legal.decline_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: VscodeTheme.red,
                      side: const BorderSide(color: VscodeTheme.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(lang.tr('legal.decline_btn')),
                    onPressed: () => _decline(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: VscodeTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(lang.tr('legal.accept_btn')),
                    onPressed: () => onAccepted?.call(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const String _textRu = '''
## 1. Общие положения

**1.1.** Настоящее Пользовательское соглашение (далее — «Соглашение») определяет условия использования приложения **XunCode** (далее — «Приложение»), редактора кода для мобильных и настольных платформ, а также права и обязанности Пользователя и Правообладателя.

**1.2.** Начиная использовать Приложение, Пользователь принимает условия настоящего Соглашения в полном объёме. Если Пользователь не согласен с условиями — он обязан прекратить использование Приложения.

**1.3.** Правообладатель Приложения — XunKal1 (H4F8): https://github.com/H4F8

## 2. Лицензия и открытый код

**2.1.** Приложение распространяется свободно как программное обеспечение с открытым исходным кодом по лицензии **Apache License 2.0**.

**2.2.** Пользователь вправе использовать, изучать, изменять и распространять Приложение на условиях лицензии Apache-2.0. Полный текст лицензии доступен в репозитории Приложения (файл LICENSE).

**2.3.** Соглашение не отменяет и не заменяет условия лицензии Apache-2.0, а дополняет их в части практического использования Приложения.

## 3. Правила использования

**3.1.** Приложение предназначено для написания, редактирования и выполнения программного кода, работы с файлами проектов и терминалом.

**3.2.** Пользователь использует Приложение исключительно в целях, не запрещённых законодательством его страны.

**3.3.** Запрещается использовать Приложение для создания, распространения или исполнения вредоносного программного обеспечения, нарушения прав третьих лиц и совершения противоправных действий.

**3.4.** Вся ответственность за созданный, изменённый или исполненный Пользователем код и команды лежит исключительно на Пользователе.

## 4. Терминал и пользовательская среда Linux

**4.1.** Приложение включает терминал и опциональную пользовательскую среду Alpine Linux на базе proot, работающую в пространстве пользователя без root-доступа.

**4.2.** Все команды, выполняемые в терминале (в том числе через плагины), исполняются от имени Пользователя. Правообладатель не контролирует содержание выполняемых команд.

**4.3.** Функция очистки кэша среды удаляет файлы пользовательского окружения. Перед её использованием Пользователь обязан сохранить важные данные проекта.

## 5. Плагины сторонних разработчиков

**5.1.** Приложение позволяет устанавливать плагины из внешних источников (GitHub-репозитории, маркетплейс). Плагины создаются третьими лицами и не являются частью Приложения.

**5.2.** Несмотря на наличие песочницы, Правообладатель не гарантирует корректность и безопасность сторонних плагинов. Установка и использование плагинов осуществляются Пользователем на свой риск.

**5.3.** Претензии по работе сторонних плагинов направляются их авторам.

## 6. Данные пользователя и резервные копии

**6.1.** Файлы проектов создаются, хранятся и изменяются локально на устройстве Пользователя.

**6.2.** Пользователь самостоятельно обеспечивает резервное копирование важных данных. Правообладатель не несёт ответственности за утрату файлов, данных или исходного кода вследствие любых обстоятельств, включая сбои Приложения, действия Пользователя, работу сторонних плагинов или обновление программной среды.

## 7. Конфиденциальность

**7.1.** Приложение не собирает, не хранит и не передаёт персональные данные Пользователя. Приложение не содержит рекламы и трекеров.

**7.2.** Приложение выполняет сетевые запросы исключительно к сервисам GitHub (проверка обновлений, загрузка плагинов) и к адресам сред разработки, указанным самим Пользователем.

**7.3.** Настройки Приложения хранятся локально на устройстве Пользователя.

## 8. Обновления

**8.1.** Приложение проверяет наличие обновлений через официальный репозиторий GitHub правообладателя.

**8.2.** Обычные обновления устанавливаются добровольно. Критические обновления безопасности могут блокировать работу Приложения до их установки — это защищает данные и устройство Пользователя.

## 9. Отказ от гарантий

**9.1.** Приложение предоставляется «КАК ЕСТЬ» («AS IS»). Правообладатель не предоставляет никаких гарантий, явных или подразумеваемых, включая гарантии пригодности для конкретных целей и отсутствия нарушений прав третьих лиц.

**9.2.** Правообладатель не гарантирует непрерывную и безошибочную работу Приложения.

## 10. Ограничение ответственности

**10.1.** Правообладатель не несёт ответственности за любой прямой или косвенный ущерб, включая упущенную выгоду, потерю данных, потерю прибыли, возникшие в результате использования или невозможности использования Приложения.

**10.2.** Ответственность Правообладателя ограничена суммой, фактически уплаченной Пользователем за Приложение (0 рублей / 0 долларов США, поскольку Приложение бесплатное).

## 11. Изменения условий

**11.1.** Правообладатель вправе изменять условия настоящего Соглашения. Актуальная редакция публикуется в Приложении и/или в официальном репозитории GitHub.

**11.2.** Продолжение использования Приложения после публикации изменений означает согласие Пользователя с новой редакцией Соглашения.

*Редакция от 21 августа 2026 года.*
''';

const String _textEn = '''
## 1. General provisions

**1.1.** This User Agreement (the "Agreement") governs the use of the **XunCode** application (the "Application"), a code editor for mobile and desktop platforms, and defines the rights and obligations of the User and the Rights Holder.

**1.2.** By using the Application, the User accepts this Agreement in full. If the User disagrees with these terms, they must stop using the Application.

**1.3.** Rights Holder of the Application: XunKal1 (H4F8) — https://github.com/H4F8

## 2. License and open source

**2.1.** The Application is distributed freely as open-source software under the **Apache License 2.0**.

**2.2.** The User may use, study, modify and distribute the Application under the terms of Apache-2.0. The full license text is available in the repository (LICENSE file).

**2.3.** This Agreement does not replace Apache-2.0 but supplements it regarding practical use of the Application.

## 3. Rules of use

**3.1.** The Application is intended for writing, editing and executing program code, working with project files and the terminal.

**3.2.** The User uses the Application solely for purposes permitted by the laws of their country.

**3.3.** It is prohibited to use the Application to create, distribute or execute malicious software, infringe third-party rights or perform unlawful actions.

**3.4.** All responsibility for any code written, modified or executed by the User, and for commands run by the User, lies solely with the User.

## 4. Terminal and user-space Linux environment

**4.1.** The Application includes a terminal and an optional Alpine Linux user-space environment based on proot, running without root access.

**4.2.** All commands executed in the terminal (including via plugins) are executed on behalf of the User. The Rights Holder does not control their content.

**4.3.** The cache-cleanup function deletes user-environment files. Before using it, the User must back up important project data.

## 5. Third-party plugins

**5.1.** The Application allows installing plugins from external sources (GitHub repositories, marketplace). Plugins are created by third parties and are not part of the Application.

**5.2.** Despite sandboxing, the Rights Holder does not guarantee the correctness or safety of third-party plugins. Installing and using plugins is done at the User's own risk.

**5.3.** Claims regarding third-party plugins should be directed to their authors.

## 6. User data and backups

**6.1.** Project files are created, stored and modified locally on the User's device.

**6.2.** The User is solely responsible for backing up important data. The Rights Holder is not liable for loss of files, data or source code due to any circumstances, including Application failures, User actions, third-party plugins or environment updates.

## 7. Privacy

**7.1.** The Application does not collect, store or transmit the User's personal data. The Application contains no ads or trackers.

**7.2.** Network requests are made exclusively to GitHub services (update checks, plugin downloads) and to development-environment addresses specified by the User.

**7.3.** Application settings are stored locally on the User's device.

## 8. Updates

**8.1.** The Application checks for updates via the official GitHub repository of the Rights Holder.

**8.2.** Regular updates are voluntary. Critical security updates may block the Application until installed — this protects the User's data and device.

## 9. Disclaimer of warranties

**9.1.** The Application is provided "AS IS". The Rights Holder makes no warranties, express or implied, including fitness for a particular purpose and non-infringement.

**9.2.** The Rights Holder does not guarantee uninterrupted or error-free operation of the Application.

## 10. Limitation of liability

**10.1.** The Rights Holder is not liable for any direct or indirect damages, including lost profits, loss of data or loss of revenue resulting from the use or inability to use the Application.

**10.2.** The Rights Holder's liability is limited to the amount actually paid by the User for the Application (USD 0, as the Application is free).

## 11. Changes to the terms

**11.1.** The Rights Holder may modify this Agreement. The current version is published in the Application and/or in the official GitHub repository.

**11.2.** Continued use of the Application after publication of changes constitutes acceptance of the new version.

*Effective as of August 21, 2026.*
''';
