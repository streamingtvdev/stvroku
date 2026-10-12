' ********************************************************************
' * StreamingTV BETA: SettingsScreen Controller
' * Account info, preview toggle, and confirmed sign-out.
' * StreamingTV (linked) logout deletes the device from the account.
' * XC/M3U logout removes this MAC from the system.
' ********************************************************************

sub init()
    m.accountStatusLabel = m.top.findNode("accountStatusLabel")
    m.providerNameLabel = m.top.findNode("providerNameLabel")
    m.deviceModelLabel = m.top.findNode("deviceModelLabel")
    m.btnTogglePreview = m.top.findNode("btnTogglePreview")
    m.btnPreviewLabel = m.top.findNode("btnPreviewLabel")
    m.btnLogout = m.top.findNode("btnLogout")
    m.btnLogoutLabel = m.top.findNode("btnLogoutLabel")
    m.hdrAccountStatus = m.top.findNode("hdrAccountStatus")
    m.hdrProvider = m.top.findNode("hdrProvider")
    m.hdrDevice = m.top.findNode("hdrDevice")
    m.hdrPreferences = m.top.findNode("hdrPreferences")
    
    m.confirmOverlay = m.top.findNode("confirmOverlay")
    m.confirmTitle = m.top.findNode("confirmTitle")
    m.confirmBody = m.top.findNode("confirmBody")
    m.btnConfirmYes = m.top.findNode("btnConfirmYes")
    m.btnConfirmNo = m.top.findNode("btnConfirmNo")
    
    m.focusIndex = 0 ' 0: Toggle Preview, 1: Logout
    m.confirmIndex = 1 ' 0: Yes, 1: No (default No)
    m.apiBase = "https://api.pirateking.cloud"
    m.apiTask = invalid
    
    LoadInfo()
    UpdateFocusStyles()
    OnThemeChanged()
end sub

sub OnThemeChanged()
    theme = m.top.theme
    if theme <> invalid
        if m.hdrAccountStatus <> invalid then m.hdrAccountStatus.color = theme.accentPrimary
        if m.hdrProvider <> invalid then m.hdrProvider.color = theme.accentPrimary
        if m.hdrDevice <> invalid then m.hdrDevice.color = theme.accentPrimary
        if m.hdrPreferences <> invalid then m.hdrPreferences.color = theme.accentPrimary
        UpdateFocusStyles()
    end if
end sub

sub LoadInfo()
    loginMode = Storage_GetAuth("login_mode", "")
    brandName = Storage_GetAuth("provider_brand_name", "StreamingTV")
    user = Storage_GetAuth("username", "")
    
    if loginMode = "paired"
        m.accountStatusLabel.text = "Linked Device (BETA)"
    else
        m.accountStatusLabel.text = "Player Setup active (User: " + user + ")"
    end if
    
    m.providerNameLabel.text = brandName + " • BETA " + AppVersion()
    
    devInfo = CreateObject("roDeviceInfo")
    model = devInfo.GetModel()
    isLow = IsLowMemoryDevice()
    tierStr = "Standard Hardware"
    if isLow then tierStr = "Constrained Hardware (Preview Optimization Active)"
    m.deviceModelLabel.text = "Model: " + model + " • " + tierStr
    
    pref = Storage_GetPref("enable_live_preview", "")
    if pref = "false" or (pref = "" and isLow)
        m.btnPreviewLabel.text = "PREVIEW: OFF"
    else
        m.btnPreviewLabel.text = "PREVIEW: ON"
    end if
end sub

sub TogglePreview()
    pref = Storage_GetPref("enable_live_preview", "")
    isLow = IsLowMemoryDevice()
    isCurrentlyOn = true
    if pref = "false" or (pref = "" and isLow)
        isCurrentlyOn = false
    end if
    
    if isCurrentlyOn
        Storage_SetPref("enable_live_preview", "false")
        m.btnPreviewLabel.text = "PREVIEW: OFF"
    else
        Storage_SetPref("enable_live_preview", "true")
        m.btnPreviewLabel.text = "PREVIEW: ON"
    end if
end sub

sub UpdateFocusStyles()
    theme = m.top.theme
    if theme = invalid then theme = GetDefaultTheme()
    
    if m.focusIndex = 0
        m.btnTogglePreview.color = theme.accentPrimary
        m.btnLogout.color = "0x551515FF"
    else
        m.btnTogglePreview.color = theme.cardColor
        m.btnLogout.color = "0x992525FF"
    end if
end sub

' ====================================================================
' Logout with confirmation
' ====================================================================

sub ShowLogoutConfirm()
    loginMode = Storage_GetAuth("login_mode", "")
    if loginMode = "paired"
        m.confirmTitle.text = "SIGN OUT?"
        m.confirmBody.text = "This removes the device from your account. You will need a new link code to use this TV again."
    else
        m.confirmTitle.text = "SIGN OUT?"
        m.confirmBody.text = "This removes this MAC from the system and clears saved playlists on this TV."
    end if
    m.confirmIndex = 1 ' default to No
    UpdateConfirmStyles()
    m.confirmOverlay.visible = true
    m.btnConfirmNo.setFocus(true)
end sub

sub UpdateConfirmStyles()
    theme = m.top.theme
    if theme = invalid then theme = GetDefaultTheme()
    if m.confirmIndex = 0
        m.btnConfirmYes.color = "0x992525FF"
        m.btnConfirmNo.color = theme.cardColor
    else
        m.btnConfirmYes.color = theme.cardColor
        m.btnConfirmNo.color = theme.accentPrimary
    end if
end sub

sub CloseLogoutConfirm()
    m.confirmOverlay.visible = false
    m.top.setFocus(true)
end sub

sub PerformLogout()
    m.confirmOverlay.visible = false
    loginMode = Storage_GetAuth("login_mode", "")
    token = Storage_GetAuth("device_token", "")
    mac = Storage_GetAuth("mac_address", DeviceMacAddress())
    pin = Storage_GetAuth("setup_pin", "")
    
    if m.apiTask = invalid
        m.apiTask = CreateObject("roSGNode", "ApiTask")
        m.apiTask.observeField("response", "OnLogoutResponse")
    end if
    
    if loginMode = "paired" and token <> ""
        m.apiTask.context = "logout"
        m.apiTask.action = "device_logout"
        m.apiTask.args = { apiBase: m.apiBase, token: token }
        m.apiTask.control = "RUN"
    else
        m.apiTask.context = "logout"
        m.apiTask.action = "player_unbind"
        m.apiTask.args = { apiBase: m.apiBase, mac: mac, pin: pin }
        m.apiTask.control = "RUN"
    end if
end sub

sub OnLogoutResponse()
    ' Clear local auth either way and hand back to MainScene
    Storage_ClearAllAuth()
    m.top.logoutRequested = true
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    
    if m.confirmOverlay.visible
        if key = "left" or key = "right"
            m.confirmIndex = 1 - m.confirmIndex
            UpdateConfirmStyles()
            return true
        else if key = "OK"
            if m.confirmIndex = 0
                PerformLogout()
            else
                CloseLogoutConfirm()
            end if
            return true
        else if key = "back"
            CloseLogoutConfirm()
            return true
        end if
        return true
    end if
    
    if key = "up" or key = "down"
        m.focusIndex = 1 - m.focusIndex
        UpdateFocusStyles()
        return true
    else if key = "OK"
        if m.focusIndex = 0
            TogglePreview()
            return true
        else if m.focusIndex = 1
            ShowLogoutConfirm()
            return true
        end if
    end if
    
    return false
end function
