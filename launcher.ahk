#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ============================================================
;  QuickLauncher — лаунчер приложений (тrey + горячая клавиша)
;  Хранение списка: %APPDATA%\QuickLauncher\apps.txt
;  Горячая клавиша: Ctrl+Alt+Space (меню под курсором)
; ============================================================

; --- Настройки ---
ConfigDir  := A_AppData "\QuickLauncher"
ConfigFile := ConfigDir "\apps.txt"
HotkeyStr  := "^!Space"          ; Ctrl+Alt+Space
TrayTipText := "QuickLauncher`nCtrl+Alt+Space — меню приложений"

global Apps := []
global ConfigDir, ConfigFile, HotkeyStr

; ============================================================
;  Загрузка / сохранение списка
; ============================================================
; Формат файла: Название|C:\путь\к\программе   (одна строка = один пункт)
LoadApps() {
    global Apps, ConfigFile
    Apps := []
    if !FileExist(ConfigFile)
        return
    for line in StrSplit(FileRead(ConfigFile, "UTF-8-RAW"), "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        parts := StrSplit(line, "|", , 2)
        if (parts.Length >= 2 && parts[2] != "")
            Apps.Push({ name: parts[1] != "" ? parts[1] : parts[2], path: parts[2] })
    }
}

SaveApps() {
    global Apps, ConfigDir, ConfigFile
    if !DirExist(ConfigDir)
        DirCreate(ConfigDir)
    text := "; QuickLauncher — список приложений (Название|Путь)`r`n"
    for app in Apps
        text .= app.name "|" app.path "`r`n"
    f := FileOpen(ConfigFile, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
}

RemoveApp(app) {
    global Apps
    for i, a in Apps {
        if (a.name = app.name && a.path = app.path) {
            Apps.RemoveAt(i)
            break
        }
    }
    SaveApps()
    RebuildTray()
}

; ============================================================
;  Запуск
; ============================================================
Launch(app, *) {
    if !FileExist(app.path) {
        choice := MsgBox(
            "Файл не найден:`n" app.path "`n`nУдалить этот пункт из лаунчера?",
            "QuickLauncher", "YesNo IconX")
        if (choice = "Yes")
            RemoveApp(app)
        return
    }
    try {
        Run app.path
    } catch as e {
        MsgBox("Не удалось запустить:`n" app.path "`n`n" e.Message, "QuickLauncher", "IconX")
    }
}

; ============================================================
;  Меню приложений (тrey и горячая клавиша)
; ============================================================
; Уникальное имя пункта: в Menu не может быть двух одинаковых имён
UniqueName(name, taken) {
    if (name = "")
        name := "Приложение"
    base := name, n := 2
    while taken.Has(name)
        name := base " (" n++ ")"
    taken[name] := 1
    return name
}

AddAppItems(m, handler) {
    global Apps
    taken := Map()
    for app in Apps {
        mnuName := UniqueName(app.name, taken)
        m.Add(mnuName, handler.Bind(app))
        try m.SetIcon(mnuName, app.path)   ; иконка из exe/lnk, если получилось
    }
    return taken
}

ShowAppsMenu() {
    global Apps
    m := Menu()
    if (Apps.Length = 0) {
        m.Add("(нет приложений — добавьте…)", (*) => ShowAddGui())
    } else {
        AddAppItems(m, Launch)
    }
    m.Add()
    m.Add("Добавить приложение…", (*) => ShowAddGui())
    m.Show()
}

ShowDeleteMenu() {
    global Apps
    if (Apps.Length = 0) {
        MsgBox("Список приложений пуст.", "QuickLauncher", "Iconi")
        return
    }
    m := Menu()
    AddAppItems(m, ConfirmDelete)
    m.Add()
    m.Add("Отмена", (*) => "")
    m.Show()
}

ConfirmDelete(app, *) {
    choice := MsgBox(
        "Удалить «" app.name "» из лаунчера?`n`n" app.path,
        "QuickLauncher", "YesNo IconQuestion")
    if (choice = "Yes")
        RemoveApp(app)
}

; ============================================================
;  Добавление приложения (диалог)
; ============================================================
ShowAddGui() {
    g := Gui("+AlwaysOnTop", "QuickLauncher — добавление")
    g.SetFont("s10")
    g.Add("Text", "xm w420", "Путь к программе, ярлыку (.lnk) или папке:")
    pathEdit := g.Add("Edit", "xm w420 vPath")
    g.Add("Button", "x+6 w90", "Обзор…").OnEvent("Click", (*) => Browse(pathEdit, nameEdit))
    g.Add("Text", "xm w420", "Название в меню (пусто = имя файла):")
    nameEdit := g.Add("Edit", "xm w420 vName")
    g.Add("Button", "xm w100 Default", "Добавить").OnEvent("Click", OnOk)
    g.Add("Button", "x+8 w100", "Отмена").OnEvent("Click", (*) => g.Destroy())

    OnOk(*) {
        path := Trim(pathEdit.Value)
        if (path = "") {
            MsgBox("Укажите путь к приложению.", "QuickLauncher", "Icon!")
            pathEdit.Focus()
            return
        }
        path := StrReplace(path, "/", "\")
        if !FileExist(path) {
            MsgBox("Не найдено:`n" path, "QuickLauncher", "IconX")
            return
        }
        name := Trim(nameEdit.Value)
        if (name = "")
            name := FileNameWithoutExt(path)

        global Apps
        for app in Apps {
            if (StrLower(app.path) = StrLower(path)) {
                MsgBox("Уже добавлено как «" app.name "».", "QuickLauncher", "Iconi")
                return
            }
        }
        Apps.Push({ name: name, path: path })
        SaveApps()
        RebuildTray()
        g.Destroy()
        TrayTip("Добавлено: " name, "QuickLauncher")
    }

    g.Show()
}

Browse(pathEdit, nameEdit) {
    start := ""
    try {
        if (Trim(pathEdit.Value) != "" && InStr(FileExist(Trim(pathEdit.Value)), "D"))
            start := Trim(pathEdit.Value)
    }
    path := FileSelect(
        3,                                                    ; файл обязан существовать
        start,
        "Выберите программу",
        "Программы (*.exe; *.bat; *.cmd; *.com; *.msc; *.lnk);;Все файлы (*.*)")
    if (path = "")
        return
    pathEdit.Value := path
    if (Trim(nameEdit.Value) = "")
        nameEdit.Value := FileNameWithoutExt(path)
}

FileNameWithoutExt(path) {
    SplitPath path, , , , &stem
    return stem != "" ? stem : path
}

; ============================================================
;  Трей
; ============================================================
RebuildTray() {
    global Apps, HotkeyStr
    tray := A_TrayMenu
    tray.Delete()
    if (Apps.Length) {
        AddAppItems(tray, Launch)
        tray.Add()
    } else {
        tray.Add("(нет приложений)", (*) => ShowAddGui())
        tray.Add()
    }
    tray.Add("Добавить приложение…", (*) => ShowAddGui())
    tray.Add("Удалить приложение…", (*) => ShowDeleteMenu())
    tray.Add()
    hkName := "Горячая клавиша: " HotkeyToText(HotkeyStr)
    tray.Add(hkName, (*) => "")
    tray.Disable(hkName)
    tray.Add("Выход", (*) => ExitApp())
}

HotkeyToText(hk) {
    ; порядок важен: сначала «+» (Shift), иначе «+» из «Ctrl+» сработает как Shift
    hk := StrReplace(hk, "+", "Shift+")
    hk := StrReplace(hk, "^", "Ctrl+")
    hk := StrReplace(hk, "!", "Alt+")
    hk := StrReplace(hk, "#", "Win+")
    return hk
}

; ============================================================
;  Запуск лаунчера
; ============================================================
A_IconTip := TrayTipText
LoadApps()
RebuildTray()
try Hotkey(HotkeyStr, (*) => ShowAppsMenu())
