#!/usr/bin/env bash

# Скрипт для быстрой настройки Git и загрузки на GitHub
# Использование: ./setup-git.sh YOUR_GITHUB_USERNAME

set -e

if [[ $# -eq 0 ]]; then
  echo "Использование: ./setup-git.sh YOUR_GITHUB_USERNAME"
  echo "Пример: ./setup-git.sh bglglzd"
  exit 1
fi

GITHUB_USERNAME="$1"
REPO_NAME="vps-sanity-check"

echo "🔧 Настройка Git репозитория..."

# Проверка наличия Git
if ! command -v git &> /dev/null; then
  echo "❌ Git не установлен!"
  echo "Установите Git: https://git-scm.com/download/win"
  exit 1
fi

# Инициализация
echo "📦 Инициализация Git..."
git init

# Добавление файлов
echo "➕ Добавление файлов..."
git add .

# Первый коммит
echo "💾 Создание первого коммита..."
git commit -m "Initial commit: VPS Sanity Check v1.0.0"

# Переименование ветки
echo "🌿 Настройка ветки main..."
git branch -M main

# Добавление remote
echo "🔗 Добавление remote репозитория..."
git remote add origin "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git" || {
  echo "⚠️  Remote уже существует, обновляю URL..."
  git remote set-url origin "https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
}

echo ""
echo "✅ Git репозиторий настроен!"
echo ""
echo "📝 Следующие шаги:"
echo "1. Создайте репозиторий на GitHub: https://github.com/new"
echo "   Название: ${REPO_NAME}"
echo "   НЕ ставьте галочки на инициализацию!"
echo ""
echo "2. Загрузите код:"
echo "   git push -u origin main"
echo ""
echo "⚠️  При необходимости используйте Personal Access Token вместо пароля"

