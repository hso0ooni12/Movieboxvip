# StreamWeb iOS — IPA غير موقّع عبر GitHub

تطبيق iPhone/iPad أصلي مبني بـ **SwiftUI + WKWebView** لعرض صفحة ويب داخل واجهة تطبيق. المشروع مضبوط افتراضيًا على:

`https://streamimdb.ru/`

المشروع لا يستخدم Apple Cloud Signing ولا يحتاج أي شهادة داخل GitHub. يقوم GitHub Actions ببناء ملف **IPA غير موقّع**، ثم توقّعه أنت لاحقًا ببرنامج التوقيع والشهادة الخاصة بك.

> استخدم المشروع فقط عندما تملك حق عرض الموقع ومحتواه داخل تطبيق. المشروع لا ينزّل الفيديو، لا يفك DRM، ولا يتجاوز حماية الوسائط.

## المزايا

- دعم iPhone وiPad من iOS 16 فما فوق.
- رجوع، تقدّم، الرئيسية، تحديث/إيقاف، مشاركة، وفتح في Safari.
- سحب للأسفل للتحديث وشريط تقدم للتحميل.
- معالجة أخطاء الشبكة وانقطاع الإنترنت.
- حفظ الكوكيز والجلسة باستخدام مخزن WebKit الدائم.
- دعم الفيديو داخل الصفحة وAirPlay وPicture in Picture عندما يسمح المشغّل بذلك.
- واجهة عربية وإنجليزية.
- أيقونة وشاشة تشغيل وPrivacy Manifest.
- مانع إعلانات محلي مفعّل افتراضيًا.
- بناء IPA غير موقّع بالكامل من GitHub Actions، دون أسرار Apple.

## مانع الإعلانات

المانع يعمل بثلاث طبقات:

1. قواعد `WKContentRuleList` تمنع تحميل نطاقات إعلانية شائعة.
2. CSS وJavaScript محليان يخفيان حاويات الإعلانات التي تُضاف بعد تحميل الصفحة.
3. النوافذ الخارجية التي تفتحها السكربتات تلقائيًا تُلغى، بينما تبقى الروابط التي يضغطها المستخدم مسموحة.

لا يقرأ المانع كلمات المرور أو النماذج أو رسائل الصفحة، ولا يرسل بيانات إلى خادم خارجي. قد تتغير شبكات الإعلانات لاحقًا، لذلك توجد القواعد في:

`StreamWeb/Resources/AdBlockRules.json`

إذا تسبب الحجب في مشكلة مع مشغّل معيّن، شغّل Workflow مع إيقاف **Ad blocking enabled** للتجربة.

## الملفات المهمة

- `StreamWeb/Resources/AppConfig.json`: الرابط واللون وخيارات التطبيق.
- `StreamWeb/Resources/AdBlockRules.json`: قواعد حجب موارد الإعلانات.
- `StreamWeb/Browser/AdBlocker.swift`: تثبيت القواعد، التنظيف البصري، ومنع النوافذ الإعلانية.
- `.github/workflows/build-ipa.yml`: بناء IPA غير موقّع لجهاز iPhone.
- `.github/workflows/ci.yml`: فحص المشروع وبناء نسخة Simulator.
- `scripts/configure.py`: تغيير الاسم والرابط وBundle ID من شاشة Run workflow.

## رفع المشروع إلى GitHub من الآيفون

1. أنشئ مستودعًا فارغًا في GitHub، ويفضل أن يكون **Private**.
2. افتح **Code → Codespaces → Create codespace** من Safari.
3. ارفع ZIP إلى مستكشف الملفات داخل Codespace.
4. افتح Terminal ونفّذ:

```bash
unzip StreamWeb-iOS-GitHub.zip -d /tmp/streamweb
cp -R /tmp/streamweb/StreamWeb-iOS/. .
rm -rf /tmp/streamweb
rm -f StreamWeb-iOS-GitHub.zip
git add .
git commit -m "Initial unsigned iOS app"
git push
```

## استخراج IPA غير موقّع

1. افتح تبويب **Actions** في المستودع.
2. اختر **Build Unsigned IPA**.
3. اضغط **Run workflow**.
4. أدخل:
   - اسم التطبيق.
   - رابط الموقع.
   - Bundle ID المطلوب.
   - اللون.
   - تفعيل مانع الإعلانات.
5. بعد نجاح التشغيل، افتح قسم **Artifacts**.
6. حمّل `unsigned-ipa` وفك ضغطه.
7. ستحصل على ملف باسم قريب من:

`StreamWeb-unsigned.ipa`

الـIPA الناتج يحتوي تطبيق جهاز حقيقي داخل `Payload/StreamWeb.app`، ولا يحتوي توقيعًا أو Provisioning Profile. أدخله في برنامج التوقيع الخاص بك واختر شهادة المطور وملف التهيئة المناسبين.

## Bundle ID

بعض برامج التوقيع تستطيع تغيير Bundle ID، وبعضها يعتمد على القيمة الموجودة داخل التطبيق. لتفادي الخطأ، أدخل Bundle ID المتوافق مع شهادتك أو ملف التهيئة عند تشغيل Workflow، مثل:

`com.yourname.streamweb`

## التخصيص الافتراضي

```json
{
  "appName": "Stream Web",
  "homeURL": "https://streamimdb.ru/",
  "opensExternalHostsInSafari": false,
  "accentHex": "#E50914",
  "adBlockingEnabled": true
}
```

لا يلزم تعديل هذا الملف يدويًا؛ حقول **Run workflow** تعدله قبل البناء.

## فحص المشروع

شغّل **Validate iOS Project** من Actions. هذا المسار يبني نسخة Simulator للفحص فقط، وليس IPA للتثبيت.

## الأمان

- لا ترفع ملفات P12 أو P8 أو mobileprovision أو كلمات مرور الشهادات.
- الـWorkflow لا يطلب GitHub Secrets.
- لا توجد مكتبات إعلانات أو تحليلات مضافة إلى التطبيق.
- بيانات الموقع والكوكيز تبقى ضمن WebKit، وفق سلوك الموقع نفسه.

## ملاحظات

- لا يمكن تثبيت IPA غير موقّع مباشرة على iPhone؛ وقّعه أولًا بأداتك.
- تغيّر الموقع أو نطاقات الإعلانات قد يتطلب تحديث `AdBlockRules.json`.
- الحجب القوي قد يمنع نافذة خارجية يحتاجها موقع ما؛ يمكن تعطيله من مدخل Workflow دون تعديل الكود.

## الرخصة

كود القالب تحت رخصة MIT. الرخصة لا تمنح حقوقًا في الموقع أو الأفلام أو الصور أو العلامات التجارية التابعة للغير.
