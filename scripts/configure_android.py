from pathlib import Path
import xml.etree.ElementTree as ET
android = '{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
p = Path('android/app/src/main/AndroidManifest.xml')
tree = ET.parse(p)
root = tree.getroot()
if not any(x.get(android+'name') == 'android.permission.INTERNET' for x in root.findall('uses-permission')):
    ET.SubElement(root, 'uses-permission', {android+'name': 'android.permission.INTERNET'})
app = root.find('application')
app.set(android+'label', 'Calorie Diary')
app.set(android+'allowBackup', 'false')
app.set(android+'usesCleartextTraffic', '${allowCleartext}')
activity = app.find('activity')
if not any(x.find('data') is not None and x.find('data').get(android+'scheme') == 'com.fatstar.calorie_diary' for x in activity.findall('intent-filter')):
    filt = ET.SubElement(activity, 'intent-filter')
    ET.SubElement(filt, 'action', {android+'name': 'android.intent.action.VIEW'})
    ET.SubElement(filt, 'category', {android+'name': 'android.intent.category.DEFAULT'})
    ET.SubElement(filt, 'category', {android+'name': 'android.intent.category.BROWSABLE'})
    ET.SubElement(filt, 'data', {android+'scheme': 'com.fatstar.calorie_diary', android+'host': 'auth'})
tree.write(p, encoding='unicode', xml_declaration=True)
p = Path('android/app/build.gradle.kts')
s = p.read_text()
if '// Calorie Diary signing' not in s:
    s = s.replace('    buildTypes {', '''    // Calorie Diary signing: release fails without a keystore; no debug fallback.
    signingConfigs {
        create("diaryRelease") {
            val keyPath = System.getenv("DIARY_KEYSTORE_PATH")
            if (keyPath != null) {
                storeFile = file(keyPath)
                storePassword = System.getenv("DIARY_STORE_PASSWORD")
                keyAlias = System.getenv("DIARY_KEY_ALIAS")
                keyPassword = System.getenv("DIARY_KEY_PASSWORD")
            }
        }
    }
    defaultConfig {
        manifestPlaceholders["allowCleartext"] = "false"
    }
    buildTypes {
        debug {
            manifestPlaceholders["allowCleartext"] = "true"
        }''')
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("diaryRelease")')
    p.write_text(s)
