#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ============================================================
;  QuickLauncher — панель быстрого запуска с прозрачным фоном
;  Хранение списка: %APPDATA%\QuickLauncher\apps.txt
;  Горячая клавиша: Ctrl+Alt+Space — панель под курсором
; ============================================================

; --- Настройки ---
ConfigDir   := A_AppData "\QuickLauncher"
ConfigFile  := ConfigDir "\apps.txt"
HotkeyStr   := "^!Space"                 ; Ctrl+Alt+Space
PanelW      := 432                       ; ширина панели
PanelH      := 472                       ; высота панели
PanelAlpha  := 228                       ; прозрачность 0..255 (255 = непрозрачно)
TrayTipText := "QuickLauncher`nCtrl+Alt+Space — панель лаунчера"

global Apps := []
global ConfigDir, ConfigFile, HotkeyStr, PanelW, PanelH, PanelAlpha
global PanelGui := "", PanelEdit := "", PanelLV := "", PanelEmpty := "", PanelRows := []

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
    RefreshPanelIfOpen()
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
;  Панель (прозрачное окно, поиск, иконки)
; ============================================================
ShowPanel(*) {
    global PanelGui, PanelW, PanelH, PanelAlpha
    if IsObject(PanelGui) {          ; повторное нажатие хоткея — закрыть
        HidePanel()
        return
    }

    g := Gui("+AlwaysOnTop -Caption +ToolWindow", "QuickLauncher")
    g.BackColor := "14161c"

    g.SetFont("s8 Bold c7d8497", "Segoe UI")
    g.Add("Text", "x16 y16 w400 h14", "БЫСТРЫЙ ЗАПУСК")

    g.SetFont("s10 cffffff", "Segoe UI")
    PanelEdit := g.Add("Edit", "x16 y36 w400 h34 Background1e2129 cffffff")

    PanelLV := g.Add("ListView", "x16 y80 w400 h352 -Hdr", ["Приложение"])
    PanelLV.OnEvent("DoubleClick", (*) => PanelLaunch())
    PanelLV.ModifyCol(1, 368)
    StyleListView(PanelLV.Hwnd)

    PanelEmpty := g.Add("Text", "x16 y80 w400 h352 Center c7d8497", " ")
    PanelEmpty.Visible := false

    g.SetFont("s8 c6b7280", "Segoe UI")
    g.Add("Text", "x16 y444 w400 h14", "Enter — открыть · Esc — закрыть · Del — убрать из списка")

    g.Add("Button", "x0 y0 w1 h1 Default Hide").OnEvent("Click", (*) => PanelLaunch())
    g.OnEvent("Escape", (*) => HidePanel())

    PanelGui := g
    PanelEdit.OnEvent("Change", (*) => RefreshPanelList(PanelEdit.Value))

    ; размещение — по центру монитора, где курсор
    CenterOnCursorMonitor(PanelW, PanelH, &px, &py)
    g.Show("w" PanelW " h" PanelH " x" px " y" py)

    hwnd := g.Hwnd
    ApplyRoundCorners(hwnd, PanelW, PanelH, 16)
    ApplyTransparentBg(hwnd, PanelAlpha)
    DllCall("user32\SendMessageW", "ptr", PanelEdit.Hwnd, "uint", 0x1501, "ptr", 1, "ptr", StrPtr("Поиск приложения…"))

    RefreshPanelList("")
    PanelEdit.Focus()
}

HidePanel() {
    global PanelGui
    if IsObject(PanelGui) {
        try PanelGui.Destroy()
        PanelGui := ""
    }
}

RefreshPanelIfOpen() {
    global PanelGui, PanelEdit
    if IsObject(PanelGui) {
        try RefreshPanelList(PanelEdit.Value)
    }
}

RefreshPanelList(filter := "") {
    global Apps, PanelLV, PanelRows, PanelEmpty
    if !IsObject(PanelLV)
        return
    PanelLV.Delete()
    PanelRows := []
    filter := StrLower(Trim(filter))
    for app in Apps {
        if (filter != "" && !InStr(StrLower(app.name), filter) && !InStr(StrLower(app.path), filter))
            continue
        PanelRows.Push(app)
        row := PanelLV.Add(, app.name)
        try PanelLV.SetIcon(row, app.path)      ; иконка из exe/lnk
    }
    if PanelRows.Length {
        PanelLV.Modify(1, "Select Focus")
        PanelEmpty.Visible := false
    } else {
        PanelEmpty.Value := Apps.Length ? "Ничего не найдено" : "Пока пусто — добавьте приложения`nчерез меню в трее"
        PanelEmpty.Visible := true
    }
}

PanelLaunch(*) {
    global PanelLV, PanelRows
    if !IsObject(PanelLV) || !PanelRows.Length
        return
    row := PanelLV.GetNext()
    app := (row && row <= PanelRows.Length) ? PanelRows[row] : PanelRows[1]
    HidePanel()
    Launch(app)
}

; Enter / Del в списке (WM_KEYDOWN)
PanelKeyHandler(wParam, lParam, msg, hwnd) {
    global PanelGui, PanelLV, PanelRows
    if !IsObject(PanelGui) || !IsObject(PanelLV) || hwnd != PanelLV.Hwnd
        return
    if (wParam = 0x0D) {            ; Enter
        PanelLaunch()
    } else if (wParam = 0x2E) {     ; Del
        row := PanelLV.GetNext()
        if (row && row <= PanelRows.Length)
            ConfirmDelete(PanelRows[row])
    }
}

; закрытие при клике мимо панели (WM_ACTIVATE → неактивно)
PanelActivateHandler(wParam, lParam, msg, hwnd) {
    global PanelGui
    if !IsObject(PanelGui) || hwnd != PanelGui.Hwnd
        return
    if (wParam = 0)                 ; WA_INACTIVE
        HidePanel()
}

CenterOnCursorMonitor(w, h, &x, &y) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    mon := 1
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &L, &T, &R, &B)
        if (mx >= L && mx < R && my >= T && my < B) {
            mon := A_Index
            break
        }
    }
    MonitorGetWorkArea(mon, &L, &T, &R, &B)
    x := L + (R - L - w) // 2
    y := T + (B - T - h) // 2
}

; Скруглённые углы (Win11 — DWM, иначе регион)
ApplyRoundCorners(hwnd, w, h, r := 16) {
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 33, "int*", 2, "uint", 4)
    try {
        rgn := DllCall("gdi32\CreateRoundRectRgn", "int", 0, "int", 0, "int", w, "int", h, "int", r, "int", r, "ptr")
        DllCall("user32\SetWindowRgn", "ptr", hwnd, "ptr", rgn, "int", 1)
    }
}

; Прозрачный фон: acrylic-размытие (Win10/11) + общий уровень прозрачности
ApplyTransparentBg(hwnd, alpha) {
    ; SetWindowCompositionAttribute → ACCENT_ENABLE_ACRYLICBLURBEHIND
    for state in [4, 3] {           ; 4 = acrylic, 3 = blur
        accent := Buffer(16, 0)
        NumPut("int", state, accent, 0)          ; AccentState
        NumPut("int", 2, accent, 4)              ; AccentFlags
        NumPut("uint", 0xE01c1f28, accent, 8)    ; GradientColor 0xAABBGGRR (тёмный синевой)
        if (A_PtrSize = 8) {
            data := Buffer(24, 0)
            NumPut("uint", 19, data, 0)          ; WCA_ACCENT_POLICY
            NumPut("ptr", accent.Ptr, data, 8)
            NumPut("ptr", accent.Size, data, 16)
        } else {
            data := Buffer(12, 0)
            NumPut("uint", 19, data, 0)
            NumPut("ptr", accent.Ptr, data, 4)
            NumPut("ptr", accent.Size, data, 8)
        }
        if DllCall("user32\SetWindowCompositionAttribute", "ptr", hwnd, "ptr", data)
            break
    }
    ; общий уровень прозрачности окна (работает всегда)
    WinSetTransparent(alpha, "ahk_id " hwnd)
}

; Тёмная тема для ListView
StyleListView(hwnd) {
    LVM_SETBKCOLOR := 0x1041
    LVM_SETTEXTCOLOR := 0x1043
    LVM_SETTEXTBKCOLOR := 0x1044
    LVM_SETEXTENDEDLISTVIEWSTYLE := 0x1036
    ex := 0x20 | 0x10000            ; FULLROWSELECT | DOUBLEBUFFER
    DllCall("user32\SendMessageW", "ptr", hwnd, "uint", LVM_SETBKCOLOR, "ptr", 0, "ptr", 0x0014161c)
    DllCall("user32\SendMessageW", "ptr", hwnd, "uint", LVM_SETTEXTCOLOR, "ptr", 0, "ptr", 0x00ffffff)
    DllCall("user32\SendMessageW", "ptr", hwnd, "uint", LVM_SETTEXTBKCOLOR, "ptr", 0, "ptr", 0x0014161c)
    DllCall("user32\SendMessageW", "ptr", hwnd, "uint", LVM_SETEXTENDEDLISTVIEWSTYLE, "ptr", ex, "ptr", ex)
}

; ============================================================
;  Меню (тrey)
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
        try m.SetIcon(mnuName, app.path)
    }
    return taken
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
        3,
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
    tray.Add("Открыть панель…", (*) => ShowPanel())
    tray.Add()
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
try Hotkey(HotkeyStr, (*) => ShowPanel())
OnMessage(0x100, PanelKeyHandler)        ; WM_KEYDOWN
OnMessage(0x0006, PanelActivateHandler)  ; WM_ACTIVATE
