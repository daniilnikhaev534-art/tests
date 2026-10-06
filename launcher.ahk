#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; Глобальный перехват ошибок для стабильности
OnError(GlobalErrorHandler)
GlobalErrorHandler(thrown, mode) {
    try {
        errDir := A_AppData "\QuickLauncher"
        if !DirExist(errDir)
            DirCreate(errDir)
        errLog := errDir "\error.log"
        msg := Format("[{1}] Line {2}: {3}`n{4}`n`n", FormatTime(, "yyyy-MM-dd HH:mm:ss"), thrown.Line, thrown.Message, thrown.Stack)
        FileAppend(msg, errLog, "UTF-8")
    }
    return true
}

; ============================================================
;  QuickLauncher — космический круговой лаунчер «Сатурн»
;  Хранение списка: %APPDATA%\QuickLauncher\apps.txt
;  Горячая клавиша: Ctrl+Alt+Space — вылет Сатурна под курсором
; ============================================================

; --- Настройки ---
ConfigDir    := A_AppData "\QuickLauncher"
ConfigFile   := ConfigDir "\apps.txt"
SettingsFile := ConfigDir "\settings.ini"
HotkeyStr    := "^!Space"                 ; Ctrl+Alt+Space
TrayTipText  := "QuickLauncher — Сатурн`nCtrl+Alt+Space — вызов орбиты"

; --- Глобальные переменные ---
global Apps := []
global ConfigDir, ConfigFile, SettingsFile, HotkeyStr, TrayTipText
global IsModalOpen := false

; Режим космической заставки (Screensaver / Idle)
global ScreensaverEnabled    := true
global ScreensaverTimeoutMin := 3
global ScreensaverBlackout   := true
global IsScreensaverActive   := false
global ScreensaverBgGui      := ""
global ScreensaverInitX      := 0
global ScreensaverInitY      := 0
global ScreensaverStartTime  := 0

; Переменные классической панели
global PanelW := 440, PanelH := 480
global PanelGui := "", PanelEdit := "", PanelLV := "", PanelEmpty := "", PanelRows := [], PanelIL := 0

; Переменные окна «Сатурн» (GDI+)
global RadialW := 760, RadialH := 760
global RadialCX := RadialW // 2, RadialCY := RadialH // 2
global RadialWinX := 0, RadialWinY := 0
global RadialGui := "", RadialHwnd := 0
global RadialHdcScreen := 0, RadialHdcMem := 0, RadialHbm := 0, RadialObm := 0, RadialGraphics := 0
global GdipToken := 0, GdipModule := 0
global FontTitle := 0, FontSub := 0, FontLabel := 0, FontFamily := 0

; Геометрия Сатурна и наклонных 3D-колец
global PI := 3.141592653589793
global PlanetR       := 130              ; Планета Сатурн (диаметр 260px)
global SaturnRingRx  := 295              ; Полуось наклонного кольца Сатурна X
global SaturnRingRy  := 112              ; Полуось наклонного кольца Сатурна Y
global SaturnTiltDeg := -28.0            ; Реалистичный угол наклона колец Сатурна
global AppRingRx     := 250              ; Полуось X орбиты приложений строго по золотому кольцу
global AppRingRy     := 95               ; Полуось Y орбиты приложений строго по золотому кольцу
global NodeR         := 22               ; Радиус круглого узла приложения (диаметр 44px)
global LblW          := 84               ; Базовая ширина плашки названия
global LblH          := 20               ; Высота плашки названия

; Состояние лаунчера «Сатурн»
global RadialIsOpen := false
global AnimState := "closed"             ; "open", "idle", "close", "closed"
global AnimFrame := 0, AnimTotalFrames := 14
global AnimScale := 1.0, AnimAlpha := 255
global OrbitRotation := 0.0              ; Орбитальный поворот приложений по кольцу
global PlanetSpin := 0.0                 ; Непрерывное вращение Сатурна вокруг оси
global HoveredIndex := 0, SelectedIndex := 1, HoveredPlanet := false
global PendingLaunchApp := ""

; Фоновые звёзды
global StarList := [
    { x: 70, y: 120, a: 0x65, r: 1.5 },
    { x: 140, y: 80, a: 0x90, r: 2.0 },
    { x: 230, y: 55, a: 0x50, r: 1.2 },
    { x: 620, y: 85, a: 0x75, r: 1.8 },
    { x: 690, y: 170, a: 0x95, r: 2.2 },
    { x: 710, y: 340, a: 0x50, r: 1.2 },
    { x: 660, y: 600, a: 0x85, r: 1.8 },
    { x: 540, y: 680, a: 0x60, r: 1.5 },
    { x: 180, y: 690, a: 0x90, r: 2.0 },
    { x: 80, y: 610, a: 0x55, r: 1.2 },
    { x: 45, y: 380, a: 0x75, r: 1.6 }
]

; ============================================================
;  Инициализация GDI+
; ============================================================
InitGDIPlus() {
    global GdipModule, GdipToken, FontFamily, FontTitle, FontSub, FontLabel
    if (GdipToken)
        return true

    GdipModule := DllCall("LoadLibrary", "str", "gdiplus.dll", "ptr")
    if !GdipModule
        return false

    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("uint", 1, si, 0)
    token := 0
    status := DllCall("gdiplus\GdiplusStartup", "ptr*", &token, "ptr", si, "ptr", 0)
    if (status != 0)
        return false
    GdipToken := token

    ; Создание крупных, ярких шрифтов Segoe UI Bold
    hFam := 0
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Segoe UI", "ptr", 0, "ptr*", &hFam)
    FontFamily := hFam

    hFTitle := 0, hFSub := 0, hFLabel := 0
    DllCall("gdiplus\GdipCreateFont", "ptr", FontFamily, "float", 14.0, "int", 1, "int", 2, "ptr*", &hFTitle) ; Крупный 14pt Bold
    DllCall("gdiplus\GdipCreateFont", "ptr", FontFamily, "float", 10.5, "int", 1, "int", 2, "ptr*", &hFSub)   ; 10.5pt Bold
    DllCall("gdiplus\GdipCreateFont", "ptr", FontFamily, "float", 11.5, "int", 1, "int", 2, "ptr*", &hFLabel) ; 11.5pt Bold (крупный и яркий)

    FontTitle := hFTitle
    FontSub := hFSub
    FontLabel := hFLabel
    return true
}

ShutdownGDIPlus() {
    global GdipModule, GdipToken, FontFamily, FontTitle, FontSub, FontLabel, Apps
    for app in Apps {
        if (app.HasProp("pBitmap") && app.pBitmap) {
            try DllCall("gdiplus\GdipDisposeImage", "ptr", app.pBitmap)
            app.pBitmap := 0
        }
    }
    DestroyRadialGraphics()
    if FontTitle {
        try DllCall("gdiplus\GdipDeleteFont", "ptr", FontTitle)
        FontTitle := 0
    }
    if FontSub {
        try DllCall("gdiplus\GdipDeleteFont", "ptr", FontSub)
        FontSub := 0
    }
    if FontLabel {
        try DllCall("gdiplus\GdipDeleteFont", "ptr", FontLabel)
        FontLabel := 0
    }
    if FontFamily {
        try DllCall("gdiplus\GdipDeleteFontFamily", "ptr", FontFamily)
        FontFamily := 0
    }
    if GdipToken {
        try DllCall("gdiplus\GdipShutdown", "ptr", GdipToken)
        GdipToken := 0
    }
    if GdipModule {
        try DllCall("FreeLibrary", "ptr", GdipModule)
        GdipModule := 0
    }
}

; ============================================================
;  Утилиты и работа с иконками
; ============================================================
ExpandEnv(str) {
    if !InStr(str, "%")
        return str
    bufSize := DllCall("kernel32\ExpandEnvironmentStringsW", "wstr", str, "ptr", 0, "uint", 0)
    if (bufSize <= 0)
        return str
    buf := Buffer(bufSize * 2)
    DllCall("kernel32\ExpandEnvironmentStringsW", "wstr", str, "ptr", buf, "uint", bufSize)
    return StrGet(buf)
}

GetIconInfo(path, &iconFile, &iconNum) {
    expanded := ExpandEnv(path)
    iconFile := expanded
    iconNum := 1
    if (SubStr(expanded, -4) = ".lnk") {
        try {
            FileGetShortcut(expanded, &target, , , , &scIconFile, &scIconNum)
            if (scIconFile != "") {
                iconFile := ExpandEnv(scIconFile)
                iconNum := scIconNum ? scIconNum : 1
                return
            }
            if (target != "") {
                iconFile := ExpandEnv(target)
                iconNum := 1
                return
            }
        }
    }
}

ExtractGdipBitmap(path) {
    GetIconInfo(path, &iconFile, &iconNum)
    hIcon := 0
    pIconId := 0

    DllCall("user32\PrivateExtractIconsW",
        "wstr", iconFile,
        "int", iconNum - 1,
        "int", 48,
        "int", 48,
        "ptr*", &hIcon,
        "ptr*", &pIconId,
        "uint", 1,
        "uint", 0)

    if (!hIcon && iconFile != path) {
        DllCall("user32\PrivateExtractIconsW",
            "wstr", path,
            "int", 0,
            "int", 48,
            "int", 48,
            "ptr*", &hIcon,
            "ptr*", &pIconId,
            "uint", 1,
            "uint", 0)
    }

    if (!hIcon) {
        DllCall("shell32\ExtractIconExW", "wstr", iconFile, "int", iconNum - 1, "ptr*", &hIcon, "ptr", 0, "uint", 1)
    }
    if (!hIcon) {
        DllCall("shell32\ExtractIconExW", "wstr", A_WinDir "\System32\shell32.dll", "int", 2, "ptr*", &hIcon, "ptr", 0, "uint", 1)
    }
    if (!hIcon)
        return 0

    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromHICON", "ptr", hIcon, "ptr*", &pBitmap)
    DllCall("user32\DestroyIcon", "ptr", hIcon)
    return pBitmap
}

AddIconToIL(il, path) {
    GetIconInfo(path, &iconFile, &iconNum)
    idx := 0
    try idx := IL_Add(il, iconFile, iconNum)
    if (!idx && iconFile != path) {
        try idx := IL_Add(il, path, 1)
    }
    if (!idx) {
        try idx := IL_Add(il, A_WinDir "\System32\shell32.dll", 3)
    }
    return idx ? idx : 1
}

BuildAppResources() {
    global Apps, PanelIL, PanelLV
    InitGDIPlus()
    if PanelIL {
        try IL_Destroy(PanelIL)
        PanelIL := 0
    }
    try PanelIL := IL_Create(Apps.Length ? Apps.Length : 10, 5, 0)

    for app in Apps {
        if PanelIL {
            try app.iconIndex := AddIconToIL(PanelIL, app.path)
        }
        if (app.HasProp("pBitmap") && app.pBitmap) {
            try DllCall("gdiplus\GdipDisposeImage", "ptr", app.pBitmap)
            app.pBitmap := 0
        }
        try app.pBitmap := ExtractGdipBitmap(app.path)
    }

    if (IsObject(PanelLV) && PanelIL) {
        try PanelLV.SetImageList(PanelIL, 1)
    }
}

; ============================================================
;  Загрузка / сохранение списка приложений
; ============================================================
LoadApps() {
    global Apps, ConfigFile
    Apps := []
    if !FileExist(ConfigFile) {
        BuildAppResources()
        return
    }
    for line in StrSplit(FileRead(ConfigFile, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        parts := StrSplit(line, "|", , 2)
        if (parts.Length >= 2 && parts[2] != "")
            Apps.Push({ name: parts[1] != "" ? parts[1] : parts[2], path: parts[2] })
    }
    BuildAppResources()
}

SaveApps() {
    global Apps, ConfigDir, ConfigFile, RadialIsOpen
    try {
        if !DirExist(ConfigDir)
            DirCreate(ConfigDir)
        text := "; QuickLauncher — список приложений (Название|Путь)`r`n"
        for app in Apps
            text .= app.name "|" app.path "`r`n"
        f := FileOpen(ConfigFile, "w", "UTF-8")
        f.Write(text)
        f.Close()
    }
    BuildAppResources()
    RefreshPanelIfOpen()
    if (RadialIsOpen)
        try RenderRadialFrame()
}

LoadSettings() {
    global SettingsFile, ScreensaverEnabled, ScreensaverTimeoutMin, ScreensaverBlackout
    try {
        ScreensaverEnabled    := IniRead(SettingsFile, "Screensaver", "Enabled", "1") = "1"
        ScreensaverTimeoutMin := Integer(IniRead(SettingsFile, "Screensaver", "TimeoutMin", "3"))
        ScreensaverBlackout   := IniRead(SettingsFile, "Screensaver", "Blackout", "1") = "1"
    } catch {
        ScreensaverEnabled    := true
        ScreensaverTimeoutMin := 3
        ScreensaverBlackout   := true
    }
}

SaveSettings() {
    global SettingsFile, ScreensaverEnabled, ScreensaverTimeoutMin, ScreensaverBlackout, ConfigDir
    try {
        if !DirExist(ConfigDir)
            DirCreate(ConfigDir)
        IniWrite(ScreensaverEnabled ? "1" : "0", SettingsFile, "Screensaver", "Enabled")
        IniWrite(String(ScreensaverTimeoutMin), SettingsFile, "Screensaver", "TimeoutMin")
        IniWrite(ScreensaverBlackout ? "1" : "0", SettingsFile, "Screensaver", "Blackout")
    }
}

RemoveApp(app) {
    global Apps, SelectedIndex, HoveredIndex
    if !IsObject(app)
        return
    removed := false
    for i, a in Apps {
        if (a.name = app.name && a.path = app.path) {
            if (a.HasProp("pBitmap") && a.pBitmap) {
                try DllCall("gdiplus\GdipDisposeImage", "ptr", a.pBitmap)
                a.pBitmap := 0
            }
            Apps.RemoveAt(i)
            removed := true
            break
        }
    }
    if (!removed)
        return

    if (SelectedIndex > Apps.Length)
        SelectedIndex := Max(1, Apps.Length)
    HoveredIndex := 0

    SaveApps()
    SafeRebuildTray()
}

SafeRebuildTray() {
    SetTimer(RebuildTray, -60)
}

; ============================================================
;  Запуск приложений
; ============================================================
Launch(app, *) {
    global IsModalOpen
    targetPath := ExpandEnv(app.path)
    if !FileExist(targetPath) {
        IsModalOpen := true
        choice := MsgBox(
            "Файл не найден:`n" app.path "`n`nУдалить этот пункт из лаунчера?",
            "QuickLauncher", "YesNo IconX")
        IsModalOpen := false
        if (choice = "Yes")
            RemoveApp(app)
        return
    }
    try {
        if InStr(FileExist(targetPath), "D") {
            Run('"' targetPath '"')
        } else {
            SplitPath(targetPath, , &dir)
            Run('"' targetPath '"', dir != "" ? dir : "")
        }
    } catch as e {
        IsModalOpen := true
        MsgBox("Не удалось запустить:`n" app.path "`n`n" e.Message, "QuickLauncher", "IconX")
        IsModalOpen := false
    }
}

OpenFileLocation(app, *) {
    path := ExpandEnv(app.path)
    if FileExist(path) {
        try Run('explorer.exe /select,"' path '"')
    }
}

; ============================================================
;  GDI+ Помощники рисования
; ============================================================
GdipCreateSolidBrush(argb) {
    pBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &pBrush)
    return pBrush
}

GdipCreatePen(argb, width) {
    pPen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", width, "int", 2, "ptr*", &pPen)
    return pPen
}

GdipDrawRoundedRect(pG, pBrush, pPen, x, y, w, h, r) {
    pPath := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &pPath)
    d := r * 2
    DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x, "float", y, "float", d, "float", d, "float", 180, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x + w - d, "float", y, "float", d, "float", d, "float", 270, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x + w - d, "float", y + h - d, "float", d, "float", d, "float", 0, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x, "float", y + h - d, "float", d, "float", d, "float", 90, "float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", pPath)
    if (pBrush)
        DllCall("gdiplus\GdipFillPath", "ptr", pG, "ptr", pBrush, "ptr", pPath)
    if (pPen)
        DllCall("gdiplus\GdipDrawPath", "ptr", pG, "ptr", pPen, "ptr", pPath)
    DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
}

GdipDrawText(pG, text, x, y, w, h, font, pBrush, align := 1, lineAlign := 1) {
    hFormat := 0
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr*", &hFormat)
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", hFormat, "int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", hFormat, "int", lineAlign)
    DllCall("gdiplus\GdipSetStringFormatTrimming", "ptr", hFormat, "int", 3)
    DllCall("gdiplus\GdipSetStringFormatFlags", "ptr", hFormat, "int", 0x1000)

    rectF := Buffer(16, 0)
    NumPut("float", x, rectF, 0)
    NumPut("float", y, rectF, 4)
    NumPut("float", w, rectF, 8)
    NumPut("float", h, rectF, 12)

    DllCall("gdiplus\GdipDrawString",
        "ptr", pG, "wstr", text, "int", -1,
        "ptr", font, "ptr", rectF, "ptr", hFormat, "ptr", pBrush)
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", hFormat)
}

; ============================================================
;  Круговой лаунчер «Сатурн» (GDI+)
; ============================================================
CreateRadialGraphics() {
    global RadialW, RadialH, RadialHdcScreen, RadialHdcMem, RadialHbm, RadialObm, RadialGraphics
    if RadialGraphics
        return

    RadialHdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
    RadialHdcMem := DllCall("CreateCompatibleDC", "ptr", RadialHdcScreen, "ptr")

    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0)
    NumPut("int", RadialW, bi, 4)
    NumPut("int", -RadialH, bi, 8)
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    NumPut("uint", 0, bi, 16)

    pBits := 0
    RadialHbm := DllCall("CreateDIBSection", "ptr", RadialHdcScreen, "ptr", bi, "uint", 0, "ptr*", &pBits, "ptr", 0, "uint", 0, "ptr")
    RadialObm := DllCall("SelectObject", "ptr", RadialHdcMem, "ptr", RadialHbm, "ptr")

    pG := 0
    DllCall("gdiplus\GdipCreateFromHDC", "ptr", RadialHdcMem, "ptr*", &pG)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pG, "int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", pG, "int", 4)
    RadialGraphics := pG
}

DestroyRadialGraphics() {
    global RadialHdcScreen, RadialHdcMem, RadialHbm, RadialObm, RadialGraphics
    if RadialGraphics {
        try DllCall("gdiplus\GdipDeleteGraphics", "ptr", RadialGraphics)
        RadialGraphics := 0
    }
    if RadialObm && RadialHdcMem {
        try DllCall("SelectObject", "ptr", RadialHdcMem, "ptr", RadialObm)
        RadialObm := 0
    }
    if RadialHbm {
        try DllCall("DeleteObject", "ptr", RadialHbm)
        RadialHbm := 0
    }
    if RadialHdcMem {
        try DllCall("DeleteDC", "ptr", RadialHdcMem)
        RadialHdcMem := 0
    }
    if RadialHdcScreen {
        try DllCall("ReleaseDC", "ptr", 0, "ptr", RadialHdcScreen)
        RadialHdcScreen := 0
    }
}

ShowRadial(*) {
    global RadialGui, RadialHwnd, RadialIsOpen, AnimState, AnimFrame, AnimTotalFrames
    global AnimScale, AnimAlpha, OrbitRotation, HoveredIndex, SelectedIndex, HoveredPlanet
    global RadialW, RadialH, RadialWinX, RadialWinY, Apps, IsModalOpen

    if (IsModalOpen)
        return

    ; Если уже открыт — мгновенно закрываем
    if (RadialIsOpen) {
        CloseRadial()
        return
    }

    InitGDIPlus()
    CreateRadialGraphics()

    if !RadialGui {
        RadialGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000", "QuickLauncherSaturn")
        RadialHwnd := RadialGui.Hwnd
    }

    ; Позиционирование по центру курсора мыши (с привязкой к монитору)
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)

    mon := GetMonitorAt(mx, my)
    MonitorGetWorkArea(mon, &mL, &mT, &mR, &mB)

    winX := mx - RadialW // 2
    winY := my - RadialH // 2
    if (winX < mL)
        winX := mL
    if (winY < mT)
        winY := mT
    if (winX + RadialW > mR)
        winX := mR - RadialW
    if (winY + RadialH > mB)
        winY := mB - RadialH

    RadialWinX := winX
    RadialWinY := winY

    ; Активируем окно для полноценного перехвата фокуса и кликов
    RadialGui.Show("x" winX " y" winY " w" RadialW " h" RadialH)
    WinActivate("ahk_id " RadialHwnd)

    RadialIsOpen := true
    AnimState := "open"
    AnimFrame := 0
    AnimTotalFrames := 14
    HoveredIndex := 0
    SelectedIndex := Apps.Length ? 1 : 0
    HoveredPlanet := false

    ; Запуск таймеров: анимация и надёжный авто-дисмисс
    SetTimer(RadialAnimTick, 16)
    SetTimer(RadialWatchDismiss, 30)
}

CloseRadial(launchApp := "") {
    global RadialIsOpen, AnimState, AnimFrame, AnimTotalFrames, PendingLaunchApp
    if (!RadialIsOpen && AnimState = "closed")
        return

    PendingLaunchApp := launchApp
    AnimState := "close"
    AnimFrame := 0
    AnimTotalFrames := 8
    SetTimer(RadialAnimTick, 16)
    SetTimer(RadialWatchDismiss, 0)
}

; Мгновенное закрытие без анимации (для вызова модальных окон, удаления и перезагрузок)
CloseRadialImmediate() {
    global RadialIsOpen, AnimState, RadialGui, IsScreensaverActive, ScreensaverBgGui
    RadialIsOpen := false
    AnimState := "closed"
    SetTimer(RadialAnimTick, 0)
    SetTimer(RadialWatchDismiss, 0)
    if (IsScreensaverActive) {
        IsScreensaverActive := false
        SetTimer(CheckScreensaverWakeup, 0)
        if ScreensaverBgGui
            try ScreensaverBgGui.Hide()
    }
    if RadialGui
        try RadialGui.Hide()
}

; Надёжный вотчер: убирает Сатурн при клике мимо, переключении окна, уводе мыши или Esc
RadialWatchDismiss() {
    global RadialIsOpen, RadialHwnd, AnimState, RadialWinX, RadialWinY, RadialW, RadialH, RadialCX, RadialCY
    global IsScreensaverActive

    ; В режиме заставки закрытием управляет отдельный обработчик CheckScreensaverWakeup
    if (IsScreensaverActive)
        return

    if (!RadialIsOpen || AnimState = "close") {
        SetTimer(RadialWatchDismiss, 0)
        return
    }

    ; 1. Если активно другое окно (кликнули на рабочий стол, браузер и т.д.)
    try {
        fg := DllCall("user32\GetForegroundWindow", "ptr")
        if (fg && fg != RadialHwnd) {
            CloseRadial()
            return
        }
    }

    ; 2. Если нажата любая кнопка мыши вне окна
    if (GetKeyState("LButton", "P") || GetKeyState("RButton", "P")) {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&curX, &curY)
        if (curX < RadialWinX || curX > RadialWinX + RadialW || curY < RadialWinY || curY > RadialWinY + RadialH) {
            CloseRadial()
            return
        }
    }

    ; 3. Если нажат Esc
    if GetKeyState("Escape", "P") {
        CloseRadial()
        return
    }

    ; 4. Если мышь уведена далеко за пределы Сатурна (> 390px от центра)
    CoordMode("Mouse", "Screen")
    MouseGetPos(&curX, &curY)
    dx := curX - (RadialWinX + RadialCX)
    dy := curY - (RadialWinY + RadialCY)
    if (Sqrt(dx * dx + dy * dy) > 390) {
        CloseRadial()
        return
    }
}

GetMonitorAt(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &L, &T, &R, &B)
        if (x >= L && x < R && y >= T && y < B)
            return A_Index
    }
    return 1
}

; ============================================================
;  Космическая заставка Сатурна (Screensaver / Idle)
; ============================================================
StartScreensaver() {
    global IsScreensaverActive, ScreensaverBlackout, ScreensaverBgGui
    global ScreensaverInitX, ScreensaverInitY, ScreensaverStartTime
    global RadialIsOpen, RadialW, RadialH, RadialWinX, RadialWinY, RadialGui, RadialHwnd
    global AnimState, AnimFrame, AnimTotalFrames, HoveredIndex, SelectedIndex, HoveredPlanet, Apps

    if (IsScreensaverActive)
        return

    ; Если лаунчер уже был открыт — закрываем перед заставкой
    if (RadialIsOpen)
        CloseRadialImmediate()

    IsScreensaverActive := true
    ScreensaverStartTime := A_TickCount
    CoordMode("Mouse", "Screen")
    MouseGetPos(&ScreensaverInitX, &ScreensaverInitY)

    ; 1. Полноэкранный чёрный космический фон (эффект выключенного экрана)
    if (ScreensaverBlackout) {
        if !ScreensaverBgGui {
            ScreensaverBgGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "SaturnScreensaverBg")
            ScreensaverBgGui.BackColor := "0x04060A"
        }
        ScreensaverBgGui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    }

    ; 2. Вылет Сатурна строго по центру экрана
    InitGDIPlus()
    CreateRadialGraphics()

    if !RadialGui {
        RadialGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000", "QuickLauncherSaturn")
        RadialHwnd := RadialGui.Hwnd
    }

    winX := (A_ScreenWidth - RadialW) // 2
    winY := (A_ScreenHeight - RadialH) // 2
    RadialWinX := winX
    RadialWinY := winY

    RadialGui.Show("x" winX " y" winY " w" RadialW " h" RadialH)
    WinActivate("ahk_id " RadialHwnd)

    RadialIsOpen := true
    AnimState := "open"
    AnimFrame := 0
    AnimTotalFrames := 14
    HoveredIndex := 0
    SelectedIndex := Apps.Length ? 1 : 0
    HoveredPlanet := false

    SetTimer(RadialAnimTick, 16)
    SetTimer(CheckScreensaverWakeup, 80)
}

StopScreensaver() {
    global IsScreensaverActive, ScreensaverBgGui, RadialIsOpen
    if (!IsScreensaverActive)
        return

    IsScreensaverActive := false
    SetTimer(CheckScreensaverWakeup, 0)

    if ScreensaverBgGui {
        try ScreensaverBgGui.Hide()
    }

    if (RadialIsOpen) {
        CloseRadial()
    }
}

CheckIdleScreensaver() {
    global ScreensaverEnabled, ScreensaverTimeoutMin, IsScreensaverActive, RadialIsOpen, IsModalOpen
    if (!ScreensaverEnabled || IsScreensaverActive || RadialIsOpen || IsModalOpen)
        return

    ; A_TimeIdlePhysical считает миллисекунды с последнего физического действия на клавиатуре или мыши
    idleSec := A_TimeIdlePhysical // 1000
    if (idleSec >= ScreensaverTimeoutMin * 60) {
        StartScreensaver()
    }
}

CheckScreensaverWakeup() {
    global IsScreensaverActive, ScreensaverInitX, ScreensaverInitY, ScreensaverStartTime
    if (!IsScreensaverActive) {
        SetTimer(CheckScreensaverWakeup, 0)
        return
    }

    ; Защитная пауза 1.2 сек после старта
    if (A_TickCount - ScreensaverStartTime < 1200)
        return

    ; Физическое движение мыши
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    mouseMoved := (Abs(mx - ScreensaverInitX) > 16 || Abs(my - ScreensaverInitY) > 16)

    ; Нажатие клавиш клавиатуры или кнопок мыши
    inputDetected := (A_TimeIdlePhysical < 250)

    if (mouseMoved || inputDetected) {
        StopScreensaver()
    }
}

RadialAnimTick() {
    global AnimState, AnimFrame, AnimTotalFrames, AnimScale, AnimAlpha, OrbitRotation, PlanetSpin
    global RadialIsOpen, RadialGui, PendingLaunchApp, HoveredIndex, IsScreensaverActive, ScreensaverBgGui

    if (AnimState = "open") {
        AnimFrame++
        progress := AnimFrame / AnimTotalFrames
        if (progress >= 1.0) {
            progress := 1.0
            AnimState := "idle"
            ; Переводим таймер в режим плавного непрерывного вращения Сатурна и орбиты
            SetTimer(RadialAnimTick, 28)
        }
        ; Back-Out пружинящий вылет
        c1 := 1.70158
        c3 := c1 + 1.0
        t := progress - 1.0
        AnimScale := 1.0 + c3 * (t ** 3) + c1 * (t ** 2)
        AnimAlpha := Min(255, Integer(255 * (progress * 1.4)))
        OrbitRotation := (1.0 - progress) * (-0.25)
        RenderRadialFrame()
    } else if (AnimState = "idle") {
        ; Непрерывное вращение Сатурна вокруг оси
        PlanetSpin += 0.007

        ; Непрерывное орбитальное движение приложений по кольцу (пауза при наведении курсора!)
        if (HoveredIndex = 0) {
            OrbitRotation += 0.0016
        }
        RenderRadialFrame()
    } else if (AnimState = "close") {
        AnimFrame++
        progress := AnimFrame / AnimTotalFrames
        if (progress >= 1.0) {
            AnimState := "closed"
            RadialIsOpen := false
            SetTimer(RadialAnimTick, 0)
            if (IsScreensaverActive) {
                IsScreensaverActive := false
                SetTimer(CheckScreensaverWakeup, 0)
                if ScreensaverBgGui
                    try ScreensaverBgGui.Hide()
            }
            if RadialGui
                try RadialGui.Hide()
            if (PendingLaunchApp != "") {
                appToRun := PendingLaunchApp
                PendingLaunchApp := ""
                Launch(appToRun)
            }
            return
        }
        AnimScale := 1.0 - (progress ** 2) * 0.4
        AnimAlpha := Max(0, Integer(255 * (1.0 - progress)))
        RenderRadialFrame()
    }
}

; ------------------------------------------------------------
;  Отрисовка Сатурна: наклонные 3D-кольца, идеально ровные спутники
; ------------------------------------------------------------
RenderRadialFrame() {
    global RadialHwnd, RadialGraphics, RadialHdcScreen, RadialHdcMem
    global RadialW, RadialH, RadialCX, RadialCY
    global PlanetR, SaturnRingRx, SaturnRingRy, SaturnTiltDeg, AppRingRx, AppRingRy, PlanetSpin, NodeR, LblW, LblH, PI, Apps, StarList
    global AnimScale, AnimAlpha, OrbitRotation, HoveredIndex, SelectedIndex, HoveredPlanet
    global FontTitle, FontSub, FontLabel

    if (!RadialGraphics || !RadialHwnd)
        return

    scale := AnimScale
    alphaVal := AnimAlpha
    if (scale <= 0)
        return

    pG := RadialGraphics
    DllCall("gdiplus\GdipGraphicsClear", "ptr", pG, "uint", 0)

    ; 1. Невидимый слой-подложка для кликабельности всей площади
    pBaseBrush := GdipCreateSolidBrush(0x02000000)
    DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pBaseBrush,
        "float", 10, "float", 10, "float", RadialW - 20, "float", RadialH - 20)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBaseBrush)

    ; 2. Фоновые космические звёзды
    for star in StarList {
        starAlpha := Integer((star.a & 0xFF) * (alphaVal / 255.0))
        pStarBrush := GdipCreateSolidBrush((starAlpha << 24) | 0xFFF5DC)
        DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pStarBrush,
            "float", star.x, "float", star.y, "float", star.r * 2, "float", star.r * 2)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pStarBrush)
    }

    curPlanetR := PlanetR * scale
    curSatRx   := SaturnRingRx * scale
    curSatRy   := SaturnRingRy * scale

    ; 3. ЗАДНЯЯ ПОЛОВИНА НАКЛОНЁННЫХ КОЛЕЦ САТУРНА (проходит СЗАДИ планеты, углы 180° - 360°)
    ; MatrixOrderPrepend = 0 обеспечивает строгое центрирование колец на планете (RadialCX, RadialCY)
    DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", pG, "float", RadialCX, "float", RadialCY, "int", 0)
    DllCall("gdiplus\GdipRotateWorldTransform", "ptr", pG, "float", SaturnTiltDeg, "int", 0)

    ; Внутреннее полупрозрачное кольцо C (креповое кольцо)
    pPenC := GdipCreatePen(0x35B58A55, 12 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenC,
        "float", -(curSatRx * 0.68), "float", -(curSatRy * 0.68),
        "float", curSatRx * 1.36, "float", curSatRy * 1.36, "float", 180, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenC)

    ; Главное сияющее кольцо B (золотое сияние сзади)
    pPenGlowB := GdipCreatePen(0x30E0A845, 24 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenGlowB,
        "float", -(curSatRx * 0.85), "float", -(curSatRy * 0.85),
        "float", curSatRx * 1.70, "float", curSatRy * 1.70, "float", 180, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenGlowB)

    pPenB := GdipCreatePen(0xB5FCD34D, 16 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenB,
        "float", -(curSatRx * 0.85), "float", -(curSatRy * 0.85),
        "float", curSatRx * 1.70, "float", curSatRy * 1.70, "float", 180, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenB)

    pPenBCore := GdipCreatePen(0xD0FFFBEB, 4 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenBCore,
        "float", -(curSatRx * 0.85), "float", -(curSatRy * 0.85),
        "float", curSatRx * 1.70, "float", curSatRy * 1.70, "float", 180, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenBCore)

    ; Внешнее кольцо A (сзади, отделено щелью Кассини)
    pPenA := GdipCreatePen(0x80CBA668, 10 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenA,
        "float", -(curSatRx * 0.98), "float", -(curSatRy * 0.98),
        "float", curSatRx * 1.96, "float", curSatRy * 1.96, "float", 180, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenA)

    pPenAEdge := GdipCreatePen(0xA0FDE047, 2.0 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenAEdge,
        "float", -curSatRx, "float", -curSatRy,
        "float", curSatRx * 2, "float", curSatRy * 2, "float", 180, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenAEdge)

    DllCall("gdiplus\GdipResetWorldTransform", "ptr", pG)

    ; 4. ПЛАНЕТА САТУРН (СФЕРА, АТМОСФЕРА, ОБЛАЧНЫЕ ПОЛОСЫ И 3D-ОБЪЁМ)
    atmoPens := []
    atmoPens.Push(GdipCreatePen(0x18F59E0B, 16 * scale))
    atmoPens.Push(GdipCreatePen(0x35FCD34D, 8 * scale))
    atmoPens.Push(GdipCreatePen(0x60FDE047, 2.5 * scale))
    for pen in atmoPens {
        DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pen,
            "float", RadialCX - curPlanetR, "float", RadialCY - curPlanetR,
            "float", curPlanetR * 2, "float", curPlanetR * 2)
        DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    }

    ; Облачные полосы Сатурна в маске сферы (наклонены параллельно кольцам!)
    pPlanetPath := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &pPlanetPath)
    DllCall("gdiplus\GdipAddPathEllipse", "ptr", pPlanetPath,
        "float", RadialCX - curPlanetR, "float", RadialCY - curPlanetR,
        "float", curPlanetR * 2, "float", curPlanetR * 2)
    DllCall("gdiplus\GdipSetClipPath", "ptr", pG, "ptr", pPlanetPath, "int", 0)

    ; Поворот облачных поясов параллельно экватору и кольцам Сатурна
    DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", pG, "float", RadialCX, "float", RadialCY, "int", 0)
    DllCall("gdiplus\GdipRotateWorldTransform", "ptr", pG, "float", SaturnTiltDeg, "int", 0)

    bandColors := [
        0xFF6E4724, ; Северный полюс
        0xFF8F6034, ; Умеренный пояс
        0xFFB5844B, ; Тропический пояс
        0xFFDFA869, ; Золотистый янтарный пояс
        0xFFF5D7A4, ; Яркая экваториальная зона (крем/золото)
        0xFFEDCB92, ; Экватор
        0xFFD09E60, ; Южный тропический пояс
        0xFFAC7840, ; Южный умеренный пояс
        0xFF8A592D, ; Субполярный пояс
        0xFF603A1A  ; Полярный вихрь
    ]
    bandH := (curPlanetR * 2) / bandColors.Length
    for i, col in bandColors {
        pBrush := GdipCreateSolidBrush(col)
        y := -curPlanetR + (i - 1) * bandH
        DllCall("gdiplus\GdipFillRectangle", "ptr", pG, "ptr", pBrush,
            "float", -curPlanetR * 1.5, "float", y,
            "float", curPlanetR * 3, "float", bandH + 1.2 * scale)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    }

    ; Вращающиеся атмосферные вихри и штормовые пояса Сатурна (вращение планеты вокруг оси)
    Loop 5 {
        stormPhase := PlanetSpin + (A_Index - 1) * 1.28
        stormX := curPlanetR * 1.2 * Cos(stormPhase)
        stormY := -curPlanetR * 0.45 + (A_Index - 1) * (bandH * 1.8)
        stormAlpha := Integer(Max(0, Sin(stormPhase)) * 80 * (alphaVal / 255.0))
        if (stormAlpha > 8) {
            stormCol := (stormAlpha << 24) | 0xFFFBE0
            pStorm := GdipCreateSolidBrush(stormCol)
            DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pStorm,
                "float", stormX - 22 * scale, "float", stormY - 5 * scale,
                "float", 44 * scale, "float", 10 * scale)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", pStorm)
        }
    }

    ; Тень от колец на планете (параллельна кольцам вдоль экватора)
    pRingShadow := GdipCreateSolidBrush(0x80050302)
    DllCall("gdiplus\GdipFillRectangle", "ptr", pG, "ptr", pRingShadow,
        "float", -curPlanetR * 1.5, "float", 2 * scale,
        "float", curPlanetR * 3, "float", 12 * scale)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pRingShadow)

    DllCall("gdiplus\GdipResetWorldTransform", "ptr", pG)

    ; 3D объём: подсветка сверху-слева (Солнце) и мягкий сферический терминатор тени снизу-справа
    pSunlight := GdipCreateSolidBrush(0x30FFF8E7)
    DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pSunlight,
        "float", RadialCX - curPlanetR * 0.95, "float", RadialCY - curPlanetR * 0.95,
        "float", curPlanetR * 1.3, "float", curPlanetR * 1.3)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pSunlight)

    pShadowBrush := GdipCreateSolidBrush(0x60060302)
    DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pShadowBrush,
        "float", RadialCX - curPlanetR * 0.4, "float", RadialCY - curPlanetR * 0.35,
        "float", curPlanetR * 1.6, "float", curPlanetR * 1.6)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pShadowBrush)

    pDeepShadow := GdipCreateSolidBrush(0x50020101)
    DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pDeepShadow,
        "float", RadialCX - curPlanetR * 0.1, "float", RadialCY - curPlanetR * 0.05,
        "float", curPlanetR * 1.35, "float", curPlanetR * 1.35)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pDeepShadow)

    DllCall("gdiplus\GdipResetClip", "ptr", pG)
    DllCall("gdiplus\GdipDeletePath", "ptr", pPlanetPath)

    ; Контур планеты
    pPlanetBorder := GdipCreatePen(HoveredPlanet ? 0xFFFFE082 : 0x85F59E0B, 2.0 * scale)
    DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pPlanetBorder,
        "float", RadialCX - curPlanetR, "float", RadialCY - curPlanetR,
        "float", curPlanetR * 2, "float", curPlanetR * 2)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPlanetBorder)

    ; 5. ПЕРЕДНЯЯ ПОЛОВИНА НАКЛОНЁННЫХ КОЛЕЦ САТУРНА (проходит СПЕРЕДИ планеты, углы 0° - 180°)
    ; MatrixOrderPrepend = 0 центрирует кольца ровно по центру (RadialCX, RadialCY)
    DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", pG, "float", RadialCX, "float", RadialCY, "int", 0)
    DllCall("gdiplus\GdipRotateWorldTransform", "ptr", pG, "float", SaturnTiltDeg, "int", 0)

    ; Кольцо C (спереди планеты)
    pPenCFront := GdipCreatePen(0x45B58A55, 12 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenCFront,
        "float", -(curSatRx * 0.68), "float", -(curSatRy * 0.68),
        "float", curSatRx * 1.36, "float", curSatRy * 1.36, "float", 0, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenCFront)

    ; Главное сияющее кольцо B (спереди)
    pPenGlowBFront := GdipCreatePen(0x40E0A845, 24 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenGlowBFront,
        "float", -(curSatRx * 0.85), "float", -(curSatRy * 0.85),
        "float", curSatRx * 1.70, "float", curSatRy * 1.70, "float", 0, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenGlowBFront)

    pPenBFront := GdipCreatePen(0xD5FCD34D, 16 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenBFront,
        "float", -(curSatRx * 0.85), "float", -(curSatRy * 0.85),
        "float", curSatRx * 1.70, "float", curSatRy * 1.70, "float", 0, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenBFront)

    pPenBCoreFront := GdipCreatePen(0xF0FFFBEB, 4 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenBCoreFront,
        "float", -(curSatRx * 0.85), "float", -(curSatRy * 0.85),
        "float", curSatRx * 1.70, "float", curSatRy * 1.70, "float", 0, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenBCoreFront)

    ; Внешнее кольцо A (спереди)
    pPenAFront := GdipCreatePen(0x95CBA668, 10 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenAFront,
        "float", -(curSatRx * 0.98), "float", -(curSatRy * 0.98),
        "float", curSatRx * 1.96, "float", curSatRy * 1.96, "float", 0, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenAFront)

    pPenAEdgeFront := GdipCreatePen(0xC0FDE047, 2.0 * scale)
    DllCall("gdiplus\GdipDrawArc", "ptr", pG, "ptr", pPenAEdgeFront,
        "float", -curSatRx, "float", -curSatRy,
        "float", curSatRx * 2, "float", curSatRy * 2, "float", 0, "float", 180)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenAEdgeFront)

    DllCall("gdiplus\GdipResetWorldTransform", "ptr", pG)

    ; 6. ТОНКИЙ ЗОЛОТИСТЫЙ ТРЕК ОРБИТЫ НА КОЛЬЦАХ САТУРНА
    curAppRx := AppRingRx * scale
    curAppRy := AppRingRy * scale

    DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", pG, "float", RadialCX, "float", RadialCY, "int", 0)
    DllCall("gdiplus\GdipRotateWorldTransform", "ptr", pG, "float", SaturnTiltDeg, "int", 0)
    pPenTrack := GdipCreatePen(0x2DFDE047, 1.4 * scale)
    DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pPenTrack,
        "float", -curAppRx, "float", -curAppRy,
        "float", curAppRx * 2, "float", curAppRy * 2)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPenTrack)
    DllCall("gdiplus\GdipResetWorldTransform", "ptr", pG)

    ; 7. УЗЛЫ-ПРИЛОЖЕНИЯ НА КОЛЬЦАХ И РАДИАЛЬНЫЕ ПЛАШКИ НАЗВАНИЙ
    N := Apps.Length
    activeApp := ""

    tiltRad := SaturnTiltDeg * (PI / 180.0)
    cosTilt := Cos(tiltRad)
    sinTilt := Sin(tiltRad)

    bestFrontY := -999999
    bestFrontIdx := 0

    if (N > 0) {
        for i, app in Apps {
            angle := (2 * PI * (i - 1) / N) - (PI / 2) + OrbitRotation

            x0 := curAppRx * Cos(angle)
            y0 := curAppRy * Sin(angle)

            nx := RadialCX + (x0 * cosTilt - y0 * sinTilt)
            ny := RadialCY + (x0 * sinTilt + y0 * cosTilt)

            ; Плавное исчезновение приложений при заходе ЗА планету Сатурн
            inFront := (y0 >= 0)
            alphaMult := 1.0
            if (!inFront) {
                pDist := Sqrt((nx - RadialCX)**2 + (ny - RadialCY)**2)
                edgeDist := pDist - curPlanetR
                ; Плавное угасание между -15px (полностью скрыто) и +35px (полностью видно)
                fadeStart := -15.0 * scale
                fadeEnd   := 35.0 * scale
                if (edgeDist <= fadeStart) {
                    alphaMult := 0.0
                } else if (edgeDist < fadeEnd) {
                    alphaMult := (edgeDist - fadeStart) / (fadeEnd - fadeStart)
                } else {
                    alphaMult := 1.0
                }
            }

            ; Запоминаем самое переднее видимое приложение для центрального хаба
            if (y0 > bestFrontY && alphaMult > 0.5) {
                bestFrontY := y0
                bestFrontIdx := i
            }

            ; Если приложение полностью скрыто за диском планеты — пропускаем отрисовку!
            if (alphaMult <= 0.02)
                continue

            isHovered := (HoveredIndex = i) || (HoveredIndex = 0 && SelectedIndex = i && alphaMult >= 0.5)
            if (isHovered)
                activeApp := app

            depthScale := inFront ? 1.05 : 0.94
            nodeScale := isHovered ? 1.22 : depthScale
            r := NodeR * scale * nodeScale

            ; Альфа-прозрачность для плавного исчезновения/появления
            effAlpha := Integer(alphaVal * alphaMult)
            nodeAlpha := Integer(0xFF * (effAlpha / 255.0))
            glowAlpha1 := Integer(0x50 * (effAlpha / 255.0))
            glowAlpha2 := Integer(0x90 * (effAlpha / 255.0))
            glowAlphaDef := Integer(0x35 * (effAlpha / 255.0))
            borderAlpha := Integer(0xF5 * (effAlpha / 255.0))

            ; Золотистое сияние вокруг узла на кольце
            if (isHovered) {
                pGlow1 := GdipCreatePen((glowAlpha1 << 24) | 0xFDE047, 10 * scale)
                DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pGlow1,
                    "float", nx - (r + 10 * scale), "float", ny - (r + 10 * scale),
                    "float", (r + 10 * scale) * 2, "float", (r + 10 * scale) * 2)
                DllCall("gdiplus\GdipDeletePen", "ptr", pGlow1)

                pGlow2 := GdipCreatePen((glowAlpha2 << 24) | 0xF59E0B, 5 * scale)
                DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pGlow2,
                    "float", nx - (r + 5 * scale), "float", ny - (r + 5 * scale),
                    "float", (r + 5 * scale) * 2, "float", (r + 5 * scale) * 2)
                DllCall("gdiplus\GdipDeletePen", "ptr", pGlow2)
            } else {
                pGlow := GdipCreatePen((glowAlphaDef << 24) | 0xF59E0B, 4.0 * scale)
                DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pGlow,
                    "float", nx - (r + 3 * scale), "float", ny - (r + 3 * scale),
                    "float", (r + 3 * scale) * 2, "float", (r + 3 * scale) * 2)
                DllCall("gdiplus\GdipDeletePen", "ptr", pGlow)
            }

            ; Подложка узла на кольце
            nodeBgColor := isHovered ? ((nodeAlpha << 24) | 0x261C30) : ((nodeAlpha << 24) | 0x140F1A)
            pNodeBg := GdipCreateSolidBrush(nodeBgColor)
            DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pNodeBg,
                "float", nx - r, "float", ny - r, "float", r * 2, "float", r * 2)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", pNodeBg)

            ; Золотистый контур спутника
            borderCol := isHovered ? ((borderAlpha << 24) | 0xFFF0A0) : ((borderAlpha << 24) | 0xF59E0B)
            borderW   := isHovered ? 2.8 * scale : 1.8 * scale
            pNodeBorder := GdipCreatePen(borderCol, borderW)
            DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pNodeBorder,
                "float", nx - r, "float", ny - r, "float", r * 2, "float", r * 2)
            DllCall("gdiplus\GdipDeletePen", "ptr", pNodeBorder)

            ; Иконка приложения (с полупрозрачностью при угасании)
            if (app.HasProp("pBitmap") && app.pBitmap) {
                icoSize := (isHovered ? 34 : 30) * scale * (inFront ? 1.0 : 0.94)
                if (alphaMult >= 0.95) {
                    DllCall("gdiplus\GdipDrawImageRectRect", "ptr", pG, "ptr", app.pBitmap,
                        "float", nx - icoSize / 2, "float", ny - icoSize / 2, "float", icoSize, "float", icoSize,
                        "float", 0, "float", 0, "float", 48, "float", 48,
                        "int", 2, "ptr", 0, "ptr", 0, "ptr", 0)
                } else {
                    ; Плавное угасание иконки через ColorMatrix
                    cm := Buffer(100, 0)
                    NumPut("float", 1.0, cm, 0)
                    NumPut("float", 1.0, cm, 24)
                    NumPut("float", 1.0, cm, 48)
                    NumPut("float", effAlpha / 255.0, cm, 72)
                    NumPut("float", 1.0, cm, 96)
                    pAttr := 0
                    DllCall("gdiplus\GdipCreateImageAttributes", "ptr*", &pAttr)
                    DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "ptr", pAttr, "int", 0, "int", 1, "ptr", cm, "ptr", 0, "int", 0)
                    DllCall("gdiplus\GdipDrawImageRectRect", "ptr", pG, "ptr", app.pBitmap,
                        "float", nx - icoSize / 2, "float", ny - icoSize / 2, "float", icoSize, "float", icoSize,
                        "float", 0, "float", 0, "float", 48, "float", 48,
                        "int", 2, "ptr", pAttr, "ptr", 0, "ptr", 0)
                    DllCall("gdiplus\GdipDisposeImageAttributes", "ptr", pAttr)
                }
            }

            ; Радиальное смещение плашки наружу от центра планеты
            cdx := nx - RadialCX
            cdy := ny - RadialCY
            cdist := Sqrt(cdx * cdx + cdy * cdy)
            ux := cdist > 0 ? (cdx / cdist) : 0
            uy := cdist > 0 ? (cdy / cdist) : 1

            labelOffset := r + (isHovered ? 16 : 13) * scale
            lx := nx + ux * labelOffset
            ly := ny + uy * labelOffset

            curLblW := (isHovered ? 100 : 86) * scale
            curLblH := (isHovered ? 23 : 19) * scale
            lblX := lx - curLblW / 2
            lblY := ly - curLblH / 2

            pillBgAlpha := Integer(0xEE * (effAlpha / 255.0))
            pillBorderAlpha := Integer(0x95 * (effAlpha / 255.0))
            pillBg     := isHovered ? ((pillBgAlpha << 24) | 0x261838) : ((pillBgAlpha << 24) | 0x120C18)
            pillBorder := isHovered ? ((borderAlpha << 24) | 0xFFF0A0) : ((pillBorderAlpha << 24) | 0xF59E0B)
            pPillBrush := GdipCreateSolidBrush(pillBg)
            pPillPen   := GdipCreatePen(pillBorder, (isHovered ? 2.0 : 1.4) * scale)
            GdipDrawRoundedRect(pG, pPillBrush, pPillPen, lblX, lblY, curLblW, curLblH, 6 * scale)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", pPillBrush)
            DllCall("gdiplus\GdipDeletePen", "ptr", pPillPen)

            pTextBrush := GdipCreateSolidBrush((nodeAlpha << 24) | 0xFFFFFF)
            GdipDrawText(pG, app.name, lblX + 3 * scale, lblY + 1 * scale, curLblW - 6 * scale, curLblH, FontLabel, pTextBrush, 1, 1)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", pTextBrush)
        }
    }

    ; Если выбранное приложение зашло за планету и мы не наводим мышь — показываем ближайшее переднее
    if (activeApp = "" && bestFrontIdx > 0 && HoveredIndex = 0) {
        SelectedIndex := bestFrontIdx
        activeApp := Apps[bestFrontIdx]
    }

    ; 8. ЦЕНТР САТУРНА: КРУПНАЯ ИНФОРМАЦИЯ И ПОДСКАЗКИ
    if (activeApp != "") {
        pHubGlow := GdipCreateSolidBrush(0xCC140E1C)
        DllCall("gdiplus\GdipFillEllipse", "ptr", pG, "ptr", pHubGlow,
            "float", RadialCX - 62 * scale, "float", RadialCY - 54 * scale,
            "float", 124 * scale, "float", 108 * scale)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pHubGlow)

        pHubBorder := GdipCreatePen(0xFFFCD34D, 1.8 * scale)
        DllCall("gdiplus\GdipDrawEllipse", "ptr", pG, "ptr", pHubBorder,
            "float", RadialCX - 62 * scale, "float", RadialCY - 54 * scale,
            "float", 124 * scale, "float", 108 * scale)
        DllCall("gdiplus\GdipDeletePen", "ptr", pHubBorder)

        ; Крупная иконка в центре
        if (activeApp.HasProp("pBitmap") && activeApp.pBitmap) {
            cIcoSize := 42 * scale
            DllCall("gdiplus\GdipDrawImageRectRect", "ptr", pG, "ptr", activeApp.pBitmap,
                "float", RadialCX - cIcoSize / 2, "float", RadialCY - 44 * scale, "float", cIcoSize, "float", cIcoSize,
                "float", 0, "float", 0, "float", 48, "float", 48,
                "int", 2, "ptr", 0, "ptr", 0, "ptr", 0)
        }

        ; Крупное яркое название
        pTitleBrush := GdipCreateSolidBrush(0xFFFFFFFF)
        GdipDrawText(pG, activeApp.name, RadialCX - 60 * scale, RadialCY + 5 * scale, 120 * scale, 22 * scale, FontTitle, pTitleBrush, 1, 1)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pTitleBrush)

        ; Яркая подсказка запуска
        pSubBrush := GdipCreateSolidBrush(0xFFFDE047)
        GdipDrawText(pG, "Клик — запуск", RadialCX - 60 * scale, RadialCY + 28 * scale, 120 * scale, 18 * scale, FontSub, pSubBrush, 1, 1)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pSubBrush)
    } else {
        ; Эмблема Сатурна
        pTitleBrush := GdipCreateSolidBrush(0xFFFDE047)
        GdipDrawText(pG, "САТУРН", RadialCX - 60 * scale, RadialCY - 20 * scale, 120 * scale, 24 * scale, FontTitle, pTitleBrush, 1, 1)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pTitleBrush)

        pSubBrush := GdipCreateSolidBrush(0xFFFFFBEB)
        GdipDrawText(pG, N ? "Орбита приложений" : "Нет программ", RadialCX - 60 * scale, RadialCY + 5 * scale, 120 * scale, 18 * scale, FontSub, pSubBrush, 1, 1)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pSubBrush)

        pCloseBrush := GdipCreateSolidBrush(0xFFD4A86A)
        GdipDrawText(pG, "Esc — закрыть", RadialCX - 60 * scale, RadialCY + 26 * scale, 120 * scale, 16 * scale, FontSub, pCloseBrush, 1, 1)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pCloseBrush)
    }

    ; 9. Применение кадра через UpdateLayeredWindow
    blend := Buffer(4, 0)
    NumPut("uchar", 0, blend, 0)
    NumPut("uchar", 0, blend, 1)
    NumPut("uchar", alphaVal, blend, 2)
    NumPut("uchar", 1, blend, 3)

    ptSrc := Buffer(8, 0)
    ptDst := Buffer(8, 0)
    szDst := Buffer(8, 0)
    NumPut("int", RadialW, szDst, 0)
    NumPut("int", RadialH, szDst, 4)

    DllCall("UpdateLayeredWindow",
        "ptr", RadialHwnd,
        "ptr", RadialHdcScreen,
        "ptr", 0,
        "ptr", szDst,
        "ptr", RadialHdcMem,
        "ptr", ptSrc,
        "uint", 0,
        "ptr", blend,
        "uint", 2)
}

; ============================================================
;  Обработка мыши и клавиатуры для Сатурна
; ============================================================
RadialHitTest(mx, my, &hitType, &hitIndex) {
    global RadialCX, RadialCY, AppRingRx, AppRingRy, SaturnTiltDeg, NodeR, LblW, LblH, PI, Apps, OrbitRotation, AnimScale, PlanetR

    hitType := "none"
    hitIndex := 0

    scale := AnimScale > 0 ? AnimScale : 1.0
    curPlanetR := PlanetR * scale

    dx := mx - RadialCX
    dy := my - RadialCY
    distCenter := Sqrt(dx * dx + dy * dy)

    ; Клик по центральному ядру запускает выбранное приложение
    if (distCenter <= 62 * scale) {
        hitType := "center"
        return
    }

    N := Apps.Length
    if (N = 0)
        return

    tiltRad := SaturnTiltDeg * (PI / 180.0)
    cosT := Cos(tiltRad)
    sinT := Sin(tiltRad)
    curAppRx := AppRingRx * scale
    curAppRy := AppRingRy * scale

    Loop N {
        i := A_Index
        angle := (2 * PI * (i - 1) / N) - (PI / 2) + OrbitRotation

        x0 := curAppRx * Cos(angle)
        y0 := curAppRy * Sin(angle)

        nx := RadialCX + (x0 * cosT - y0 * sinT)
        ny := RadialCY + (x0 * sinT + y0 * cosT)

        ; Проверка скрытия за планетой: скрытые приложения нельзя кликнуть
        inFront := (y0 >= 0)
        alphaMult := 1.0
        if (!inFront) {
            pDist := Sqrt((nx - RadialCX)**2 + (ny - RadialCY)**2)
            edgeDist := pDist - curPlanetR
            fadeStart := -15.0 * scale
            fadeEnd   := 35.0 * scale
            if (edgeDist <= fadeStart) {
                alphaMult := 0.0
            } else if (edgeDist < fadeEnd) {
                alphaMult := (edgeDist - fadeStart) / (fadeEnd - fadeStart)
            }
        }

        if (alphaMult < 0.25)
            continue ; Узел скрыт за планетой

        nodeScale := inFront ? 1.05 : 0.94
        r := NodeR * scale * nodeScale

        ndx := mx - nx
        ndy := my - ny
        nodeDist := Sqrt(ndx * ndx + ndy * ndy)

        if (nodeDist <= r + 8) {
            hitType := "node"
            hitIndex := i
            return
        }

        cdx := nx - RadialCX
        cdy := ny - RadialCY
        cdist := Sqrt(cdx * cdx + cdy * cdy)
        ux := cdist > 0 ? (cdx / cdist) : 0
        uy := cdist > 0 ? (cdy / cdist) : 1

        offset := r + 14 * scale
        lx := nx + ux * offset
        ly := ny + uy * offset

        curW := (LblW + 10) * scale
        curH := (LblH + 6) * scale
        if (mx >= lx - curW / 2 && mx <= lx + curW / 2 && my >= ly - curH / 2 && my <= ly + curH / 2) {
            hitType := "node"
            hitIndex := i
            return
        }
    }
}

RadialMouseMove(wParam, lParam, msg, hwnd) {
    global RadialHwnd, RadialIsOpen, HoveredIndex, HoveredPlanet, SelectedIndex

    if (!RadialIsOpen || hwnd != RadialHwnd)
        return

    mx := lParam & 0xFFFF
    my := (lParam >> 16) & 0xFFFF
    if (mx > 0x7FFF)
        mx -= 0x10000
    if (my > 0x7FFF)
        my -= 0x10000

    RadialHitTest(mx, my, &hitType, &hitIndex)

    oldHovIdx := HoveredIndex
    oldHovPlanet := HoveredPlanet

    if (hitType = "node") {
        HoveredIndex := hitIndex
        SelectedIndex := hitIndex
        HoveredPlanet := false
    } else if (hitType = "center") {
        HoveredIndex := 0
        HoveredPlanet := true
    } else {
        HoveredIndex := 0
        HoveredPlanet := false
    }

    if (HoveredIndex != oldHovIdx || HoveredPlanet != oldHovPlanet) {
        RenderRadialFrame()
    }
}

RadialLButtonUp(wParam, lParam, msg, hwnd) {
    global RadialHwnd, RadialIsOpen, Apps, SelectedIndex

    if (!RadialIsOpen || hwnd != RadialHwnd)
        return

    mx := lParam & 0xFFFF
    my := (lParam >> 16) & 0xFFFF
    if (mx > 0x7FFF)
        mx -= 0x10000
    if (my > 0x7FFF)
        my -= 0x10000

    RadialHitTest(mx, my, &hitType, &hitIndex)

    if (hitType = "node" && hitIndex >= 1 && hitIndex <= Apps.Length) {
        CloseRadial(Apps[hitIndex])
    } else if (hitType = "center" && SelectedIndex >= 1 && SelectedIndex <= Apps.Length) {
        CloseRadial(Apps[SelectedIndex])
    } else {
        CloseRadial()
    }
}

RadialRButtonUp(wParam, lParam, msg, hwnd) {
    global RadialHwnd, RadialIsOpen, Apps, IsModalOpen

    if (!RadialIsOpen || hwnd != RadialHwnd)
        return

    mx := lParam & 0xFFFF
    my := (lParam >> 16) & 0xFFFF
    if (mx > 0x7FFF)
        mx -= 0x10000
    if (my > 0x7FFF)
        my -= 0x10000

    RadialHitTest(mx, my, &hitType, &hitIndex)

    if (hitType = "node" && hitIndex >= 1 && hitIndex <= Apps.Length) {
        app := Apps[hitIndex]
        IsModalOpen := true
        m := Menu()
        m.Add("Запустить: " app.name, (*) => (CloseRadialImmediate(), Launch(app)))
        m.Add("Открыть папку с файлом", (*) => OpenFileLocation(app))
        m.Add()
        m.Add("Удалить из списка", (*) => (CloseRadialImmediate(), ConfirmDelete(app)))
        m.Show()
        IsModalOpen := false
    } else {
        CloseRadial()
    }
}

; ------------------------------------------------------------
;  Вращение колёсиком мыши: переключение приложений по кругу
; ------------------------------------------------------------
RadialMouseWheel(wParam, lParam, msg, hwnd) {
    global RadialHwnd, RadialIsOpen, OrbitRotation, Apps, SelectedIndex, HoveredIndex, PI

    if (!RadialIsOpen)
        return

    N := Apps.Length
    if (N = 0)
        return

    delta := (wParam >> 16) & 0xFFFF
    if (delta > 0x7FFF)
        delta -= 0x10000

    step := (2 * PI / N)

    if (delta > 0) {
        SelectedIndex := (SelectedIndex >= N) ? 1 : SelectedIndex + 1
        OrbitRotation -= step
    } else {
        SelectedIndex := (SelectedIndex <= 1) ? N : SelectedIndex - 1
        OrbitRotation += step
    }

    HoveredIndex := SelectedIndex
    RenderRadialFrame()
    return 0
}

RadialKeyHandler(wParam, lParam, msg, hwnd) {
    global RadialHwnd, RadialIsOpen, Apps, SelectedIndex, HoveredIndex, OrbitRotation, PI, IsModalOpen
    global PanelGui

    if (IsModalOpen)
        return

    if IsObject(PanelGui) {
        PanelKeyHandler(wParam, lParam, msg, hwnd)
        return
    }

    if (!RadialIsOpen)
        return

    N := Apps.Length
    step := N ? (2 * PI / N) : 0

    if (wParam = 0x1B) {            ; Esc
        CloseRadial()
        return 0
    }

    if (wParam = 0x0D || wParam = 0x20) { ; Enter или Space
        idx := HoveredIndex ? HoveredIndex : SelectedIndex
        if (idx >= 1 && idx <= N)
            CloseRadial(Apps[idx])
        return 0
    }

    if (wParam = 0x27 || wParam = 0x28) { ; Вправо / вниз
        if (N > 0) {
            SelectedIndex := (SelectedIndex >= N) ? 1 : SelectedIndex + 1
            HoveredIndex := SelectedIndex
            OrbitRotation -= step
            RenderRadialFrame()
        }
        return 0
    }

    if (wParam = 0x25 || wParam = 0x26) { ; Влево / вверх
        if (N > 0) {
            SelectedIndex := (SelectedIndex <= 1) ? N : SelectedIndex - 1
            HoveredIndex := SelectedIndex
            OrbitRotation += step
            RenderRadialFrame()
        }
        return 0
    }

    if (wParam = 0x2E) {            ; Del
        idx := HoveredIndex ? HoveredIndex : SelectedIndex
        if (idx >= 1 && idx <= N) {
            app := Apps[idx]
            CloseRadialImmediate()
            ConfirmDelete(app)
        }
        return 0
    }

    if (wParam >= 0x31 && wParam <= 0x39) { ; Цифры 1..9
        digit := wParam - 0x30
        if (digit <= N) {
            CloseRadial(Apps[digit])
            return 0
        }
    }
}

RadialActivateHandler(wParam, lParam, msg, hwnd) {
    global RadialHwnd, RadialIsOpen, IsModalOpen, PanelGui

    if (IsModalOpen)
        return

    if IsObject(PanelGui) {
        PanelActivateHandler(wParam, lParam, msg, hwnd)
        return
    }

    if (RadialIsOpen && hwnd = RadialHwnd && (wParam & 0xFFFF) = 0) {
        CloseRadial()
    }
}

; ============================================================
;  Классическая панель (поиск, фильтрация, список)
; ============================================================
ShowClassicPanel(*) {
    global PanelGui, PanelW, PanelH, PanelEdit, PanelLV, PanelEmpty, PanelIL
    if IsObject(PanelGui) {
        HidePanel()
        return
    }
    if (RadialIsOpen)
        CloseRadial()

    g := Gui("+AlwaysOnTop -Caption +ToolWindow", "QuickLauncher")
    g.BackColor := "161922"

    g.SetFont("s9 Bold c8b9bb4", "Segoe UI")
    g.Add("Text", "x18 y14 w404 h16", "БЫСТРЫЙ ПОИСК")

    g.SetFont("s11 cffffff", "Segoe UI")
    PanelEdit := g.Add("Edit", "x16 y34 w408 h34 Background222734 cffffff -E0x200")

    g.SetFont("s10 cffffff", "Segoe UI")
    PanelLV := g.Add("ListView", "x16 y76 w408 h360 -Hdr -Multi Background161922 cffffff -E0x200 +LV0x10020", ["Приложение"])
    if (PanelIL)
        PanelLV.SetImageList(PanelIL, 1)
    PanelLV.OnEvent("DoubleClick", (*) => PanelLaunch())
    PanelLV.OnEvent("ContextMenu", PanelContextMenu)
    PanelLV.ModifyCol(1, 404)
    StyleListView(PanelLV.Hwnd)

    g.SetFont("s10 c7d8597", "Segoe UI")
    PanelEmpty := g.Add("Text", "x16 y76 w408 h360 Center Background161922", " ")
    PanelEmpty.Visible := false

    g.SetFont("s8 c7d8597", "Segoe UI")
    g.Add("Text", "x18 y450 w404 h16", "Enter — запуск · Esc — закрыть · Del — убрать · ↑ ↓ — выбор")

    goBtn := g.Add("Button", "x-100 y-100 w1 h1 Default -Tabstop")
    goBtn.OnEvent("Click", (*) => PanelLaunch())
    g.OnEvent("Escape", (*) => HidePanel())

    PanelGui := g
    PanelEdit.OnEvent("Change", (*) => RefreshPanelList(PanelEdit.Value))

    CenterOnCursorMonitor(PanelW, PanelH, &px, &py)
    g.Show("w" PanelW " h" PanelH " x" px " y" py)

    hwnd := g.Hwnd
    ApplyRoundCorners(hwnd, 16)
    StyleListView(PanelLV.Hwnd)

    DllCall("user32\SendMessageW", "ptr", PanelEdit.Hwnd, "uint", 0x1501, "ptr", 1, "ptr", StrPtr("Поиск приложения…"))
    DllCall("user32\SendMessageW", "ptr", PanelEdit.Hwnd, "uint", 0x00D3, "ptr", 1 | 2, "ptr", 10 | (10 << 16))

    RefreshPanelList("")
    PanelEdit.Focus()
}

HidePanel() {
    global PanelGui, PanelEdit, PanelLV, PanelEmpty, PanelRows
    if IsObject(PanelGui) {
        p := PanelGui
        PanelGui := ""
        PanelEdit := ""
        PanelLV := ""
        PanelEmpty := ""
        PanelRows := []
        try p.Destroy()
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
    PanelLV.Opt("-Redraw")
    PanelLV.Delete()
    PanelRows := []
    filter := StrLower(Trim(filter))
    for app in Apps {
        if (filter != "" && !InStr(StrLower(app.name), filter) && !InStr(StrLower(app.path), filter))
            continue
        PanelRows.Push(app)
        iconIdx := app.HasProp("iconIndex") ? app.iconIndex : 1
        PanelLV.Add("Icon" . iconIdx, app.name)
    }
    if PanelRows.Length {
        PanelLV.Modify(1, "Select Focus")
        PanelLV.Visible := true
        PanelEmpty.Visible := false
    } else {
        PanelLV.Visible := false
        PanelEmpty.Value := Apps.Length ? "Ничего не найдено" : "Пока пусто — добавьте приложения`nчерез меню в трее"
        PanelEmpty.Visible := true
    }
    PanelLV.Opt("+Redraw")
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

PanelContextMenu(ctrl, item, isRightClick, x, y) {
    global PanelRows, IsModalOpen
    if (!item || item > PanelRows.Length)
        return
    app := PanelRows[item]
    IsModalOpen := true
    m := Menu()
    m.Add("Запустить: " app.name, (*) => (HidePanel(), Launch(app)))
    m.Add("Открыть папку с файлом", (*) => OpenFileLocation(app))
    m.Add()
    m.Add("Удалить из списка", (*) => ConfirmDelete(app))
    m.Show()
    IsModalOpen := false
}

PanelKeyHandler(wParam, lParam, msg, hwnd) {
    global PanelGui, PanelLV, PanelEdit, PanelRows, IsModalOpen
    if !IsObject(PanelGui) || !IsObject(PanelLV) || IsModalOpen
        return

    try {
        if (hwnd != PanelLV.Hwnd && hwnd != PanelEdit.Hwnd && hwnd != PanelGui.Hwnd)
            return
    } catch {
        return
    }

    if (wParam = 0x28) {
        if (PanelRows.Length > 0) {
            row := PanelLV.GetNext()
            nextRow := (row && row < PanelRows.Length) ? row + 1 : (row ? row : 1)
            PanelLV.Modify(0, "-Select")
            PanelLV.Modify(nextRow, "Select Focus Vis")
        }
        return 0
    }

    if (wParam = 0x26) {
        if (PanelRows.Length > 0) {
            row := PanelLV.GetNext()
            prevRow := (row && row > 1) ? row - 1 : 1
            PanelLV.Modify(0, "-Select")
            PanelLV.Modify(prevRow, "Select Focus Vis")
        }
        return 0
    }

    if (wParam = 0x0D) {
        PanelLaunch()
        return 0
    }

    if (wParam = 0x2E) {
        if (hwnd = PanelLV.Hwnd || GetKeyState("Shift", "P")) {
            row := PanelLV.GetNext()
            if (row && row <= PanelRows.Length)
                ConfirmDelete(PanelRows[row])
            return 0
        }
    }
}

PanelActivateHandler(wParam, lParam, msg, hwnd) {
    global PanelGui, IsModalOpen
    if !IsObject(PanelGui) || IsModalOpen
        return
    try {
        if (hwnd = PanelGui.Hwnd && (wParam & 0xFFFF) = 0)
            HidePanel()
    }
}

CenterOnCursorMonitor(w, h, &x, &y) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    mon := GetMonitorAt(mx, my)
    MonitorGetWorkArea(mon, &L, &T, &R, &B)
    x := L + (R - L - w) // 2
    y := T + (B - T - h) // 2
}

ApplyRoundCorners(hwnd, r := 16) {
    hr := DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 33, "int*", 2, "uint", 4, "int")
    if (hr = 0)
        return
    WinGetPos(, , &w, &h, "ahk_id " hwnd)
    if (w > 0 && h > 0) {
        rgn := DllCall("gdi32\CreateRoundRectRgn", "int", 0, "int", 0, "int", w + 1, "int", h + 1, "int", r, "int", r, "ptr")
        DllCall("user32\SetWindowRgn", "ptr", hwnd, "ptr", rgn, "int", 1)
    }
}

StyleListView(hwnd) {
    try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
}

; ============================================================
;  Диалоги добавления и удаления
; ============================================================
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
        GetIconInfo(app.path, &iconFile, &iconNum)
        try {
            m.SetIcon(mnuName, iconFile, iconNum)
        } catch {
            try m.SetIcon(mnuName, A_WinDir "\System32\shell32.dll", 3)
        }
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
    global IsModalOpen
    if !IsObject(app)
        return
    IsModalOpen := true
    choice := MsgBox(
        "Удалить «" app.name "» из лаунчера?`n`n" app.path,
        "QuickLauncher", "YesNo IconQuestion")
    IsModalOpen := false
    if (choice = "Yes")
        RemoveApp(app)
}

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
        rawPath := Trim(pathEdit.Value, ' "`t`r`n')
        if (rawPath = "") {
            MsgBox("Укажите путь к приложению.", "QuickLauncher", "Icon!")
            pathEdit.Focus()
            return
        }
        path := StrReplace(rawPath, "/", "\")
        expandedPath := ExpandEnv(path)
        if !FileExist(expandedPath) {
            MsgBox("Не найдено:`n" path, "QuickLauncher", "IconX")
            return
        }
        name := Trim(nameEdit.Value)
        if (name = "")
            name := FileNameWithoutExt(path)

        global Apps
        for app in Apps {
            if (StrLower(app.path) = StrLower(path) || StrLower(ExpandEnv(app.path)) = StrLower(expandedPath)) {
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
        curVal := ExpandEnv(Trim(pathEdit.Value, ' "`t`r`n'))
        if (curVal != "" && InStr(FileExist(curVal), "D"))
            start := curVal
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

ShowSettingsGui(*) {
    global ScreensaverEnabled, ScreensaverTimeoutMin, ScreensaverBlackout
    g := Gui("+AlwaysOnTop", "QuickLauncher — Настройки заставки «Сатурн»")
    g.SetFont("s10", "Segoe UI")

    chkEnabled := g.Add("Checkbox", "xm w420 Checked" (ScreensaverEnabled ? 1 : 0), "Включать заставку при бездействии ноутбука")

    g.Add("Text", "xm y+15", "Время бездействия до включения:")
    timeouts := [1, 2, 3, 5, 10, 15, 20, 30]
    timeoutLabels := []
    selectedIdx := 3
    for idx, t in timeouts {
        suffix := (t = 1) ? "минута" : ((t >= 2 && t <= 4) ? "минуты" : "минут")
        timeoutLabels.Push(t " " suffix)
        if (t = ScreensaverTimeoutMin)
            selectedIdx := idx
    }
    ddTimeout := g.Add("DropDownList", "x+10 yp-3 w160 Choose" selectedIdx, timeoutLabels)

    chkBlackout := g.Add("Checkbox", "xm y+15 w420 Checked" (ScreensaverBlackout ? 1 : 0), "Затемнять экран (эффект выключенного монитора / космос)")

    g.Add("Text", "xm y+10 cGray", "При движении мыши или нажатии любой клавиши заставка выключается.")

    btnTest := g.Add("Button", "xm y+16 w170", "Проверить заставку")
    btnTest.OnEvent("Click", (*) => (g.Destroy(), Sleep(200), StartScreensaver()))

    btnSave := g.Add("Button", "x+60 w100 Default", "Сохранить")
    btnCancel := g.Add("Button", "x+8 w80", "Отмена")

    btnSave.OnEvent("Click", (*) => OnSave())
    btnCancel.OnEvent("Click", (*) => g.Destroy())

    OnSave() {
        global ScreensaverEnabled, ScreensaverTimeoutMin, ScreensaverBlackout
        ScreensaverEnabled := (chkEnabled.Value = 1)
        selIndex := ddTimeout.Value
        if (selIndex >= 1 && selIndex <= timeouts.Length)
            ScreensaverTimeoutMin := timeouts[selIndex]
        ScreensaverBlackout := (chkBlackout.Value = 1)
        SaveSettings()
        g.Destroy()
        TrayTip("Настройки заставки сохранены", "QuickLauncher")
    }

    g.Show("w440")
}

; ============================================================
;  Трей
; ============================================================
RebuildTray() {
    global Apps, HotkeyStr
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Лаунчер «Сатурн»…", (*) => ShowRadial())
    tray.Add("Классическая панель поиска…", (*) => ShowClassicPanel())
    tray.Add()
    tray.Add("Запустить заставку «Сатурн»", (*) => StartScreensaver())
    tray.Add("Настройки заставки…", (*) => ShowSettingsGui())
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
    tray.Add("Выход", OnExitClean)
}

HotkeyToText(hk) {
    hk := StrReplace(hk, "+", "Shift+")
    hk := StrReplace(hk, "^", "Ctrl+")
    hk := StrReplace(hk, "!", "Alt+")
    hk := StrReplace(hk, "#", "Win+")
    return hk
}

OnExitClean(*) {
    ShutdownGDIPlus()
    ExitApp()
}

; ============================================================
;  Запуск и регистрация обработчиков
; ============================================================
A_IconTip := TrayTipText
LoadApps()
LoadSettings()
RebuildTray()
SetTimer(CheckIdleScreensaver, 1000)

; Горячая клавиша вызывает Сатурн
try Hotkey(HotkeyStr, (*) => ShowRadial())

; Регистрация системных сообщений Windows
OnMessage(0x0200, RadialMouseMove)        ; WM_MOUSEMOVE
OnMessage(0x0202, RadialLButtonUp)        ; WM_LBUTTONUP
OnMessage(0x0205, RadialRButtonUp)        ; WM_RBUTTONUP
OnMessage(0x020A, RadialMouseWheel)       ; WM_MOUSEWHEEL
OnMessage(0x0100, RadialKeyHandler)       ; WM_KEYDOWN
OnMessage(0x0006, RadialActivateHandler) ; WM_ACTIVATE
OnExit((*) => ShutdownGDIPlus())

