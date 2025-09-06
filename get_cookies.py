#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sqlite3
import os
import sys
import tempfile
import shutil
import configparser
from pathlib import Path

# --- НАСТРОЙКИ ---
# Домен, для которого нужно извлечь cookies
TARGET_DOMAIN = 'youtube.com'
# Файл для сохранения cookies по умолчанию
DEFAULT_COOKIES_FILE = str(Path.home() / 'youtube_cookies.txt')
# --- КОНЕЦ НАСТРОЕК ---

def find_firefox_profile_path():
    """Автоматически находит путь к профилю Firefox по умолчанию."""
    
    # Вероятные пути к файлу profiles.ini
    potential_paths = [
        Path.home() / ".mozilla/firefox/profiles.ini",
        Path.home() / "snap/firefox/common/.mozilla/firefox/profiles.ini",
        Path.home() / ".var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini",
    ]
    
    profiles_ini_path = None
    for path in potential_paths:
        if path.exists():
            print(f"[*] Найден файл конфигурации: {path}")
            profiles_ini_path = path
            break
    
    if not profiles_ini_path:
        print("[!] Не удалось найти profiles.ini в стандартных местах.", file=sys.stderr)
        return None

    config = configparser.ConfigParser()
    config.read(profiles_ini_path)

    for section in config.sections():
        # Ищем профиль по умолчанию
        if section.startswith('Profile') and config.has_option(section, 'Default'):
            relative_path = config[section]['Path']
            is_relative = config[section].get('IsRelative', '1')
            if is_relative == '1':
                return profiles_ini_path.parent / relative_path
            else:
                return Path(relative_path)
    
    print("[!] Не удалось найти профиль по умолчанию в profiles.ini.", file=sys.stderr)
    return None

def main():
    """Основная функция скрипта."""
    
    # Можно передать путь к файлу как аргумент командной строки
    output_file = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_COOKIES_FILE
    
    profile_path = find_firefox_profile_path()
    if not profile_path:
        sys.exit(1)
        
    print(f"[*] Используется профиль: {profile_path}")

    cookies_db_path = profile_path / 'cookies.sqlite'
    if not cookies_db_path.exists():
        print(f"[!] Файл cookies.sqlite не найден в профиле: {cookies_db_path}", file=sys.stderr)
        sys.exit(1)

    # Создаем временную директорию для обхода блокировки файла
    temp_dir = tempfile.mkdtemp()
    print(f"[*] Создана временная директория: {temp_dir}")
    
    try:
        # Копируем базу данных и вспомогательные файлы для целостности
        shutil.copy2(cookies_db_path, temp_dir)
        wal_file = cookies_db_path.with_suffix('.sqlite-wal')
        shm_file = cookies_db_path.with_suffix('.sqlite-shm')
        if wal_file.exists():
            shutil.copy2(wal_file, temp_dir)
        if shm_file.exists():
            shutil.copy2(shm_file, temp_dir)

        temp_db_path = Path(temp_dir) / 'cookies.sqlite'
        print(f"[*] База данных cookies скопирована во временный файл: {temp_db_path}")

        conn = sqlite3.connect(f'file:{temp_db_path}?mode=ro', uri=True)
        cursor = conn.cursor()

        # SQL-запрос для извлечения cookies для нужного домена
        query = "SELECT host, path, isSecure, expiry, name, value FROM moz_cookies WHERE host LIKE ?"
        cursor.execute(query, (f'%{TARGET_DOMAIN}',))
        
        print(f"[*] Извлекаю cookies для домена '{TARGET_DOMAIN}'...")
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("# Netscape HTTP Cookie File\n")
            f.write("# Этот файл сгенерирован автоматически. Не редактируйте его.\n\n")
            
            count = 0
            for row in cursor.fetchall():
                host, path, is_secure, expiry, name, value = row
                
                # Преобразование в формат Netscape
                include_subdomains = "TRUE" if host.startswith('.') else "FALSE"
                is_secure_str = "TRUE" if is_secure else "FALSE"
                
                line = f"{host}\t{include_subdomains}\t{path}\t{is_secure_str}\t{expiry}\t{name}\t{value}\n"
                f.write(line)
                count += 1
        
        print(f"[*] ✅ Готово! {count} cookies сохранены в файл: {output_file}")

    except Exception as e:
        print(f"[!] Произошла ошибка: {e}", file=sys.stderr)
    finally:
        # Гарантированно удаляем временную директорию
        shutil.rmtree(temp_dir)
        print(f"[*] Временная директория удалена.")

if __name__ == '__main__':
    main()
