# Инструкция по загрузке на GitHub

## Шаг 1: Установка Git (если не установлен)

### Windows:
1. Скачайте Git с официального сайта: https://git-scm.com/download/win
2. Установите с настройками по умолчанию
3. Перезапустите терминал/PowerShell

### Проверка установки:
```bash
git --version
```

## Шаг 2: Настройка Git (первый раз)

```bash
git config --global user.name "bglglzd"
git config --global user.email "your-email@example.com"
```

## Шаг 3: Создание репозитория на GitHub

1. Зайдите на https://github.com
2. Нажмите кнопку **"+"** в правом верхнем углу → **"New repository"**
3. Заполните:
   - **Repository name:** `vps-sanity-check`
   - **Description:** `🔐 Minimalistic VPS security sanity checker`
   - **Visibility:** Public (или Private, как хотите)
   - **НЕ** ставьте галочки на "Initialize with README", "Add .gitignore", "Choose a license"
4. Нажмите **"Create repository"**

## Шаг 4: Инициализация Git в проекте

Откройте терминал в папке проекта и выполните:

```bash
# Перейти в папку проекта
cd "C:\Users\bglgl\Desktop\Projects\VPS_SC"

# Инициализировать Git репозиторий
git init

# Добавить все файлы
git add .

# Сделать первый коммит
git commit -m "Initial commit: VPS Sanity Check v1.0.0"

# Переименовать ветку в main (если нужно)
git branch -M main

# Добавить remote репозиторий (замените YOUR_USERNAME на ваш GitHub username)
git remote add origin https://github.com/YOUR_USERNAME/vps-sanity-check.git

# Загрузить на GitHub
git push -u origin main
```

## Шаг 5: Если потребуется авторизация

GitHub больше не поддерживает пароли для HTTPS. Используйте один из вариантов:

### Вариант 1: Personal Access Token (рекомендуется)
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token (classic)
3. Выберите scope: `repo`
4. Скопируйте токен
5. При `git push` используйте токен вместо пароля

### Вариант 2: SSH ключ
```bash
# Генерировать SSH ключ
ssh-keygen -t ed25519 -C "your-email@example.com"

# Скопировать публичный ключ
cat ~/.ssh/id_ed25519.pub

# Добавить ключ в GitHub: Settings → SSH and GPG keys → New SSH key
```

Затем используйте SSH URL:
```bash
git remote set-url origin git@github.com:YOUR_USERNAME/vps-sanity-check.git
```

## Быстрая команда (все в одном)

Если Git уже настроен, выполните:

```bash
cd "C:\Users\bglgl\Desktop\Projects\VPS_SC"
git init
git add .
git commit -m "Initial commit: VPS Sanity Check v1.0.0"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/vps-sanity-check.git
git push -u origin main
```

**Не забудьте заменить `YOUR_USERNAME` на ваш GitHub username!**

## Проверка

После успешной загрузки откройте:
```
https://github.com/YOUR_USERNAME/vps-sanity-check
```

Вы должны увидеть все файлы проекта.

## Дальнейшие обновления

Когда будете вносить изменения:

```bash
git add .
git commit -m "Описание изменений"
git push
```

