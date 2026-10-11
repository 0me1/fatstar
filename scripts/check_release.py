"""Check the installed release APK's real login screen and Android crashes."""
import subprocess
import time
from pathlib import Path

def adb(*args):
    return subprocess.run(['adb', *args], check=True, capture_output=True, text=True).stdout

adb('logcat', '-c')
adb('install', 'build/app/outputs/flutter-apk/app-release.apk')
adb('shell', 'am', 'start', '-W', '-n', 'com.fatstar.calorie_diary/.MainActivity')
ready = False
for _ in range(15):
    try:
        adb('shell', 'uiautomator', 'dump', '/sdcard/diary-window.xml')
        adb('pull', '/sdcard/diary-window.xml', '/tmp/diary-window.xml')
        screen = Path('/tmp/diary-window.xml').read_text()
        if 'Calorie Diary' in screen and 'Войти' in screen:
            ready = True
            break
    except subprocess.CalledProcessError:
        pass
    time.sleep(1)
assert ready, 'Release APK did not show the working login screen'
crashes = adb('logcat', '-d', '-s', 'AndroidRuntime:E')
Path('build/app/outputs/flutter-apk/android-crashes.txt').write_text(crashes)
assert 'FATAL EXCEPTION' not in crashes, 'Android reported a fatal exception'
assert adb('shell', 'pidof', 'com.fatstar.calorie_diary').strip(), 'Application stopped'
print('Release APK installed and login screen verified')
