#!/bin/bash
# Проверка наличия ydotool
if ! command -v ydotool &> /dev/null; then
    notify-send "Ошибка" "ydotool не установлен. Пожалуйста, установите его для работы скрипта."
    exit 1
fi

# Проверка wl-clipboard только для GNOME
if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    if ! command -v wl-copy &> /dev/null; then
        notify-send "Ошибка" "Вы используете GNOME, но wl-clipboard не установлен."
        exit 1
    fi
fi
# --- НАСТРОЙКИ ---
CONVERTER_PATH="$HOME/Applications/convert.sh"
SLEEP_TIME=0.01
CLEAN_SED='s/^\(["'\'']?//; s/["'\'']?,\)$//'

# --- 1. ПРИНУДИТЕЛЬНЫЙ СБРОС КЛАВИШ ---
# Гарантируем, что никакие модификаторы не зажаты перед началом
ydotool key 29:0 42:0 56:0 125:0 58:0
sleep $SLEEP_TIME

# --- 2. БЭКАП ТЕКУЩЕГО БУФЕРА ---
# Сохраняем то, что было в буфере до запуска скрипта
if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    CLIP_BACKUP=$(wl-paste)
elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
    CLIP_BACKUP=$(gdbus call --session --dest org.kde.klipper --object-path /klipper --method org.kde.klipper.klipper.getClipboardContents | sed -E "$CLEAN_SED")
fi

# --- 3. ЗАХВАТ ТЕКСТА (Вырезание) ---
# Нажимаем Ctrl+X
ydotool key 29:1 45:1 45:0 29:0
sleep $SLEEP_TIME

# Получаем вырезанный текст из Klipper
if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    CLIP_BACKUP=$(wl-paste)
elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
    NEW_CLIP=$(gdbus call --session --dest org.kde.klipper --object-path /klipper --method org.kde.klipper.klipper.getClipboardContents | sed -E "$CLEAN_SED")
fi

# --- 4. ОБРАБОТКА И ВСТАВКА ---
# --- ЗАЩИТА СПЕЦСИМВОЛОВ \t \r \n (как пар символов) ОТ КОНВЕРТАЦИИ ---
# Заменяем последовательности "\t", "\r", "\n" на временные маркеры,
# которые не будут затронуты при конвертации, а после конвертации восстановим.
text=$(echo "$NEW_CLIP" | sed 's/\\t/\x01/g; s/\\r/\x02/g; s/\\n/\x03/g')
# Де-экранируем (\n, \", \\) — теперь здесь реальные переносы строк
# text=$(printf "%b" "${trimmed//\\\"/\"}")
# text=$trimmed
# echo "text: $text"

# --- 2. КОНВЕРТАЦИЯ (AWK) ---
converted=$(echo -n "$text" | awk '
BEGIN {
    ambig = ".,:;!?/\x27\x22"
    RS="^$"
    target_layout = -1

    # Мапа EN -> RU
    m_en["q"]="й"; m_en["w"]="ц"; m_en["e"]="у"; m_en["r"]="к"; m_en["t"]="е"
    m_en["y"]="н"; m_en["u"]="г"; m_en["i"]="ш"; m_en["o"]="щ"; m_en["p"]="з"
    m_en["["]="х"; m_en["]"]="ъ"; m_en["a"]="ф"; m_en["s"]="ы"; m_en["d"]="в"
    m_en["f"]="а"; m_en["g"]="п"; m_en["h"]="р"; m_en["j"]="о"; m_en["k"]="л"
    m_en["l"]="д"; m_en[";"]="ж"; m_en["\x27"]="э"; m_en["z"]="я"; m_en["x"]="ч"
    m_en["c"]="с"; m_en["v"]="м"; m_en["b"]="и"; m_en["n"]="т"; m_en["m"]="ь"
    m_en[","]="б"; m_en["."]="ю"; m_en["/"]="."; m_en["\x60"]="ё"; m_en["~"]="Ё"
    m_en["!"]="!"; m_en["@"]="\""; m_en["#"]="№"; m_en["$"]=";"; m_en["^"]=":"
    m_en["&"]="?"; m_en["*"]="*"; m_en["|"]="/"
    m_en["Q"]="Й"; m_en["W"]="Ц"; m_en["E"]="У"; m_en["R"]="К"; m_en["T"]="Е"
    m_en["Y"]="Н"; m_en["U"]="Г"; m_en["I"]="Ш"; m_en["O"]="Щ"; m_en["P"]="З"
    m_en["{"]="Х"; m_en["}"]="Ъ"; m_en["A"]="Ф"; m_en["S"]="Ы"; m_en["D"]="В"
    m_en["F"]="А"; m_en["G"]="П"; m_en["H"]="Р"; m_en["J"]="О"; m_en["K"]="Л"
    m_en["L"]="Д"; m_en[":"]="Ж"; m_en["\x22"]="Э"; m_en["Z"]="Я"; m_en["X"]="Ч"
    m_en["C"]="С"; m_en["V"]="М"; m_en["B"]="И"; m_en["N"]="Т"; m_en["M"]="Ь"
    m_en["<"]="Б"; m_en[">"]="Ю"; m_en["?"]=","

    for (en in m_en) { m_ru[m_en[en]] = en }
}
{
    # --- ПРЕДВАРИТЕЛЬНЫЙ АНАЛИЗ (ДЕТЕКТОР ЧИСТОТЫ) ---
    total_ru = 0; total_en = 0
    for(i=1; i<=length($0); i++) {
        c = substr($0, i, 1)
        if (index(ambig, c) == 0) {
            if (c in m_ru) total_ru++
            else if (c in m_en) total_en++
        }
    }

    # Режим "Быстрой инверсии", если текст однородный
    if (total_ru > 0 && total_en == 0) {
        # Только русские буквы -> переводим всё в EN
        target_layout = 0
        # print "Только русские буквы -> переводим всё в EN, target_layout:" target_layout > "/dev/stderr"
        for(i=1; i<=length($0); i++) {
            c = substr($0, i, 1)
            res = res (c in m_ru ? m_ru[c] : c)
        }
        printf "%s|LAYOUT|%s", res, target_layout
        next
    }
    else if (total_en > 0 && total_ru == 0) {
        # Только латиница -> переводим всё в RU
        target_layout = 1
        # print "Только латиница -> переводим всё в RU, target_layout:" target_layout > "/dev/stderr"
        for(i=1; i<=length($0); i++) {
            c = substr($0, i, 1)
            # printf "%s", (c in m_en ? m_en[c] : c)
            res = res (c in m_en ? m_en[c] : c)
        }
        printf "%s|LAYOUT|%s", res, target_layout
        next
    }

    # --- ЕСЛИ ТЕКСТ СМЕШАННЫЙ (ТЕКУЩАЯ ЛОГИКА) ---
    main_layout = (total_ru > total_en) ? "ru" : "en"
    s = $0; final_res = ""

    while (match(s, /[^[:space:]\x01\x02\x03]+/)) {
        final_res = final_res substr(s, 1, RSTART-1)
        token = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)

        t_ru = 0; t_en = 0
        for(k=1; k<=length(token); k++) {
            tc = substr(token, k, 1)
            if (index(ambig, tc) == 0) {
                if (tc in m_ru) t_ru++
                else if (tc in m_en) t_en++
            }
        }

        if (t_ru == 0 && t_en == 0) current_mode = main_layout
        else current_mode = (t_en >= t_ru) ? "en" : "ru"

        # print "Текущее слово:" token "язык:" current_mode > "/dev/stderr"
        for(k=1; k<=length(token); k++) {
            tc = substr(token, k, 1)
            if (index(ambig, tc) > 0) {
                if (current_mode == "en") final_res = final_res (tc in m_en ? m_en[tc] : tc)
                else final_res = final_res (tc in m_ru ? m_ru[tc] : tc)
            } else {
                if (tc in m_ru) final_res = final_res m_ru[tc]
                else if (tc in m_en) final_res = final_res m_en[tc]
                else final_res = final_res tc
            target_layout = (current_mode == "en" ? 0 : 1)
            # print "target_layout:" target_layout > "/dev/stderr"
            }
        }
    }
    printf "%s%s|LAYOUT|%s", final_res, s, target_layout
}')


# echo "converted: $converted"

# Извлекаем всё, что ПОСЛЕ |LAYOUT|
target_layout="${converted##*|LAYOUT|}"
# echo "target_layout: $target_layout"

# Извлекаем всё, что ДО |LAYOUT|
converted_clean="${converted%|LAYOUT|*}"
# --- 3. ЗАПИСЬ В БУФЕР ---
# echo "converted_clean: $converted_clean"
# --- ВОССТАНОВЛЕНИЕ СПЕЦСИМВОЛОВ \t \r \n ---
converted_end=$(echo "$converted_clean" | sed 's/\x01/\\t/g; s/\x02/\\r/g; s/\x03/\\n/g')

# echo "converted_end: $converted_end"
gdbus call --session --dest org.kde.klipper --object-path /klipper \
--method org.kde.klipper.klipper.setClipboardContents "$converted_end" > /dev/null

if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    # Логика для Fedora GNOME
    if [[ "$target_layout" == "0" ]]; then
        gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ru')]"
    else
        gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'ru'), ('xkb', 'us')]"
    fi
elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
    if [[ "$target_layout" == "0" || "$target_layout" == "1" ]]; then
        # echo "Раскаладка переключена! на $target_layout"
        gdbus call --session --dest org.kde.keyboard --object-path /Layouts --method org.kde.KeyboardLayouts.setLayout "$target_layout" > /dev/null
    fi
fi

sleep $SLEEP_TIME

# Вставляем обработанный текст (Ctrl+V)
ydotool key 29:1 47:1 47:0 29:0

# Сразу отпускаем кнопки, чтобы не "залипли"
ydotool key 29:0 47:0


# --- 5. ВОССТАНОВЛЕНИЕ ИСТОРИИ (В фоне) ---
# Возвращаем в буфер то, что там было до вырезания, через полсекунды
(
    sleep $SLEEP_TIME
    if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
        echo "$CLIP_BACKUP" | wl-copy
    elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
        gdbus call --session --dest org.kde.klipper --object-path /klipper --method org.kde.klipper.klipper.setClipboardContents "$CLIP_BACKUP" > /dev/null
    fi
) &

# Финальный сброс всех возможных кнопок
ydotool key 29:0 42:0 56:0 58:0 125:0
