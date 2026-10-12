' ********************************************************************
' * StreamingTV: Utilities & Hardware Tiering
' ********************************************************************

function AppVersion() as String
    return "1.1.0"
end function

function Base64Decode(s as Dynamic) as String
    if s = invalid then return ""
    txt = AnyToStr(s)
    if txt = "" then return ""
    ba = CreateObject("roByteArray")
    ba.FromBase64String(txt)
    out = ba.ToAsciiString()
    if out = invalid then return txt
    return out
end function

function Base64DecodeBytes(s as Dynamic) as Object
    ba = CreateObject("roByteArray")
    txt = AnyToStr(s)
    if txt <> "" then ba.FromBase64String(txt)
    return ba
end function

function Base64EncodeBytes(ba as Object) as String
    if ba = invalid then return ""
    return ba.ToBase64String()
end function

function Sha256Bytes(text as String) as Object
    digest = CreateObject("roEVPDigest")
    if digest = invalid then return invalid
    algos = ["sha256", "SHA256", "SHA-256"]
    out = invalid
    for each algo in algos
        digest.Setup(algo)
        ba = CreateObject("roByteArray")
        ba.FromAsciiString(text)
        out = digest.Process(ba)
        if out <> invalid
            if type(out) = "roByteArray" and out.Count() > 0 then return out
            s = AnyToStr(out)
            if Len(s) >= 32 then return out
        end if
    end for
    return out
end function

function Sha256Hex(text as String) as String
    out = Sha256Bytes(text)
    if out = invalid then return ""
    if type(out) = "roByteArray"
        if out.Count() = 0 then return ""
        hex = ""
        for i = 0 to out.Count() - 1
            hex = hex + Right("0" + DecToHex(out[i]), 2)
        end for
        return LCase(hex)
    end if
    s = AnyToStr(out)
    return LCase(s)
end function

function DecToHex(n as Integer) as String
    digits = "0123456789ABCDEF"
    if n < 0 then n = n + 256
    return Mid(digits, (n \ 16) + 1, 1) + Mid(digits, (n Mod 16) + 1, 1)
end function

' AES-256-CBC decrypt. key = SHA256(pin + ":" + mac), iv = 16 raw bytes.
' Returns plaintext string, or "" on failure.
function AesCbcDecrypt(pinCode as String, mac as String, ivB64 as String, cipherB64 as String) as String
    keyOut = Sha256Bytes(pinCode + ":" + mac)
    if keyOut = invalid then return ""
    keyBytes = invalid
    if type(keyOut) = "roByteArray"
        keyBytes = keyOut
    else
        ' String form — convert hex to bytes if needed, else use ascii
        keyBytes = CreateObject("roByteArray")
        hexKey = LCase(AnyToStr(keyOut))
        if Len(hexKey) = 64
            keyBytes.FromHexString(hexKey)
            if keyBytes.Count() <> 32
                keyBytes.Clear()
                for i = 1 to 63 step 2
                    keyBytes.Push(Val("&h" + Mid(hexKey, i, 2)))
                end for
            end if
        else
            keyBytes.FromAsciiString(pinCode + ":" + mac)
        end if
    end if
    if keyBytes.Count() < 16 then return ""
    ivBytes = Base64DecodeBytes(ivB64)
    if ivBytes = invalid or ivBytes.Count() < 16 then return ""
    cipherBytes = Base64DecodeBytes(cipherB64)
    if cipherBytes = invalid or cipherBytes.Count() = 0 then return ""

    dec = CreateObject("roAESDecrypter")
    if dec = invalid then return ""
    dec.SetCipher("AES-256-CBC")
    dec.SetSecretKey(keyBytes)
    dec.SetInitializationVector(ivBytes)
    plainBytes = dec.Decrypt(cipherBytes)
    if plainBytes = invalid or plainBytes.Count() = 0 then return ""

    ' PKCS#7 Unpadding: WebCrypto AES-CBC appends PKCS#7 padding. Strip it so JSON is clean.
    padLen = plainBytes[plainBytes.Count() - 1]
    if padLen >= 1 and padLen <= 16 and padLen <= plainBytes.Count()
        isPad = true
        for pi = plainBytes.Count() - padLen to plainBytes.Count() - 1
            if plainBytes[pi] <> padLen
                isPad = false
                exit for
            end if
        end for
        if isPad
            unpadded = CreateObject("roByteArray")
            for pi = 0 to plainBytes.Count() - padLen - 1
                unpadded.Push(plainBytes[pi])
            end for
            plainBytes = unpadded
        end if
    end if

    plain = plainBytes.ToAsciiString()
    if plain = invalid then return ""
    return plain
end function

function PinHash(pinCode as String, mac as String) as String
    ' Same construction the web site / API use for lookup.
    digest = Sha256Bytes(pinCode + ":" + mac)
    if digest = invalid then return ""
    return LCase(Base64EncodeBytes(digest))
end function

' XC short-EPG titles/descriptions are usually base64. Decode when possible.
function EpgText(val as Dynamic) as String
    raw = AnyToStr(val)
    if raw = "" then return ""
    decoded = Base64Decode(raw)
    if decoded <> "" and decoded <> raw then return decoded
    return raw
end function

function IsLowMemoryDevice() as Boolean
    devInfo = CreateObject("roDeviceInfo")
    model = devInfo.GetModel()
    
    ' Check models known for constrained RAM (~512MB: Express 37xx, 38xx, 3900-3930)
    lowModels = ["3700X", "3710X", "3800X", "3810X", "3900X", "3910X", "3920X", "3930X", "3931X"]
    for each lowModel in lowModels
        if model = lowModel or Left(model, 4) = Left(lowModel, 4)
            return true
        end if
    end for
    
    ' Also check general model details if available
    details = devInfo.GetModelDetails()
    if details <> invalid and details.DoesExist("ram")
        if Val(details.ram) < 1000
            return true
        end if
    end if
    
    return false
end function

function GetDefaultTheme() as Object
    return {
        backgroundColor: "0x0E1015FF",
        panelColor: "0x1A1D24FF",
        cardColor: "0x242832FF",
        cardSelectedColor: "0x323846FF",
        accentPrimary: "0xF57C00FF",
        accentSecondary: "0xFF9800FF",
        accentFocused: "0xFFA726FF",
        textColorPrimary: "0xFFFFFFFF",
        textColorSecondary: "0xAAAAAAFF",
        textColorMuted: "0x666666FF",
        brandName: "StreamingTV",
        brandLogo: "pkg:/images/logo_header.png",
        isCustomBranded: false
    }
end function

function ApplyBrandConfig(brandConfig as Object) as Object
    theme = GetDefaultTheme()
    if brandConfig = invalid then return theme
    
    if brandConfig.DoesExist("brand_name") and brandConfig.brand_name <> ""
        theme.brandName = brandConfig.brand_name
        theme.isCustomBranded = true
    end if
    
    if brandConfig.DoesExist("logo_url") and brandConfig.logo_url <> ""
        theme.brandLogo = brandConfig.logo_url
    end if
    
    accent = ""
    if brandConfig.DoesExist("accent_color") and brandConfig.accent_color <> ""
        accent = brandConfig.accent_color
    else if brandConfig.DoesExist("primary_color") and brandConfig.primary_color <> ""
        accent = brandConfig.primary_color
    end if

    if accent <> ""
        hexColor = accent
        if Left(hexColor, 1) = "#" then hexColor = Mid(hexColor, 2)
        if Len(hexColor) = 6
            theme.accentPrimary = "0x" + UCase(hexColor) + "FF"
            theme.accentSecondary = "0x" + UCase(hexColor) + "FF"
            theme.accentFocused = "0x" + UCase(hexColor) + "FF"
        end if
    end if
    
    return theme
end function

' Parses config from /api/device/config (theme object or root keys) and caches in registry
sub ApplyBrandConfigData(config as Dynamic)
    if config = invalid or type(config) <> "roAssociativeArray" then return
    
    brandName = ""
    logoUrl = ""
    accentColor = ""
    
    ' 1. Check brand name from top-level keys
    if config.DoesExist("reseller_brand") and config.reseller_brand <> invalid and AnyToStr(config.reseller_brand) <> ""
        brandName = AnyToStr(config.reseller_brand)
    else if config.DoesExist("app_name") and config.app_name <> invalid and AnyToStr(config.app_name) <> ""
        brandName = AnyToStr(config.app_name)
    end if
    
    ' 2. Check theme object (from /api/device/config)
    if config.DoesExist("theme") and type(config.theme) = "roAssociativeArray"
        th = config.theme
        if th.DoesExist("logo_url") and th.logo_url <> invalid and AnyToStr(th.logo_url) <> ""
            logoUrl = AnyToStr(th.logo_url)
        else if th.DoesExist("icon_url") and th.icon_url <> invalid and AnyToStr(th.icon_url) <> ""
            logoUrl = AnyToStr(th.icon_url)
        end if
        
        if th.DoesExist("accent_color") and th.accent_color <> invalid and AnyToStr(th.accent_color) <> ""
            accentColor = AnyToStr(th.accent_color)
        else if th.DoesExist("primary_color") and th.primary_color <> invalid and AnyToStr(th.primary_color) <> ""
            accentColor = AnyToStr(th.primary_color)
        end if
    end if
    
    ' 3. Check legacy or alternate brand object
    if config.DoesExist("brand") and type(config.brand) = "roAssociativeArray"
        b = config.brand
        if brandName = "" and b.DoesExist("brand_name") and b.brand_name <> invalid
            brandName = AnyToStr(b.brand_name)
        end if
        if logoUrl = "" and b.DoesExist("logo_url") and b.logo_url <> invalid
            logoUrl = AnyToStr(b.logo_url)
        end if
        if accentColor = "" and b.DoesExist("accent_color") and b.accent_color <> invalid
            accentColor = AnyToStr(b.accent_color)
        else if accentColor = "" and b.DoesExist("primary_color") and b.primary_color <> invalid
            accentColor = AnyToStr(b.primary_color)
        end if
    end if
    
    if brandName <> "" then Storage_SetAuth("provider_brand_name", brandName)
    if logoUrl <> "" then Storage_SetAuth("provider_logo", logoUrl)
    if accentColor <> "" then Storage_SetAuth("provider_accent_color", accentColor)
end sub

function FormatUnixTime(epochSec as Dynamic) as String
    if epochSec = invalid or Val(epochSec) = 0 then return ""
    dt = CreateObject("roDateTime")
    dt.FromSeconds(Val(epochSec))
    dt.ToLocalTime()
    
    hours = dt.GetHours()
    mins = dt.GetMinutes()
    
    ampm = "AM"
    if hours >= 12
        ampm = "PM"
        if hours > 12 then hours = hours - 12
    end if
    if hours = 0 then hours = 12
    
    minStr = Str(mins).Trim()
    if Len(minStr) = 1 then minStr = "0" + minStr
    
    return Str(hours).Trim() + ":" + minStr + " " + ampm
end function

function AnyToStr(val as Dynamic) as String
    if val = invalid then return ""
    if type(val) = "roString" or type(val) = "String" then return val.Trim()
    return Box(val).ToStr().Trim()
end function

function TruncateText(txt as Dynamic, maxLen as Integer) as String
    if txt = invalid then return ""
    s = AnyToStr(txt)
    if Len(s) <= maxLen then return s
    return Left(s, maxLen - 3) + "..."
end function

