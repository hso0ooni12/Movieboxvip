# استخراج IPA غير موقّع من GitHub باستخدام الآيفون

لا يحتاج هذا المشروع إلى Apple Cloud Signing، ولا إلى شهادة أو Provisioning Profile داخل GitHub.

## الخطوات

1. ارفع المشروع إلى مستودع GitHub، ويفضل أن يكون Private.
2. افتح تبويب **Actions**.
3. اختر **Build Unsigned IPA**.
4. اضغط **Run workflow**.
5. أدخل اسم التطبيق والرابط وBundle ID واللون.
6. اترك **Ad blocking enabled** مفعّلًا.
7. بعد نجاح التشغيل، افتح قسم **Artifacts** وحمّل `unsigned-ipa`.
8. فك ملف Artifact ZIP لتحصل على ملف ينتهي بـ `-unsigned.ipa`.
9. افتح ملف IPA في برنامج التوقيع الذي تستخدمه، واختر شهادة المطور وملف التهيئة الخاصين بك.

## ملاحظات

- ملف IPA الناتج لا يحتوي على `_CodeSignature` أو `embedded.mobileprovision`.
- لا ترفع شهادتك أو كلمة مرورها أو ملفات P12/P8 إلى المستودع.
- بعض برامج التوقيع تغيّر Bundle ID تلقائيًا، وبعضها يحتاج أن يطابق ملف التهيئة؛ أدخل Bundle ID المناسب لحالتك عند تشغيل Workflow.
- عند تحديث الكود، شغّل Workflow مرة أخرى لتحصل على IPA جديد غير موقّع.
